# Implementation Plan: 第六批精修（ui-refine-batch-5）

**Input**: Feature specification from `spec/ui-refine-batch-5/spec.md`

## Summary

两处 MessageBubble 修复：①第五批把 token 用量并入操作行时用了 `.width('100%')`，而助手气泡 Column 是内容自适应宽度（仅 `constraintSize({ maxWidth: '84%' })`）——百分比宽度在此类父容器下按最大可用宽度解析且不参与气泡宽度测量，窄气泡时隐形 Row 比气泡宽，右端的 ↑↓ 用量渲染到气泡背景外（宽气泡齐宽看不出来，短文本气泡必现）。修法：操作行改 `alignSelf(ItemAlign.Stretch)`（随气泡实际宽度拉伸、不参与气泡宽度测量——宽气泡用量仍靠右、窄气泡不溢出），并给气泡 Column 加条件 minWidth（新增 `bubbleMinWidth(): number`：流式 0 / 非流式带用量 200 / 非流式无用量 120，保证按钮+用量自然宽度在窄气泡内也放得下，Blank 有剩余空间可占）。②用户反馈按钮离上下太宽：操作行 `margin({ top: 11 })` → `({ top: 6 })`、气泡底 padding 14 → 7（上下各缩窄 50%，左右 padding 14 与其余布局不动）。单文件改动，服务器零改动。

## Technical Context

**Language/Version**: ArkTS（HarmonyOS API 26+，SDK 6.0.5）
**Primary Dependencies**: ArkUI（Column/Row/Blank、alignSelf 通用属性、constraintSize）
**State Management**: 保留项目现有 State Management V1（@Component/@ObjectLink/@State）
**Storage**: 无
**Testing**: devecocli build + 模拟器（127.0.0.1:5555）dumpLayout 布局断言（用量 Text bounds ⊆ 气泡 Column bounds）+ 截图 VLM 分析 + 坐标点击回归
**Target Platform**: HarmonyOS 模拟器（验证环境）
**Performance Goals**: 无新增开销（纯布局属性变更）
**Constraints**: 单文件（MessageBubble.ets）改动；不回归第五批全部 6 项与前四批功能；ArkTS 严格模式编译通过
**Scale/Scope**: 2 个用户故事，1 个文件，2 处布局修改 + 1 个私有方法

## Project Structure

### Documentation (this feature)

```text
spec/ui-refine-batch-5/
├── spec.md              # Feature specification
├── plan.md              # This file
└── tasks.md             # Task breakdown
```

### Source Code (repository root)

```text
entry/src/main/ets/
└── components/
    └── MessageBubble.ets            # US1: 操作行 width('100%')→alignSelf(Stretch)+气泡条件 minWidth；US2: margin 11→6、底 padding 14→7
```

**Structure Decision**: 遵循既有工程架构，本批为单文件增量修改，不新增文件。

## Complexity Tracking

> 无 Constitution Check 违规，无需填写。

## Research & Decisions

- **Decision 1（US1 用量溢出根因与修法）**: 根因=操作行 `.width('100%')` 挂在内容自适应宽度的气泡 Column（无显式 width，仅 constraintSize maxWidth 84%）内：百分比按最大可用宽度解析且不参与父容器内容宽度测量 → 窄气泡时 Row 宽于气泡，右端用量溢出气泡背景（第五批验证用长文本宽气泡恰好齐宽，未暴露）。修法=改 `alignSelf(ItemAlign.Stretch)`：Column 交叉轴拉伸属性，子项随父项最终宽度自适应且不参与父项宽度测量，宽气泡（Blank 撑开、用量靠右）与窄气泡（Row 收缩至气泡宽）两态都正确。
  **Rationale**: Stretch 是 ArkUI 处理"子项随内容自适应父容器拉伸"的标准方案，无百分比解析歧义；对 minWidth 撑底的窄气泡同样成立。
  **Alternatives considered**: 保留 width('100%') 并给气泡加 minWidth（百分比仍按最大可用宽度解析，minWidth 无法收窄已解析的 Row 宽度，窄气泡仍溢出）；测量文本宽度 onAreaChange 回设 Row 宽（引入状态回环与抖动，复杂度高）；Flex wrap 换行（宽气泡用量不再靠右，第五批"平齐+靠右"效果丢失）。

- **Decision 2（US1 minWidth 保底档位）**: 气泡 Column `constraintSize` 增加 `minWidth: this.bubbleMinWidth()`（新增私有方法）：流式 0（无操作行，不撑宽流式短文本气泡）；非流式带用量 200（三按钮 72 + Row space 6×5 间距 30 + 用量 Text ~56（fontSize 10 含 6 位数字余量）+ 气泡 padding 28 = 186，取 200 留余量）；非流式无用量 120（按钮 72 + 间距 18 + padding 28 = 118，取 120）。
  **Rationale**: stretch 后 Row 宽度上限=气泡宽度；窄文本气泡若小于操作行自然宽度，Blank 归零后固定宽按钮+用量仍会溢出，必须由气泡 minWidth 保底；分档避免无谓撑宽。
  **Alternatives considered**: 统一 minWidth 200（无用量与流式气泡被无谓撑宽）；不给 minWidth（窄气泡按钮溢出）。

- **Decision 3（US2 间距减半数值）**: 操作行与上方文本 `margin({ top: 11 })` → `({ top: 6 })`；气泡底 `padding(14)` → `padding({ left: 14, right: 14, top: 14, bottom: 7 })`。上下间距各缩约 50%，左右与顶部 padding 不动（顶部是文本与气泡上边的距离，非按钮间距）。
  **Rationale**: 用户点名"按钮离上下太宽 缩窄50%"；上方间距=margin top（11→6 取整），下方间距=气泡底 padding（14→7 精确减半）。
  **Alternatives considered**: 同比例缩顶部 padding（用户所指为按钮上下间距，非文本上边距，不动）。

## Data Model

- **MessageBubble（布局调整，无数据结构变化）**: 新增私有方法 `bubbleMinWidth(): number`（streaming → 0；非流式带用量 → 200；非流式无用量 → 120）；msg.usageIn/usageOut 等字段不变。

## Contracts & Interfaces

- **助手气泡布局契约**: 气泡 Column：`.constraintSize({ maxWidth: '84%', minWidth: this.bubbleMinWidth() })`、`.padding({ left: 14, right: 14, top: 14, bottom: 7 })`；操作行 Row：`.alignSelf(ItemAlign.Stretch)`、`.margin({ top: 6 })`，其余（space 6、三按钮 24/14、Blank、用量 Text fontSize 10/text_tertiary）不变。
- **不改动清单**: 用户气泡分支（bg_bubble_user/padding 14,10/borderRadius 18,4,18,18）、思考折叠、工具调用卡、附件块、排队撤回、错误重试、TTS 三态逻辑、朗读链路。
