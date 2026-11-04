# Implementation Plan: OctopPet 吉祥物动效素材集成（mascot-integration）

**Input**: Feature specification from `spec/mascot-integration/spec.md`

## Summary

将两个 MIT 许可动画 WebP 章鱼吉祥物素材（peek 探头章鱼 96×64px 30 帧 / type 打字章鱼 88×44px 24 帧，均透明通道无限循环）加入应用资源，并集成到四个场景：思考胶囊中心图标升级为打字章鱼（保留双弧线环绕）、空会话欢迎卡上方探头章鱼、通用空态组件 EmptyView 默认升级为探头章鱼（参数可回退）、关于页新增 MIT 开源致谢卡。全部为 UI 层改动，零网络/服务/存储变更。

## Technical Context

**Language/Version**: ArkTS（HarmonyOS ArkUI，API 12+）
**Primary Dependencies**: ArkUI Image 组件（原生支持动画 WebP 自动循环播放）、现有 OctopThinkingIndicator / EmptyView / WelcomeCard / AboutPage 组件
**State Management**: 沿用项目现有 State Management V1（@Component/@State），本批不引入 V2
**Storage**: N/A（纯资源文件随包分发）
**Testing**: devecocli build 编译验证 + 模拟器（127.0.0.1:5555）部署实测（uinput 触控 + dumpLayout + snapshot_display 截图 + 像素亮度分析）
**Target Platform**: HarmonyOS 模拟器 / 真机
**Project Type**: mobile-app（既有 HarmonyOS 项目增量改动）
**Performance Goals**: 动画仅在承载状态可见时渲染（随 if 条件挂载/卸载）；小区域 24-30 帧动画，无帧率硬指标
**Constraints**: 服务器零改动；素材离线本地化；非本批场景页面视觉零变化；像素风放大禁用插值模糊
**Scale/Scope**: 新增 2 个媒体资源文件，修改 4 个 ArkTS 文件

## Project Structure

### Documentation (this feature)

```text
spec/mascot-integration/
├── spec.md              # 需求规格
├── plan.md              # 本文件
└── tasks.md             # 任务清单
```

### Source Code (repository root)

```text
entry/src/main/
├── resources/base/media/
│   ├── octop_mascot_peek.webp        # 新增：探头章鱼动画（copy 自临时目录）
│   └── octop_mascot_type.webp        # 新增：打字章鱼动画（copy 自临时目录）
└── ets/
    ├── components/
    │   ├── OctopThinkingIndicator.ets   # 修改：中心 logo → 打字章鱼
    │   └── EmptyView.ets                # 修改：默认探头章鱼模式 + 回退参数
    ├── pages/
    │   ├── chat/ChatHomeTab.ets         # 修改：emptyStateBuilder 欢迎卡上方加探头章鱼
    │   └── me/AboutPage.ets             # 修改：新增开源致谢卡
    └── （无新增源码文件）
```

**Structure Decision**: 遵循既有项目架构（pages/components/service/model 分层），不引入 MVVM 迁移、不新增目录与源码文件；本批为纯 UI 装饰增强，2 个资源 + 4 个文件的最小改动集即覆盖全部需求。

## Complexity Tracking

（无 Constitution Check 违规）

## Research & Decisions

**Decision 1 - 资源命名与放置**：素材复制为 `entry/src/main/resources/base/media/octop_mascot_peek.webp` 与 `octop_mascot_type.webp`，以 `$r('app.media.octop_mascot_peek')` / `$r('app.media.octop_mascot_type')` 引用。
**Rationale**: 媒体资源必须置于 resources/base/media/（ArkTS 源码树外）；命名带 octop_mascot_ 前缀避免与现有资源冲突且语义清晰。
**Alternatives considered**: 保留原文件名 peek/type（过短易冲突，弃用）；base64 内嵌（体积膨胀且不可复用，弃用）。

**Decision 2 - 思考胶囊中心替换为打字章鱼**：`OctopThinkingIndicator` 组件内将中心 `octop_logo` 图（正方形 0.55×indSize）替换为打字章鱼 Image，显式宽高约 32×16vp（indSize=44 时，保持 2:1 原始宽高比，半对角线 17.9 < 弧线圆半径 22 不触碰弧线），`objectFit(ImageFit.Contain)` + `interpolation(ImageInterpolation.None)` 保持像素锐利；玫瑰/品牌蓝双弧线环绕动画与组件签名完全不变。
**Rationale**: 打字章鱼语义与"AI 正在思考/生成"完全契合；保留弧线是既有品质动效不回归的最小改动；显式宽高比 Contain 双保险防拉伸。
**Alternatives considered**: 在胶囊旁并列追加章鱼（胶囊宽度增大、破坏现有玻璃胶囊布局，弃用）；新建独立组件（无复用方，弃用）。

**Decision 3 - 空会话探头章鱼置于 emptyStateBuilder**：在 `ChatHomeTab.emptyStateBuilder` 顶部（WelcomeCard 之上）加探头章鱼 Image，约 90×60vp（保持 3:2 宽高比），居中、Contain + None 插值，随空态整体挂载/卸载。
**Rationale**: spec FR-004 明确要求"WelcomeCard 上方"；emptyStateBuilder 是空会话唯一渲染入口，无消息时挂载、产生消息后整枝卸载，天然满足 FR-009 按需渲染。
**Alternatives considered**: 嵌入 WelcomeCard 组件内部（与 spec "上方"表述不符，弃用）；放消息列表滚动区（随滚动移动不稳定，弃用）。

**Decision 4 - EmptyView 默认升级 + 布尔回退参数**：`EmptyView` 新增普通成员 `mascot: boolean = true`；为 true 时图标区渲染探头章鱼 Image（约 96×64vp，Contain + None 插值，替代原 96×96 双层圆形徽章 + SymbolGlyph 整体），为 false 时渲染原徽章形态；标题/副标题/内边距/对齐全部不动。现有 30+ 调用方零修改即获得章鱼形态。
**Rationale**: 用户"把能加上的都加上"要求全空态覆盖，默认值实现零调用方改动；回退参数保留工程灵活性；章鱼替换整个徽章而非塞进圆形底，避免透明像素风图叠色底发灰。
**Alternatives considered**: 默认 false 逐页启用（违背"都加上"，弃用）；保留圆形底叠章鱼（peek 含白色横幅元素，叠 brand_light 底视觉杂乱，弃用）。

**Decision 5 - 关于页致谢卡**：`AboutPage` 版本行下方新增卡片（bg_card 圆角卡样式与版本卡一致），标题"开源致谢"，正文注明吉祥物动效素材源自开源项目 OctopPet（作者 jubaoliang）并基于 MIT License 授权使用。
**Rationale**: MIT 义务是保留版权与许可声明；关于页是应用标准致谢位置；样式复用版本卡视觉语言零学习成本。
**Alternatives considered**: HelpPage（语义弱于关于页，弃用）；单独开源许可页（过重，本批仅一项第三方素材，弃用）。

**Decision 6 - 像素锐利与解码策略**：所有章鱼 Image 统一 `interpolation(ImageInterpolation.None)`（近邻采样，96×64/88×44 放大无发糊）、`objectFit(ImageFit.Contain)`、显式宽高按素材原始宽高比设定；不启用 autoResize（保持原始位图由 GPU 缩放，避免解码侧重采样柔化像素）。
**Rationale**: 像素风是素材风格本体，模糊即缺陷；显式宽高比 + Contain 双重防拉伸（FR-008）。
**Alternatives considered**: 默认插值（发糊，弃用）；autoResize(true)（解码缩放引入平滑，弃用）。

**Decision 7 - 动画播放策略**：完全依赖 ArkUI Image 对动画 WebP 的原生自动循环播放，不自建帧驱动（不用 ImageAnimator/setInterval）。
**Rationale**: 官方 Image 组件支持动图自动播放，零代码成本、系统级优化（LTPO 降频由系统处理）；素材帧数据完整（ANIM/ANMF 块已解析确认）。
**Alternatives considered**: ImageAnimator 逐帧驱动（需拆帧资源，成本高收益零，弃用）；若个别场景实测不自动播放，按 spec 假设以静态首帧降级验收并记录。

## Data Model

（无新增数据实体。本批仅引入 2 个静态媒体资源常量：`octop_mascot_peek` / `octop_mascot_type`（Resource 类型），不涉及持久化、网络协议或领域模型变更。）

## Contracts & Interfaces

**UI 组件契约变更**：

1. **EmptyView（components/EmptyView.ets）**
   - 新增可选普通成员：`mascot: boolean`，默认 `true`
   - `mascot=true`：图标区渲染 `octop_mascot_peek` 动画（约 96×64vp，Contain + None 插值，居中）
   - `mascot=false`：渲染原 96×96 双层圆形徽章 + SymbolGlyph（现状完全保留）
   - 既有成员 `title` / `subtitle` / `icon` 语义不变；`icon` 仅在 `mascot=false` 时生效
   - 现有全部调用方无需修改

2. **OctopThinkingIndicator（components/OctopThinkingIndicator.ets）**
   - 对外签名不变（`indSize: number = 44`）
   - 内部视觉变更：弧线环绕中心由 `octop_logo` 静态图替换为 `octop_mascot_type` 动画（显式 2:1 宽高，约 32×16vp @indSize=44）
   - 双弧线动画（animateTo 140ms×-1 循环、dashArc 几何、颜色）零改动

3. **ChatHomeTab.emptyStateBuilder（pages/chat/ChatHomeTab.ets）**
   - 渲染顺序变更：探头章鱼 Image（约 90×60vp，居中）→ WelcomeCard（welcome 非空时）→ 最近会话卡（条件不变）
   - 无新成员、无新状态

4. **AboutPage（pages/me/AboutPage.ets）**
   - 新增静态致谢卡节点（位于版本行卡之后、底部"基于 HarmonyOS ArkUI 构建"文本之前）
   - 无新成员、无新状态、与版本号加载逻辑解耦

**资源契约**：`$r('app.media.octop_mascot_peek')`、`$r('app.media.octop_mascot_type')` 必须与 resources/base/media/ 下实际文件名一一对应（编译期校验）。

**回归红线**：思考胶囊双弧线/光晕/玻璃胶囊结构；WelcomeCard 文案与最近会话卡；EmptyView 标题副标题布局；AboutPage 版本卡逻辑；第十二批全部键盘态/滚动/任务面板行为——均不得回归。
