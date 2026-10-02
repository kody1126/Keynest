# 本地 API / 密钥管理工具调研

核查日期：2026-09-22。范围：官方仓库、发布记录、官方接口文档；重点候选做了静态源码抽查。未安装候选软件，未提供真实账户密钥，未做完整安全审计。

## 结论

已有成熟的局部方案。本轮没有找到经充分验证、同时满足“通用 API 收藏、本地加密保险箱、多厂商额度总览”的完整产品。这是检索结论，不是断言市场上不存在。

如果今天就要保管重要密钥，优先考虑 KeePassXC。若主要用途是切换 AI 编程工具，CC Switch 更合适；若主要管理中转站账户与 API 凭据，All API Hub 值得先试。自建的价值在于把本地加密收藏与准确的额度数据放到同一简洁界面，不是重新发明密码算法。

## 候选比较

| 项目 | 已核实能力 | 局限与选型判断 |
| --- | --- | --- |
| [KeePassXC](https://github.com/keepassxreboot/keepassxc) | 跨平台、离线 KDBX 加密库、分组、自定义字段、CLI；[2.7.12 发布](https://github.com/keepassxreboot/keepassxc/releases/tag/2.7.12) | 成熟保管方案；可用密码字段存 Key，自定义字段存 Base URL/控制台；未发现内置多模型余额面板。 |
| [CC Switch](https://github.com/farion1231/cc-switch) | 本地 Tauri/SQLite；供应商、MCP、Skills 管理；[3.20.3，2026-09-11](https://github.com/farion1231/cc-switch/releases/tag/v3.20.3)；MIT | [额度模板](https://github.com/farion1231/cc-switch/blob/main/docs/user-manual/en/2-providers/2.5-usage-query.md)丰富，但偏配置切换，后台查询针对当前启用供应商；未确认主密码保护的数据库静态加密。会写工具配置。 |
| [All API Hub](https://github.com/qixing-jk/all-api-hub) | 浏览器扩展；API Credential Library；Base URL/Key 收藏、余额/模型/连接测试；[4.0.0，2026-09-20](https://github.com/qixing-jk/all-api-hub/releases/tag/v4.0.0)；AGPL-3.0 | 与需求很接近，重点适配 New API/Sub2API 等站点。默认浏览器存储；可选 WebDAV 加密同步不等于本地库有独立主密码保护。 |
| [Infisical](https://github.com/Infisical/infisical) | [自托管](https://infisical.com/docs/self-hosting/overview)、权限、版本、轮换、CLI；核心 MIT，企业目录另有许可；[0.165.13，2026-09-18](https://github.com/Infisical/infisical/releases/tag/v0.165.13) | 成熟开发者秘密管理平台，个人部署偏重；未发现内置跨模型余额面板。其[加密架构](https://infisical.com/docs/internals/security)不能表述为服务器完全无法解密。 |
| [New API](https://github.com/QuantumNous/new-api) | 模型代理、分发、内部令牌额度、部分上游[余额刷新](https://docs.newapi.ai/en/docs/api/management/channel-management/channel-update_balance-id-get)；AGPL；[1.0.0-rc.40，2026-09-21](https://github.com/QuantumNous/new-api/releases/tag/v1.0.0-rc.40) | 网关自己的额度不等于所有上游账户余额；对单纯收藏场景过重。 |
| [Lokalite](https://github.com/RubenGlez/lokalite) | macOS 14+；CryptoKit AES-GCM、Keychain、项目环境、CLI/MCP、加密备份；[2.8.0，2026-09-04](https://github.com/RubenGlez/lokalite/releases/tag/v2.8.0)；MIT | 非常贴近开发者秘密保管；没有余额看板。小型项目，不能因签名公证就当作安全审计。[Keychain 实现](https://github.com/RubenGlez/lokalite/blob/335078c3dda62f2b3adc0c7bc880b7b8e71c8499/Sources/LokaliteCore/Keychain/KeychainStore.swift)说明生物识别在应用层实施，不能声称每次读取都有硬件级用户在场约束。 |
| [TokenMaxxer](https://github.com/joshuasknott/tokenmaxxer) | 本地桌面额度看板、系统凭据存储、多个 provider；[0.1.0，2026-09-01](https://github.com/joshuasknott/tokenmaxxer/releases/tag/v0.1.0)；MIT | 很适合参考额度界面与适配器；官方明确是 public preview、包未签名，不能称成熟稳定保险箱。其[实现矩阵](https://github.com/joshuasknott/tokenmaxxer/blob/main/docs/PROVIDER_IMPLEMENTATION_MATRIX.md)区分普通/管理员凭证。 |
| [Townrain/API-Key-Manager](https://github.com/Townrain/API-Key-Manager) | 45+ provider、CLI/Web/Windows 桌面、加密存储；5.0.3；MIT | 只适合作为参考。本次源码抽查发现跨供应商发 Key 探测、默认 Web 边界与加密主密钥保存问题，见下。 |

版本与维护信息是本次快照。下载前应再次检查官方发布记录；许可证以采用版本的 LICENSE 为准。

## Townrain/API-Key-Manager 重点抽查

基线 commit：`de9a9a706d4d941ac364532d55d37fab8fc8554c`。未执行项目，以下属于静态观察/推论。

1. [detector.py](https://github.com/Townrain/API-Key-Manager/blob/de9a9a706d4d941ac364532d55d37fab8fc8554c/key_manager/detector.py#L132) 对未能唯一识别的 Key 遍历多个 provider，构造认证头并发请求；随后可能发真实聊天请求。这不符合“只向已选择的服务商发送 Key”的边界。
2. [web.py](https://github.com/Townrain/API-Key-Manager/blob/de9a9a706d4d941ac364532d55d37fab8fc8554c/web.py#L48) 默认 Web 模式监听 `0.0.0.0`；[首页处理](https://github.com/Townrain/API-Key-Manager/blob/de9a9a706d4d941ac364532d55d37fab8fc8554c/key_manager/web/_app.py#L164) 会注入派生 token，而[中间件](https://github.com/Townrain/API-Key-Manager/blob/de9a9a706d4d941ac364532d55d37fab8fc8554c/key_manager/web/middleware.py#L97)放行首页。结合[完整密钥接口](https://github.com/Townrain/API-Key-Manager/blob/de9a9a706d4d941ac364532d55d37fab8fc8554c/key_manager/web/routes/keys.py#L151)，静态推断默认配置的访问者可能取得可用 token；未做攻击复现。
3. [storage.py](https://github.com/Townrain/API-Key-Manager/blob/de9a9a706d4d941ac364532d55d37fab8fc8554c/key_manager/storage.py#L107) 在未提供环境密钥/配置口令时生成口令，明文追加同目录配置。整目录泄露时，密文和解密材料可能一起暴露。

## 额度同步可行性

“额度”必须拆成余额、Key 消费限额、历史消费、速率配额、订阅窗口，不能都显示成一个余额数值。不同币种不直接求和，多 Key 也可能共用同一个账户余额。

| 平台 | 官方来源与接口 | 普通推理 Key | 正确显示方式 |
| --- | --- | --- | --- |
| DeepSeek | [GET /user/balance](https://api-docs.deepseek.com/api/get-user-balance/) | 可以 | 每币种的 `total_balance`、赠送/充值余额；属于账户余额。 |
| SiliconFlow | [官方 OpenAPI /v1/user/info](https://github.com/siliconflow/siliconcloud/blob/main/openapi.yaml) | 可以 | `totalBalance` 总余额；响应中的邮箱、用户名等不保留。不能只取 `balance` 当全部余额。 |
| OpenRouter | [GET /api/v1/key](https://openrouter.ai/docs/api/api-reference/api-keys/get-current-api-key) | 可以 | `limit_remaining` 是 Key 限额剩余；null 为未设 Key 上限，不代表账户无限余额。[账户 /credits](https://openrouter.ai/docs/api/api-reference/credits/get-remaining-credits)需要 management key。 |
| OpenAI | [Usage](https://developers.openai.com/api/reference/resources/admin/subresources/organization/subresources/usage)、[Costs](https://developers.openai.com/api/reference/resources/admin/subresources/organization/subresources/usage/methods/costs)、[管理 API](https://platform.openai.com/docs/api-reference/administration) | 组织管理授权，不能假定普通 Key 可用 | 用量/成本与充值余额不同。本轮未找到公开的普通 Key 剩余充值余额接口；不采用历史 dashboard 私有接口。 |
| Anthropic | [Usage and Cost API](https://platform.claude.com/docs/en/manage-claude/usage-cost-api) | 需要组织级 Admin 授权，个人账户不支持 Admin API | 历史用量/成本，不能换算为 Claude Pro/Max 的订阅剩余量。 |
| Gemini | [计费](https://ai.google.dev/gemini-api/docs/billing)、[配额](https://ai.google.dev/gemini-api/docs/rate-limits)、[Cloud Monitoring](https://docs.cloud.google.com/monitoring/api/ref_v3/rest/v3/projects.timeSeries/list) | 未找到普通 Gemini Key 独立余额接口 | 当前有预付/后付计费；项目指标查询另需 OAuth/IAM。不要把项目配额当每个 Key 独享。 |
| Moonshot/Kimi | [国内余额](https://platform.kimi.com/docs/api/balance)、[国际余额](https://platform.kimi.ai/docs/api/balance) | 可以 | 国内人民币、国际美元，Key 不互通；现金余额可能为负。后续适配候选。 |
| 阿里百炼 | [QueryAccountBalance](https://help.aliyun.com/zh/user-center/developer-reference/api-bssopenapi-2017-12-14-queryaccountbalance) | 另需阿里云 AccessKey/RAM 授权 | 阿里云整个账户余额，不是百炼独占余额；Coding Plan 另算。 |

## 首版实施决定

制作一个范围受限的本地实验：中文收藏界面、整库加密、密码解锁、标签搜索、加密备份/恢复，以及前三家官方只读额度适配器。使用 Node 内置成熟密码实现，不发明加密算法；没有遥测、云端账户、远程资产和推理测试。

手动刷新为默认，可选择本会话每 5 分钟刷新；这是产品轮询策略，不是平台实时性保证。数据必须附带上次成功同步时间。查询失败保留旧快照并显示失败，不将失败转换成零余额。自定义 Base URL 只用于收藏，初版不带 Key 调用任意 URL。

真实密钥联调、系统钥匙串/原生桌面封装、主密码更换、更多 provider、依赖及独立安全审计属于后续工作。实验版不能宣称达到 KeePassXC 等成熟密码管理器的安全程度。
