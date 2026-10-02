# Keynest 图标样式库

当前暂定 **C2「冰蓝通透」**：保留 C 的钥匙扣造型，采用 F 方向的浅冰蓝配色。选择记录在 [AppIcon.selection](../AppIcon.selection)。全部 **12 个样式**、生成脚本及导出资源均保留，方便继续修改和比较。

## 三组预览

| 组别 | 方向 | 预览与说明 |
| --- | --- | --- |
| A–D | 最初的四种造型 | [四格预览](options/Keynest-icon-options.png) · [说明](options/README.md) |
| E–H | 浅色 AI 钥匙 | [四格预览](options-light-ai/Keynest-light-ai-options.png) · [说明](options-light-ai/README.md) |
| C1–C4 | 保留 C 造型的浅色配色 | [四格预览](options-c-palette/Keynest-C-palette-options.png) · [说明](options-c-palette/README.md) |

## 全部样式

每个样式都有 1024/256 PNG、十个标准尺寸的 `.iconset`、静态 `.icns` 和浅深背景的 16/32/64/128 像素检查图。

| 编号 | 名称 | 1024 预览 | 小尺寸检查 | ICNS |
| --- | --- | --- | --- | --- |
| A | 冰青玻璃 | [PNG](options/A.png) | [QA](options/A-small-size-QA.png) | [ICNS](options/A.icns) |
| B | 深蓝保险库 | [PNG](options/B.png) | [QA](options/B-small-size-QA.png) | [ICNS](options/B.icns) |
| C | 暖白钥匙扣 | [PNG](options/C.png) | [QA](options/C-small-size-QA.png) | [ICNS](options/C.icns) |
| D | 淡紫字形 | [PNG](options/D.png) | [QA](options/D-small-size-QA.png) | [ICNS](options/D.icns) |
| E | 珍珠星钥 | [PNG](options-light-ai/E.png) | [QA](options-light-ai/E-small-size-QA.png) | [ICNS](options-light-ai/E.icns) |
| F | 冰蓝光环 | [PNG](options-light-ai/F.png) | [QA](options-light-ai/F-small-size-QA.png) | [ICNS](options-light-ai/F.icns) |
| G | 薄荷连结 | [PNG](options-light-ai/G.png) | [QA](options-light-ai/G-small-size-QA.png) | [ICNS](options-light-ai/G.icns) |
| H | 浅紫灵钥 | [PNG](options-light-ai/H.png) | [QA](options-light-ai/H-small-size-QA.png) | [ICNS](options-light-ai/H.icns) |
| C1 | 珍珠蓝紫 | [PNG](options-c-palette/C1.png) | [QA](options-c-palette/C1-small-size-QA.png) | [ICNS](options-c-palette/C1.icns) |
| **C2** | **冰蓝通透（暂定使用）** | [PNG](options-c-palette/C2.png) | [QA](options-c-palette/C2-small-size-QA.png) | [ICNS](options-c-palette/C2.icns) |
| C3 | 雾白双蓝 | [PNG](options-c-palette/C3.png) | [QA](options-c-palette/C3-small-size-QA.png) | [ICNS](options-c-palette/C3.icns) |
| C4 | 冰蓝银白 | [PNG](options-c-palette/C4.png) | [QA](options-c-palette/C4-small-size-QA.png) | [ICNS](options-c-palette/C4.icns) |

256 像素版本位于对应目录的 `<编号>-256.png`；标准 PNG 表示位于 `<编号>.iconset/`。

## 切换与重建

1. 编辑 `macos/Resources/AppIcon.selection`，把内容设为一个编号：`A`、`B`、`C`、`D`、`E`、`F`、`G`、`H`、`C1`、`C2`、`C3` 或 `C4`。文件只需一行编号，当前为 `C2`。
2. 在 `macos/` 目录执行下列命令。正式 App 从所选候选的 `.iconset` 编译 ICNS；演示 App 继承本次正式构建的图标。

```sh
zsh scripts/build-app.sh
zsh scripts/build-demo-app.sh
zsh scripts/install-apps.sh
open ~/Applications/Keynest.app
```

构建产物位于 `macos/dist/apps.noindex/Keynest.app` 和 `macos/dist/apps.noindex/Keynest Demo.app`。更新前先退出应用；安装脚本会校验并替换 `~/Applications/` 中的对应副本，将旧版压缩归档。日常使用只打开已安装版本，避免系统搜索收录多个开发副本。

如需新的分发包，在 `macos/` 目录运行 `zsh scripts/package-app.sh`，会重建两个 App 并打包。这里的选择只在构建时生效，应用没有运行时图标选择设置；切换编号不改动其他候选或密钥库。

## 生成脚本与后续修改

| 样式 | 生成脚本 | 输出目录（相对 `macos/`） |
| --- | --- | --- |
| A 原始母版 | [make-icon.swift](../../scripts/make-icon.swift) | `Resources/AppIcon.iconset` 与 `Resources/design` |
| A–D | [make-icon-options.swift](../../scripts/make-icon-options.swift) | `Resources/design/options` |
| E–H | [make-icon-light-options.swift](../../scripts/make-icon-light-options.swift) | `Resources/design/options-light-ai` |
| C1–C4 | [make-icon-c-palettes.swift](../../scripts/make-icon-c-palettes.swift) | `Resources/design/options-c-palette` |

修改对应脚本里的颜色或路径后，在 `macos/` 目录重新生成该组。例如修改 C2 配色：

```sh
swift scripts/make-icon-c-palettes.swift Resources/design/options-c-palette
zsh scripts/build-app.sh
zsh scripts/build-demo-app.sh
```

其他组的 PNG 与 `.iconset` 重建命令：

```sh
swift scripts/make-icon.swift Resources/AppIcon.iconset Resources/design
swift scripts/make-icon-options.swift Resources/design/options
swift scripts/make-icon-light-options.swift Resources/design/options-light-ai
```

`make-icon-options.swift` 从保留的 A 母版复制 A，再绘制 B–D。`Resources/AppIcon.iconset`、`Resources/AppIcon.icns`、`design/Keynest-1024.png` 和 `design/IconComposer-layers/` 是原始 A 资源，其旧文件名不代表当前选择；应用构建以 `AppIcon.selection` 为准。

生成脚本更新 PNG 和 `.iconset`。若修改了候选后还需要更新样式库中的独立 ICNS，可在 `macos/` 目录执行对应转换，例如：

```sh
iconutil -c icns Resources/design/options-c-palette/C2.iconset -o Resources/design/options-c-palette/C2.icns
```

这些都是静态兼容图标；未宣称完成 macOS 27 动态 Icon Composer 材质验证。最初的官方设计依据与工具链范围保留在 [图标设计记录](../../../research/keynest-icon-design.md)。
