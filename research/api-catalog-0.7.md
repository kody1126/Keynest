# Keynest 0.7：Skills / Agent API 预设补充

核实日期：2026-09-29。共 61 个预设，原有 47 个 ID、顺序及已有保存记录不变；在尾部新增 14 个。它们只提供本地表单默认值，不检测密钥、不调用 API、不启用额度查询。

新增“Agent 工具”浏览分组：浏览器、工具连接、代码文档和记忆服务建议归为 `skill`。搜索服务继续在“搜索与采集”，追踪和向量数据库归“开发与数据”。这些只是创建空白草稿时的分类建议，切换预设不会改变已有条目的分类、凭据、工具关联、环境、账号、标签和备注。

## 新增目录与官方依据

| 稳定 ID | 名称 / 分组 | 保存的默认 API 地址 | 鉴权与额外配置 | 官方依据 |
| --- | --- | --- | --- | --- |
| `perplexity` | Perplexity / 搜索与采集 | `https://api.perplexity.ai` | API Key / Bearer；具体功能选择对应路径，旧 Sonar 应迁移到 Agent API | [Quickstart](https://docs.perplexity.ai/docs/getting-started/quickstart)、[Sonar 迁移公告](https://community.perplexity.ai/t/sonar-is-moving-to-the-agent-api/5802) |
| `apify` | Apify / 搜索与采集 | `https://api.apify.com/v2` | API Token，官方推荐 Bearer header；运行 Actor 还需 Actor ID | [API v2 与 Authentication](https://docs.apify.com/api/v2) |
| `browserbase` | Browserbase / Agent 工具 | `https://api.browserbase.com/v1` | `X-BB-API-Key`；浏览器会话配置的 Project ID 可另记于账号标签，连接 URL 由会话返回 | [Create a Session](https://docs.browserbase.com/reference/api/create-a-session)、[官方 SDK schema](https://github.com/browserbase/sdk-python/blob/main/openapi.v1.yaml) |
| `browserless` | Browserless / Agent 工具 | `https://production-sfo.browserless.io` | API token；这是共享云默认区域 HTTPS 主机，其他地域/专用 fleet 需修改；WebSocket 与 REST 路径不同 | [Connection URLs](https://docs.browserless.io/overview/connection-urls)、[REST Quickstart](https://docs.browserless.io/rest-apis/quick-start) |
| `parallel` | Parallel / 搜索与采集 | `https://api.parallel.ai` | `x-api-key`；新搜索集成使用 `/v1/search`，不要照搬旧 beta 示例 | [Search Quickstart](https://docs.parallel.ai/search/search-quickstart) |
| `context7` | Context7 / Agent 工具 | `https://context7.com/api` | Bearer API Key；当前自然语言搜索 `/v3/search`、库查找与上下文 `/v2/...`，MCP 地址另配 | [API Guide](https://context7.com/docs/api-guide)、[API Keys](https://context7.com/docs/howto/api-keys) |
| `composio` | Composio / Agent 工具 | `https://backend.composio.dev/api/v3` | 项目 `x-api-key`，组织密钥另用 `x-org-api-key`；第三方连接仍需各自 OAuth 或服务凭据；部分 Tool Router 接口使用 v3.1 | [v3 API Reference](https://docs.composio.dev/reference/v3)、[Authentication](https://docs.composio.dev/reference/v3/authentication)、[新接口说明](https://docs.composio.dev/reference/authenticating-to-composio) |
| `mem0` | Mem0 / Agent 工具 | `https://api.mem0.ai` | 托管平台 `Authorization: Token`；还需用户或 Agent 标识，自托管不使用该地址 | [Add Memories](https://docs.mem0.ai/api-reference/memory/add-memories) |
| `langsmith` | LangSmith / 开发与数据 | `https://api.smith.langchain.com` | LangSmith API Key / `X-Api-Key`，按工作区、项目、地域或自托管选择地址 | [API Key 与区域配置](https://docs.langchain.com/langsmith/create-account-api-key)、[官方 API 示例](https://docs.langchain.com/langsmith/managed-deep-agents-api/threads/get-thread) |
| `langfuse` | Langfuse / 开发与数据 | `https://cloud.langfuse.com/api/public` | Public Key + Secret Key 的 HTTP Basic Auth；公钥放账号标签，私钥放密钥栏；其他区域/自托管另有 host | [Public API](https://langfuse.com/docs/api-and-data-platform/features/public-api) |
| `qdrant` | Qdrant / 开发与数据 | 留空，填写自己的集群 URL | 数据库 API Key / `api-key`；与 Cloud 管理密钥区分 | [Cluster 设置](https://qdrant.tech/course/multi-vector-search/module-0/qdrant-setup/)、[Security](https://qdrant.tech/documentation/operations/security/)、[Cloud 管理凭据示例](https://qdrant.tech/documentation/cloud-tools/pulumi/) |
| `pinecone` | Pinecone / 开发与数据 | 留空，填写索引专属 HTTPS host | 项目 API Key / `Api-Key`；向量请求使用 index host，不把控制平面 `api.pinecone.io` 当数据端点 | [Target an index](https://docs.pinecone.io/guides/manage-data/target-an-index)、[数据平面鉴权示例](https://docs.pinecone.io/reference/api/2025-04/data-plane/list) |
| `weaviate` | Weaviate / 开发与数据 | 留空，填写集群 REST endpoint | 集群 API Key；外部嵌入提供商可能另需一把 API Key | [连接 Weaviate Cloud](https://docs.weaviate.io/cloud/manage-clusters/connect)、[Authentication](https://docs.weaviate.io/deploy/configuration/authentication) |
| `zep` | Zep / Agent 工具 | `https://api.getzep.com` | Zep Cloud API Key；与旧 Community Edition 区分，版本路径按当前 SDK | [SDK 初始化](https://help.getzep.com/v3/install-sdks)、[官方 API URL](https://help.getzep.com/faq) |

## 易混淆的范围

Perplexity 在 2026-08-13 的官方公告中给出 Sonar 迁移方向，并将原端点计划退役日列为 9 月 27 日。当前 quickstart 已把 Sonar 归入 Legacy，并展示 `/v1/agent` 与独立 Search、Router API。因此新增名称使用 **Perplexity**，仍接受 `Sonar` / `Perplexity Sonar` 搜索别名，不把旧 Sonar 路径作为新接入默认值。本次没有发出 API 请求验证旧路径是否仍能响应。[官方公告](https://community.perplexity.ai/t/sonar-is-moving-to-the-agent-api/5802)、[当前 Quickstart](https://docs.perplexity.ai/docs/getting-started/quickstart)

Browserless 官方 REST 接口把 token 作为查询参数，但本工具保存的地址故意不含 token；把密钥单独保存在密钥字段。Composio 保存的是 Composio 自身的项目凭据，不能代替 Google、Slack 等下游账户授权。Langfuse 的公私钥是配对凭据，不把两者拼成一段伪造“单一 API Key”。

Qdrant、Pinecone、Weaviate 的地址留空是明确产品选择：用户需要项目/集群/索引的真实地址。预设不会生成假的示例 URL，也不会为了方便而填入功能不同的管理端点。已有 Supabase 项目地址的行为保持一致。

## 图标与验证边界

全部 61 个预设声明 `hasBundledIcon = true`，按稳定 ID 对应本地 `Resources/ProviderIcons/<id>.png`；每项仍保留原生符号以应对资源读取失败。真实品牌图标、来源和许可证由本轮图标任务统一补齐。

本轮增加检查：新分组与 `skill` 分类建议、61 个唯一稳定 ID、所有品牌 PNG 的存在及文件签名、项目专属地址留空、多项凭据提示、Perplexity 的旧名称可检索，以及切换预设保留已有用户数据。最终与资源、模板和迁移合并后的完整检查通过 140 项测试、7104 条断言；另有 74 条 AppModel 集成断言通过，详见 [验证记录](../macos/verification.md)。
