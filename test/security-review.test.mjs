import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, readFile, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { setTimeout as delay } from 'node:timers/promises';
import { Vault, validateEntry } from '../src/vault.mjs';

const password = 'review-only-password-32';
const entry = secret => ({name: 'Review fixture', provider: 'generic', secret, baseUrl: '', tags: [], notes: ''});

test('credential validation allows ordinary letters and digits', () => {
  assert.equal(validateEntry(entry('sk-normal-key-0123')).secret, 'sk-normal-key-0123');
});

test('credential validation rejects real CR, LF and NUL', () => {
  for (const control of ['\r', '\n', '\0']) {
    assert.throws(() => validateEntry(entry(`sk-abc${control}xyz`)));
  }
});

test('tampered authenticated backup never changes the existing vault', async () => {
  const directory = await mkdtemp(path.join(tmpdir(), 'api-vault-review-'));
  try {
    const vault = new Vault(directory);
    await vault.init();
    await vault.setup(password);
    const previous = await readFile(vault.file, 'utf8');
    const tampered = JSON.parse(previous);
    const tag = Buffer.from(tampered.tag, 'base64');
    tag[0] ^= 1;
    tampered.tag = tag.toString('base64');
    await assert.rejects(vault.restore(tampered, password));
    assert.equal(await readFile(vault.file, 'utf8'), previous);
    assert.equal(vault.entries().length, 0);
    vault.lock();
  } finally {
    await rm(directory, {recursive: true, force: true});
  }
});

test('locking during restore authentication cancels the disk replacement', async () => {
  const directory = await mkdtemp(path.join(tmpdir(), 'api-vault-restore-lock-'));
  try {
    const vault = new Vault(directory);
    await vault.init();
    await vault.setup(password);
    const previous = await readFile(vault.file, 'utf8');
    const restoring = vault.restore(JSON.parse(previous), password);
    vault.lock();
    await assert.rejects(restoring, /恢复已取消/);
    assert.equal(await readFile(vault.file, 'utf8'), previous);
    assert.equal(vault.status().locked, true);
  } finally {
    await rm(directory, {recursive: true, force: true});
  }
});

async function serverFixture(t, quotaFetcher) {
  const { startServer } = await import('../src/server.mjs');
  const directory = await mkdtemp(path.join(tmpdir(), 'api-vault-security-http-'));
  const app = await startServer({dataDir: directory, port: 0, quotaFetcher});
  t.after(async () => {
    await app.close();
    await rm(directory, {recursive: true, force: true});
  });
  const api = async (route, method = 'POST', data = {}) => {
    const response = await fetch(app.origin + route, {
      method,
      headers: {Authorization: `Bearer ${app.token}`, 'Content-Type': 'application/json'},
      body: method === 'GET' ? undefined : JSON.stringify(data),
    });
    return {status: response.status, data: await response.json()};
  };
  await api('/api/setup', 'POST', {password});
  const created = await api('/api/entries', 'POST', {...entry('sk-security-review-only'), provider: 'deepseek'});
  return {app, api, id: created.data.entry.id};
}

test('unexpected provider errors never return credential material to the browser', async t => {
  const {api, id} = await serverFixture(t, async (_provider, secret) => {
    throw new Error(`Simulated upstream diagnostic Authorization: Bearer ${secret}`);
  });
  const response = await api(`/api/entries/${id}/sync`);
  assert.equal(response.status, 502);
  assert(!JSON.stringify(response.data).includes('sk-security-review-only'));
  assert(!JSON.stringify(response.data).includes('Authorization'));
});

test('manual lock preempts a pending sync and invalidates previously queued unlock', async t => {
  let release;
  const gate = new Promise(resolve => { release = resolve; });
  let markStarted;
  const started = new Promise(resolve => { markStarted = resolve; });
  const {app, api, id} = await serverFixture(t, async () => {
    markStarted();
    await gate;
    return {kind: 'balance', fetchedAt: new Date().toISOString(), metrics: [{label: '余额', value: '1', currency: 'CNY'}]};
  });
  const syncing = api(`/api/entries/${id}/sync`);
  await started;
  const delivered = new Promise(resolve => {
    const observed = req => {
      if (req.url === '/api/unlock') {
        app.server.off('request', observed);
        req.once('end', () => setImmediate(resolve));
      }
    };
    app.server.on('request', observed);
  });
  const unlocking = api('/api/unlock', 'POST', {password});
  await delivered;
  const locking = api('/api/lock');
  try {
    const outcome = await Promise.race([locking, delay(1000).then(() => null)]);
    assert.notEqual(outcome, null, 'Lock must complete while provider request is still pending');
    assert.equal(outcome.status, 200);
  } finally {
    release();
    await Promise.allSettled([syncing, locking, unlocking]);
  }
  assert.notEqual((await unlocking).status, 200, 'Old queued unlock must not reopen a newly locked vault');
  assert.equal((await syncing).status, 423);
  assert.equal(app.vault.status().locked, true);
});
