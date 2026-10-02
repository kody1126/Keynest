# Keynest 0.7 工具、Skill 与 Agent 模板

核实日期：2026-09-29。离线目录包含 **25 个凭据整理模板**：15 个真实品牌工具与 10 个通用功能组合。其中 8 项归入 Skill，9 项归入客户端，8 项归入 Agent 与工作流。

模板用于减少名称、用途与凭据关系的重复录入。它们不是安装包、官方工作流或已运行的 Skill，也不会自动写入其他工具的环境变量或配置。每个槽位代表一个凭据角色；候选提供商是可选其一的替代方案，不是要逐个创建的密钥清单。必需槽位表示本模板选择的 API Key 配置路径，不表示该工具的订阅、OAuth 或本地模型模式也需要 API Key。

## 真实品牌工具与官方依据

| 稳定 ID | 工具 | 默认槽位；括号内为可选项 | 官方依据及范围 |
| --- | --- | --- | --- |
| `cursor` | Cursor | Anthropic，可选 OpenAI / Google | [API Keys](https://docs.cursor.com/settings/api-keys)：自带提供商密钥与 Cursor 订阅、专用功能分开。 |
| `cline` | Cline | OpenRouter，可选 Anthropic / OpenAI | [OpenRouter 配置](https://docs.cline.bot/provider-config/openrouter)直接说明提供商、Key、模型和自定义地址；[官方文档索引](https://docs.cline.bot/llms.txt)列出其他提供商、账户与本地模型路径。 |
| `roo-code` | Roo Code | Anthropic，可换模型提供商 | [Anthropic 配置](https://roocodeinc.github.io/Roo-Code/providers/anthropic/)说明设置中的 API Key 和模型选择；侧栏列出 OpenRouter、OpenAI、Google、DeepSeek。 |
| `continue` | Continue | Anthropic；（OpenAI 向量化） | [配置参考](https://docs.continue.dev/reference)将模型分为 chat、embed 等角色；[Secrets 说明](https://docs.continue.dev/faqs)区分配置引用和环境加载，模板不生成配置。 |
| `opencode` | OpenCode | Anthropic，可换 OpenAI / Google / OpenRouter | [Providers](https://opencode.ai/docs/providers)说明 connect、模型选择、API Key 和其他认证路径。 |
| `claude-code` | Claude Code | Anthropic API Key | [Authentication](https://code.claude.com/docs/en/authentication)明确支持订阅登录与 `ANTHROPIC_API_KEY`；本模板只覆盖后者。 |
| `openclaw` | OpenClaw | Anthropic；（Brave 搜索） | [Model providers](https://docs.openclaw.ai/concepts/model-providers)区分模型提供商和频道认证；[Web search](https://docs.openclaw.ai/tools/web)记录 Brave 与 `BRAVE_API_KEY`。 |
| `dify` | Dify | OpenAI；（OpenAI / Cohere 向量化） | [模型供应商](https://docs.dify.ai/zh-hans/guides/model-configuration/readme)区分系统和自定义供应商，以及语言和向量化模型。 |
| `n8n` | n8n | OpenAI；（Firecrawl）；（Resend） | [OpenAI credentials](https://docs.n8n.io/integrations/builtin/credentials/openai)说明 API Key 节点凭据。采集与邮件是本项目设计的内容工作流组合，可使用相应服务节点或 HTTP 节点，不是 n8n 的必需安装项。 |
| `flowise` | Flowise | OpenAI；（Qdrant / Pinecone） | [Credentials](https://docs.flowiseai.com/migration-guide/v1.3.0-migration-guide)说明节点凭据复用；[Qdrant](https://docs.flowiseai.com/integrations/langchain/vector-stores/qdrant)和 [Pinecone](https://docs.flowiseai.com/integrations/langchain/vector-stores/pinecone)分别说明 API Key、集群或索引配置。 |
| `langgraph` | LangGraph | Anthropic；（LangSmith） | [LangGraph quickstart](https://docs.langchain.com/oss/python/langgraph/quickstart)为框架使用入口；[模型集成示例](https://docs.langchain.com/oss/python/integrations/llms/openai)区分模型 API Key 与可选 `LANGSMITH_API_KEY` 追踪。 |
| `crewai` | CrewAI | OpenAI，可选 Anthropic / Google | [LLMs](https://docs.crewai.com/en/concepts/llms)记录模型提供商及各自 API Key；不是额外的 CrewAI 平台登录凭据。 |
| `open-webui` | Open WebUI | OpenAI，可换兼容服务 | [OpenAI-compatible](https://docs.openwebui.com/getting-started/quick-start/connect-a-provider/starting-with-openai-compatible/)将连接定义为 URL、Key 和模型配置，并支持本地服务器。 |
| `anythingllm` | AnythingLLM | OpenAI | [OpenAI LLM](https://docs.anythingllm.com/setup/llm-configuration/cloud/openai)说明云端模型凭据供工作区与 Agent 使用；模板没有要求本地模型创建密钥。 |
| `cherry-studio` | Cherry Studio | OpenAI，可选豆包 / DeepSeek；（Tavily） | [提供商设置](https://docs.cherry-ai.com/cherry-studio-wen-dang/en-us/cherry-studio/preview/settings/providers)说明 Key 与地址；[联网搜索](https://docs.cherry-ai.com/cherry-studio-wen-dang/en-us/websearch)说明 Tavily。 |

真实工具图标使用 `Resources/ToolIcons/<logoID>.png`，`logoID` 与上表 ID 相同。品牌图像由独立资产目录记录来源与许可；离线加载，不从用户收藏网址抓取图标。

## 通用功能组合

这些组合由本项目设计，用真实提供商品牌图标表示所选 API，不冒充独立软件品牌。`logoID` 为 `nil`、`website` 为空。来源入口和凭据差异沿用 [API 预设目录](api-catalog-0.6.md)及 0.7 新增提供商资料。

| 稳定 ID | 功能 | 槽位与补充配置 |
| --- | --- | --- |
| `web-search-skill` | 联网搜索 Skill | Tavily / Brave / Exa 选一家；请求格式并不通用。 |
| `web-crawl-skill` | 网页采集 Skill | Firecrawl / Jina / Apify 选一家；Apify 还需 Actor 标识。 |
| `voice-assistant` | 语音助手 | 模型、语音合成两个主槽；语音识别可选。模型与声音 ID 属于实际工作流配置。 |
| `knowledge-agent` | 知识库 Agent | OpenAI 模型与向量化；Qdrant / Pinecone 可选。托管向量库地址由用户填写，不采用管理 API 主机冒充数据端点。 |
| `cloudflare-skill` | Cloudflare 运维 Skill | [Cloudflare 管理 API](https://developers.cloudflare.com/api/)的 Token；按所需 DNS / Workers 操作选择权限，Account / Zone ID 另配。 |
| `github-skill` | GitHub 仓库 Skill | [GitHub REST](https://docs.github.com/en/rest)的 PAT；仓库和组织标识与权限需匹配实际任务。 |
| `notion-skill` | Notion 笔记 Skill | [Notion API](https://developers.notion.com/reference/intro)的内部集成令牌；目标页面需授予集成访问权限。 |
| `email-skill` | 邮件通知 Skill | [Resend](https://resend.com/docs/api-reference/introduction) / [SendGrid](https://www.twilio.com/docs/sendgrid/api-reference/how-to-use-the-sendgrid-v3-api/requests)选一家，发件身份另配。 |
| `map-weather-skill` | 地图天气 Skill | [高德 Web 服务](https://lbs.amap.com/api/webservice/summary) / [Mapbox](https://docs.mapbox.com/api/overview/)选一家；[OpenWeather](https://openweathermap.org/api)天气可选。 |
| `browser-skill` | 浏览器自动化 Skill | [Browserbase](https://docs.browserbase.com/reference/api/create-a-session) / [Browserless](https://docs.browserless.io/overview/connection-urls)选一家；前者还需 Project ID，后者需对应部署或地域地址。 |

## Core 契约与验证

`ToolTemplate` 是不可变目录，提供 `all`、严格 ID 查询 `match(templateID:)` 和本地 `matches(search:)`。`ToolTemplateKind` 为 client / agent / skill；`ToolCredentialSlot` 提供稳定槽位 ID、标题、候选提供商 ID、默认提供商、是否可选以及可选环境变量提示。

仅在单一提供商的变量名明确时填写 `environmentVariable`，本版为 `ANTHROPIC_API_KEY`、`BRAVE_API_KEY` 和 `LANGSMITH_API_KEY`；它只是展示文字。选择不同提供商的槽位不显示某一家专用变量名。

目录不包含秘密值或网络操作。向导负责让用户复用已有记录或明确输入新密钥，并在确认后保存工具及关联。可选槽默认不选，同一凭据可关联多个角色或工具。工具组本身只需保存模板 ID，不复制执行逻辑。

`ToolTemplateTests` 检查稳定 ID、已知提供商引用、默认项与可选项、槽位数量上限、品牌和泛用组合区分、文案适配工具字段长度、精确查找、本地搜索、变量名与认证方式差异。执行结果统一记录在 [原生验证记录](../macos/verification.md)。
