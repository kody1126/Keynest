# Keynest 图标候选

这里保留第一组 A–D 静态 macOS 图标。当前暂定使用第三组的 **C2「冰蓝通透」**，A–D 的所有资源仍完整保留。查看 [全部 12 个样式与切换方法](../README.md)。本组生成脚本只更新候选资源，不改选择文件或已安装应用。

| 方案 | 方向 | 主要形状 |
| --- | --- | --- |
| A · 冰青玻璃 | 通透、轻盈 | 白色钥匙与两层收纳片；保留原始方案 |
| B · 深蓝保险库 | 稳重、安全 | 实体保险库门与明亮钥匙孔 |
| C · 暖白钥匙扣 | 极简、中性 | 石墨色钥匙圈与细长挂扣 |
| D · 淡紫字形 | 品牌识别 | 定制 K 轮廓，左上圆孔兼作钥匙环 |

- `Keynest-icon-options.png`：四格中文标注对比图。
- `{A,B,C,D}.png`：1024 像素透明背景大图。
- `{A,B,C,D}-256.png`：256 像素预览。
- `{A,B,C,D}-small-size-QA.png`：各方案在浅、深背景上的 16/32/64/128 实际像素联系图。
- `{A,B,C,D}.iconset/` 与 `{A,B,C,D}.icns`：标准图标表示与已编译的可选资源。

渲染脚本为 `macos/scripts/make-icon-options.swift`，保持独立于应用构建。A 从保留的原始 `macos/Resources/AppIcon.iconset` 复制；该源资产不代表当前选择。B、C、D 使用 AppKit/Core Graphics 路径直接绘制，每种像素尺寸独立渲染。

从项目根目录重新生成预览：

```sh
swift macos/scripts/make-icon-options.swift macos/Resources/design/options
```

如果需要重建候选 ICNS，再分别用 `iconutil -c icns` 转换对应 `.iconset`。在当前自动化沙盒中 iconutil 需要获准的沙盒外执行环境；源 PNG 本身尺寸与格式有效。

本次已检查所有方案的浅深背景小尺寸表现，并验证 ICNS 容器。设计沿用 [Apple HIG 图标规范](https://developer.apple.com/design/human-interface-guidelines/app-icons) 的清晰、简洁与光学平衡原则，官方来源与工具链范围详见项目 `research/keynest-icon-design.md`。这些候选是静态效果，不是已验证的 macOS 27 动态 Icon Composer 材质。
