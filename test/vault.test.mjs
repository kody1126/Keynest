import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, readFile, stat, rm, mkdir, chmod, link, symlink, unlink, writeFile } from 'node:fs/promises';
import { execFile } from 'node:child_process';
import os from 'node:os';
import path from 'node:path';
import { createCipheriv, randomBytes, scrypt as scryptCallback } from 'node:crypto';
import { promisify } from 'node:util';
import { Vault, publicEntry, validateEntry } from '../src/vault.mjs';

const password = 'test-password-never-real';
const entry = {name: 'Private production key', provider: 'deepseek', secret: 'sk-only-a-test-secret', baseUrl: 'https://api.deepseek.com', tags: ['private-project'], notes: 'Confidential note'};
async function fixture(t, options = {}) {
  const dir = await mkdtemp(path.join(os.tmpdir(), 'vault-test-'));
  t.after(() => rm(dir, {recursive: true, force: true}));
  const vault = new Vault(dir, options); await vault.init(); return vault;
}
test('encrypted persistence hides secret and metadata; wrong password fails; restart recovers', async t => {
  const vault = await fixture(t); await vault.setup(password);
  const saved = await vault.upsert(entry);
  assert.equal(saved.secret, undefined);
  assert(!saved.maskedSecret.includes('secret'));
  const raw = await readFile(vault.file, 'utf8');
  for (const sensitive of [entry.secret, entry.name, entry.tags[0], entry.notes, password]) assert(!raw.includes(sensitive));
  assert.equal((await stat(vault.file)).mode & 0o777, 0o600);
  assert.equal((await stat(vault.directory)).mode & 0o777, 0o700);
  vault.lock(); assert.throws(() => vault.entries(), /锁定/);
  await assert.rejects(vault.unlock('incorrect-password'), /密码不正确/);
  const reopened = new Vault(vault.directory); await reopened.init(); await reopened.unlock(password);
  assert.equal(reopened.get(saved.id).secret, entry.secret);
  await reopened.upsert({...entry, name: 'Renamed', secret: ''}, saved.id);
  assert.equal(reopened.get(saved.id).secret, entry.secret);
  reopened.lock();
});
test('backup recovery requires original password and never overwrites nonempty data', async t => {
  const source = await fixture(t); await source.setup(password); const saved = await source.upsert(entry);
  const backup = await source.backup();
  await assert.rejects(source.restore(backup, password), /空保险库/);
  const target = await fixture(t);
  await assert.rejects(target.restore(backup, 'incorrect-password'), /密码不正确/);
  assert.equal(target.status().initialized, false);
  await target.restore(backup, password);
  assert.equal(target.status().locked, true);
  await target.unlock(password); assert.equal(target.get(saved.id).secret, entry.secret);
  source.lock(); target.lock();
});
test('idle lock is not kept alive by list/status polling; nonce changes after edits', async t => {
  let now = 0;
  const vault = await fixture(t, {idleMs: 100, monotonicNow: () => now}); await vault.setup(password);
  const before = JSON.parse(await readFile(vault.file, 'utf8'));
  await vault.upsert(entry);
  const after = JSON.parse(await readFile(vault.file, 'utf8'));
  assert.notEqual(before.nonce, after.nonce);
  now = 99; vault.entries(); vault.status();
  now = 100; assert.equal(vault.status().locked, true);
});
test('credential edits clear stale quota, metadata edits preserve it', async t => {
  const vault = await fixture(t); await vault.setup(password); const saved = await vault.upsert(entry);
  const quota = {kind: 'balance', fetchedAt: new Date().toISOString(), metrics: [{label: '余额', value: '1.00', currency: 'CNY'}]};
  await vault.quota(saved.id, quota, entry.secret);
  await vault.upsert({...entry, name: 'New name', secret: ''}, saved.id);
  assert.deepEqual(vault.get(saved.id).quota, quota);
  await vault.upsert({...entry, secret: 'sk-a-new-secret'}, saved.id);
  assert.equal(vault.get(saved.id).quota, undefined);
  vault.lock();
});

async function authenticatedBackup(content) {
  const salt = randomBytes(32), nonce = randomBytes(12);
  const key = await promisify(scryptCallback)(password, salt, 32, {N: 131072, r: 8, p: 1, maxmem: 256 * 1024 * 1024});
  try {
    const cipher = createCipheriv('aes-256-gcm', key, nonce);
    cipher.setAAD(Buffer.from('api-vault-lab:v1:scrypt-131072-8-1:aes-256-gcm'));
    const data = Buffer.concat([cipher.update(JSON.stringify(content)), cipher.final()]);
    return {version: 1, cipher: 'aes-256-gcm', kdf: 'scrypt-131072-8-1', salt: salt.toString('base64'),
      nonce: nonce.toString('base64'), tag: cipher.getAuthTag().toString('base64'), data: data.toString('base64')};
  } finally { key.fill(0); }
}

test('authenticated import rejects malformed quota and unknown stored fields without replacing the vault', async t => {
  const target = await fixture(t); await target.setup(password);
  const before = await readFile(target.file, 'utf8');
  const stored = {...entry, id: '11111111-1111-4111-8111-111111111111',
    createdAt: '2026-01-01T00:00:00Z', updatedAt: '2026-01-01T00:00:00Z'};
  const snapshot = {kind: 'balance', fetchedAt: '2026-01-01T00:00:00Z', metrics: [{label: '余额', value: '1.00', currency: 'CNY'}]};
  for (const malformed of [
    {...stored, quota: {...snapshot, metrics: {privateKey: entry.secret}}},
    {...stored, quota: {...snapshot, metrics: [{label: '余额', value: entry.secret, currency: 'CNY'}]}},
    {...stored, otherSecret: entry.secret},
    {...stored, updatedAt: {secret: entry.secret}},
  ]) {
    const backup = await authenticatedBackup({version: 1, entries: [malformed]});
    await assert.rejects(target.restore(backup, password), /密码不正确|损坏|格式/);
    assert.equal(await readFile(target.file, 'utf8'), before);
    assert.deepEqual(target.entries(), []);
  }
  target.lock();
});

test('valid imported quotas retain null limits and small scientific-notation usage', async t => {
  const stored = {...entry, id: '11111111-1111-4111-8111-111111111111',
    createdAt: '2026-01-01T00:00:00Z', updatedAt: '2026-01-01T00:00:00Z',
    quota: {kind: 'key_limit', fetchedAt: '2026-01-01T00:00:00Z', metrics: [
      {label: '未设置 Key 上限', value: null, currency: 'USD'},
      {label: '本次用量', value: '1e-7', currency: 'USD'},
    ]}};
  const backup = await authenticatedBackup({version: 1, entries: [stored]});
  const target = await fixture(t);
  await target.restore(backup, password); await target.unlock(password);
  assert.deepEqual(target.entries()[0].quota, stored.quota);
  assert.equal(target.entries()[0].secret, undefined);
  target.lock();
});

test('invalid quota updates preserve the prior encrypted snapshot and public projection excludes unexpected fields', async t => {
  const vault = await fixture(t); await vault.setup(password);
  const saved = await vault.upsert(entry);
  const quota = {kind: 'balance', fetchedAt: '2026-01-01T00:00:00Z', metrics: [{label: '余额', value: '1', currency: 'CNY'}]};
  await vault.quota(saved.id, quota, entry.secret);
  const before = await readFile(vault.file, 'utf8');
  await assert.rejects(vault.quota(saved.id, {...quota, metrics: [{label: '余额', value: entry.secret, currency: 'CNY'}]}, entry.secret), /格式/);
  assert.equal(await readFile(vault.file, 'utf8'), before);
  assert.deepEqual(vault.get(saved.id).quota, quota);
  const projected = publicEntry({...vault.get(saved.id), futurePrivateField: entry.secret});
  assert.equal(JSON.stringify(projected).includes(entry.secret), false);
  vault.lock();
});

test('initialization refuses a hard-linked vault without changing the outside file permissions', async t => {
  const source = await fixture(t); await source.setup(password);
  const raw = await readFile(source.file);
  const root = await mkdtemp(path.join(os.tmpdir(), 'vault-hardlink-test-'));
  t.after(() => rm(root, {recursive: true, force: true}));
  const outside = path.join(root, 'outside.json');
  await writeFile(outside, raw); await chmod(outside, 0o644);
  const target = new Vault(path.join(root, 'vault'));
  await mkdir(target.directory);
  await link(outside, target.file);
  await assert.rejects(target.init(), /普通文件|独占/);
  assert.equal((await stat(outside)).mode & 0o777, 0o644);
  assert.deepEqual(await readFile(outside), raw);
  source.lock();
});

test('unlock and backup recheck replaced hard links and symbolic links through file descriptors', async t => {
  const vault = await fixture(t); await vault.setup(password);
  const raw = await readFile(vault.file);
  const root = await mkdtemp(path.join(os.tmpdir(), 'vault-replacement-test-'));
  t.after(() => rm(root, {recursive: true, force: true}));
  const outside = path.join(root, 'outside.json');
  await writeFile(outside, raw); await chmod(outside, 0o644);
  for (const replace of [link, symlink]) {
    if (vault.status().locked) await vault.unlock(password);
    await unlink(vault.file); await replace(outside, vault.file);
    await assert.rejects(vault.backup());
    vault.lock(); await assert.rejects(vault.unlock(password));
    assert.equal(vault.status().locked, true);
    assert.equal((await stat(outside)).mode & 0o777, 0o644);
    assert.deepEqual(await readFile(outside), raw);
    await unlink(vault.file); await writeFile(vault.file, raw, {mode: 0o600});
  }
});

test('special nodes and oversized replacement files are rejected before chmod or blocking reads', {timeout: 3000}, async t => {
  const vault = await fixture(t); await vault.setup(password);
  await unlink(vault.file);
  await promisify(execFile)('mkfifo', [vault.file]);
  await assert.rejects(vault.backup(), /普通文件/);
  await assert.rejects(new Vault(vault.directory).init(), /普通文件/);
  await unlink(vault.file); await mkdir(vault.file);
  await assert.rejects(vault.backup(), /普通文件/);
  await rm(vault.file, {recursive: true});
  await writeFile(vault.file, Buffer.alloc(4 * 1024 * 1024 + 1));
  await chmod(vault.file, 0o644);
  await assert.rejects(vault.backup(), /4 MiB/);
  assert.equal((await stat(vault.file)).mode & 0o777, 0o644);
  vault.lock();
});

test('idle expiry uses elapsed monotonic time while entry timestamps remain wall-clock dates', async t => {
  let wall = Date.UTC(2026, 9, 2), elapsed = 1000;
  const vault = await fixture(t, {idleMs: 100, now: () => wall, monotonicNow: () => elapsed});
  await vault.setup(password);
  const saved = await vault.upsert(entry);
  assert.equal(saved.createdAt, new Date(wall).toISOString());
  wall -= 24 * 60 * 60 * 1000; elapsed = 1099;
  assert.equal(vault.status().locked, false);
  elapsed = 1100;
  assert.equal(vault.status().locked, true, 'Moving the wall clock back must not extend the session');
});

test('new URLs reject parser-stripped control characters before any save', () => {
  for (const baseUrl of ['https://api.deep\nseek.com/v1', '\thttps://api.deepseek.com', 'https://api.deepseek.com/v1\r', 'https://api.deepseek.com/\0path']) {
    assert.throws(() => validateEntry({...entry, baseUrl}), /控制字符/);
  }
});

test('legacy authenticated backups canonicalize control-bearing URLs without changing the secret', async t => {
  const legacySecret = '  sk-legacy-fake-keep-exact  ';
  const legacyURL = 'https://api.deep\nseek.com/v1/' + '汉'.repeat(500) + '\t';
  const canonicalURL = new URL(legacyURL).href;
  assert(legacyURL.length <= 1000 && canonicalURL.length > 1000);
  const stored = {...entry, secret: legacySecret, baseUrl: legacyURL,
    id: '11111111-1111-4111-8111-111111111111', createdAt: '2026-01-01T00:00:00Z', updatedAt: '2026-01-01T00:00:00Z'};
  const backup = await authenticatedBackup({version: 1, entries: [stored]});
  const target = await fixture(t);
  await target.restore(backup, password); await target.unlock(password);
  assert.equal(target.get(stored.id).secret, legacySecret);
  assert.equal(target.get(stored.id).baseUrl, canonicalURL);
  assert.throws(() => validateEntry({...entry, baseUrl: canonicalURL}), /过长/, 'New input retains its 1000-character limit');
  const second = await fixture(t);
  await second.restore(await target.backup(), password); await second.unlock(password);
  assert.equal(second.get(stored.id).secret, legacySecret);
  assert.equal(second.get(stored.id).baseUrl, canonicalURL);
  await second.upsert({...publicEntry(second.get(stored.id)), name: 'Edited legacy fixture', secret: ''}, stored.id);
  second.lock(); await second.unlock(password);
  assert.equal(second.get(stored.id).name, 'Edited legacy fixture');
  assert.equal(second.get(stored.id).baseUrl, canonicalURL);
  assert.equal(second.get(stored.id).secret, legacySecret);
  target.lock(); second.lock();
});
