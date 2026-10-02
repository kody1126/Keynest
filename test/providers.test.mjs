import test from 'node:test';
import assert from 'node:assert/strict';
import { providers, fetchQuota, QuotaError } from '../src/providers.mjs';

const SECRET = 'test-secret-never-send-to-a-real-provider';
const deepseek = {
  is_available: true,
  balance_infos: [{ currency: 'CNY', total_balance: '110.00100', granted_balance: '10.00100', topped_up_balance: '100.00' }],
};
const siliconflow = { code: 20000, message: 'OK', status: true, data: { totalBalance: '88.88', balance: '0.88', chargeBalance: '88.00', email: 'private@example.test', name: 'Private Name' } };
const openrouter = { data: { limit: 100, limit_remaining: 74.5, usage: 25.5, usage_daily: 1.1, usage_weekly: 3.3, usage_monthly: 20.2, label: SECRET } };
const response = (data, options) => new Response(JSON.stringify(data), { headers: { 'content-type': 'application/json' }, ...options });
const mockFetch = (data) => async () => response(data);

test('only three adapters have immutable fixed official HTTPS endpoints', () => {
  assert.deepEqual(providers.filter((provider) => provider.endpoint).map((provider) => provider.id), ['deepseek', 'siliconflow', 'openrouter']);
  assert(Object.isFrozen(providers));
  for (const provider of providers) assert(Object.isFrozen(provider));
  for (const id of ['generic', 'openai', 'anthropic', 'gemini', 'moonshot', 'dashscope']) {
    assert.equal(providers.find((provider) => provider.id === id).endpoint, null);
  }
});

for (const [id, endpoint, fixture] of [
  ['deepseek', 'https://api.deepseek.com/user/balance', deepseek],
  ['siliconflow', 'https://api.siliconflow.cn/v1/user/info', siliconflow],
  ['openrouter', 'https://openrouter.ai/api/v1/key', openrouter],
]) {
  test(`${id} sends one request only to its official endpoint and disables redirects`, async () => {
    let calls = 0;
    const quota = await fetchQuota(id, SECRET, { fetchImpl: async (url, options) => {
      calls++;
      assert.equal(url, endpoint);
      assert.equal(options.method, 'GET');
      assert.equal(options.redirect, 'error');
      assert.equal(options.credentials, 'omit');
      assert.equal(options.cache, 'no-store');
      assert.equal(options.headers.Authorization, `Bearer ${SECRET}`);
      assert.equal(options.headers.Accept, 'application/json');
      assert(options.signal instanceof AbortSignal);
      assert.equal(options.signal.aborted, false);
      return response(fixture);
    } });
    assert.equal(calls, 1);
    assert(Number.isFinite(Date.parse(quota.fetchedAt)));
    assert.equal(JSON.stringify(quota).includes(SECRET), false);
  });
}

test('DeepSeek retains decimal precision and separates each currency', async () => {
  const fixture = structuredClone(deepseek);
  fixture.balance_infos.push({ currency: 'USD', total_balance: '2.1234567890123456789', granted_balance: '0', topped_up_balance: '2.1234567890123456789' });
  const quota = await fetchQuota('deepseek', SECRET, { fetchImpl: mockFetch(fixture) });
  assert.equal(quota.kind, 'balance');
  assert.equal(quota.metrics.length, 6);
  assert.equal(quota.metrics[0].value, '110.00100');
  assert.equal(quota.metrics[3].value, '2.1234567890123456789');
  assert.equal(quota.metrics[3].currency, 'USD');
});

test('DeepSeek unavailable status remains visible without replacing the amount', async () => {
  const quota = await fetchQuota('deepseek', SECRET, { fetchImpl: mockFetch({ ...deepseek, is_available: false }) });
  assert.match(quota.note, /余额不足/);
  assert.equal(quota.metrics[0].value, '110.00100');
});

test('SiliconFlow uses totalBalance and discards the account profile', async () => {
  const quota = await fetchQuota('siliconflow', SECRET, { fetchImpl: mockFetch(siliconflow) });
  assert.deepEqual(quota.metrics, [{ label: '账户总余额', value: '88.88', currency: 'CNY' }]);
  assert.equal(JSON.stringify(quota).includes('private@example.test'), false);
  assert.equal(JSON.stringify(quota).includes('Private Name'), false);
});

test('OpenRouter distinguishes key limit from account balance', async () => {
  const quota = await fetchQuota('openrouter', SECRET, { fetchImpl: mockFetch(openrouter) });
  assert.equal(quota.kind, 'key_limit');
  assert.equal(quota.metrics[0].label, 'Key 限额剩余');
  assert.equal(quota.metrics[0].value, '74.5');
  assert.match(quota.note, /不是账户余额/);
});

test('OpenRouter null means no key cap, never unlimited account credit', async () => {
  const quota = await fetchQuota('openrouter', SECRET, { fetchImpl: mockFetch({ data: { ...openrouter.data, limit: null, limit_remaining: null } }) });
  assert.equal(quota.metrics[0].value, null);
  assert.equal(quota.metrics[0].label, '未设置 Key 上限');
  assert.equal(quota.metrics[1].value, null);
  assert.match(quota.note, /仍受实际余额限制/);
});

test('a zero balance or limit is valid, missing fields are not zero', async () => {
  const sf = await fetchQuota('siliconflow', SECRET, { fetchImpl: mockFetch({ ...siliconflow, data: { totalBalance: '0' } }) });
  assert.equal(sf.metrics[0].value, '0');
  const or = await fetchQuota('openrouter', SECRET, { fetchImpl: mockFetch({ data: { ...openrouter.data, limit: 0, limit_remaining: 0 } }) });
  assert.equal(or.metrics[0].value, '0');
});

test('missing, null, wrongly typed, duplicate and malformed schemas are rejected', async () => {
  for (const [id, fixture] of [
    ['deepseek', null],
    ['deepseek', { ...deepseek, is_available: 'true' }],
    ['deepseek', { ...deepseek, balance_infos: [] }],
    ['deepseek', { ...deepseek, balance_infos: [deepseek.balance_infos[0], deepseek.balance_infos[0]] }],
    ['deepseek', { ...deepseek, balance_infos: [{ ...deepseek.balance_infos[0], total_balance: 110 }] }],
    ['deepseek', { ...deepseek, balance_infos: [{ ...deepseek.balance_infos[0], currency: 'XYZ' }] }],
    ['deepseek', { ...deepseek, balance_infos: [{ ...deepseek.balance_infos[0], granted_balance: undefined }] }],
    ['siliconflow', { ...siliconflow, data: { balance: '1', chargeBalance: '2' } }],
    ['siliconflow', { ...siliconflow, data: { totalBalance: null } }],
    ['siliconflow', { ...siliconflow, data: { totalBalance: 'NaN' } }],
    ['siliconflow', { ...siliconflow, status: false }],
    ['siliconflow', { ...siliconflow, code: 20012 }],
    ['openrouter', { data: { ...openrouter.data, limit_remaining: undefined } }],
    ['openrouter', { data: { ...openrouter.data, limit_remaining: '74.5' } }],
    ['openrouter', { data: { ...openrouter.data, limit: null } }],
    ['openrouter', { data: { ...openrouter.data, usage: -1 } }],
    ['openrouter', { data: { ...openrouter.data, usage_monthly: undefined } }],
  ]) {
    await assert.rejects(fetchQuota(id, SECRET, { fetchImpl: mockFetch(fixture) }), /数据格式/);
  }
});

test('unsupported providers and invalid credentials fail before any network request', async () => {
  let calls = 0;
  const fetchImpl = async () => { calls++; throw new Error(SECRET); };
  for (const id of ['generic', 'openai', 'unknown', '__proto__']) {
    await assert.rejects(fetchQuota(id, SECRET, { fetchImpl }), /仅支持收藏/);
  }
  for (const secret of ['', null, 'contains\nnewline', 'contains space', 'x'.repeat(8193)]) {
    await assert.rejects(fetchQuota('deepseek', secret, { fetchImpl }), /密钥格式/);
  }
  assert.equal(calls, 0);
});

test('upstream and network errors never surface upstream text or credentials', async () => {
  for (const status of [401, 403, 429, 500]) {
    await assert.rejects(fetchQuota('deepseek', SECRET, { fetchImpl: async () => new Response(`${SECRET} private upstream body`, { status }) }), (error) => {
      assert.equal(error.message.includes(SECRET), false);
      assert.equal(error.message.includes('upstream'), false);
      return true;
    });
  }
  await assert.rejects(fetchQuota('deepseek', SECRET, { fetchImpl: async () => { throw new Error(`https://evil.test/?key=${SECRET}`); } }), (error) => {
    assert(error instanceof QuotaError);
    assert.equal(error.message, '额度查询失败，请检查网络连接及服务商状态。');
    return true;
  });
});

test('redirect responses are rejected even when a mock ignores fetch options', async () => {
  await assert.rejects(fetchQuota('deepseek', SECRET, { fetchImpl: async () => new Response(null, { status: 302, headers: { Location: 'https://evil.test/' } }) }), /拒绝转发密钥/);
  await assert.rejects(fetchQuota('deepseek', SECRET, { fetchImpl: async () => ({ redirected: true, status: 200 }) }), /拒绝转发密钥/);
});

test('malformed JSON and invalid UTF-8 produce a sanitized schema error', async () => {
  for (const body of [`invalid json ${SECRET}`, new Uint8Array([0xc0, 0xaf])]) {
    await assert.rejects(fetchQuota('deepseek', SECRET, { fetchImpl: async () => new Response(body) }), (error) => {
      assert.match(error.message, /数据格式/);
      assert.equal(error.message.includes(SECRET), false);
      return true;
    });
  }
});

test('oversize content-length is rejected before reading and body is cancelled', async () => {
  let cancelled = false;
  const body = new ReadableStream({ cancel() { cancelled = true; } });
  await assert.rejects(fetchQuota('deepseek', SECRET, { fetchImpl: async () => new Response(body, { headers: { 'content-length': String(1024 * 1024 + 1) } }) }), /超过 1 MiB/);
  assert.equal(cancelled, true);
});

test('actual streamed bytes are capped even if the server lies about length', async () => {
  let cancelled = false;
  const body = new ReadableStream({
    start(controller) {
      controller.enqueue(new Uint8Array(1024 * 1024));
      controller.enqueue(new Uint8Array(1));
    },
    cancel() { cancelled = true; },
  });
  await assert.rejects(fetchQuota('deepseek', SECRET, { fetchImpl: async () => new Response(body, { headers: { 'content-length': '1' } }) }), /超过 1 MiB/);
  assert.equal(cancelled, true);
});

test('10 second deadline aborts a request that never responds', async (t) => {
  t.mock.timers.enable({ apis: ['setTimeout'] });
  let signal;
  const pending = fetchQuota('deepseek', SECRET, { fetchImpl: async (_url, options) => {
    signal = options.signal;
    return new Promise(() => {});
  } });
  t.mock.timers.tick(10_000);
  await assert.rejects(pending, /超过 10 秒/);
  assert.equal(signal.aborted, true);
});

test('10 second deadline also covers a stalled response body', async (t) => {
  t.mock.timers.enable({ apis: ['setTimeout'] });
  let cancelled = false;
  const pending = fetchQuota('deepseek', SECRET, { fetchImpl: async () => new Response(new ReadableStream({ cancel() { cancelled = true; } })) });
  await Promise.resolve();
  await Promise.resolve();
  t.mock.timers.tick(10_000);
  await assert.rejects(pending, /超过 10 秒/);
  assert.equal(cancelled, true);
});
