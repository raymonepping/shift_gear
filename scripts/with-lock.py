#!/usr/bin/env python3
"""Inherited POSIX lock shared across commands/checkouts for the API target."""
import fcntl
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import secrets


def target():
    try:
        result = subprocess.run(['oc', 'config', 'view', '--minify', '-o', 'json'],
                                capture_output=True, timeout=5, check=True)
        return json.loads(result.stdout)['clusters'][0]['cluster']['server']
    except (OSError, subprocess.SubprocessError, ValueError, KeyError, IndexError):
        return 'unconfigured'


def lock_path(server):
    return Path(tempfile.gettempdir()) / f'shiftgear-{os.getuid()}-{hashlib.sha256(server.encode()).hexdigest()[:20]}.lock'


def config_fingerprint():
    """Bind inherited target knowledge to the complete ordered local config.

    No config contents or credential values leave this process. A changed or
    unreadable config must be resolved anew; a cache is never target authority.
    """
    value = os.environ.get('KUBECONFIG')
    paths = value.split(os.pathsep) if value else [str(Path.home() / '.kube/config')]
    digest = hashlib.sha256()
    configured = False
    for name in filter(None, paths):
        path = Path(name).expanduser().resolve()
        digest.update(str(path).encode() + b'\0')
        try:
            data = path.read_bytes()
        except FileNotFoundError:
            digest.update(b'missing\0')
            continue
        except OSError:
            return None, True
        configured |= bool(data.strip())
        digest.update(str(len(data)).encode() + b'\0' + data)
    return digest.hexdigest(), configured


def inherited(path):
    try:
        fd = int(os.environ['SG_LOCK_FD'])
        actual, expected = os.fstat(fd), path.stat()
        if (actual.st_dev, actual.st_ino) == (expected.st_dev, expected.st_ino):
            return True
    except (OSError, KeyError, ValueError):
        pass
    # Node/Ansible workers can close inherited descriptors. Accept only
    # an inherited nonce whose lock owner is a live process ancestor.
    try:
        owner = int(os.environ['SG_LOCK_OWNER'])
        nonce = os.environ['SG_LOCK_NONCE']
        if not nonce or path.read_text() != nonce:
            return False
        parent = os.getppid()
        for _ in range(64):
            if parent == owner:
                return True
            if parent <= 1:
                break
            parent = int(subprocess.check_output(['ps', '-o', 'ppid=', '-p', str(parent)], text=True).strip())
    except (OSError, KeyError, ValueError, subprocess.SubprocessError):
        pass
    return False


def main():
    fingerprint, configured = config_fingerprint()
    cached = os.environ.get('SG_LOCK_TARGET')
    if (cached and fingerprint and fingerprint == os.environ.get('SG_LOCK_CONFIG_DIGEST')
            and inherited(lock_path(cached))):
        # During cold start the CLI can temporarily disappear. Keep the
        # authenticated ancestor's lock only while config bytes still match.
        server = cached
    else:
        server = target()
        if server == 'unconfigured' and configured:
            print('Cannot resolve the configured target; refusing an ambiguous lock.', file=sys.stderr)
            return 78
    path = lock_path(server)
    if sys.argv[1:] == ['--check']:
        return 0 if inherited(path) else 1
    fd = os.open(path, os.O_CREAT | os.O_RDWR, 0o600)
    try:
        fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError:
        print('Another Shift Gear command owns this target. Wait for it to finish.', file=sys.stderr)
        return 75
    nonce = secrets.token_hex(24)
    os.ftruncate(fd, 0)
    os.write(fd, nonce.encode())
    return subprocess.call(sys.argv[1:], env={**os.environ, 'SG_LOCK_FD': str(fd),
                           'SG_LOCK_OWNER': str(os.getpid()), 'SG_LOCK_NONCE': nonce,
                           'SG_LOCK_TARGET': server, 'SG_LOCK_CONFIG_DIGEST': fingerprint or ''}, pass_fds=(fd,))


if __name__ == '__main__':
    sys.exit(main())
