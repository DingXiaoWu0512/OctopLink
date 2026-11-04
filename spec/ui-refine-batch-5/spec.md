# Feature Specification: 第六批精修（token 用量收回气泡内 + 按钮上下间距缩窄 50%）

**Created**: 2026-10-29
**Status**: Approved
**Input**: User description: "Token使用量跑到聊天气泡外面去了 不好看，气泡框里的按钮离上下太宽了 缩窄50%"

## Overview

第五批把助手气泡的 token 用量（↑输入 ↓输出）并入了操作行（复制/朗读/重试按钮同一行）。实测暴露两个问题，本批修复：①操作行为实现"按钮居左、用量靠右"使用了 `.width('100%')`，但助手气泡 Column 是内容自适应宽度（仅 `constraintSize({ maxWidth: '84%' })`，无显式 width）——百分比宽度在这种父容器下按最大可用宽度解析且不参与气泡宽度测量，导致隐形 Row 比窄气泡宽：长文本气泡恰好齐宽看不出问题，**短文本（窄）气泡时最右侧的用量文本渲染到气泡背景外面**，视觉上"token 使用量跑到聊天气泡外面"；修法为操作行改 `alignSelf(ItemAlign.Stretch)`（随气泡实际宽度拉伸：宽气泡用量仍靠右、窄气泡不溢出）+ 气泡加条件 minWidth 保底（保证按钮+用量在窄气泡内也放得下）。②操作按钮与上方文本的间距（margin top 11vp）和与气泡底边的间距（padding bottom 14vp）用户觉得太宽，各缩窄 50%：11→6、14→7。全部改动限于 MessageBubble.ets 一个文件，服务器零改动，复制/朗读三态/重试交互不动。

## User Scenarios & Testing *(mandatory)*

### User Story 1 - token 用量收回气泡内 (Priority: P1)

助手气泡的 ↑↓ 用量在任何宽度（短回复窄气泡、长回复宽气泡）下都显示在气泡背景框内，不再溢出到气泡外；宽气泡时用量仍靠右、与三按钮同一行垂直居中平齐（第五批"平齐"效果保留）；无用量消息右侧不占位；复制/朗读/重试功能无回归。

**Why this priority**: 用户直接报告的视觉缺陷——用量文本渲染在气泡卡片外面，破坏气泡容器感。

**Independent Test**: 打开包含短回复（窄气泡，如"你好呀"）和带用量的长回复两类消息的对话：窄气泡的用量在气泡背景内；宽气泡的用量仍在操作行右端与按钮同行。

**Acceptance Scenarios**:

1. **Given** 带用量的短回复（气泡宽度不足以容纳按钮+用量时气泡按 minWidth 保底），**When** 查看，**Then** ↑↓ 用量完整显示在气泡背景框内（dumpLayout 断言：用量 Text bounds 完全落在气泡 Column bounds 内）。
2. **Given** 带用量的长回复（气泡达到 maxWidth 84%），**When** 查看，**Then** 三按钮居左、用量靠右、同一行垂直居中平齐（第五批效果保留）。
3. **Given** 无用量的消息，**When** 查看，**Then** 操作行右侧无用量不占位，气泡不被无谓撑宽。
4. **Given** 复制/朗读（三态）/重试按钮，**When** 依次点击，**Then** 功能正常无回归。
5. **Given** 流式输出中的消息，**When** 查看，**Then** 气泡渲染不受 minWidth 影响（流式期无操作行，不强制最小宽度）。

---

### User Story 2 - 按钮上下间距缩窄 50% (Priority: P2)

助手气泡内操作行与上方文本的垂直间距、与气泡底边的垂直间距各缩窄 50%（margin top 11→6、气泡底 padding 14→7），气泡更紧凑；左右 padding 与文本区不动；按钮尺寸/交互不动。

**Why this priority**: 用户点名"按钮离上下太宽了 缩窄50%"。

**Independent Test**: 对比修改前后截图：按钮与文本间距、与气泡底边间距目视各窄一半；按钮仍完整可点。

**Acceptance Scenarios**:

1. **Given** 带操作行的助手气泡，**When** 查看，**Then** 操作行与上方文本间距约 6vp（原 11vp），与气泡底边间距约 7vp（原 14vp），均缩窄 50%。
2. **Given** 气泡布局，**When** 查看，**Then** 左右 padding（14）与文本行距不变，仅按钮上下间距收紧。
3. **Given** 复制/朗读/重试按钮，**When** 点击，**Then** 热区与功能正常（尺寸 24/14 不动）。

---

### Edge Cases

- 气泡窄于按钮+用量自然宽度时：minWidth 保底撑开气泡，用量不截断不溢出。
- 用量数字较大（如 ↑999999）时仍需在 minWidth 气泡内完整显示（minWidth 含余量）。
- 无用量且文本极短（如"好的"）时：气泡按无用量档 minWidth（120）保底，三按钮完整在气泡内。
- 流式输出期间（无操作行）不应用按钮档 minWidth，避免短流式文本气泡被无谓撑宽。
- 用户气泡（右侧蓝底）布局完全不动。

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: 助手气泡操作行 MUST 使用 `alignSelf(ItemAlign.Stretch)` 替代 `.width('100%')`，使操作行随气泡实际宽度拉伸，消除窄气泡下用量溢出气泡背景的缺陷。
- **FR-002**: 助手气泡 Column MUST 增加条件 minWidth（流式 0 / 非流式带用量 200 / 非流式无用量 120），保证按钮+用量在窄气泡内完整容纳。
- **FR-003**: 操作行 margin top MUST 由 11 缩至 6，气泡底 padding MUST 由 14 缩至 7（各缩窄 50%）；左右 padding 与其余布局不动。
- **FR-004**: 上述改动 MUST NOT 改变按钮尺寸（24/14）、复制/朗读三态/重试交互、用户气泡布局、思考/工具调用/附件区块。

### Key Entities

- **MessageBubble 助手气泡结构**：气泡 Column（bg_card 背景、borderRadius 4/18/18/18、padding 14、constraintSize maxWidth 84%）→ MarkdownText + 操作行 Row（三按钮 + Blank + ↑↓用量 Text）。
- **bubbleMinWidth(): number**：MessageBubble 新增私有方法，按消息状态返回气泡最小宽度（streaming → 0；非流式带用量 → 200；非流式无用量 → 120）。
- **操作行 Row**：`alignSelf(ItemAlign.Stretch)` + `margin({ top: 6 })`，其余（space 6、按钮样式、Blank、用量 Text fontSize 10）不变。

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: 窄气泡与宽气泡两种场景下，用量 Text bounds 100% 落在气泡 Column bounds 内（dumpLayout 断言通过）。
- **SC-002**: 宽气泡场景按钮与用量同行垂直居中平齐保持（中心 y 偏差 ≤1px）。
- **SC-003**: 按钮上方间距 6vp±1、下方间距 7vp±1（缩窄 50% 达成）。
- **SC-004**: 复制/朗读/重试功能无回归；用户气泡无变化。
- **SC-005**: 本批 2 项逐条验收通过（2/2）。

## Assumptions

- 根因判断：`.width('100%')` 在无显式宽度的自适应父容器（仅 constraintSize 约束）中按最大可用宽度解析且不参与父容器内容宽度测量，导致 Row 宽于窄气泡、右端用量溢出气泡背景；`alignSelf(ItemAlign.Stretch)` 在 Column 中使子项随父项最终宽度拉伸且不参与父项宽度测量，是 ArkUI 标准"随内容自适应容器拉伸"方案，在两种百分比解析语义下均正确。
- minWidth 数值已按按钮（3×24+间距 5×6）+ 用量 Text（fontSize 10，含 6 位数余量）+ 气泡 padding 28 核算：带用量 200、无用量 120 均含安全余量。
- 服务器端零改动；仅改 MessageBubble.ets 单文件。
- 第五批已交付其余 5 项（市场榜单/头像/手机工具提示/帮助页/全局默认模型）无回归。

## Open Questions

- （无——两处问题根因与修法均已明确）
