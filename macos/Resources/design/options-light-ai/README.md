# Keynest · 浅色 AI 钥匙图标

第二组候选 E / F / G / H，回应“浅色调、AI 钥匙风格”的反馈。当前暂定使用第三组的 **C2「冰蓝通透」**；本组及其他样式均保留，查看 [全部 12 个样式与切换方法](../README.md)。本组生成脚本不改选择文件或已安装应用。

| 方案 | 主题 | 造型 |
| --- | --- | --- |
| E · 珍珠星钥 | 珍珠白、冰蓝与柔紫 | 钥匙圆孔改为四角星芒负形 |
| F · 冰蓝光环 | 冰蓝与柔和天蓝 | 横向光环作钥匙头，配竖向钥匙柄 |
| G · 薄荷连结 | 薄荷白与清透青绿 | 连续双环与钥匙柄融合，表达连结 |
| H · 浅紫灵钥 | 淡紫与珍珠粉 | 星芒直接成为钥匙头，保留圆孔和匙齿 |

保持单个主符号，用形状传达智能感；图标内没有 AI 字母、节点电路或装饰性文字。所有方案使用浅底、柔和渐变与有限的高光阴影，适合与现有 macOS 图标一起比较。

## 资源

- `Keynest-light-ai-options.png`：四格中文方案预览。
- `{E,F,G,H}.png`：1024 像素 PNG。
- `{E,F,G,H}-256.png`：256 像素 PNG。
- `{E,F,G,H}-small-size-QA.png`：16 / 32 / 64 / 128 实际像素，在浅深背景的联系图。
- `{E,F,G,H}.iconset/`：每版十个标准 PNG 表示。
- `{E,F,G,H}.icns`：已实际编译的静态候选图标。

## 制作和检查

独立脚本为 `macos/scripts/make-icon-light-options.swift`，使用 AppKit / Core Graphics 矢量路径。在项目根目录重建：

```sh
swift macos/scripts/make-icon-light-options.swift macos/Resources/design/options-light-ai
```

ICNS 使用 `iconutil -c icns` 分别编译对应 `.iconset`。本机自动化沙盒限制下，iconutil 转换需要获准的沙盒外环境。

- 四版大图及全部浅深背景小尺寸图已目视检查。
- G/H 经过一次路径合并调整：头、柄、匙齿使用真正的布尔并集，统一填色和阴影，消除不自然的内部接缝；匙齿间保留清楚的负形间距。
- 16/32 像素适度加粗细部，不保留大尺寸的细高光线。
- 所有 PNG 的声明与实际尺寸、四个 ICNS 容器均已检查。

这些是静态兼容图标，不宣称具有已验证的 macOS 27 动态折射。设计依据沿用项目 `research/keynest-icon-design.md` 中的 Apple HIG 和 Icon Composer 官方材料。
