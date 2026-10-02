const MAX_RESPONSE_BYTES = 1024 * 1024;
const TIMEOUT_MS = 10_000;

// Public API references checked 2026-09-22. No console cookies or private APIs.
// https://api-docs.deepseek.com/api/get-user-balance/
// https://github.com/siliconflow/siliconcloud/blob/main/openapi.yaml
// https://openrouter.ai/docs/api_reference/limits
export const providers = Object.freeze([
  { id: 'generic', name: '其他服务', quotaKind: null, endpoint: null, description: '本地收藏密钥与接口信息。' },
  { id: 'deepseek', name: 'DeepSeek', quotaKind: 'balance', endpoint: 'https://api.deepseek.com/user/balance', description: '用此密钥向 DeepSeek 官方查询账户余额。' },
  { id: 'siliconflow', name: '硅基流动', quotaKind: 'balance', endpoint: 'https://api.siliconflow.cn/v1/user/info', description: '用此密钥向硅基流动中国站查询账户总余额。' },
  { id: 'openrouter', name: 'OpenRouter', quotaKind: 'key_limit', endpoint: 'https://openrouter.ai/api/v1/key', description: '查询此 Key 的消费限额和用量；账户余额需要单独的管理权限。' },
  { id: 'openai', name: 'OpenAI', quotaKind: null, endpoint: null, description: '本地收藏；本版未接入组织用量查询。' },
  { id: 'anthropic', name: 'Anthropic', quotaKind: null, endpoint: null, description: '本地收藏；组织用量查询需要额外权限。' },
  { id: 'gemini', name: 'Google Gemini', quotaKind: null, endpoint: null, description: '本地收藏；项目配额与账单查询需要额外权限。' },
  { id: 'moonshot', name: 'Moonshot / Kimi', quotaKind: null, endpoint: null, description: '本地收藏；本版暂未接入余额查询。' },
  { id: 'dashscope', name: '阿里云百炼', quotaKind: null, endpoint: null, description: '本地收藏；阿里云账户余额查询需要单独的财务权限。' },
].map((provider) => Object.freeze(provider)));

export class QuotaError extends Error {}

function invalidResponse() {
  return new QuotaError('服务商返回的数据格式不符合预期，未更新额度。');
}

function object(value) {
  if (value === null || typeof value !== 'object' || Array.isArray(value)) throw invalidResponse();
  return value;
}

function decimal(value) {
  // Retain monetary strings exactly; never turn missing values into zero.
  if (typeof value !== 'string' || value.length > 128 || !/^-?\d+(?:\.\d+)?$/.test(value)) throw invalidResponse();
  return value;
}

function numeric(value, { nullable = false, nonnegative = false } = {}) {
  if (nullable && value === null) return null;
  if (typeof value !== 'number' || !Number.isFinite(value) || (nonnegative && value < 0)) throw invalidResponse();
  return String(value);
}

function deepseek(data) {
  object(data);
  if (typeof data.is_available !== 'boolean' || !Array.isArray(data.balance_infos) || data.balance_infos.length < 1 || data.balance_infos.length > 2) throw invalidResponse();
  const currencies = new Set();
  const metrics = data.balance_infos.flatMap((item) => {
    object(item);
    if (!['CNY', 'USD'].includes(item.currency) || currencies.has(item.currency)) throw invalidResponse();
    currencies.add(item.currency);
    return [
      { label: '账户总余额', value: decimal(item.total_balance), currency: item.currency },
      { label: '赠送余额', value: decimal(item.granted_balance), currency: item.currency },
      { label: '充值余额', value: decimal(item.topped_up_balance), currency: item.currency },
    ];
  });
  return {
    kind: 'balance', metrics,
    note: data.is_available ? '账户余额快照；不同币种分别展示。' : '服务商报告当前账户余额不足，无法调用 API。',
  };
}

function siliconflow(data) {
  object(data);
  if (data.code !== 20000 || data.status !== true) throw invalidResponse();
  const info = object(data.data);
  // Only totalBalance is used. Do not retain the accompanying account profile.
  return {
    kind: 'balance',
    metrics: [{ label: '账户总余额', value: decimal(info.totalBalance), currency: 'CNY' }],
    note: '硅基流动中国站账户总余额快照。',
  };
}

function openrouter(data) {
  const info = object(object(data).data);
  const remaining = numeric(info.limit_remaining, { nullable: true });
  const limit = numeric(info.limit, { nullable: true, nonnegative: true });
  if ((remaining === null) !== (limit === null)) throw invalidResponse();
  const metrics = [
    { label: remaining === null ? '未设置 Key 上限' : 'Key 限额剩余', value: remaining, currency: 'USD' },
    { label: 'Key 消费上限', value: limit, currency: 'USD' },
    { label: '累计消费', value: numeric(info.usage, { nonnegative: true }), currency: 'USD' },
    { label: '今日消费（UTC）', value: numeric(info.usage_daily, { nonnegative: true }), currency: 'USD' },
    { label: '本周消费（UTC）', value: numeric(info.usage_weekly, { nonnegative: true }), currency: 'USD' },
    { label: '本月消费（UTC）', value: numeric(info.usage_monthly, { nonnegative: true }), currency: 'USD' },
  ];
  return {
    kind: 'key_limit', metrics,
    note: remaining === null
      ? '未设置 Key 上限；账户仍受实际余额限制。此接口不返回账户余额。'
      : '此处为单个 Key 的消费限额，不是账户余额；正在处理的请求可能尚未结算。',
  };
}

const adapters = new Map([['deepseek', deepseek], ['siliconflow', siliconflow], ['openrouter', openrouter]]);

async function readJson(response, signal) {
  const contentLength = response.headers.get('content-length');
  if (contentLength && /^\d+$/.test(contentLength) && Number(contentLength) > MAX_RESPONSE_BYTES) {
    if (response.body) void response.body.cancel().catch(() => {});
    throw new QuotaError('服务商响应超过 1 MiB，已停止读取。');
  }
  if (!response.body) throw invalidResponse();
  const reader = response.body.getReader();
  const cancel = () => { void reader.cancel().catch(() => {}); };
  signal.addEventListener('abort', cancel, { once: true });
  const chunks = [];
  let bytes = 0;
  try {
    while (true) {
      signal.throwIfAborted();
      const { done, value } = await reader.read();
      signal.throwIfAborted();
      if (done) break;
      bytes += value.byteLength;
      if (bytes > MAX_RESPONSE_BYTES) {
        cancel();
        throw new QuotaError('服务商响应超过 1 MiB，已停止读取。');
      }
      chunks.push(value);
    }
    const buffer = Buffer.concat(chunks, bytes);
    try {
      return JSON.parse(new TextDecoder('utf-8', { fatal: true }).decode(buffer));
    } catch {
      throw invalidResponse();
    }
  } finally {
    signal.removeEventListener('abort', cancel);
    reader.releaseLock();
  }
}

export async function fetchQuota(providerId, secret, { fetchImpl = globalThis.fetch } = {}) {
  const provider = providers.find((item) => item.id === providerId);
  const adapter = adapters.get(providerId);
  if (!provider || !adapter) throw new QuotaError('此服务商目前仅支持收藏，尚未接入额度查询。');
  if (typeof secret !== 'string' || secret.length < 1 || secret.length > 8192 || /[\s\x00-\x1f\x7f]/.test(secret)) {
    throw new QuotaError('密钥格式无效，请检查后重试。');
  }
  const controller = new AbortController();
  let timer;
  const deadline = new Promise((_, reject) => {
    timer = setTimeout(() => {
      reject(new QuotaError('额度查询超过 10 秒，已停止请求。'));
      controller.abort();
    }, TIMEOUT_MS);
  });
  try {
    const operation = async () => {
      const response = await fetchImpl(provider.endpoint, {
        method: 'GET',
        headers: { Authorization: `Bearer ${secret}`, Accept: 'application/json' },
        redirect: 'error',
        credentials: 'omit',
        cache: 'no-store',
        signal: controller.signal,
      });
      controller.signal.throwIfAborted();
      if (response.redirected || (response.status >= 300 && response.status < 400)) {
        throw new QuotaError('服务商返回重定向，已拒绝转发密钥。');
      }
      if (!response.ok) {
        if (response.body) void response.body.cancel().catch(() => {});
        if (response.status === 401 || response.status === 403) throw new QuotaError('密钥无效或无权查询，请检查服务商与密钥。');
        if (response.status === 429) throw new QuotaError('服务商限制了查询频率，请稍后重试。');
        throw new QuotaError('服务商暂时无法完成额度查询，请稍后重试。');
      }
      const result = adapter(await readJson(response, controller.signal));
      return { ...result, fetchedAt: new Date().toISOString() };
    };
    return await Promise.race([operation(), deadline]);
  } catch (error) {
    if (error instanceof QuotaError) throw error;
    // Transport, upstream and parsing errors can contain credentials or URLs.
    throw new QuotaError('额度查询失败，请检查网络连接及服务商状态。');
  } finally {
    clearTimeout(timer);
    controller.abort();
  }
}
