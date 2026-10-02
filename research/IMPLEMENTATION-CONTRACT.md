# 实验版接口约定

只监听 127.0.0.1，启动生成随机 token，URL fragment #token=...，UI 读取后立即 history.replaceState 清除。Token 只驻留 JS 内存；所有 /api 请求需 Authorization: Bearer <token>。UI reload 后可从终端重新打开链接。无 localStorage、cookie、外部资源。POST body JSON，失败 {error:string}，401 token、423 locked。

- GET /api/status -> {initialized:boolean,locked:boolean,idleMinutes:10}
- POST /api/setup {password}，至少 12 个字符 -> {ok:true}，创建后解锁
- POST /api/unlock {password} -> {ok:true}
- POST /api/lock {} -> {ok:true}
- POST /api/activity {} -> {ok:true}，只在实际用户交互时节流调用，后台轮询不续期
- GET /api/providers -> {providers:[{id,name,quotaKind,endpoint,description}]}，endpoint 可 null
- GET /api/entries -> {entries:[Entry]}，不返回 secret，返回 maskedSecret
- POST /api/entries {name,provider,secret,baseUrl,tags,notes} -> {entry:Entry}
- PUT /api/entries/:id same，空 secret 保留原值 -> {entry:Entry}
- DELETE /api/entries/:id -> {ok:true}
- POST /api/entries/:id/reveal {} -> {secret:string}
- POST /api/entries/:id/sync {} -> {entry:Entry}，失败 HTTP 502 {error}，保留旧 quota
- GET /api/backup -> encrypted vault JSON（fetch 后生成下载文件）
- POST /api/restore {backup:object,password:string} -> {ok:true}。仅空库允许恢复（初始化前或初始化后 entries=0）；恢复后锁定。非空库拒绝覆盖。用备份原密码解锁。

Entry: {id,name,provider,baseUrl,tags:string[],notes,maskedSecret,createdAt,updatedAt,quota?:{kind:'balance'|'key_limit',fetchedAt:ISO,metrics:[{label,value:string|null,currency?:string}],note?:string}}

Provider adapters module src/providers.mjs 导出：providers 数组；async fetchQuota(providerId, secret, {fetchImpl=globalThis.fetch}={}) -> quota。固定官方 https URL，禁止重定向，不读取 entry.baseUrl。支持 deepseek/siliconflow/openrouter；另有 generic/openai/anthropic/gemini/moonshot/dashscope，只收藏。硅基 totalBalance；OpenRouter limit_remaining 仅 key limit，null 标“未设置 Key 上限”，不代表账户无限余额。限制 response 最大 1 MiB、timeout 10s，验证 schema，不保存个人账户 profile，不展示原始错误内容或 key。

界面：中文本地管理台，浅色简洁 sidebar + collection cards/list + quota panel。初次设置、锁屏、新增/编辑、删除确认、揭示/复制、搜索/provider filter、备份下载/恢复。10 分钟无用户操作前端锁库（server 自有同样硬限制）；轮询 status/entries 不算用户操作。手动刷新额度默认；可显式开启本会话 5 分钟自动刷新（锁屏/隐藏页面停止），仅支持的 provider。显示更新时间、旧快照提示与失败状态。不跨币种合计、不做推理测试。
