# macOS 原生密钥收藏工具：交互参考

核实日期：2026-09-23。只读取 Apple 官方规范、开发者官网／文档、App Store 产品页与作者 GitHub；未安装或运行外部 App。下列功能描述来自产品方，并非独立安全审计。设计建议是针对本次产品目标的取舍。

## 可以借鉴的产品

| 产品 | 已核实的交互 | 对本项目的价值 |
| --- | --- | --- |
| [SecretKit API Key Vault](https://apps.apple.com/us/app/secretkit-api-key-vault/id6758926821?mt=12) | 按项目整理、每个 Key 可写备注、复制后自动清理、空闲锁定。当前版本提供默认关闭的可选加密 iCloud 同步。 | 一条密钥需要用途上下文；锁定与复制反馈融入日常操作。不能再将当前版本描述为完全没有同步功能。 |
| [KeyStack: Env Secrets Manager](https://apps.apple.com/us/app/keystack-env-secrets-manager/id6769442454?mt=12) | 项目与环境筛选、一条变量可关联多个项目、导入前预览与标记重复、批量操作、轮换到期标记。 | 通用秘密以用途／项目组织；导入采用预览再保存。这里指 Nerd Snipe 的 Mac App，与 usekeystack.com 授权码平台不同。 |
| [Lokalite](https://github.com/RubenGlez/lokalite) | 菜单栏搜索、复制与揭示，最近使用置顶，可配置全局快捷键，项目与环境、30 秒剪贴板清理。 | 主窗口整理；后续菜单栏小窗承担随手查找和复制。 |
| [SnippetsLab](https://www.renfei.org/snippets-lab/) | 文件夹、标签、智能分组、模糊搜索；菜单栏助手支持键盘查找与复制。 | 借鉴收藏库的信息架构及快速取用，而非将其当作密钥保管的安全方案。 |

## 五条具体设计建议

1. **使用可调整宽度的三栏收藏库。** 左侧为「全部」「星标」「最近使用」和「标签」，中间列表显示名称、用途一句话、来源域名、少量标签，右侧显示所选条目。类型可以是 API Key、Skill 凭据、服务令牌或其他；服务商是条目属性及可选筛选。初版可用 `NavigationSplitView`，保留系统边栏显隐和窗口缩放行为。Apple 建议边栏层级保持简洁，并在需要时增加内容列表与详情栏。[Apple Sidebars](https://developer.apple.com/design/human-interface-guidelines/sidebars?changes=_6_7)、[Apple Split views](https://developer.apple.com/design/human-interface-guidelines/split-views?changes=_3_5&language=objc)

2. **搜索只有一个明确入口，默认搜名称、标签、用途、来源。** 使用工具栏系统搜索框和 `⌘F`，输入立即筛选；空搜索回到当前集合。标签可点击追加筛选，支持大小写无关且保留原始显示；搜索秘密值不作为默认功能，也不向 Spotlight 导出密钥或备注。Apple 强调主搜索位置与统一入口；SnippetsLab 的标签和搜索作用域可参考。[Apple Searching](https://developer.apple.com/design/human-interface-guidelines/searching)、[Apple Search fields](https://developer.apple.com/design/human-interface-guidelines/search-fields)、[SnippetsLab 标签与搜索](https://www.renfei.org/snippets-lab/manual/mac/essentials.html)

3. **复制密钥是第一操作，揭示是独立操作。** 在详情的掩码密钥旁放「复制」和眼睛按钮；复制无需先显示秘密。列表支持方向键选择、`⌘C` 复制所选条目（编辑文字时保留系统文字复制），复制后就地显示「已复制」，不弹确认框。清理剪贴板前核对它仍是本次写入内容，避免擦除用户后来复制的其他内容。菜单栏快捷取用可作为后续功能。参考产品均将快速复制放在主要路径。[SecretKit](https://apps.apple.com/us/app/secretkit-api-key-vault/id6758926821?mt=12)、[Lokalite](https://github.com/RubenGlez/lokalite)、[SnippetsLab Assistant](https://www.renfei.org/snippets-lab/manual/mac/assistant.html)

4. **新增表单允许先保存一个简单收藏，详情保留足够上下文。** 首屏只有名称与密钥必填；可选「用途／来源」「来源链接」「标签」「备注」，更多配置再展开。来源链接表示申请、文档或项目页面，与 API Base URL 分开；只有用户点击才用系统浏览器打开，不自动抓取 favicon。编辑时使用同一布局，来源域名在列表中帮助辨认。SecretKit 的每 Key 备注、KeyStack 的项目／环境信息证明上下文有价值；区分来源链接与 Base URL 是本产品的设计取舍。[SecretKit](https://apps.apple.com/us/app/secretkit-api-key-vault/id6758926821?mt=12)、[KeyStack](https://apps.apple.com/us/app/keystack-env-secrets-manager/id6769442454?mt=12)

5. **工具栏只保留高频命令，额度放在详情下方。** 工具栏建议为边栏显隐、搜索、添加、锁定；所选条目的编辑、删除放详情或上下文菜单，并在 macOS 菜单栏提供同名命令。额度区仅为支持项显示「查询额度」及上次更新时间；未接入条目也能完整收藏。使用系统字体、SF Symbols、系统选中色与标准控件，让系统处理材质、明暗模式、缩窄时的溢出；不要把统计卡片挤到收藏列表前面。Apple 建议慎选工具栏项目并优先标准组件。[Apple Toolbars](https://developer.apple.com/design/human-interface-guidelines/toolbars?changes=la)、[Apple Designing for macOS](https://developer.apple.com/design/human-interface-guidelines/designing-for-macos/)

## 首版完成标准

用户能从「打开 App → 搜索一个用途或标签 → 选中 → 复制」完成最常见任务；从「添加 → 名称与密钥 → 保存」完成最短收藏路径。增加备注、来源链接和额度查询应保持这两条路径简洁。
