#!/usr/bin/env python3
"""C02 actual access, redaction, fsync/restart continuity and metric scrape proof."""
import datetime as dt
import json
import ssl
import subprocess
import time
import urllib.error
import urllib.request
import uuid
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / '.build/observability-proof.json'
IMAGE = 'registry.access.redhat.com/ubi9/nodejs-24-minimal@sha256:fe7301f641a4b16cfb36354623f2e1c3bb7838607321ce769e877ca201079a47'


def oc(*args, data=None, timeout=150):
    p = subprocess.run(['oc', '--request-timeout=130s', *args], input=json.dumps(data) if data is not None else None,
                       stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=timeout)
    if p.returncode:
        raise RuntimeError('Observability proof command failed; inspect named resource readiness')
    return p.stdout


def in_ui(script, *args):
    return json.loads(oc('-n', 'sg-app', 'exec', 'deployment/sg-ui', '--', 'node', '-e', script, *args, timeout=20))


def main(checks, owned, selection):
    backend = selection['metrics_backend']
    archive_enabled = selection['audit_archive_enabled']
    def check(name, condition):
        if not condition:
            raise RuntimeError('Observability proof failed: ' + name)
        checks[name] = True
    def archive(marker):
        return in_ui("fetch('http://sg-audit.sg-app.svc:8080/archive',{signal:AbortSignal.timeout(3000)}).then(async r=>{if(!r.ok)throw Error();const b=await r.json();console.log(JSON.stringify({status:b.archive,rows:b.entries.filter(e=>e.path.includes(process.argv[1]))}))}).catch(()=>process.exit(1))", marker)
    def scrape():
        if backend == 'opentelemetry':
            return in_ui("fetch('http://sg-otel.sg-app.svc:9090/metrics',{signal:AbortSignal.timeout(3000)}).then(r=>r.text()).then(b=>console.log(JSON.stringify(/^up(?:\\{[^\\n]*\\})? 1 [0-9]+$/m.test(b)))).catch(()=>process.exit(1))")
        return in_ui("fetch('http://sg-metrics.sg-app.svc:9090/api/v1/query?query=up%7Bjob%3D%22sg-audit%22%7D',{signal:AbortSignal.timeout(3000)}).then(r=>r.json()).then(b=>console.log(JSON.stringify(b.data.result.some(s=>s.value[1]==='1')))).catch(()=>process.exit(1))")
    if backend != 'none':
        name = 'sg-otel' if backend == 'opentelemetry' else 'sg-metrics'
        oc('-n', 'sg-app', 'rollout', 'status', 'deployment/' + name, '--timeout=120s')
        available = False
        for _ in range(20):
            try:
                if scrape(): available = True; break
            except RuntimeError: pass
            time.sleep(2)
        check('private ' + backend + ' destination scrape', available)
    else:
        deployments = json.loads(oc('-n', 'sg-app', 'get', 'deployments', '-o', 'json'))['items']
        check('disabled metrics has no backend workload dependency', not any(item['metadata']['name'] in ('sg-otel', 'sg-metrics') for item in deployments))
    if not archive_enabled:
        check('disabled archive keeps collector ready without storage', in_ui("Promise.all([fetch('http://sg-audit.sg-app.svc:8080/healthz'),fetch('http://sg-audit.sg-app.svc:8080/archive')]).then(rs=>console.log(JSON.stringify(rs[0].ok&&rs[1].status===503))).catch(()=>process.exit(1))"))
        pod = json.loads(oc('-n', 'sg-app', 'get', 'deployment', 'sg-audit', '-o', 'json'))
        check('disabled archive does not mount its PVC', not any(volume['name'] == 'archive' for volume in pod['spec']['template']['spec']['volumes']))
    base = 'sg-c02-' + uuid.uuid4().hex[:12]
    js = """const expected=process.argv[1]==='reader';async function get(url){try{const r=await fetch(url,{signal:AbortSignal.timeout(2000)});return r.ok?'allowed':'http-refusal'}catch(e){return e.name==='TimeoutError'?'blocked':'error'}}Promise.all([get('http://sg-audit.sg-app.svc:8081/metrics'),get('http://sg-audit.sg-app.svc:8080/archive'),...(process.argv[2]?[get(process.argv[2])]:[])]).then(r=>{const ok=r[0]===(expected?'allowed':'blocked')&&r[1]==='blocked'&&(r.length===2||r[2]==='blocked');console.log(JSON.stringify({ok}));process.exit(ok?0:1)})"""
    for mode in ('reader', 'untrusted'):
        name = base + '-' + mode
        labels = {'shift-gear/proof': base}
        if mode == 'reader': labels['shift-gear/audit-metrics-reader'] = 'true'
        pod = {'apiVersion': 'v1', 'kind': 'Pod', 'metadata': {'name': name, 'namespace': 'sg-app', 'labels': labels},
               'spec': {'restartPolicy': 'Never', 'automountServiceAccountToken': False,
                        'securityContext': {'runAsNonRoot': True, 'seccompProfile': {'type': 'RuntimeDefault'}},
                        'containers': [{'name': 'probe', 'image': IMAGE, 'command': ['node', '-e', js, mode, 'http://sg-otel.sg-app.svc:9090/metrics' if backend == 'opentelemetry' else 'http://sg-metrics.sg-app.svc:9090/api/v1/query?query=up' if backend == 'prometheus' else ''],
                                        'securityContext': {'allowPrivilegeEscalation': False, 'readOnlyRootFilesystem': True, 'capabilities': {'drop': ['ALL']}},
                                        'resources': {'requests': {'cpu': '5m', 'memory': '32Mi'}, 'limits': {'memory': '64Mi'}}}]}}
        oc('create', '-f', '-', data=pod); owned.append(name)
        oc('-n', 'sg-app', 'wait', '--for=jsonpath={.status.phase}=Succeeded', 'pod/' + name, '--timeout=120s')
        check(mode + ' actual network boundaries', json.loads(oc('-n', 'sg-app', 'logs', name))['ok'])
    if not archive_enabled: return
    marker = 'c02-proof-' + uuid.uuid4().hex
    canary = 'redaction-' + uuid.uuid4().hex
    domain = json.loads((ROOT / '.build/terraform/infra.json').read_text())['cluster']['apps_domain']
    request = urllib.request.Request(f'https://vault.{domain}/v1/auth/ldap/login/{marker}',
                                    data=json.dumps({'password': canary}).encode(),
                                    headers={'Content-Type': 'application/json', 'X-Vault-Namespace': 'shift-gear'})
    try:
        with urllib.request.urlopen(request, context=ssl.create_default_context(cafile=str(ROOT / '.secrets/tls/pub/ca.pem')), timeout=10):
            raise RuntimeError('Fixture authentication unexpectedly succeeded')
    except urllib.error.HTTPError as error:
        check('audited fixture refused', error.code in (400, 401, 403))
    before = None
    for _ in range(20):
        current = archive(marker)
        if current['rows']:
            before = current['rows'][0]; break
        time.sleep(1)
    check('marker committed to retained source', before is not None)
    check('fixed retained projection', set(before) == {'schemaVersion', 'id', 'retainedAt', 'time', 'type', 'operation', 'namespace', 'path', 'hasError'})
    scan = """const fs=require('node:fs');const dir='/var/lib/sg-audit';let found=false,seen=0,matched=false;for(const name of fs.readdirSync(dir).filter(n=>/^segment-[0-9-]+[a-f0-9-]*\\.ndjson$/.test(n))){const raw=fs.readFileSync(dir+'/'+name,'utf8');seen++;if(raw.includes(process.argv[1]))found=true;if(raw.includes(process.argv[2]))matched=true}console.log(JSON.stringify({redacted:!found&&seen>0&&matched}))"""
    check('raw password absent from actual retained files', json.loads(oc('-n', 'sg-app', 'exec', 'deployment/sg-audit', '--', 'node', '-e', scan, canary, before['id'], timeout=20))['redacted'])
    pods = json.loads(oc('-n', 'sg-app', 'get', 'pods', '-l', 'app.kubernetes.io/name=sg-audit', '-o', 'json'))['items']
    active = [pod for pod in pods if not pod['metadata'].get('deletionTimestamp')]
    check('single archive writer', len(active) == 1)
    old_uid = active[0]['metadata']['uid']
    oc('-n', 'sg-app', 'delete', 'pod', active[0]['metadata']['name'], '--wait=true', '--timeout=60s')
    oc('-n', 'sg-app', 'rollout', 'status', 'deployment/sg-audit', '--timeout=120s')
    recovered = None
    for _ in range(30):
        try:
            rows = archive(marker)['rows']
            recovered = next((row for row in rows if row['id'] == before['id']), None)
            if recovered: break
        except RuntimeError: pass
        time.sleep(2)
    check('record identity and timestamp survive replacement', recovered == before)
    pods = json.loads(oc('-n', 'sg-app', 'get', 'pods', '-l', 'app.kubernetes.io/name=sg-audit', '-o', 'json'))['items']
    check('replacement actually occurred', any(pod['metadata']['uid'] != old_uid and pod['status']['phase'] == 'Running' for pod in pods))
    if backend == 'none': return
    resumed = False
    for _ in range(15):
        try:
            if scrape(): resumed = True; break
        except RuntimeError: pass
        time.sleep(2)
    check('scrape resumes after replacement', resumed)


if __name__ == '__main__':
    initial = subprocess.check_output([str(ROOT / 'scripts/automation-digest.sh')], text=True).strip()
    checks, owned = {}, []
    selection = None
    receipt = {'selection': selection, 'schemaVersion': '1', 'result': 'running', 'at': dt.datetime.now(dt.timezone.utc).isoformat(), 'inputDigest': initial}
    OUTPUT.parent.mkdir(exist_ok=True)
    OUTPUT.write_text(json.dumps(receipt, indent=2) + '\n')
    failure = None
    try:
        selection = json.loads((ROOT / '.build/terraform/workloads.json').read_text())['observability']
        main(checks, owned, selection)
    except Exception as error:
        failure = str(error) if isinstance(error, RuntimeError) else 'Observability proof incomplete'
    finally:
        for name in owned:
            try: oc('-n', 'sg-app', 'delete', 'pod', name, '--wait=true', '--ignore-not-found=true', '--timeout=30s', timeout=40)
            except Exception: failure = 'Observability proof cleanup failed'
    if subprocess.check_output([str(ROOT / 'scripts/automation-digest.sh')], text=True).strip() != initial:
        failure = 'Inputs changed during observability proof'
    receipt.update(selection=selection, result='fail' if failure else 'pass', at=dt.datetime.now(dt.timezone.utc).isoformat(), checks=checks)
    OUTPUT.write_text(json.dumps(receipt, indent=2) + '\n')
    if failure: raise SystemExit(failure)
    print(f'PASS: {len(checks)} live C02 checks; selected optional integration checks; disabled sources are explicit. No restore performed.')
