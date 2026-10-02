# Keynest

**简体中文** · [English](README.en.md)

一个原生 macOS API 密钥管理工具。解锁后从首页找到平台，直接复制需要的那把密钥；用账号、环境和 API 主机区分同平台的多把密钥。也可以把工具需要的密钥组织在一起，同一把密钥供多个工具使用。

当前主版本为 **0.8.1 安全修复版 · 原生 Mac 实验版**，使用 SwiftUI / AppKit，不需要 Node.js、浏览器或云端账户。面向 macOS 14 及以上的 Apple Silicon Mac。

## 打开应用

从 [GitHub Releases](https://github.com/kody1126/Keynest/releases) 下载 macOS 安装包，或按下方说明从源码构建。建议安装到 `~/Applications/Keynest.app`。可从 Finder 打开，或运行：

```sh
open "$HOME/Applications/Keynest.app"
```

当前分发包为 `Keynest-0.8.1-arm64.dmg`（[下载 v0.8.1](https://github.com/kody1126/Keynest/releases/tag/v0.8.1)），同时包含正式版 `Keynest.app` 和独立演示版 `Keynest Demo.app`。统一安装到 `~/Applications` 后打开。应用使用本地 ad-hoc 签名，未进行 Apple Developer ID 签名或公证。

第一次打开时，设置至少 **12 个字符**的主密码。进入首页后选择一个平台，粘贴密钥并点击「保存到首页」；名称与通用 API 地址按预设填入，项目专属地址按提示填写，账号和环境可以按需展开。「完整编辑…」可继续填写标签、备注或工具关联。以后解锁默认进入首页。忘记主密码后无法找回。

支持 Touch ID 的 Mac 可以勾选「解锁后启用 Touch ID」，或解锁后在设置中开启。以后打开 App 时会调用系统指纹验证；主密码保留为备用，取消验证后可切换密码。指纹变化、更换主密码或迁移到另一台 Mac 后需要重新启用。指纹解锁资料只保存在这台 Mac，不会放入导出的加密备份。

## 先体验演示库

打开 `~/Applications/Keynest Demo.app`，输入测试密码 **`Keynest-Demo-2026`** 即可，不需要用户名。这是本地演示库，不是模型服务商的真实 API 账号。

新演示库包含 **34 把虚构密钥、10 个工具**，包含 Cline、OpenClaw、n8n、LangGraph 的密钥组合，以及 Skill 与 Agent 服务示例。可以体验添加、编辑、关联、搜索、显示、复制与 Touch ID；额度请求、备份导入导出及改密码在演示版中禁用。目录升级保留已有修改，不补回被删除的旧样例，测试密码不变。

演示数据保存到 `~/Library/Application Support/Keynest Demo/`，与正式库分开。**演示密码是公开的，请勿放入真实凭据。** 官网链接仍可手动交给浏览器打开，所以演示版不是完全离线模式。详细说明见 [演示版使用说明](macos/README.md#独立演示版)。

## 日常使用

- **首页直接取用**：密钥按平台放在卡片中，每把都有独立的「复制」按钮。每张卡片直接展示最多 2 把，超过 2 把时点击「查看全部」明确选择；账号、环境和 API 主机名帮助区分个人、团队与自建网关。
- **首页筛选与搜索**：用「全部 / 模型 / Skill 与服务 / 常用」分段筛选。首页搜索平台名称及别名、密钥名称、账号、环境、标签和关联工具名称，不搜索密钥字段、网址或备注。管理页保留原来的元数据搜索，包括网址与备注。
- **快速添加**：从首页选择平台，主要只需粘贴密钥。已有同平台密钥时，可选信息自动展开，并生成不同的编号默认名，方便继续填写账号或用途；「完整编辑…」始终可达。首页卡片底部也可继续添加同平台密钥。
- **25 个工具模板**：Cursor、Cline、OpenClaw、Dify、n8n、LangGraph 等，以及搜索、采集、浏览器、Cloudflare、GitHub、Notion、邮件和地图天气 Skill。选工具后复用已有密钥或录入新密钥，一次保存全部关联；可选用途默认关闭。
- **按工具组织**：管理页保留全部密钥、常用密钥、未归组、我的工具和分类。一个工具可关联多把密钥，一把密钥也可关联多个工具；移除工具只清除关联，密钥仍保留。
- **区分账号与环境**：每把密钥可标注账号和环境，列表支持环境筛选。在工具内新建密钥会自动归入当前工具，也可以关联已有密钥。
- **61 个服务商预设**：按模型与推理、图像与语音、搜索与采集、开发与数据、消息与协作、Agent 工具分组，不按国家分类。提供 API 官网、默认请求地址及填写提示；项目专属地址留空由用户填写。61 个 API 品牌图标和 15 个工具品牌图标随包提供，无需联网加载。
- **API 官网入口**：已知平台的首页卡片、快速添加、完整编辑和详情提供独立的「API 官网」链接。API 地址仍作为接口地址保存；已有自定义来源网站保持原样。
- **查看与编辑**：首页每把密钥的更多菜单可复制 API 地址、设置常用、查看详情或编辑。管理页的列表和详情也可复制密钥；两种搜索都不读取密钥字段。
- **隐藏与锁定**：密钥默认隐藏，显示后 20 秒自动隐藏，切换条目或窗口失焦也会隐藏；闲置 10 分钟或系统休眠后锁定。
- **复制内容**：密钥或 API 地址仅写入本机剪贴板，关闭该次复制的跨设备接力，并标记为敏感临时内容；30 秒后清除本次复制内容；如果这期间复制了其他内容，保留新的剪贴板内容。
- **备份**：通过工具栏菜单导出 `.keynest` 加密备份。导入到现有密钥库时合并条目，不覆盖已有记录；全新密钥库也能从备份恢复。

常用快捷键：`⌘1` 首页、`⌘2` 管理全部密钥、`⌘F` 首页搜索、`⌘N` 添加密钥、`⇧⌘N` 添加工具、`⇧⌘L` 锁定。`⇧⌘C` 复制所选密钥、`⌘E` 编辑所选密钥，需要先在管理页选中记录；首页不自动选中任何一把。完整使用与构建方法见 [macOS 使用说明](macos/README.md)。

编辑时可以重新选择预设。密钥、备注、标签和自定义名称或地址会保留；只替换空字段或上一预设的默认值。从表单返回选择器后取消，会回到原草稿。切换到不同预设会关闭原额度查询设置并清除旧快照，选择预设本身不发送密钥。

只有全新空白草稿仍使用默认分类时，首次选择预设才会自动建议分类；编辑已有收藏或之后切换预设不会重新归类。

## 可选额度查询

编辑收藏时展开「高级选项」，明确选择额度服务；之后在详情的「额度查询」中手动刷新。默认不启用，没有全平台实时同步或后台轮询。

| 服务 | 本版查询范围 |
| --- | --- |
| DeepSeek | 官方 API 账户余额，币种分别显示 |
| 硅基流动 | 中国站账户总余额 |
| OpenRouter | 当前 Key 的限额与用量，不是账户总余额 |

其余模型与工具仍然可以正常收藏。额度是查询时的快照，可能存在上游结算延迟；未设置 Key 限额不表示无限余额。多个 Key 也可能共用同一个账户余额。

正式版查询只访问选定服务的固定官方 HTTPS 接口，不猜测密钥归属，不向多个平台试送密钥。填写了 API 地址时，会检查它与额度服务是否同源；不匹配时不发送密钥。API 官网与来源网站只在用户点击时交给默认浏览器打开。

## 数据与安全

原生版本的数据文件位于：

```text
~/Library/Application Support/Keynest/vault.keynest
```

名称、密钥、标签、备注及额度快照整体以 AES-256-GCM 加密，使用 PBKDF2-HMAC-SHA256（600,000 次迭代、32 字节随机 salt）从主密码派生密钥，每次写入使用新的随机 nonce。没有使用 MD5。正式版不保存你设置的主密码。应用不主动云同步、不自动读取其他工具的凭据，也不修改 CLI、MCP 或 Skills 的配置。

Touch ID 使用 Secure Enclave 的当前指纹集合访问控制来保护解锁能力，本地只保存硬件绑定的私钥表示和经过加密封装的解锁资料；验证失败不能解密密钥库。实现与验证范围见 [Touch ID 记录](research/touch-id-0.6.md)。

0.8.1 沿用 0.7 的数据载荷版本 3，读取旧版 1 / 2，演示目录修订号仍为 7；本次修复不改变加密格式或重填演示数据。0.7 引入的旧库升级保护继续适用：第一次保存旧格式前，在原目录保留 `vault-before-0.7.keynest` 原始密文备份，已有 0.5 备份也会保留。0.6 及更早版本无法读取载荷版本 3，回退需使用升级前备份及当时的密码。详细规则见 [升级与兼容性](macos/README.md#升级与兼容性)。

0.8.1 修复取消导入后仍提交、剪贴板归属竞争、硬链接文件权限、异常 URL、特定解锁资料切片崩溃，以及磁盘同步失败后内存与密文不一致的问题；闲置锁定改用单调时钟，两个 App 启用 Hardened Runtime。旧密码继续可用，新建或修改密码额外限制为最多 16 KiB UTF-8。详见 [本轮安全检查与修复](research/security-review-0.8.1.md)。

这是未经独立安全审计的实验版。静态文件加密不能防止已经控制本机的恶意软件、解锁时的内存读取、截屏或第三方剪贴板历史。系统备份软件仍可能备份加密文件。详细机制与限制见 [macOS 安全边界](macos/README.md#安全边界)。

## 图标样式

当前暂定 **C2「冰蓝通透」**：保留 C 的钥匙扣造型，使用 F 方向的浅冰蓝配色。[查看当前样式](macos/Resources/design/options-c-palette/C2.png)。

全部 **12 个样式**及其生成脚本、PNG、ICNS 和小尺寸预览均保留，方便继续调整：

- [A–D：四种造型方向](macos/Resources/design/options/Keynest-icon-options.png)
- [E–H：浅色 AI 钥匙](macos/Resources/design/options-light-ai/Keynest-light-ai-options.png)
- [C1–C4：钥匙扣浅色配色](macos/Resources/design/options-c-palette/Keynest-C-palette-options.png)

构建时读取 [AppIcon.selection](macos/Resources/AppIcon.selection) 选择样式；修改其中的编号后重新构建即可切换，不删除其他候选。完整索引与操作见 [图标样式库](macos/Resources/design/README.md)。

## 开发与参考

- [原生版本的构建、备份及开发说明](macos/README.md)
- [macOS 设计参考](research/macos-design-references.md)
- [现有项目与额度接口调研](research/2026-09-22-landscape.md)
- [0.5 产品方向与取舍](research/product-direction-0.5.md)
- [0.7 API 预设及官方来源](research/api-catalog-0.7.md)
- [Skill / Agent 工具模板与来源](research/skill-agent-templates-0.7.md)
- [0.8 首页与快速添加说明](research/home-usability-0.8.md)
- [0.8.1 安全检查与修复](research/security-review-0.8.1.md)
- [原生版本验证记录](macos/verification.md)

原生源码位于 `macos/`，没有第三方 Swift Package 依赖。使用 macOS Command Line Tools 即可检查、构建和打包，不需要安装完整 Xcode：

```sh
git clone https://github.com/kody1126/Keynest.git
cd Keynest/macos
bash scripts/run-checks.sh
bash scripts/run-app-checks.sh
zsh scripts/build-app.sh
zsh scripts/build-demo-app.sh
zsh scripts/package-app.sh
zsh scripts/install-apps.sh
```

中间 App 只放在 `macos/dist/apps.noindex/`，不要从构建目录或 DMG 直接运行。安装脚本将两份 App 安装到 `~/Applications`；替换前核对身份与签名，把旧 App 保存为经过校验的 `.build/app-backups/` ZIP，失败时尝试回滚。安装不启动 App、不访问密钥库，也不更改系统索引设置。

打包脚本会构建两个 App、生成 DMG、执行镜像校验并输出 SHA-256 文件。0.8.1 的检查范围、构建和实机验证结果统一以 [验证记录](macos/verification.md) 为准。

## 保留的 Web 实验

根目录的 Node.js / Web 实现保留为早期 **0.1 技术实验**。它与原生 App 的数据位置、加密格式和功能不同，当前主入口是原生 App。

需要回看 Web 实验时，使用 Node.js 22 或更高版本，在项目根目录运行 `npm start`，从终端输出的本机链接进入。它默认把数据保存到项目 `.data/vault.json`，通过 `API_VAULT_DATA_DIR` 可以指定其他目录。测试命令为 `npm test`。

原生版本不会自动导入、覆盖或删除 Web 实验的 `.data` 数据。两者的加密备份格式不互通，请分别保管。

## 许可证与参与

项目原创代码采用 [MIT 许可证](LICENSE)。第三方品牌图标保留各自的许可与商标权利，不因本项目 MIT 许可而获得额外授权，详见 [第三方声明](THIRD_PARTY_NOTICES.md)。

欢迎通过 [Issues](https://github.com/kody1126/Keynest/issues) 反馈使用问题，或参照 [贡献说明](CONTRIBUTING.md) 提交修改。漏洞请按 [安全政策](SECURITY.md) 私下报告，不要提交真实密钥或密钥库。

本项目后续更新会在检查通过后提交并推送至 GitHub，同时维护中英文 README；项目协作规则见 [AGENTS.md](AGENTS.md)。这不是后台自动上传机制，个人密钥库、测试运行数据和构建产物不会进入源码仓库。
