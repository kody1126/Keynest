import { randomBytes, randomUUID, scrypt as scryptCallback, createCipheriv, createDecipheriv } from 'node:crypto';
import { promisify } from 'node:util';
import { mkdir, rename, chmod, lstat, unlink, open } from 'node:fs/promises';
import { constants as fsConstants } from 'node:fs';
import { performance } from 'node:perf_hooks';
import path from 'node:path';

const scrypt = promisify(scryptCallback);
const AAD = Buffer.from('api-vault-lab:v1:scrypt-131072-8-1:aes-256-gcm');
const MAX_FILE = 4 * 1024 * 1024;
const MAX_INPUT_URL = 1000;
// One UTF-16 code unit can expand to at most nine ASCII percent-encoding
// characters. Existing canonicalized URLs must survive future reads and edits.
const MAX_STORED_URL = MAX_INPUT_URL * 9;
const own = (o, k) => Object.prototype.hasOwnProperty.call(o, k);
export class VaultError extends Error {
  constructor(message, status = 400) { super(message); this.status = status; }
}
export function validatePassword(password) {
  if (typeof password !== 'string' || password.length < 12 || password.length > 1024) {
    throw new VaultError('主密码需要 12–1024 个字符。');
  }
}
function base64(value, bytes) {
  if (typeof value !== 'string' || !/^[A-Za-z0-9+/]+={0,2}$/.test(value)) throw new VaultError('备份文件格式不正确。');
  const buffer = Buffer.from(value, 'base64');
  if (buffer.toString('base64') !== value || (bytes && buffer.length !== bytes)) throw new VaultError('备份文件格式不正确。');
  return buffer;
}
export function validateEnvelope(input) {
  if (!input || typeof input !== 'object' || input.version !== 1 || input.cipher !== 'aes-256-gcm' || input.kdf !== 'scrypt-131072-8-1') {
    throw new VaultError('不支持的保险库文件格式。');
  }
  if (JSON.stringify(input).length > MAX_FILE) throw new VaultError('备份文件过大。');
  base64(input.salt, 32); base64(input.nonce, 12); base64(input.tag, 16); base64(input.data);
  return {version: 1, cipher: input.cipher, kdf: input.kdf, salt: input.salt, nonce: input.nonce, tag: input.tag, data: input.data};
}
async function derive(password, salt) {
  validatePassword(password);
  return scrypt(password, salt, 32, {N: 131072, r: 8, p: 1, maxmem: 256 * 1024 * 1024});
}
function seal(content, key, salt) {
  const nonce = randomBytes(12);
  const cipher = createCipheriv('aes-256-gcm', key, nonce);
  cipher.setAAD(AAD);
  const plain = Buffer.from(JSON.stringify(content));
  try {
    const data = Buffer.concat([cipher.update(plain), cipher.final()]);
    return {version: 1, cipher: 'aes-256-gcm', kdf: 'scrypt-131072-8-1', salt: salt.toString('base64'), nonce: nonce.toString('base64'), tag: cipher.getAuthTag().toString('base64'), data: data.toString('base64')};
  } finally { plain.fill(0); }
}
function recordFields(value, required, optional = []) {
  const allowed = new Set([...required, ...optional]);
  if (!value || typeof value !== 'object' || Array.isArray(value) ||
      required.some(field => !own(value, field)) || Object.keys(value).some(field => !allowed.has(field))) {
    throw new VaultError('保险库内容格式不正确。');
  }
}
function timestamp(value) {
  if (typeof value !== 'string' || value.length > 40 || !Number.isFinite(Date.parse(value))) {
    throw new VaultError('保险库时间格式不正确。');
  }
}
function validateQuota(quota) {
  recordFields(quota, ['kind', 'fetchedAt', 'metrics'], ['note']);
  if (!['balance', 'key_limit'].includes(quota.kind) || !Array.isArray(quota.metrics) ||
      quota.metrics.length < 1 || quota.metrics.length > 20) throw new VaultError('额度快照格式不正确。');
  timestamp(quota.fetchedAt);
  if (own(quota, 'note') && (typeof quota.note !== 'string' || quota.note.length > 1000)) throw new VaultError('额度快照格式不正确。');
  for (const metric of quota.metrics) {
    recordFields(metric, ['label', 'value', 'currency']);
    if (typeof metric.label !== 'string' || !metric.label || metric.label.length > 120 ||
        typeof metric.currency !== 'string' || !/^[A-Z]{3}$/.test(metric.currency)) throw new VaultError('额度快照格式不正确。');
    if (metric.value !== null && (typeof metric.value !== 'string' || metric.value.length > 128 ||
        !/^-?\d+(?:\.\d+)?(?:e[+-]?\d+)?$/i.test(metric.value) || !Number.isFinite(Number(metric.value)))) {
      throw new VaultError('额度快照数值格式不正确。');
    }
  }
}
function validateStoredEntry(entry) {
  recordFields(entry, ['id', 'name', 'provider', 'secret', 'baseUrl', 'tags', 'notes', 'createdAt', 'updatedAt'], ['quota']);
  if (typeof entry.id !== 'string' || !/^[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}$/.test(entry.id)) throw new VaultError('条目标识格式不正确。');
  for (const field of ['name', 'provider', 'secret', 'baseUrl', 'notes']) {
    if (typeof entry[field] !== 'string') throw new VaultError('条目格式不正确。');
  }
  const values = validateEntry(entry, undefined, {legacyURL: true});
  timestamp(entry.createdAt); timestamp(entry.updatedAt);
  if (own(entry, 'quota')) validateQuota(entry.quota);
  return {...entry, ...values};
}
async function decrypt(envelope, password) {
  const e = validateEnvelope(envelope);
  const key = await derive(password, base64(e.salt, 32));
  let plain;
  try {
    const decipher = createDecipheriv('aes-256-gcm', key, base64(e.nonce, 12));
    decipher.setAAD(AAD); decipher.setAuthTag(base64(e.tag, 16));
    plain = Buffer.concat([decipher.update(base64(e.data)), decipher.final()]);
    const content = JSON.parse(plain.toString('utf8'));
    recordFields(content, ['version', 'entries']);
    if (content.version !== 1 || !Array.isArray(content.entries) || content.entries.length > 2000) throw new Error('schema');
    const ids = new Set();
    content.entries = content.entries.map(entry => {
      const normalized = validateStoredEntry(entry);
      if (ids.has(entry.id)) throw new Error('schema');
      ids.add(entry.id);
      return normalized;
    });
    return {key, salt: base64(e.salt, 32), content};
  } catch {
    key.fill(0);
    throw new VaultError('密码不正确，或保险库文件已损坏。', 400);
  } finally { plain?.fill(0); }
}
function textField(value, label, max, fallback = '') {
  const v = value ?? fallback;
  if (typeof v !== 'string' || v.length > max) throw new VaultError(`${label}格式不正确或过长。`);
  return v;
}
export function validateEntry(input, current, {legacyURL = false} = {}) {
  if (!input || typeof input !== 'object' || Array.isArray(input)) throw new VaultError('条目格式不正确。');
  const name = textField(input.name, '名称', 120).trim();
  const provider = textField(input.provider, '服务商', 40);
  const secret = current && (!own(input, 'secret') || input.secret === '') ? current.secret : textField(input.secret, '密钥', 8192);
  if (!name || !provider || !secret.trim() || /[\r\n\0]/.test(secret)) throw new VaultError('请填写名称、服务商和有效密钥。');
  const preservingStoredURL = current && input.baseUrl === current.baseUrl;
  const urlLimit = legacyURL || preservingStoredURL ? MAX_STORED_URL : MAX_INPUT_URL;
  const rawUrl = textField(input.baseUrl, 'API 地址', urlLimit);
  const hasControls = /[\x00-\x1f\x7f]/.test(rawUrl);
  if (hasControls && !legacyURL) throw new VaultError('API 地址不能包含换行、制表符或其他控制字符。');
  let baseUrl = rawUrl.trim();
  if (baseUrl) {
    let url;
    try { url = new URL(baseUrl); } catch { throw new VaultError('API 地址需要完整的 http 或 https URL。'); }
    if (!['https:', 'http:'].includes(url.protocol) || url.username || url.password || url.search || url.hash) throw new VaultError('API 地址仅接受无凭据、无查询参数的 http 或 https URL。');
    // Older v1 writers accepted raw control characters that WHATWG URL silently
    // removes/encodes. Keep the key intact, but expose and re-save that URL in its
    // parsed form instead of returning the misleading original text.
    if (legacyURL && hasControls) baseUrl = url.href;
    if (baseUrl.length > urlLimit) throw new VaultError('API 地址格式不正确或过长。');
  }
  if (!Array.isArray(input.tags) || input.tags.length > 12 || input.tags.some(t => typeof t !== 'string' || t.length > 40)) throw new VaultError('标签最多 12 个，每个不超过 40 字符。');
  return {name, provider, secret, baseUrl, tags: [...new Set(input.tags.map(t => t.trim()).filter(Boolean))], notes: textField(input.notes, '备注', 4000)};
}
export function publicEntry(entry) {
  // A projection, not "everything except secret": imported/future fields must
  // never silently become browser-visible. List views need no token material.
  const {id, name, provider, baseUrl, tags, notes, createdAt, updatedAt, quota} = entry;
  return {id, name, provider, baseUrl, tags, notes, createdAt, updatedAt,
    ...(quota === undefined ? {} : {quota}), maskedSecret: '••••••••••••'};
}
export class Vault {
  // The HTTP server serializes every read/modify/write operation. Do not call
  // async mutations concurrently; lock() is deliberately synchronous.
  constructor(directory, {idleMs = 10 * 60 * 1000, now = Date.now, monotonicNow = () => performance.now()} = {}) {
    this.directory = path.resolve(directory); this.file = path.join(this.directory, 'vault.json');
    this.idleMs = idleMs; this.now = now; this.monotonicNow = monotonicNow; this.key = null; this.content = null; this.salt = null;
    this.initialized = false; this.lastActivity = 0; this.epoch = 0;
  }
  async init() {
    await mkdir(this.directory, {recursive: true, mode: 0o700});
    const dir = await lstat(this.directory);
    if (dir.isSymbolicLink() || !dir.isDirectory() ||
        (typeof process.geteuid === 'function' && dir.uid !== process.geteuid())) throw new VaultError('数据目录必须是当前用户拥有的普通目录，不能是符号链接。');
    await chmod(this.directory, 0o700);
    try {
      await this.readEnvelope(); this.initialized = true;
    } catch (e) { if (e.code !== 'ENOENT') throw e; }
  }
  async readEnvelope() {
    // Pin the file before checking or changing it. O_NONBLOCK ensures a swapped
    // FIFO cannot hang the process before its type is rejected by fstat.
    const handle = await open(this.file, fsConstants.O_RDONLY | fsConstants.O_NOFOLLOW | fsConstants.O_NONBLOCK);
    try {
      const info = await handle.stat();
      if (!info.isFile() || info.nlink !== 1 || info.size > MAX_FILE ||
          (typeof process.geteuid === 'function' && info.uid !== process.geteuid())) {
        throw new VaultError('保险库必须是当前用户独占的普通文件，且不能超过 4 MiB。');
      }
      await handle.chmod(0o600);
      const chunks = []; let size = 0;
      while (true) {
        const chunk = Buffer.alloc(Math.min(65536, MAX_FILE + 1 - size));
        const {bytesRead} = await handle.read(chunk, 0, chunk.length, null);
        if (!bytesRead) break;
        size += bytesRead;
        if (size > MAX_FILE) throw new VaultError('保险库文件超过 4 MiB。');
        chunks.push(chunk.subarray(0, bytesRead));
      }
      return validateEnvelope(JSON.parse(Buffer.concat(chunks, size).toString('utf8')));
    } finally { await handle.close(); }
  }
  locked() {
    if (this.key && this.monotonicNow() - this.lastActivity >= this.idleMs) this.lock();
    return !this.key;
  }
  status() { return {initialized: this.initialized, locked: this.locked(), idleMinutes: this.idleMs / 60000}; }
  requireUnlocked() { if (this.locked()) throw new VaultError('保险库已锁定，请重新输入主密码。', 423); }
  touch() { this.requireUnlocked(); this.lastActivity = this.monotonicNow(); }
  lock() { this.epoch++; this.key?.fill(0); this.key = null; this.salt = null; this.content = null; }
  async write(envelope) {
    const temporary = path.join(this.directory, `.vault-${randomUUID()}.tmp`);
    try {
      const handle = await open(temporary, 'wx', 0o600);
      try { await handle.writeFile(JSON.stringify(envelope)); await handle.sync(); } finally { await handle.close(); }
      await rename(temporary, this.file);
    } finally { await unlink(temporary).catch(() => {}); }
  }
  async setup(password) {
    if (this.initialized) throw new VaultError('保险库已经存在。', 409);
    const epoch = this.epoch;
    const salt = randomBytes(32); const key = await derive(password, salt);
    const content = {version: 1, entries: []};
    try {
      if (epoch !== this.epoch) throw new VaultError('操作已取消，请重试。', 409);
      await this.write(seal(content, key, salt));
      this.initialized = true;
      if (epoch === this.epoch) { this.key = key; this.salt = salt; this.content = content; this.lastActivity = this.monotonicNow(); }
      else key.fill(0);
    } catch (e) { key.fill(0); throw e; }
  }
  async unlock(password) {
    if (!this.initialized) throw new VaultError('请先创建保险库。', 409);
    const epoch = this.epoch;
    const unlocked = await decrypt(await this.readEnvelope(), password);
    if (epoch !== this.epoch) { unlocked.key.fill(0); throw new VaultError('解锁已取消。', 409); }
    this.key?.fill(0); Object.assign(this, unlocked); this.lastActivity = this.monotonicNow();
  }
  entries() { this.requireUnlocked(); return this.content.entries.map(publicEntry); }
  get(id) {
    this.requireUnlocked(); const entry = this.content.entries.find(e => e.id === id);
    if (!entry) throw new VaultError('找不到这条密钥。', 404);
    return entry;
  }
  async commit(entries) {
    this.requireUnlocked();
    const epoch = this.epoch;
    const next = {version: 1, entries};
    const sealed = seal(next, this.key, this.salt);
    if (JSON.stringify(sealed).length > MAX_FILE) throw new VaultError('保险库已达到实验版容量上限。');
    await this.write(sealed);
    if (epoch === this.epoch && this.key) this.content = next;
  }
  async upsert(input, id) {
    this.touch();
    const current = id ? this.get(id) : null;
    if (!current && this.content.entries.length >= 2000) throw new VaultError('实验版最多保存 2000 条密钥。');
    const values = validateEntry(input, current);
    const stamp = new Date(this.now()).toISOString();
    const changedCredential = current && (values.provider !== current.provider || values.secret !== current.secret || values.baseUrl !== current.baseUrl);
    const entry = {...current, ...values, id: current?.id ?? randomUUID(), createdAt: current?.createdAt ?? stamp, updatedAt: stamp};
    if (changedCredential) delete entry.quota;
    await this.commit(current ? this.content.entries.map(e => e.id === id ? entry : e) : [...this.content.entries, entry]);
    return publicEntry(entry);
  }
  async remove(id) { this.touch(); this.get(id); await this.commit(this.content.entries.filter(e => e.id !== id)); }
  async quota(id, quota, expectedSecret) {
    const current = this.get(id);
    if (current.secret !== expectedSecret) throw new VaultError('密钥已更改，请重新同步。', 409);
    validateQuota(quota);
    const entry = {...current, quota};
    await this.commit(this.content.entries.map(e => e.id === id ? entry : e));
    return publicEntry(entry);
  }
  async backup() { this.touch(); return this.readEnvelope(); }
  async restore(backup, password) {
    if (this.initialized) {
      this.requireUnlocked();
      if (this.content.entries.length) throw new VaultError('仅空保险库可以恢复备份，现有条目不会被覆盖。', 409);
    }
    const epoch = this.epoch;
    const e = validateEnvelope(backup);
    const unlocked = await decrypt(e, password);
    let normalized;
    try { normalized = seal(unlocked.content, unlocked.key, unlocked.salt); }
    finally { unlocked.key.fill(0); }
    validateEnvelope(normalized);
    if (epoch !== this.epoch) throw new VaultError('恢复已取消，保险库已锁定。', 423);
    await this.write(normalized); this.initialized = true; this.lock();
  }
}
