# C 版钥匙扣：浅色配色候选

这一组保留 C 的圆环、长挂扣、倾斜角度、大小及叠放关系，只调整配色与对应的边缘明暗。色彩沿用用户喜欢的 E 珍珠白和 F 冰蓝方向。

当前暂定使用 **C2「冰蓝通透」**。C1、C3、C4 和先前的 A–H 均完整保留，方便后续修改或切换；查看 [全部 12 个样式与切换方法](../README.md)。

| 方案 | 配色 |
| --- | --- |
| C1 · 珍珠蓝紫 | E 的珍珠白底，浅蓝圆环与柔紫挂扣 |
| C2 · 冰蓝通透（暂定使用） | F 的冰蓝底，青蓝圆环与天蓝挂扣 |
| C3 · 雾白双蓝 | 雾白底，青蓝圆环与柔和蓝色挂扣 |
| C4 · 冰蓝银白 | 柔蓝底，银白圆环与浅冰蓝挂扣 |

预览为 `Keynest-C-palette-options.png`；每版提供 1024/256 PNG、标准 `.iconset`、`.icns` 和浅深背景的 16/32/64/128 像素预览。

独立渲染脚本：`macos/scripts/make-icon-c-palettes.swift`。在 `macos` 目录执行：

```sh
swift -module-cache-path .build/icon-palette-module-cache scripts/make-icon-c-palettes.swift
```

使用 AppKit / Core Graphics 的原生路径生成；圆环和挂扣的几何直接复用第一组 C。16/32 像素沿用 C 的稍粗轮廓，银白款另有轻微边缘色以保持辨识度。

构建通过 `macos/Resources/AppIcon.selection` 选择样式，当前内容为 `C2`。修改为其他编号后重新构建即可切换；本组生成脚本只更新候选资源，不改选择文件或已安装应用。

已检查四格大图、各款浅深背景小尺寸预览、1024/256 PNG 尺寸及四个 ICNS 容器。C1–C3 对比更鲜明；C4 刻意降低饱和度和对比，适合偏好银白观感的选择。
