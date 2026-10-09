// tests/users.ts — Shift Gear personas (LDAP → Keycloak → Vault OIDC).
import { resolve } from 'node:path'

export const USERS = ['ada', 'ben', 'cleo', 'dirk', 'finn'] as const
export type User = (typeof USERS)[number]

export const ROOT = resolve(import.meta.dirname, '..', '..')
export const stateFile = (u: User) => resolve(import.meta.dirname, '.auth', `${u}.json`)

// Passwords live only in Vault KV (kv/shift-gear/identity). scripts/ui-test.sh
// reads them with Ansible's token into this process's environment
// (SG_PW_<USER>); they are never written to disk.
export function passwordOf(u: User): string {
  const p = process.env[`SG_PW_${u.toUpperCase()}`]
  if (!p) throw new Error(`no password for ${u}: run the tests through make ui-test`)
  return p
}
