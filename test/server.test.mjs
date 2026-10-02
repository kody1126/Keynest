import test from 'node:test';
import assert from 'node:assert/strict';
import http from 'node:http';
import { mkdtemp, rm, readFile } from 'node:fs/promises';
import path from 'node:path';
import os from 'node:os';
import { startServer } from '../src/server.mjs';

const password = 'test-password-never-real';
const record = {name: 'Test key', provider: 'deepseek', secret: 'sk-fake-never-real', baseUrl: 'https://api.deepseek.com', tags: ['test'], notes: ''};
async function fixture(t, extra = {}) {
  const dir = await mkdtemp(path.join(os.tmpdir(), 'vault-server-test-'));
  const app = await startServer({port: 0, dataDir: dir, ...extra});
  t.after(async () => { await app.close(); await rm(dir, {recursive: true, force: true}); });
  const api = async (url, method = 'GET', data, headers = {}) => {
    const response = await fetch(app.origin + url, {method, headers: {'Authorization': `Bearer ${app.token}`, ...(data ? {'Content-Type': 'application/json'} : {}), ...headers}, body: data ? JSON.stringify(data) : undefined});
    return {status: response.status, data: await response.json(), headers: response.headers};
  };
  return {app, api};
}
test('server requires launch token, rejects foreign origins and hostile Host', async t => {
  const {app, api} = await fixture(t);
  assert.equal(app.server.address().address, '127.0.0.1');
  assert.equal((await api('/api/status', 'GET', undefined, {Authorization: 'Bearer wrong'})).status, 401);
  assert.equal((await api('/api/status', 'GET', undefined, {Origin: 'https://evil.example'})).status, 403);
  assert.equal((await api('/api/status', 'GET', undefined, {'Sec-Fetch-Site': 'cross-site'})).status, 403);
  const result = await new Promise(resolve => {
    http.get(app.origin + '/api/status', {headers: {Host: 'evil.example', Authorization: `Bearer ${app.token}`}}, response => { response.resume(); resolve(response.statusCode); });
  });
  assert.equal(result, 403);
  const good = await api('/api/status');
  assert.equal(good.status, 200); assert.equal(good.headers.get('cache-control'), 'no-store');
  assert(good.headers.get('content-security-policy').includes("frame-ancestors 'none'"));
});
test('static allowlist rejects traversal and CORS preflight never grants foreign access', async t => {
  const {app} = await fixture(t);
  const request = (requestPath, method = 'GET', headers = {}) => new Promise((resolve, reject) => {
    const req = http.request(app.origin, {path: requestPath, method, headers}, res => {
      let body = '';
      res.setEncoding('utf8'); res.on('data', chunk => { body += chunk; });
      res.on('end', () => resolve({status: res.statusCode, headers: res.headers, body}));
    });
    req.on('error', reject); req.end();
  });
  for (const route of ['/../package.json', '/%2e%2e/src/vault.mjs', '/src/vault.mjs', '/.data/vault.json']) {
    const response = await request(route);
    assert.equal(response.status, 404);
    assert.equal(response.body.includes(app.token), false);
  }
  const preflight = await request('/api/unlock', 'OPTIONS', {
    Origin: 'https://untrusted.example', 'Access-Control-Request-Method': 'POST',
    'Access-Control-Request-Headers': 'authorization,content-type',
  });
  assert.equal(preflight.status, 403);
  assert.equal(preflight.headers['access-control-allow-origin'], undefined);
  assert.equal(preflight.headers['access-control-allow-credentials'], undefined);
  const staticPage = await request('/');
  assert.equal(staticPage.status, 200);
  assert.equal(staticPage.headers['cache-control'], 'no-store');
  assert.equal(staticPage.headers['referrer-policy'], 'no-referrer');
  assert.equal(staticPage.body.includes(app.token), false);
});
test('unlock backoff expires with monotonic elapsed time rather than the wall clock', async t => {
  let elapsed = 1000;
  const {api} = await fixture(t, {monotonicNow: () => elapsed});
  assert.equal((await api('/api/setup', 'POST', {password: 'short'})).status, 400);
  assert.equal((await api('/api/setup', 'POST', {password})).status, 429);
  elapsed += 1000;
  assert.equal((await api('/api/setup', 'POST', {password})).status, 200);
});
test('concurrent writes persist without loss; secret revealed only on explicit request', async t => {
  const {app, api} = await fixture(t);
  assert.equal((await api('/api/setup', 'POST', {password})).status, 200);
  const results = await Promise.all(Array.from({length: 6}, (_, i) => api('/api/entries', 'POST', {...record, name: `Entry ${i}`})));
  results.forEach(r => assert.equal(r.status, 201));
  const list = await api('/api/entries'); assert.equal(list.data.entries.length, 6);
  assert(!JSON.stringify(list.data).includes(record.secret));
  const id = results[0].data.entry.id;
  assert.equal((await api(`/api/entries/${id}/reveal`, 'POST', {})).data.secret, record.secret);
  await api('/api/lock', 'POST', {});
  assert.equal((await api(`/api/entries/${id}/reveal`, 'POST', {})).status, 423);
  await api('/api/unlock', 'POST', {password});
  assert.equal((await api('/api/entries')).data.entries.length, 6);
  await assert.rejects(startServer({dataDir: app.vault.directory, port: 0}), /数据目录正在使用/);
});
test('quota sync uses official provider and rejects mismatched custom URLs', async t => {
  let calls = 0;
  const {api} = await fixture(t, {quotaFetcher: async (provider, secret) => {
    calls++; assert.equal(provider, 'deepseek'); assert.equal(secret, record.secret);
    return {kind: 'balance', fetchedAt: new Date().toISOString(), metrics: [{label: '总余额', value: '5.00', currency: 'CNY'}]};
  }});
  await api('/api/setup', 'POST', {password});
  const created = await api('/api/entries', 'POST', record); const id = created.data.entry.id;
  const synced = await api(`/api/entries/${id}/sync`, 'POST', {});
  assert.equal(synced.data.entry.quota.metrics[0].value, '5.00'); assert.equal(calls, 1);
  await api(`/api/entries/${id}`, 'PUT', {...record, baseUrl: 'https://custom-relay.example/v1'});
  assert.equal((await api(`/api/entries/${id}/sync`, 'POST', {})).status, 400); assert.equal(calls, 1);
});
test('failed sync preserves prior snapshot; restore rejects populated vault', async t => {
  let fail = false;
  const {app, api} = await fixture(t, {quotaFetcher: async () => {
    if (fail) throw new Error('额度查询暂不可用。');
    return {kind: 'balance', fetchedAt: '2026-09-22T00:00:00Z', metrics: [{label: '余额', value: '7', currency: 'CNY'}]};
  }});
  await api('/api/setup', 'POST', {password});
  const id = (await api('/api/entries', 'POST', record)).data.entry.id;
  await api(`/api/entries/${id}/sync`, 'POST', {}); fail = true;
  assert.equal((await api(`/api/entries/${id}/sync`, 'POST', {})).status, 502);
  assert.equal((await api('/api/entries')).data.entries[0].quota.metrics[0].value, '7');
  const backup = (await api('/api/backup')).data;
  const raw = await readFile(app.vault.file, 'utf8');
  assert.equal((await api('/api/restore', 'POST', {backup, password})).status, 409);
  assert.equal(await readFile(app.vault.file, 'utf8'), raw);
});
