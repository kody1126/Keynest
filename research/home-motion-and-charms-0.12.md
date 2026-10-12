# 首页实时排序与挂件材质：0.12 设计依据

查阅日期：2026-10-07。本文记录设计依据和实现参数，不代替最终安装包的原生 GUI 验收。

## 实时让位排序

Apple 将 `reorderingCadence` 定义为拖动过程中重排项目、展示潜在落点的节奏，默认采用 immediate；UIKit 的交互移动接口也把持续更新目标位置与结束、取消操作分开。这里借鉴交互原则，Keynest 的 macOS 首页仍采用原生 AppKit 事件与 SwiftUI 布局，不引入 UIKit。

成熟项目 Sortable 的实际源码会记录上次目标、方向和目标移动距离，并用命中区域阈值抑制反复交换。这个问题同样存在于不同高度的瀑布流：卡片让位后自己移动到鼠标下方，不能被误当作新的拖动意图。

本次采用的约束：

- 拖动副本保持最初抓取偏移，按指针直接移动；周围真实卡片在 hover 时让位，源卡保留布局占位。减少动态效果时不使用弹簧和放大。
- 手势由窗口内的独立会话接管。源卡随布局重建不会丢失手势；不创建系统拖放会话，不向剪贴板写入卡片内容。
- 命中使用 SwiftUI 在同一 viewport 中测得的卡片矩形。让位区域带有防重复触发锁存；滚动时同步平移锁存区域，布局测量过期时不猜测目标。
- 临时顺序、一次手势提交后的编辑草稿、加密库中的已保存顺序分离。取消一次手势恢复该次手势之前的草稿；“完成”才写入加密库。
- 锁定、离开页面、失活及取消必须移除预览、事件监视器、滚动计时器和待释放任务。异步等待新布局的 mouse-up 不得越过后续取消。

一手参考：

- [Apple：reorderingCadence](https://developer.apple.com/documentation/uikit/uicollectionview/reorderingcadence-swift.property)
- [Apple：updateInteractiveMovementTargetPosition](https://developer.apple.com/documentation/uikit/uicollectionview/updateinteractivemovementtargetposition(_:))
- [Sortable：重排时记录目标变化与方向](https://github.com/SortableJS/Sortable/blob/master/src/Sortable.js#L1162-L1241)
- [Sortable：交换区域及反向阈值](https://github.com/SortableJS/Sortable/blob/master/src/Sortable.js#L1722-L1787)

Sortable 仅作算法参考，没有引入该依赖或复制其浏览器拖放实现。

## Blender 几何与 SceneKit 实时画面

Blender 导出提供顶点、法线、三角面及 `glass` / `metal` / `logo` 角色。应用按角色重新建立 SceneKit 材质；Blender 的节点材质、区域光、Cycles 折射与色彩管理不会自动包含在这些 JSON 网格中。程序生成的主挂扣与链环则是独立几何，增加品牌模型精度不会改变链条。

Apple 明确说明，`physicallyBased` 材质会忽略 `reflective`、`fresnelExponent`、`locksAmbientWithDiffuse` 等传统材质参数。本次移除这些无效设置，明确选择 Metal，通过 `lightingEnvironment`、金属度、粗糙度和清漆控制实时反射。

| 实时项目 | 当前取值与目的 |
| --- | --- |
| 品牌珐琅 | 原品牌 sRGB 色；不透明；metalness 0.04、roughness 0.18、clear coat 0.45、coat roughness 0.12，减轻大片白色高光遮盖颜色 |
| 白铂金属 | sRGB 0.84 / 0.86 / 0.88；metalness 0.95、roughness 0.16，与模型新增的银色侧壁共用 |
| 通用玻璃钥匙 | metalness 0、roughness 0.12、clear coat 0.55、coat roughness 0.10；透明度 0.76，减少透明效果时为 1；属于实时半透明近似，不声称物理折射 |
| 环境 | 一次生成的 1536 × 768 sRGB 棚拍环境，暗部间隔与三块柔光板提供金属曲率对比；环境强度 0.90 |
| 灯光与曝光 | 主光 580、补光 150、环境光 35、曝光偏移 −0.40；固定曝光；阴影贴图 2048 × 2048 |
| 清晰度与开销 | 保留 Retina 和 8× MSAA / 4× 回退；程序链环 48 × 16 分段；不启用景深、运动模糊或 bloom；保留静止、离屏、失活时停止渲染的机制 |

这些值是当前实现的艺术参数，并非 Apple 推荐的通用常数。最终应同时查看浅色与深色背景、四个与八个挂件，以及拖动中的细轮廓。网格检查能验证结构和边界，不能证明实际 App 画面已达到预期。

一手参考：

- [Apple：physicallyBased 的有效材质属性与 Metal 要求](https://developer.apple.com/documentation/scenekit/scnmaterial/lightingmodel-swift.struct/physicallybased)
- [Apple：lightingEnvironment](https://developer.apple.com/documentation/scenekit/scnscene/lightingenvironment)
- [Apple：clearCoatRoughness](https://developer.apple.com/documentation/scenekit/scnmaterial/clearcoatroughness)
- [Blender：Mesh API](https://docs.blender.org/api/current/bpy.types.Mesh.html)
- [Blender：Principled BSDF](https://docs.blender.org/manual/en/latest/render/shader_nodes/shader/principled.html)

模型生成过程、第三方品牌来源及许可继续以 [KeychainArt README](../macos/Resources/KeychainArt/README.md) 为准；本文不把品牌派生轮廓描述为原创商标。
