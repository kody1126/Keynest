# Keynest 图标设计记录

核实与制作日期：2026-09-23。

本次交付为 **Liquid Glass 视觉语言的静态兼容 ICNS**，以及供未来 Icon Composer 使用的独立 SVG 图层。它已经在本机完成 PNG 渲染与 ICNS 编译，不包含已编译的 `.icon` 材质资源；没有声称完成 macOS 27 上的动态折射、随背景变化或深浅/单色外观适配。

## 设计选择

- 一把完整、厚实的钥匙作为主要识别形状，圆孔使用真实镂空路径；两层轻薄收纳片表达“收藏与管理”。没有文字、服务商标志、闪光装饰或额外盾牌。
- 冰蓝至青绿的底座提供深度；光源来自上方，亮边集中在上缘。前后收纳片的对比弱于钥匙，保留主次。
- 1024 像素画布，静态版本预制圆角外形与细微阴影。钥匙以单个填充轮廓绘制，避免多根描边在交接处产生接缝。
- 每种图标尺寸直接渲染矢量路径。16/32 像素版本略微加粗钥匙柄、减弱后片，让小尺寸识别优先于材质细节。
- SVG 图层保留同一几何形状，但删除静态阴影、透明度、亮边与底座蒙版；背景渐变应以后在 Icon Composer 中设置。

## 官方依据

1. [Apple HIG — App icons](https://developer.apple.com/design/human-interface-guidelines/app-icons)：图标应清晰表达用途、容易辨认，并在各平台保持一致。官方索引中的变更记录标为 2026-06-08 更新 Liquid Glass 指引；此处据此保持单一主体和简洁构成。
2. [WWDC26 — Platforms State of the Union](https://developer.apple.com/videos/play/wwdc2026/102/)：2026 年的图标材质趋向更清晰、边缘更明确；Icon Composer 支持多层玻璃与可调折射。本次借用的是这套视觉方向，未宣称当前 ICNS 具备其运行时效果。
3. [Apple — Icon Composer](https://developer.apple.com/icon-composer/)：当前版本加入更清晰的镜面高光、上方光线和折射控制，并可预览多种外观。静态导出图与系统分层图标是不同产物。
4. [Creating your app icon using Icon Composer](https://developer.apple.com/documentation/xcode/creating-your-app-icon-using-icon-composer)：Mac 图层使用 1024 × 1024 画布；优先导出 SVG，并按前后顺序命名。导出时去除阴影、模糊、透明度、背景渐变和最终蒙版，由 Composer/系统完成这些效果。将 `.icon` 纳入 Xcode 构建后，还应在模拟器或真机检验外观。

最后一项的最新索引内容还明确支持在 Composer 中比较 macOS 26 与 27 的渲染。这里提供的 SVG 是进一步制作 `.icon` 的源材料，尚未经 Composer 导入验证。

## 本机工具核实

- macOS 26.5.1，构建号 25F80；只有 Command Line Tools，Swift 6.3.3。
- `/usr/bin/iconutil` 可用。
- `xcrun --find actool`、`xcrun --find icontool` 未找到对应工具；未找到 Icon Composer 或完整 Xcode 应用。
- 不下载或安装 Xcode，不伪造 `.icon` 文件格式。
- `iconutil` 在工具沙盒内将有效输入报为 `Invalid Iconset`；同一条本地转换命令在获准的沙盒外运行成功。没有变更 PNG 来规避该环境限制。

## 交付与重建

| 文件 | 用途 |
| --- | --- |
| `macos/scripts/make-icon.swift` | AppKit/Core Graphics 确定性离线渲染器，兼容现有单参数构建入口 |
| `macos/Resources/AppIcon.iconset/` | 16–1024 像素的十个标准 PNG 表示 |
| `macos/Resources/AppIcon.icns` | 经 iconutil 实际编译的静态图标 |
| `macos/Resources/design/Keynest-1024.png` | 1024 像素透明背景预览 |
| `macos/Resources/design/Keynest-small-size-QA.png` | 16/32/64/128 实际像素大小，在浅、深背景的联系图 |
| `macos/Resources/design/IconComposer-layers/` | 从后到前的三个不带材质效果 SVG 图层 |

从 `macos/` 目录运行：

```sh
swift scripts/make-icon.swift Resources/AppIcon.iconset Resources/design
iconutil -c icns Resources/AppIcon.iconset -o Resources/AppIcon.icns
```

原有 `build-app.sh` 使用的 `swift scripts/make-icon.swift .build/AppIcon.iconset` 仍有效，只会生成标准图标表示。预览和 SVG 不会进入 `.iconset` 目录。

## 已完成验收

- 渲染器编译和运行通过；10 个 PNG 的实际宽高均与文件名所声明尺寸对应。
- 1024 预览及浅深背景联系图均已目视检查；钥匙镂空、牙齿、外轮廓正常，16/32 像素仍能辨认为钥匙。
- 联系图标签位置经过一次修正，避免浅色行标签压到背景分界。
- `iconutil` 转换成功，产物为 Apple ICNS 文件。

后续若采用 Icon Composer，应将三个 SVG 分别导入并设置后片、前片、钥匙的分层材料；保留钥匙的高对比形状，调整背景渐变；最后在实际 macOS 27 环境检查默认、深色与单色模式。这里未对未来材料参数作未经验证的精确承诺。
