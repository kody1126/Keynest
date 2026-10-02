'use strict';

(() => {
  const $ = (id) => document.getElementById(id);
  let token = new URLSearchParams(location.hash.slice(1)).get('token') || '';
  if (location.hash) history.replaceState(null, '', location.pathname + location.search);
  const state = {initialized:false,locked:true,providers:[],entries:[],selected:null,filter:'all',editing:null,deleting:null,epoch:0,lastActivity:performance.now(),lastPing:0,auto:false,syncing:new Set(),errors:new Map()};
  let revealTimer, toastTimer;
  let revealed = null;
  let revealGeneration = 0;
  let polling = false;
  let autoRunning = false;
  const idleMs = 10 * 60 * 1000;
  const supported = new Set(['deepseek','siliconflow','openrouter']);

  function node(tag, className, text) {
    const item = document.createElement(tag);
    if (className) item.className = className;
    if (text !== undefined) item.textContent = text;
    return item;
  }
  function button(text, className, handler) {
    const item = node('button', className, text);
    item.type = 'button';
    item.addEventListener('click', handler);
    return item;
  }
  function showError(id, message) {
    $(id).textContent = message || '';
    $(id).hidden = !message;
  }
  function toast(message, error = false) {
    clearTimeout(toastTimer);
    $('toast').textContent = message;
    $('toast').classList.toggle('error', error);
    $('toast').hidden = false;
    toastTimer = setTimeout(() => { $('toast').hidden = true; }, error ? 7000 : 4200);
  }
  function date(value, short = false) {
    const d = new Date(value);
    if (!Number.isFinite(d.getTime())) return '时间未知';
    return d.toLocaleString('zh-CN', short ? {month:'2-digit',day:'2-digit',hour:'2-digit',minute:'2-digit',hour12:false} : {year:'numeric',month:'2-digit',day:'2-digit',hour:'2-digit',minute:'2-digit',hour12:false});
  }
  function provider(id) { return state.providers.find((p) => p.id === id) || {id,name:id || '自定义',description:''}; }
  function selected() { return state.entries.find((e) => e.id === state.selected); }
  function isCurrent(epoch) { return !state.locked && state.epoch === epoch; }
  async function api(path, method = 'GET', body) {
    if (!token) throw new Error('会话链接已失效，请重新打开终端中的完整启动链接。');
    let response;
    try {
      response = await fetch(path, {method,headers:{Authorization:`Bearer ${token}`,...(body === undefined ? {} : {'Content-Type':'application/json'})},body:body === undefined ? undefined : JSON.stringify(body),cache:'no-store',credentials:'omit',redirect:'error'});
    } catch {
      throw new Error('无法连接本机服务，请检查启动它的终端是否仍在运行。');
    }
    let result;
    try { result = await response.json(); } catch { throw new Error('本机服务返回了无法读取的数据。'); }
    if (!response.ok) {
      if (response.status === 423) enterLocked();
      if (response.status === 401) {
        token = '';
        enterLocked();
        connectionError('会话令牌无效。请重新打开终端中的完整启动链接；刷新页面不会保存会话。');
      }
      throw new Error(typeof result.error === 'string' ? result.error : '操作未完成，请重试。');
    }
    return result;
  }
  function clearReveal() {
    revealGeneration++;
    clearTimeout(revealTimer);
    revealed = null;
    const value = document.getElementById('detail-secret');
    if (value) value.textContent = selected()?.maskedSecret || '••••••••••••';
    const toggle = document.getElementById('reveal-button');
    if (toggle) toggle.textContent = '显示';
  }
  function resetForms() {
    $('entry-form').reset();
    $('restore-form').reset();
    $('access-form').reset();
    state.editing = null;
    state.deleting = null;
    for (const dialog of document.querySelectorAll('dialog[open]')) dialog.close();
  }
  function enterLocked(message) {
    state.epoch++;
    state.locked = true;
    state.entries = [];
    state.selected = null;
    state.auto = false;
    state.errors.clear();
    state.syncing.clear();
    clearReveal();
    resetForms();
    $('search').value = '';
    $('auto-sync').checked = false;
    $('entry-list').replaceChildren();
    $('details').replaceChildren();
    $('provider-nav').replaceChildren();
    for (const id of ['entry-count', 'stat-total', 'stat-providers', 'stat-syncable']) $(id).textContent = '0';
    $('workspace').hidden = true;
    $('access').hidden = false;
    renderAccess();
    if (message) toast(message);
  }
  function connectionError(message) {
    $('loading-panel').hidden = true;
    $('access-form').hidden = true;
    $('connection-panel').hidden = false;
    $('connection-message').textContent = message;
  }
  function renderAccess() {
    $('loading-panel').hidden = true;
    $('connection-panel').hidden = true;
    $('access-form').hidden = false;
    $('confirm-field').hidden = state.initialized;
    $('confirm-password').required = !state.initialized;
    $('access-password').minLength = state.initialized ? 1 : 12;
    $('access-label').textContent = state.initialized ? 'WELCOME BACK' : 'YOUR LOCAL VAULT';
    $('access-title').textContent = state.initialized ? '解锁你的密钥库' : '创建你的密钥库';
    $('access-description').textContent = state.initialized ? '输入主密码，继续整理你的 API 收藏。' : '设置一个主密码，用于加密保存在本机的数据。';
    $('password-hint').textContent = state.initialized ? '闲置 10 分钟后自动锁定。' : '至少 12 个字符。请妥善保存，遗失后无法找回。';
    $('access-submit').textContent = state.initialized ? '解锁密钥库' : '创建并解锁';
    $('access-restore').hidden = state.initialized;
    showError('access-error', '');
  }
  async function loadWorkspace() {
    const epoch = state.epoch;
    const [p, e] = await Promise.all([api('/api/providers'), api('/api/entries')]);
    if (state.epoch !== epoch) return;
    state.providers = p.providers;
    state.entries = e.entries;
    state.locked = false;
    state.initialized = true;
    state.lastActivity = performance.now();
    state.lastPing = performance.now();
    state.selected = state.entries[0]?.id || null;
    state.filter = 'all';
    $('access').hidden = true;
    $('workspace').hidden = false;
    $('entry-provider').replaceChildren(...state.providers.map((p) => { const option = node('option','',p.name); option.value = p.id; return option; }));
    render();
  }
  async function start() {
    if (!token) {
      connectionError('请打开终端中包含会话令牌的完整链接。令牌只保存在当前页面内存中，刷新页面后需要重新打开该链接。');
      return;
    }
    $('connection-panel').hidden = true;
    $('loading-panel').hidden = false;
    const epoch = state.epoch;
    try {
      const result = await api('/api/status');
      if (state.epoch !== epoch || !token) return;
      state.initialized = result.initialized;
      if (result.initialized && !result.locked) await loadWorkspace();
      else renderAccess();
    } catch (error) { connectionError(error.message); }
  }
  async function lock(manual = true) {
    if (state.locked) return;
    enterLocked(manual ? '密钥库已锁定。' : '闲置 10 分钟，密钥库已自动锁定。');
    try { await api('/api/lock', 'POST', {}); }
    catch (error) { toast(error.message, true); }
    $('access-password').focus();
  }
  function renderNav() {
    const nav = $('provider-nav');
    nav.replaceChildren();
    const add = (id, name, count, symbol) => {
      const item = button('', `nav-item${state.filter === id ? ' selected' : ''}`, () => {
        state.filter = id;
        render();
      });
      item.setAttribute('aria-pressed', String(state.filter === id));
      item.append(node('span','nav-symbol',symbol),node('span','',name),node('span','nav-count',String(count)));
      nav.append(item);
    };
    add('all','全部 API',state.entries.length,'▦');
    add('syncable','可查额度',state.entries.filter((e) => supported.has(e.provider)).length,'◷');
    nav.append(node('div','nav-divider'));
    for (const p of state.providers) {
      const count = state.entries.filter((e) => e.provider === p.id).length;
      if (count || supported.has(p.id)) add(p.id,p.name,count,'·');
    }
  }
  function filtered() {
    const query = $('search').value.trim().toLocaleLowerCase();
    return state.entries.filter((entry) => {
      const inFilter = state.filter === 'all' || state.filter === entry.provider || (state.filter === 'syncable' && supported.has(entry.provider));
      const content = [entry.name,provider(entry.provider).name,entry.baseUrl,...(entry.tags || []),entry.notes].join(' ').toLocaleLowerCase();
      return inFilter && (!query || content.includes(query));
    });
  }
  function icon(id, large = false) {
    const names = {deepseek:'D',siliconflow:'S',openrouter:'↗',openai:'O',anthropic:'A',gemini:'G',moonshot:'K',dashscope:'Q',generic:'⌘'};
    return node('span',`provider-icon${large ? ' large' : ''}${supported.has(id) || ['anthropic','gemini'].includes(id) ? ` ${id}` : ''}`,names[id] || '⌘');
  }
  function render() {
    if (state.locked) return;
    renderNav();
    const entries = filtered();
    if (!entries.some((entry) => entry.id === state.selected)) {
      clearReveal();
      state.selected = entries[0]?.id || null;
    }
    $('stat-total').textContent = state.entries.length;
    $('entry-count').textContent = state.entries.length;
    $('stat-providers').textContent = new Set(state.entries.map((e) => e.provider)).size;
    $('stat-syncable').textContent = state.entries.filter((e) => supported.has(e.provider)).length;
    $('visible-count').textContent = `${entries.length} 项`;
    $('collection-title').textContent = state.filter === 'all' ? '全部 API' : state.filter === 'syncable' ? '可查询额度的 API' : provider(state.filter).name;
    $('restore-button').disabled = state.entries.length > 0;
    $('restore-button').title = state.entries.length ? '恢复仅允许在空密钥库中进行' : '恢复到空密钥库';
    const list = $('entry-list');
    list.replaceChildren();
    for (const entry of entries) {
      const row = button('',`entry-row${entry.id === state.selected ? ' selected' : ''}`,() => { clearReveal(); state.selected = entry.id; render(); });
      row.setAttribute('aria-pressed', String(entry.id === state.selected));
      const content = node('div','entry-row-content');
      content.append(node('div','entry-row-title',entry.name),node('div','entry-row-meta',`${provider(entry.provider).name}  ·  ${entry.maskedSecret || '••••••••'}`));
      row.append(icon(entry.provider),content);
      const metric = entry.quota?.metrics?.[0];
      if (metric && metric.value !== null) row.append(node('span','row-quota',`${metric.value}${metric.currency ? ` ${metric.currency}` : ''}`));
      else row.append(node('span','row-chevron','›'));
      list.append(row);
    }
    $('empty-state').hidden = entries.length > 0;
    const isEmpty = state.entries.length === 0;
    $('empty-title').textContent = isEmpty ? '从第一枚密钥开始' : '没有找到匹配的收藏';
    $('empty-description').textContent = isEmpty ? '为 API 加上名称与用途，下次需要时轻松找到。' : '试试其他关键词，或切换服务商分类。';
    $('empty-add').hidden = !isEmpty;
    renderDetails();
  }
  function detailBlock(label, value, mono = false) {
    const block = node('div','info-block');
    block.append(node('span','detail-label',label),node('div',`detail-value${mono ? ' mono' : ''}`,value));
    return block;
  }
  function renderDetails() {
    const details = $('details');
    details.replaceChildren();
    const entry = selected();
    if (!entry) {
      const empty = node('div','details-placeholder');
      empty.append(node('span','','⌘'),node('h3','','每一枚密钥，都井井有条。'),node('p','','选择一项收藏，查看密钥信息与额度。'));
      details.append(empty);
      return;
    }
    const p = provider(entry.provider);
    const header = node('div','detail-header');
    const identity = node('div','detail-identity');
    const heading = node('div','');
    heading.append(node('h2','detail-title',entry.name),node('p','detail-provider',`${p.name} · 本机收藏`));
    identity.append(icon(entry.provider,true),heading);
    const actions = node('div','detail-header-actions');
    actions.append(button('编辑信息','button quiet',() => openEntry(entry)),button('删除','button quiet delete-action',() => openDelete(entry)));
    header.append(identity,actions);
    const body = node('div','detail-body');
    body.append(node('span','detail-label','API KEY'));
    const secretField = node('div','secret-field');
    const secretValue = node('span','secret-value',revealed?.id === entry.id ? revealed.secret : entry.maskedSecret || '••••••••••••');
    secretValue.id = 'detail-secret';
    const revealButton = button(revealed?.id === entry.id ? '隐藏' : '显示','',() => reveal(entry.id));
    revealButton.id = 'reveal-button';
    secretField.append(secretValue,revealButton,button('复制','',() => copy(entry.id)));
    body.append(secretField,node('p','field-hint','显示 20 秒后自动隐藏；复制内容会进入系统剪贴板。'));
    body.append(detailBlock('BASE URL',entry.baseUrl || '未填写',true));
    if (entry.tags?.length) {
      const block = node('div','info-block');
      const tags = node('div','tags');
      for (const tag of entry.tags) tags.append(node('span','tag',tag));
      block.append(node('span','detail-label','标签'),tags);
      body.append(block);
    }
    if (entry.notes) body.append(detailBlock('用途与备注',entry.notes));
    const quota = node('section','quota-section');
    const quotaTitle = node('div','quota-title');
    quotaTitle.append(node('h3','',entry.provider === 'openrouter' ? 'Key 额度' : '服务额度'));
    if (supported.has(entry.provider)) {
      const refresh = button(state.syncing.has(entry.id) ? '查询中…' : '↻ 刷新额度','text-button',() => sync(entry.id));
      refresh.disabled = state.syncing.has(entry.id);
      quotaTitle.append(refresh);
    }
    quota.append(quotaTitle);
    if (entry.quota) {
      const metrics = node('div','quota-metrics');
      for (const metric of entry.quota.metrics || []) {
        const box = node('div','quota-metric');
        const value = metric.value === null ? (entry.quota.kind === 'key_limit' ? '未设置 Key 上限' : '未提供') : `${metric.value}${metric.currency ? ` ${metric.currency}` : ''}`;
        box.append(node('span','',metric.label),node('strong',value.length > 17 ? 'long-value' : '',value));
        metrics.append(box);
      }
      quota.append(metrics);
      const age = Date.now() - new Date(entry.quota.fetchedAt).getTime();
      quota.append(node('p','quota-note',`${age > 10 * 60 * 1000 ? '较早的快照 · ' : '查询快照 · '}${date(entry.quota.fetchedAt,true)}。以服务商实际数据为准。`));
      if (entry.quota.note) quota.append(node('p','quota-note',entry.quota.note));
    } else {
      quota.append(node('p','quota-state',supported.has(entry.provider) ? '尚未查询额度。点击刷新，从所选服务商的官方接口获取快照。' : '当前仅支持收藏。该服务商尚未接入可靠的官方额度查询。'));
    }
    if (entry.provider === 'openrouter') quota.append(node('p','quota-note','这里显示单个 Key 的限额与用量，不是账户总余额；未设置 Key 上限也不代表无限余额。'));
    if (state.errors.has(entry.id)) quota.append(node('p','quota-error',`${state.errors.get(entry.id)}${entry.quota ? ' 已保留上次成功的快照。' : ''}`));
    body.append(quota,node('p','timestamp',`添加于 ${date(entry.createdAt)} · 已加密保存`));
    details.append(header,body);
  }
  function openEntry(entry) {
    if (state.locked) return;
    clearReveal();
    state.editing = entry?.id || null;
    $('entry-form').reset();
    $('entry-dialog-title').textContent = entry ? '编辑 API' : '添加 API';
    $('entry-save').textContent = entry ? '保存修改' : '保存收藏';
    $('entry-name').value = entry?.name || '';
    $('entry-provider').value = entry?.provider || (state.providers.some((p) => p.id === state.filter) ? state.filter : 'generic');
    $('entry-secret').required = !entry;
    $('entry-secret').placeholder = entry ? '留空则保留原密钥' : '粘贴你的 API Key';
    $('entry-secret-hint').textContent = entry ? '不需要更换密钥时请留空。更换服务商时，请确认密钥属于所选服务商。' : '密钥默认隐藏，并加密保存在本机。';
    $('entry-url').value = entry?.baseUrl || '';
    $('entry-tags').value = (entry?.tags || []).join(', ');
    $('entry-notes').value = entry?.notes || '';
    showError('entry-error','');
    $('entry-dialog').showModal();
    $('entry-name').focus();
  }
  function openDelete(entry) {
    state.deleting = entry.id;
    $('delete-description').textContent = `「${entry.name}」及其额度快照将从本机密钥库中移除。此操作无法直接撤销。`;
    showError('delete-error','');
    $('delete-dialog').showModal();
    $('delete-dialog').querySelector('.close-dialog').focus();
  }
  async function reveal(id) {
    if (revealed?.id === id) { clearReveal(); return; }
    clearReveal();
    const generation = revealGeneration;
    const epoch = state.epoch;
    try {
      const result = await api(`/api/entries/${encodeURIComponent(id)}/reveal`,'POST',{});
      if (!isCurrent(epoch) || generation !== revealGeneration || state.selected !== id || document.hidden || !document.hasFocus()) return;
      revealed = {id,secret:result.secret};
      renderDetails();
      revealTimer = setTimeout(clearReveal,20000);
    } catch (error) { toast(error.message,true); }
  }
  async function copy(id) {
    const epoch = state.epoch;
    try {
      const result = await api(`/api/entries/${encodeURIComponent(id)}/reveal`,'POST',{});
      if (!isCurrent(epoch) || document.hidden) return;
      await navigator.clipboard.writeText(result.secret);
      toast('已复制密钥，请留意系统剪贴板及其历史。');
    } catch (error) {
      toast(error.name === 'NotAllowedError' || !navigator.clipboard ? '浏览器未允许复制。可以显示密钥后手动选择复制。' : error.message,true);
    }
  }
  async function sync(id) {
    if (state.locked || state.syncing.has(id)) return;
    const epoch = state.epoch;
    state.syncing.add(id);
    if (state.selected === id) renderDetails();
    try {
      const result = await api(`/api/entries/${encodeURIComponent(id)}/sync`,'POST',{});
      if (!isCurrent(epoch)) return;
      state.entries = state.entries.map((entry) => entry.id === id ? result.entry : entry);
      state.errors.delete(id);
    } catch (error) {
      if (isCurrent(epoch)) state.errors.set(id,error.message);
    } finally {
      if (isCurrent(epoch)) { state.syncing.delete(id); render(); }
    }
  }
  async function backup() {
    const epoch = state.epoch;
    $('backup-button').disabled = true;
    try {
      const data = await api('/api/backup');
      if (!isCurrent(epoch)) return;
      const url = URL.createObjectURL(new Blob([JSON.stringify(data,null,2)],{type:'application/json'}));
      const link = node('a');
      link.href = url;
      link.download = `keynest-encrypted-${new Date().toISOString().slice(0,10)}.json`;
      document.body.append(link);
      link.click();
      link.remove();
      setTimeout(() => URL.revokeObjectURL(url),1000);
      toast('已生成加密备份。恢复时需要当前主密码。');
    } catch (error) { toast(error.message,true); }
    finally { $('backup-button').disabled = false; }
  }
  function openRestore() {
    clearReveal();
    $('restore-form').reset();
    showError('restore-error','');
    $('restore-dialog').showModal();
  }

  $('access-form').addEventListener('submit',async (event) => {
    event.preventDefault();
    const epoch = state.epoch;
    const password = $('access-password').value;
    if (!state.initialized && password !== $('confirm-password').value) { showError('access-error','两次输入的主密码不一致。'); return; }
    $('access-submit').disabled = true;
    showError('access-error','');
    try {
      await api(state.initialized ? '/api/unlock' : '/api/setup','POST',{password});
      if (state.epoch !== epoch || !token) return;
      $('access-form').reset();
      state.initialized = true;
      await loadWorkspace();
      $('search').focus();
    } catch (error) { showError('access-error',error.message); $('access-password').value = ''; $('confirm-password').value = ''; }
    finally { $('access-submit').disabled = false; }
  });
  $('entry-form').addEventListener('submit',async (event) => {
    event.preventDefault();
    const epoch = state.epoch;
    const id = state.editing;
    const entry = {name:$('entry-name').value.trim(),provider:$('entry-provider').value,secret:$('entry-secret').value,baseUrl:$('entry-url').value.trim(),tags:[...new Set($('entry-tags').value.split(/[,，]/).map((tag) => tag.trim()).filter(Boolean))],notes:$('entry-notes').value.trim()};
    if (!entry.name) { showError('entry-error','请输入收藏名称。'); return; }
    $('entry-save').disabled = true;
    showError('entry-error','');
    try {
      const result = await api(id ? `/api/entries/${encodeURIComponent(id)}` : '/api/entries',id ? 'PUT' : 'POST',entry);
      if (!isCurrent(epoch)) return;
      state.entries = id ? state.entries.map((item) => item.id === id ? result.entry : item) : [...state.entries,result.entry];
      state.selected = result.entry.id;
      state.filter = 'all';
      $('search').value = '';
      state.errors.delete(result.entry.id);
      $('entry-dialog').close();
      render();
      toast(id ? '收藏已更新。' : '已添加到你的 API 收藏。');
    } catch (error) { showError('entry-error',error.message); }
    finally { $('entry-save').disabled = false; }
  });
  $('delete-form').addEventListener('submit',async (event) => {
    event.preventDefault();
    const epoch = state.epoch;
    const id = state.deleting;
    if (!id) return;
    $('delete-confirm').disabled = true;
    try {
      await api(`/api/entries/${encodeURIComponent(id)}`,'DELETE');
      if (!isCurrent(epoch)) return;
      clearReveal();
      state.entries = state.entries.filter((entry) => entry.id !== id);
      state.errors.delete(id);
      $('delete-dialog').close();
      render();
      toast('已删除本机收藏。');
    } catch (error) { showError('delete-error',error.message); }
    finally { $('delete-confirm').disabled = false; }
  });
  $('restore-form').addEventListener('submit',async (event) => {
    event.preventDefault();
    const file = $('restore-file').files[0];
    if (!file) return;
    if (file.size > 4 * 1024 * 1024) { showError('restore-error','备份文件不能大于 4 MiB。'); return; }
    $('restore-submit').disabled = true;
    showError('restore-error','');
    try {
      let data;
      try { data = JSON.parse(await file.text()); } catch { throw new Error('无法读取这个 JSON 备份文件。'); }
      await api('/api/restore','POST',{backup:data,password:$('restore-password').value});
      state.initialized = true;
      enterLocked('备份已恢复，请使用备份原来的主密码解锁。');
    } catch (error) { showError('restore-error',error.message); $('restore-password').value = ''; }
    finally { $('restore-submit').disabled = false; }
  });
  for (const item of document.querySelectorAll('.close-dialog')) item.addEventListener('click',() => item.closest('dialog').close());
  $('entry-dialog').addEventListener('close',() => { $('entry-form').reset(); state.editing = null; });
  $('restore-dialog').addEventListener('close',() => $('restore-form').reset());
  $('delete-dialog').addEventListener('close',() => { state.deleting = null; $('delete-description').textContent = ''; });
  $('add-button').addEventListener('click',() => openEntry());
  $('empty-add').addEventListener('click',() => openEntry());
  $('lock-button').addEventListener('click',() => lock());
  $('backup-button').addEventListener('click',backup);
  $('restore-button').addEventListener('click',openRestore);
  $('access-restore').addEventListener('click',openRestore);
  $('retry').addEventListener('click',start);
  $('search').addEventListener('input',() => { clearReveal(); render(); });
  $('auto-sync').addEventListener('change',() => {
    state.auto = $('auto-sync').checked;
    toast(state.auto ? '已开启本次会话自动查询；页面隐藏或密钥库锁定时暂停。' : '已关闭自动查询。');
  });
  document.addEventListener('keydown',(event) => {
    if ((event.metaKey || event.ctrlKey) && event.key.toLowerCase() === 'k' && !state.locked && !document.querySelector('dialog[open]')) {
      event.preventDefault();
      $('search').focus();
    }
    if (event.key === 'Escape') clearReveal();
  });
  function activity() {
    if (state.locked) return;
    const now = performance.now();
    if (now - state.lastActivity >= idleMs) { lock(false); return; }
    state.lastActivity = now;
    if (now - state.lastPing > 30000) {
      state.lastPing = now;
      api('/api/activity','POST',{}).catch(() => {});
    }
  }
  document.addEventListener('pointerdown',activity,{passive:true,capture:true});
  document.addEventListener('keydown',activity,{passive:true,capture:true});
  document.addEventListener('input',activity,{passive:true,capture:true});
  document.addEventListener('visibilitychange',() => {
    clearReveal();
    if (document.hidden) {
      for (const dialog of document.querySelectorAll('dialog[open]')) dialog.close();
      $('access-password').value = '';
      $('confirm-password').value = '';
    } else if (!state.locked && performance.now() - state.lastActivity >= idleMs) lock(false);
  });
  window.addEventListener('blur',clearReveal);
  setInterval(async () => {
    if (state.locked) return;
    if (performance.now() - state.lastActivity >= idleMs) { await lock(false); return; }
    if (document.hidden || polling) return;
    polling = true;
    try {
      const result = await api('/api/status');
      if (result.locked && !state.locked) enterLocked('密钥库已自动锁定，请重新解锁。');
    } catch { /* The next explicit operation reports connection failures. */ }
    finally { polling = false; }
  },15000);
  setInterval(async () => {
    if (!state.auto || state.locked || document.hidden || autoRunning) return;
    if (performance.now() - state.lastActivity >= idleMs) { await lock(false); return; }
    autoRunning = true;
    const ids = state.entries.filter((entry) => supported.has(entry.provider)).map((entry) => entry.id);
    try {
      for (const id of ids) {
        if (!state.auto || state.locked || document.hidden) break;
        await sync(id);
      }
    } finally { autoRunning = false; }
  },5 * 60 * 1000);
  window.addEventListener('pagehide',() => {
    const launchToken = token;
    // Also cancel pending setup/unlock/load work and clear rendered metadata
    // before the browser can preserve this document in its back-forward cache.
    enterLocked();
    token = '';
    if (launchToken) fetch('/api/lock',{method:'POST',headers:{Authorization:`Bearer ${launchToken}`,'Content-Type':'application/json'},body:'{}',keepalive:true,credentials:'omit',redirect:'error',cache:'no-store'}).catch(() => {});
  });
  window.addEventListener('pageshow',(event) => {
    if (event.persisted) {
      enterLocked();
      connectionError('请重新打开终端中的完整启动链接。离开页面后，会话令牌不会保留。');
    }
  });
  start();
})();
