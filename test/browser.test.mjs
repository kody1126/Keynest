import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import vm from 'node:vm';

const source = await readFile(new URL('../public/app.js', import.meta.url), 'utf8');
const markup = await readFile(new URL('../public/index.html', import.meta.url), 'utf8');
const secret = 'browser-test-only-not-a-real-key';
const entry = {id: '11111111-1111-4111-8111-111111111111', name: 'Private fixture name', provider: 'generic',
  maskedSecret: '••••••••••••', baseUrl: '', tags: [], notes: 'Private fixture notes', createdAt: '2026-01-01T00:00:00Z'};
const deferred = () => { let resolve; const promise = new Promise(r => { resolve = r; }); return {promise, resolve}; };
const tick = () => new Promise(resolve => setImmediate(resolve));

// Run the actual browser script against a minimal DOM and controlled network.
// There is no HTTP listener, browser profile, clipboard or real credential here.
async function browser({locked = false, entriesGate, unlockGate, revealGate, clock} = {}) {
  class Events {
    listeners = new Map();
    addEventListener(type, listener) {
      if (!this.listeners.has(type)) this.listeners.set(type, []);
      this.listeners.get(type).push(listener);
    }
    emit(type, event = {}) {
      return Promise.all((this.listeners.get(type) || []).map(listener => listener({preventDefault() {}, ...event})));
    }
  }
  class Element extends Events {
    children = []; value = ''; hidden = false; open = false; files = []; _text = '';
    classList = {toggle() {}};
    constructor(tag, id = '') { super(); this.tagName = tag; this.id = id; }
    set textContent(value) { this._text = String(value); this.children = []; }
    get textContent() { return this._text + this.children.map(child => child.textContent).join(''); }
    append(...children) { this.children.push(...children); }
    replaceChildren(...children) { this._text = ''; this.children = children; }
    setAttribute() {}
    focus() {}
    showModal() { this.open = true; }
    close() { this.open = false; void this.emit('close'); }
    reset() {
      const prefix = this.id.replace('-form', '-');
      for (const element of elements.values()) if (element.id.startsWith(prefix)) element.value = '';
      if (this.id === 'access-form') elements.get('confirm-password').value = '';
    }
  }
  const elements = new Map([...markup.matchAll(/<([a-z][\w-]*)\b[^>]*\bid="([^"]+)"/g)]
    .map(([, tag, id]) => [id, new Element(tag, id)]));
  const document = new Events();
  document.body = new Element('body');
  document.body.append(...elements.values());
  const find = (element, id) => element.id === id ? element : element.children.map(child => find(child, id)).find(Boolean);
  document.getElementById = id => find(document.body, id);
  document.createElement = tag => new Element(tag);
  document.querySelectorAll = selector => selector === 'dialog[open]' ? [...elements.values()].filter(e => e.tagName === 'dialog' && e.open) : [];
  document.querySelector = selector => document.querySelectorAll(selector)[0] || null;
  document.hidden = false;
  document.hasFocus = () => true;
  elements.get('workspace').hidden = true;
  const window = new Events();
  const requests = [];
  const fetch = async (path, options = {}) => {
    requests.push({path, options});
    let value;
    if (path === '/api/status') value = {initialized: true, locked};
    else if (path === '/api/providers') value = {providers: [{id: 'generic', name: '其他服务'}]};
    else if (path === '/api/entries') { if (entriesGate) await entriesGate.promise; value = {entries: [entry]}; }
    else if (path === '/api/unlock') { if (unlockGate) await unlockGate.promise; value = {ok: true}; }
    else if (path.endsWith('/reveal')) { if (revealGate) await revealGate.promise; value = {secret}; }
    else if (path === '/api/lock' || path === '/api/activity') value = {ok: true};
    else throw new Error(`Unexpected mock request: ${path}`);
    return {ok: true, status: 200, json: async () => value};
  };
  class BrowserDate extends Date { static now() { return clock?.wall ?? Date.now(); } }
  vm.runInNewContext(source, {document, window, fetch, URLSearchParams, Date: BrowserDate,
    performance: {now: () => clock?.elapsed ?? performance.now()},
    location: {hash: '#token=mock-launch-token', pathname: '/', search: ''}, history: {replaceState() {}},
    navigator: {clipboard: {writeText: async () => { throw new Error('Clipboard is not part of these tests'); }}},
    setTimeout: () => 1, clearTimeout() {}, setInterval() {},
  });
  await tick();
  return {document, window, requests, element: id => document.getElementById(id)};
}

test('Escape invalidates an in-flight reveal rather than showing it later', async () => {
  const revealGate = deferred();
  const app = await browser({revealGate});
  const pending = app.element('reveal-button').emit('click');
  await tick();
  await app.document.emit('keydown', {key: 'Escape'});
  revealGate.resolve(); await pending;
  assert.notEqual(app.element('detail-secret').textContent, secret);
});

test('window blur hides an already revealed secret and cancels a late reveal', async () => {
  const revealGate = deferred();
  const app = await browser({revealGate});
  const pending = app.element('reveal-button').emit('click');
  await tick();
  await app.window.emit('blur');
  revealGate.resolve(); await pending;
  assert.notEqual(app.element('detail-secret').textContent, secret);
  await app.element('reveal-button').emit('click');
  assert.equal(app.element('detail-secret').textContent, secret);
  await app.window.emit('blur');
  assert.notEqual(app.element('detail-secret').textContent, secret);
});

test('pagehide clears rendered metadata and locks even during initial workspace loading', async () => {
  const entriesGate = deferred();
  const app = await browser({entriesGate});
  await app.window.emit('pagehide');
  assert.equal(app.requests.filter(r => r.path === '/api/lock').length, 1);
  entriesGate.resolve(); await tick();
  assert.equal(app.element('workspace').hidden, true);
  assert.equal(app.element('details').textContent.includes(entry.notes), false);
  assert.equal(app.element('entry-list').textContent.includes(entry.name), false);
});

test('pagehide removes unlocked DOM contents before a possible back-forward cache snapshot', async () => {
  const app = await browser();
  assert(app.element('details').textContent.includes(entry.notes));
  await app.window.emit('pagehide');
  assert.equal(app.element('workspace').hidden, true);
  assert.equal(app.element('details').textContent, '');
  assert.equal(app.element('entry-list').textContent, '');
});

test('leaving during password authentication still locks and ignores the delayed success', async () => {
  const unlockGate = deferred();
  const app = await browser({locked: true, unlockGate});
  app.element('access-password').value = 'fake-browser-password';
  const pending = app.element('access-form').emit('submit');
  await tick();
  await app.window.emit('pagehide');
  assert.equal(app.requests.filter(r => r.path === '/api/lock').length, 1);
  unlockGate.resolve(); await pending;
  assert.equal(app.requests.some(r => r.path === '/api/entries'), false);
  assert.equal(app.element('workspace').hidden, true);
});

test('wall-clock rollback cannot suppress activity pings or extend the browser idle session', async () => {
  const clock = {wall: Date.UTC(2026, 9, 2), elapsed: 1000};
  const app = await browser({clock});
  clock.wall -= 24 * 60 * 60 * 1000; clock.elapsed += 31000;
  await app.document.emit('pointerdown');
  assert.equal(app.requests.filter(r => r.path === '/api/activity').length, 1);
  clock.elapsed += 601000;
  await app.document.emit('pointerdown'); await tick();
  assert.equal(app.element('workspace').hidden, true);
  assert.equal(app.requests.filter(r => r.path === '/api/lock').length, 1);
});
