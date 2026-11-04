# Feature Specification: input-glow-hitfix（流式流光层触摸拦截修复）

**Created**: 2026-10-31
**Status**: Approved（用户长期指令：直接执行，不询问）
**Input**: 用户指令："修复新发现的问题"——第九批验证记录的既有缺陷：流式期间输入卡触摸拦截（TextArea 聚焦与停止按钮点击无效，卡外触摸全部正常，idle 态正常）

## Overview

第九批验证发现：流式期间输入卡上的触摸全部失效（点输入框不弹键盘、点停止/追问/附件/润色/录音/模型胶囊均无响应），卡外（导航/胶囊/FAB）正常，空闲态正常。根因：输入卡 `.overlay(this.inputGlowOverlay)` 把 InputFlowBorder（整卡尺寸的 visualEffect hdsEffect shader 层）盖在内容上层，尽管双层已设 HitTestMode.None，视效节点仍拦截触摸且行为间歇（batch-7/8 验证时可用、batch-9 验证时失效）。修复：流光层从"顶层 overlay"改为"底层子节点"（输入卡包一层 Stack，流光垫底、内容在上），命中测试自上而下必然先命中内容，确定性根治且不依赖 HitTestMode 语义；视觉零变化。

## User Scenarios & Testing *(mandatory)*

### User Story 1 - 流式期间输入卡触摸恢复 (Priority: P1)

流式生成中（流光边框显示期间），输入卡上全部控件恢复可交互：点击 TextArea 弹出软键盘可输入（聚焦边框 1→2vp）、点击发送/停止合并按钮可停止生成、点击追问发送可排队、plus/wand/mic/model/context 胶囊各自打开面板或启动录音。

**Why this priority**: 用户点名的待修复缺陷；流式期间无法追加追问、无法停止生成、无法输入，功能性阻断。

**Independent Test**: 流式生成中依次点击输入框与停止按钮，键盘应弹出、生成应停止。

**Acceptance Scenarios**:

1. **Given** 流式生成中（streaming=true，流光沿卡边流动），**When** 点击输入框 TextArea，**Then** 弹出软键盘、可输入文字、聚焦边框 1vp→2vp
2. **Given** 流式生成中且输入框为空，**When** 点击发送/停止合并按钮（红色 stop_circle），**Then** 停止生成（cancelTurn 生效），流光随之卸载
3. **Given** 流式生成中且输入框有文字，**When** 点击发送按钮，**Then** 追问（steer）正常排队发送
4. **Given** 流式生成中，**When** 依次点击 plus/wand/mic/model 胶囊，**Then** 附件面板/润色/录音/模型面板各自正常响应
5. **Given** 空闲态（无流光），**When** 上述全部交互，**Then** 行为与修复前一致（零回归）

---

### User Story 2 - 流光视觉与结构零回归 (Priority: P2)

流光渲染效果不变：双色（玫瑰+品牌蓝）边缘流光沿卡边框周长追逐流动、9s 单圈、streaming 时挂载/结束卸载、帧率参数不变；挂载层级改为内容下方后视觉一致（内容边缘区域透明，流光可见）。FAB（新对话按钮，卡右上外侧重叠）与斜杠面板、命中安全区等行为不变。

**Why this priority**: 修复触摸拦截不能以牺牲第六批引入的流光视觉效果为代价；结构改动需确认不牵连兄弟节点。

**Independent Test**: 流式期间截屏对比修复前：流光仍沿卡片边缘可见、位置与形态一致；FAB 正常点击。

**Acceptance Scenarios**:

1. **Given** 流式生成中，**When** 截屏，**Then** 卡片边缘可见双色流光（与修复前形态一致），截屏放大确认光带贴边框周长
2. **Given** 流式生成中，**When** 点击卡右上 FAB（新对话按钮），**Then** 正常响应（FAB 为外层 Stack 兄弟节点，层级不变）
3. **Given** 回合结束（streaming=false），**When** 观察，**Then** 流光卸载、无残留光带
4. **Given** flowW/flowH 测量，**When** 卡片尺寸变化（如长文本撑高），**Then** 流光几何仍跟随卡片实际尺寸（onAreaChange 测量保持）

### Edge Cases

- 流式开始瞬间软键盘已打开：流光层出现在内容下方，不夺焦点不遮挡输入
- flowW/flowH 初始为 0（首帧测量前）时流式已开始：流光层以 0 尺寸渲染不可见，首帧 onAreaChange 后正常（现状一致）
- 流光层保留 HitTestMode.None（双保险，即使被命中也无响应）
- 长文本撑高输入卡（maxHeight 128 撑满）：流光几何跟随新尺寸
- 斜杠面板弹出时流光仍在底层，不影响面板命中
- 第九批 TextPacer/竞态守卫等行为零变化

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: 移除输入卡 `.overlay(this.inputGlowOverlay, ...)` 挂载方式与 `inputGlowOverlay` @Builder；输入卡重构为包裹 Stack：第一个子节点为 `if (this.streaming) InputFlowBorder({ w: this.flowW, h: this.flowH })`（底层），第二个子节点为原内容 Column（TextArea + 操作行，顶层）
- **FR-002**: 输入卡全部视觉属性（width/borderRadius/backgroundColor/backgroundBlurStyle/systemMaterial/border/shadow/constraintSize/margin/onAreaChange）从原 Column 迁移至包裹 Stack，逐属性等价迁移（视觉零变化）；内容 Column 保留自身 width('100%')/padding
- **FR-003**: 流式期间输入卡全部控件（TextArea/停止/追问发送/plus/wand/mic/model/context）MUST 可交互
- **FR-004**: InputFlowBorder 组件本身（components/OctopThinkingIndicator.ets）MUST 零改动（视效参数/HitTestMode.None/几何传入方式不变）
- **FR-005**: flowW/flowH 测量保持：onAreaChange 挂包裹 Stack（测量结果与原位置等价，卡片实际尺寸）
- **FR-006**: FAB（外层 Stack TopEnd 兄弟节点）、斜杠面板、输入卡外全部交互 MUST 零回归
- **FR-007**: 第八/九批行为（TextPacer 平滑输出、竞态守卫、双层架构、steer/停止/HITL）MUST 零回归
- **FR-008**: 服务端 MUST 零改动

### Key Entities

- **包裹 Stack**：输入卡新最外层容器（子节点：流光层 + 内容 Column），承载原输入卡全部视觉属性
- **流光层 z 序**：从 overlay 顶层（内容上方）改为 Stack 底层（内容下方）——命中测试自上而下先命中内容，确定性修复

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: 流式期间点击 TextArea 弹出软键盘且可输入（聚焦态边框变化截屏取证）
- **SC-002**: 流式期间空输入点击停止按钮：生成停止、流光卸载（前后截屏取证）
- **SC-003**: 流式期间 plus/wand/mic/model 胶囊至少 3 项实测响应（面板弹出/录音启动）
- **SC-004**: 流式期间截屏确认流光沿卡边缘渲染（与修复前形态一致）
- **SC-005**: 空闲态与第八/九批已验收行为零回归（打字机平滑、双击单发、续流）

## Assumptions

- 命中测试自上而下：顶层节点先于底层节点接收触摸（ArkUI 标准行为），流光垫底后内容必然优先命中，不依赖 HitTestMode 对视效节点的语义
- 内容 Column 边缘区域透明（无背景绘制），底层流光在卡边缘可见性不受影响
- 测试环境：模拟器 127.0.0.1:5555，服务器 s3.z100.vip:35796，与第八/九批一致
- 触摸拦截的间歇性（batch-7/8 可用、batch-9 失效）不影响修复有效性判定：结构性 z 序修复与效果节点命中行为无关，以实测为准

## Open Questions

- （无——用户长期指令要求不询问直接执行）
