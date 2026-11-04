# Implementation Plan: input-glow-hitfix

**Input**: Feature specification from `spec/input-glow-hitfix/spec.md`

## Summary

把输入卡流光边框（InputFlowBorder，hdsEffect DUAL_EDGE_FLOW_LIGHT shader 层）从"顶层 `.overlay()` 挂载"（盖在 TextArea/按钮上方，视效节点间歇拦截触摸）改为"底层子节点"：输入卡内容 Column 外包一层 Stack，流光作 Stack 第一子节点垫底、内容在上；原输入卡全部视觉属性逐属性迁移到包裹 Stack。命中测试自上而下先命中内容，确定性根治触摸拦截；视觉零变化。服务端零改动。

## Technical Context

**Language/Version**: ArkTS（API 12+，DevEco 工具链）
**Primary Dependencies**: ArkUI（@Component V1 状态管理、Stack/if 条件渲染、onAreaChange）
**State Management**: 状态管理 V1（项目既有，保持不变）
**Storage**: 无
**Testing**: spec-verify 子代理构建 + 模拟器部署 + 逐条实测（点击各控件取证）
**Target Platform**: HarmonyOS 模拟器 127.0.0.1:5555；真机仅按用户明确要求
**Project Type**: 既有 HarmonyOS 应用（OctopLink，com.octop.link）定点修复
**Performance Goals**: 无新增运行时开销（少一层 overlay 挂载，渲染等价）
**Constraints**: InputFlowBorder 组件零改动；服务端零改动；ArkTS 严格模式
**Scale/Scope**: 单文件（ChatHomeTab.ets）输入卡结构定点改造

## Project Structure

### Documentation (this feature)

```text
spec/input-glow-hitfix/
├── spec.md               # 本特性规格
├── plan.md               # 本文件
└── tasks.md              # 任务清单
```

### Source Code (repository root)

```text
entry/src/main/ets/
├── pages/chat/
│   └── ChatHomeTab.ets        # 唯一改动：输入卡结构（L2621-2845 区域）——包裹 Stack + 流光垫底 + 属性迁移 + 删 overlay/builder
└── components/
    └── OctopThinkingIndicator.ets  # 只读参考（InputFlowBorder 零改动；OctopThinkingIndicator 零改动）
```

**Structure Decision**: 遵循既有项目架构，零新文件，单文件定点结构改造。

## Complexity Tracking

> 无 Constitution 违规。

## Research & Decisions

### 勘察结论（写入 spec 的依据）

1. **现状结构**（ChatHomeTab.ets L2621-2845）：`Stack({ alignContent: Alignment.TopEnd })` 外层容器 → 子1=输入卡 Column（TextArea L2623 + 操作行 Row L2644；属性链 L2810-2825：width/borderRadius/backgroundColor(glass)/backgroundBlurStyle(COMPONENT_REGULAR)/systemMaterial/border(1-2vp 聚焦态)/shadow/constraintSize/margin/onAreaChange(flowW/flowH 测量)/`.overlay(this.inputGlowOverlay, { align: Alignment.Center })`）→ 子2=FAB（square_and_pencil 新对话按钮，TopEnd 对齐，offset 外置）
2. **拦截根因**：`.overlay()` 把 `inputGlowOverlay`（`if (this.streaming) InputFlowBorder`，整卡尺寸 visualEffect hdsEffect shader 节点）渲染在内容**上方**；视效节点命中测试行为间歇（batch-7/8 验证流式中可交互，batch-9 验证全拦截），HitTestMode.None 不可靠
3. **症状吻合**：仅流式（streaming=true 挂载 overlay）拦截、idle（无 overlay）正常、卡外（overlay 裁剪在卡内）正常

### 设计决策

- **z 序修复优于继续调 HitTestMode**：ArkUI 命中测试自上而下，顶层先命中。流光垫底后，TextArea/按钮等内容节点位于流光上方，必然优先接收触摸——不依赖 HitTestMode 对视效节点的语义，确定性根治间歇拦截
- **包裹 Stack 而非 background builder**：卡片玻璃背景（backgroundColor glass + backgroundBlurStyle）半透明带模糊，流光若放 `.background()` 会被玻璃层压暗/模糊；放包裹 Stack 底层子节点则渲染在玻璃背景之上、内容之下，与原 overlay 视觉一致
- **属性逐属性迁移**：原输入卡 Column 的全部视觉属性迁移到包裹 Stack，内容 Column 仅保留 `width('100%')` 与 `padding({ left: 10, right: 10, bottom: 10 })`（操作行自身的 padding 属 Row）；`onAreaChange`（flowW/flowH 测量）随属性迁移到包裹 Stack，测量值等价（包裹 Stack 与原 Column 同尺寸，流光子节点以 flowW/flowH 显式尺寸填充）
- **FAB 层级不变**：FAB 仍是外层 `Stack({ alignContent: TopEnd })` 的子2（后声明=更上层），流光重构发生在外层 Stack 的子1 内部，FAB 命中与视觉不受影响
- **删除死代码**：`inputGlowOverlay` @Builder（L2314-2320）与 `.overlay()` 调用（L2825）一并删除，流光以内联 `if (this.streaming) InputFlowBorder({ w: this.flowW, h: this.flowH })` 作为包裹 Stack 第一子节点
- **InputFlowBorder 零改动**：组件契约（w/h 传入、HitTestMode.None、视效参数、9s 周期）不变，仅挂载位置变化

## Data Model

无新增数据。复用 `flowW`/`flowH`（@State，onAreaChange 测量）与 `streaming`（@State），语义不变。

## Contracts & Interfaces

- 输入卡新结构（伪结构，非代码承诺）：
  - 外层 `Stack({ alignContent: Alignment.TopEnd })`：子1=包裹 Stack、子2=FAB（均不变语义）
  - 包裹 Stack（承载原输入卡全部视觉属性链 + onAreaChange）：
    - 子1（底层）：`if (this.streaming) { InputFlowBorder({ w: this.flowW, h: this.flowH }) }`
    - 子2（顶层）：原内容 Column（TextArea + 操作行，保留内容布局属性）
- 删除项：`inputGlowOverlay` @Builder、`.overlay(this.inputGlowOverlay, ...)` 调用
- 对外契约不变：InputFlowBorder/OctopThinkingIndicator 组件零改动；TextArea/按钮/胶囊的事件回调与第九批全部行为零改动；服务端契约零改动
