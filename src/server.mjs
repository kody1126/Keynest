import http from 'node:http';
import { randomBytes, timingSafeEqual } from 'node:crypto';
import { readFile, open, unlink } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { performance } from 'node:perf_hooks';
import { Vault, VaultError } from './vault.mjs';
import { providers, fetchQuota, QuotaError } from './providers.mjs';

const ROOT = fileURLToPath(new URL('../', import.meta.url));
const BODY_LIMIT = 5 * 1024 * 1024;
const staticFiles = {'/': ['index.html', 'text/html; charset=utf-8'], '/app.js': ['app.js', 'text/javascript; charset=utf-8'], '/style.css': ['style.css', 'text/css; charset=utf-8']};
function same(a, b) {
  const left = Buffer.from(a ?? ''); const right = Buffer.from(b);
  return left.length === right.length && timingSafeEqual(left, right);
}
async function body(req) {
  if (req.headers['content-type']?.split(';')[0] !== 'application/json') throw new VaultError('请求需要 JSON 格式。', 415);
  if (Number(req.headers['content-length']) > BODY_LIMIT) throw new VaultError('请求文件过大。', 413);
  let size = 0; const chunks = [];
  for await (const chunk of req) {
    size += chunk.length;
    if (size > BODY_LIMIT) throw new VaultError('请求文件过大。', 413);
    chunks.push(chunk);
  }
  try {
    const value = JSON.parse(Buffer.concat(chunks).toString('utf8'));
    if (!value || typeof value !== 'object' || Array.isArray(value)) throw new Error();
    return value;
  } catch { throw new VaultError('JSON 格式不正确。'); }
}
export async function startServer({dataDir = path.join(ROOT, '.data'), port = 43127, token = randomBytes(32).toString('hex'), idleMs = 600000, monotonicNow = () => performance.now(), quotaFetcher = fetchQuota} = {}) {
  const vault = new Vault(dataDir, {idleMs, monotonicNow});
  await vault.init();
  const lockFile = path.join(vault.directory, 'process.lock');
  let handle;
  try {
    handle = await open(lockFile, 'wx', 0o600);
    await handle.writeFile(String(process.pid));
    await handle.close();
  } catch (e) {
    if (e.code === 'EEXIST') throw new VaultError(`数据目录正在使用，或上次异常退出留下 process.lock。确认没有其他实例后再删除锁文件。`);
    throw e;
  }
  let origin, host, chain = Promise.resolve(), pending = 0, failures = 0, retryAt = 0, closed = false;
  const timer = setInterval(() => vault.locked(), Math.min(idleMs, 1000)); timer.unref();
  function json(res, value, status = 200) { res.writeHead(status, {'Content-Type': 'application/json; charset=utf-8'}); res.end(JSON.stringify(value)); }
  async function route(req, res, url, data) {
    const method = req.method;
    if (method === 'GET' && url === '/api/status') return json(res, vault.status());
    if (method === 'GET' && url === '/api/providers') return json(res, {providers});
    if (method === 'POST' && ['/api/setup', '/api/unlock', '/api/restore'].includes(url)) {
      if (monotonicNow() < retryAt) { res.setHeader('Retry-After', Math.ceil((retryAt - monotonicNow()) / 1000)); throw new VaultError('请稍后再尝试解锁或恢复。', 429); }
      try {
        if (url === '/api/setup') await vault.setup(data.password);
        if (url === '/api/unlock') await vault.unlock(data.password);
        if (url === '/api/restore') await vault.restore(data.backup, data.password);
        failures = 0; retryAt = 0;
        return json(res, {ok: true});
      } catch (e) {
        failures++; retryAt = monotonicNow() + Math.min(30000, 500 * 2 ** Math.min(failures, 6));
        throw e;
      }
    }
    if (method === 'POST' && url === '/api/lock') { vault.lock(); return json(res, {ok: true}); }
    if (method === 'POST' && url === '/api/activity') { vault.touch(); return json(res, {ok: true}); }
    if (method === 'GET' && url === '/api/entries') return json(res, {entries: vault.entries()});
    if (method === 'GET' && url === '/api/backup') return json(res, await vault.backup());
    if (method === 'POST' && url === '/api/entries') {
      if (!providers.some(p => p.id === data.provider)) throw new VaultError('请选择已知服务商或通用密钥。');
      return json(res, {entry: await vault.upsert(data)}, 201);
    }
    const match = /^\/api\/entries\/([0-9a-f-]{36})(?:\/(reveal|sync))?$/.exec(url);
    if (match) {
      const [, id, action] = match;
      if (!action && method === 'PUT') {
        if (!providers.some(p => p.id === data.provider)) throw new VaultError('请选择已知服务商或通用密钥。');
        return json(res, {entry: await vault.upsert(data, id)});
      }
      if (!action && method === 'DELETE') { await vault.remove(id); return json(res, {ok: true}); }
      if (action === 'reveal' && method === 'POST') { vault.touch(); return json(res, {secret: vault.get(id).secret}); }
      if (action === 'sync' && method === 'POST') {
        // Polling never extends the unlock session. Only explicit user activity does.
        const entry = vault.get(id);
        const provider = providers.find(p => p.id === entry.provider);
        if (!provider?.endpoint) throw new VaultError('此服务商暂不支持额度同步。');
        if (entry.baseUrl && new URL(entry.baseUrl).origin !== new URL(provider.endpoint).origin) throw new VaultError('自定义 API 地址暂不支持额度同步；只允许向所选服务商的官方域名发送密钥。');
        const epoch = vault.epoch;
        let quota;
        try { quota = await quotaFetcher(entry.provider, entry.secret); }
        catch (e) { throw new VaultError(e instanceof QuotaError ? e.message : '额度查询失败，请稍后重试。', 502); }
        if (vault.epoch !== epoch) throw new VaultError('保险库已锁定，本次查询结果未保存。', 423);
        return json(res, {entry: await vault.quota(id, quota, entry.secret)});
      }
    }
    throw new VaultError('接口不存在。', 404);
  }
  const server = http.createServer(async (req, res) => {
    res.setHeader('Cache-Control', 'no-store');
    res.setHeader('X-Content-Type-Options', 'nosniff');
    res.setHeader('Referrer-Policy', 'no-referrer');
    res.setHeader('X-Frame-Options', 'DENY');
    res.setHeader('Content-Security-Policy', "default-src 'none'; script-src 'self'; style-src 'self'; connect-src 'self'; img-src 'self' data:; base-uri 'none'; frame-ancestors 'none'; form-action 'none'");
    res.setHeader('Permissions-Policy', 'camera=(), microphone=(), geolocation=()');
    try {
      if (req.headers.host !== host || (req.headers.origin && req.headers.origin !== origin) || !['127.0.0.1', '::ffff:127.0.0.1'].includes(req.socket.remoteAddress)) throw new VaultError('只允许来自本机页面的请求。', 403);
      const url = req.url;
      if (staticFiles[url] && req.method === 'GET') {
        const [name, type] = staticFiles[url];
        res.writeHead(200, {'Content-Type': type}); res.end(await readFile(path.join(ROOT, 'public', name))); return;
      }
      if (!url?.startsWith('/api/')) throw new VaultError('页面不存在。', 404);
      if (req.headers['sec-fetch-site'] && !['same-origin', 'none'].includes(req.headers['sec-fetch-site'])) throw new VaultError('跨站请求被拒绝。', 403);
      if (!same(req.headers.authorization, `Bearer ${token}`)) throw new VaultError('启动会话已失效，请从终端重新打开完整启动链接。', 401);
      if (!['GET', 'POST', 'PUT', 'DELETE'].includes(req.method)) throw new VaultError('不支持此请求方法。', 405);
      // Lock must never wait behind slow provider requests. Invalidate all
      // already queued work so a stale unlock/reveal cannot reopen the vault.
      if (url === '/api/lock' && req.method === 'POST') {
        await body(req); vault.lock(); json(res, {ok: true}); return;
      }
      if (pending >= 20) throw new VaultError('请求过多，请稍后再试。', 429);
      pending++;
      const requestEpoch = vault.epoch;
      try {
        const data = ['POST', 'PUT'].includes(req.method) ? await body(req) : {};
        const task = chain.then(() => {
          if (requestEpoch !== vault.epoch && !['/api/status', '/api/providers'].includes(url)) throw new VaultError('操作已取消，保险库已锁定。', 423);
          return route(req, res, url, data);
        });
        chain = task.catch(() => {});
        await task;
      } finally { pending--; }
    } catch (e) {
      if (!res.headersSent) json(res, {error: e instanceof VaultError ? e.message : '本地操作失败，请检查数据目录权限或稍后重试。'}, e instanceof VaultError ? e.status : 500);
      else res.end();
    }
  });
  server.requestTimeout = 15000; server.headersTimeout = 10000; server.keepAliveTimeout = 1000;
  async function cleanup() {
    if (closed) return;
    closed = true; clearInterval(timer); vault.lock();
    await chain.catch(() => {}); await unlink(lockFile).catch(() => {});
  }
  try {
    await new Promise((resolve, reject) => {
      server.once('error', reject); server.listen(port, '127.0.0.1', resolve);
    });
  } catch (e) { await cleanup(); throw e; }
  host = `127.0.0.1:${server.address().port}`; origin = `http://${host}`;
  return {server, vault, origin, token, url: `${origin}/#token=${token}`, async close() {
    server.closeAllConnections();
    await new Promise(resolve => server.close(resolve));
    await cleanup();
  }};
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  try {
    const port = Number(process.env.API_VAULT_PORT || 43127);
    if (!Number.isInteger(port) || port < 1024 || port > 65535) throw new Error('invalid port');
    const app = await startServer({port, dataDir: process.env.API_VAULT_DATA_DIR || path.join(ROOT, '.data')});
    console.log(`\nAPI Vault Lab · 本地实验版\n在浏览器打开以下本机链接：\n${app.url}\n\n数据：${app.vault.file}\n此启动链接仅用于本机页面会话，请勿分享。按 Ctrl+C 停止。\n`);
    for (const signal of ['SIGINT', 'SIGTERM']) process.once(signal, async () => { await app.close(); process.exit(0); });
  } catch { console.error('启动失败：检查端口、数据目录权限，或是否已有实例占用。异常退出后需确认没有运行实例，再移除数据目录的 process.lock。'); process.exitCode = 1; }
}
