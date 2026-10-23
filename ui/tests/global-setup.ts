// tests/global-setup.ts — sign in once per persona; save storageState.
// Sessions are reused across all specs in a test run.
import { chromium, type FullConfig } from '@playwright/test'
import { chmodSync, mkdirSync } from 'node:fs'
import { resolve } from 'node:path'
import { signIn } from './auth'
import { USERS, stateFile } from './users'

export default async function globalSetup(_config: FullConfig) {
  mkdirSync(resolve(import.meta.dirname, '.auth'), { recursive: true })
  chmodSync(resolve(import.meta.dirname, '.auth'), 0o700)
  const browser = await chromium.launch()
  for (const user of USERS) {
    const context = await browser.newContext({})
    await signIn(await context.newPage(), user)
    await context.storageState({ path: stateFile(user) })
    chmodSync(stateFile(user), 0o600)
    await context.close()
  }
  await browser.close()
}
