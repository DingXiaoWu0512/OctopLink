# Implementation Plan: stream-freedom-todo-progress

**Input**: Feature specification from `spec/stream-freedom-todo-progress/spec.md`

## Summary

四项聊天页改进的技术方案：**(1) 流式滚动自由**——`stickBottom` 贴底状态 + List `onScroll`（仅 Dragging/Fling 手势态）/`onReachEnd` 手势感知 + `scrollToBottom` 门禁（非 force 且未贴底直接 return）+ "回到最新"悬浮胶囊入口；流式期用户可自由上滑阅读。**(2) 任务进度面板**——移植桌面 `parseWriteTodos.ts` 为 ArkTS `ParseWriteTodos.ets`（后缀匹配/payload 兼容/状态归一/截断部分解析/id 合并数字序排序），新建 `TodoProgressPanel.ets` 展示组件，MessageBubble 按 `argsText` 数据源集成（write_todos 不再走通用工具折叠卡）。**(3) 思考态精修**——流式期 reasoning 折叠行改静态"深度思考中…"（可选计时），展开态 `constraintSize({ maxHeight: 240 })` + Scroll 限高。**(4) 键盘残留修复**——MainPage 键盘期 `.barWidth(0)` 配合现有 `barHeight 0` 彻底隐藏 TabBar pill 容器，收起复原。

## Technical Context

**Language/Version**: ArkTS（API 12 级，ArkUI 声明式）
**Primary Dependencies**: ArkUI（List/Scroll/NavDestination）、@kit.ArkUI（window 键盘高度监听沿用现状 Callback<number>）
**State Management**: 状态管理 V1（项目既有增量，沿用 @State/@Link，不迁移 V2）
**Storage**: 无新增持久化（toolCalls 数据经 upsertToolCall/fromHistoryRecord 已在内存消息模型中）
**Testing**: 模拟器 127.0.0.1:5555 手动路径验证（uinput 触控 + dumpLayout + snapshot_display .jpeg 截屏亮度/多模态分析）；构建 `devecocli build`；静态 `arkts_check`
**Target Platform**: HarmonyOS（模拟器 1280×2832，密度 3.5）
**Project Type**: mobile-app（既有 OctopLink 聊天 App 增量）
**Performance Goals**: 流式渲染零掉帧（滚动门禁减少无效 scrollEdge 调用）；部分解析每 delta 最多 O(argsText 长度) 一次
**Constraints**: 服务端零改动；第八~十一批已验收行为零回归；fresh 入场动画零破坏；构建上限 10 次
**Scale/Scope**: 改 4 文件（ChatHomeTab/MessageBubble/MainPage/MessageModels）+ 新建 2 文件（ParseWriteTodos/TodoProgressPanel）

## Project Structure

### Documentation (this feature)

```text
spec/stream-freedom-todo-progress/
├── spec.md
├── plan.md              # This file
└── tasks.md
```

### Source Code (repository root)

```text
entry/src/main/ets/
├── components/
│   ├── MessageBubble.ets        # [改] reasoning 折叠/展开精修 + TodoProgressPanel 集成 + write_todos 剔除通用卡
│   └── TodoProgressPanel.ets    # [新] 任务进度面板组件（标题/摘要/逐项状态）
├── pages/
│   ├── chat/
│   │   └── ChatHomeTab.ets      # [改] stickBottom 状态 + onScroll/onReachEnd + scrollToBottom 门禁 + 回到最新入口 + reasoningStartAt 接线
│   └── MainPage.ets             # [改] 键盘期 barWidth(0) 残留修复
├── model/
│   └── MessageModels.ets        # [改] ChatMessageModel 新增 reasoningStartAt?: number
├── utils/
│   └── ParseWriteTodos.ets      # [新] write_todos 解析器（桌面 parseWriteTodos.ts 的 ArkTS 移植）
└── service/
    └── ChatStreamController.ets # [零改动] upsertToolCall/fromHistoryRecord 数据源保持现状
```

**Structure Decision**: 遵循既有项目架构（pages/components/model/service/utils 分层，状态管理 V1），不引入 MVVM 迁移、不新增目录。新建 2 文件均为单一职责（解析器纯函数 / 面板展示组件），与既有 `components/`、`utils/` 约定一致。

## Complexity Tracking

> 无 Constitution Check 违规，无需填表。

## Research & Decisions

- **Decision 1（滚动自由 = stickBottom 门禁）**：主流聊天 App 标准行为——用户手势上滑即视为"暂停自动贴底"，滑回底端或主动操作（发送/切会话/steer）恢复贴底。
  **Rationale**: 勘察证实根因是 textPacer onFlush 每 delta 强制 `scrollEdge(Bottom)`（150ms 节流），用户 150ms 内必被拉回；门禁放在节流之前使未贴底时零滚动调用。"回到最新"入口提供显式恢复手段，onReachEnd 提供隐式恢复。
  **Alternatives considered**: ①纯节流加大（不解决"必须等生成完"）②流式期禁用自动滚动开关（需用户手动切换，侵入性大）③按 delta 高度增量滚动（实现复杂且与打字机平滑冲突）。

- **Decision 2（onScroll 仅 Dragging/Fling 态处理，Idle 过滤）**：程序化 `scrollEdge`/`scrollTo` 触发的 onScroll 回调状态为 Idle，过滤后避免"自动滚动把 stickBottom 洗掉"的自反馈。
  **Rationale**: ArkUI ScrollState 三态语义明确；手势态 offset<0（上滑，方向符号以模拟器实测校准）判定离开底部。
  **Alternatives considered**: onScrollIndex 差值判断（无法区分手势/程序化，误触发）。

- **Decision 3（TodoPanel 数据源 = argsText）**：面板只读 `ToolCallModel.argsText`（WS 分片累积 + history tool_use 解析均已就位），不读 resultText。
  **Rationale**: tool_result 的 resultText 有 500 字符截断且多工具并发可能错位；桌面权威语义（同 id 后写覆盖、数字序排序、output>args 优先）中移动端仅取 args 分支即可覆盖实时更新与历史回看两场景。
  **Alternatives considered**: ①读 resultText（截断+错位风险）②新增 WS 消息类型（违反服务端零改动）。

- **Decision 4（部分解析 = 截断 args 逐字符扫描完整 `{...}` 对象）**：每个 onToolCall delta 到达时对累积 argsText 做一次扫描，提取所有完整 JSON 对象逐个 try/parse，失败静默跳过。
  **Rationale**: 流式中 args 不完整（截断的 JSON 数组/对象），完整子对象仍可先渲染；失败静默保证不崩不显示半截。每 delta 一次 O(n) 扫描在 args 量级（KB 级）无性能问题。
  **Alternatives considered**: ①只在工具调用结束时渲染（无"实时更新"体验）②正则提取（长文回溯风险，ArkTS 正则支持有限）。

- **Decision 5（流式折叠行 = 静态"深度思考中…"）**：`msg.streaming && reasoning 非空` 时折叠行不渲染 reasoning 实时预览，显示"深度思考中…"（可选 + 计时 Ns）。
  **Rationale**: 用户观感问题（"太夸张、文字乱跳"）源于预览文字随 delta 高频重排；回合结束（streaming=false）恢复现状单行省略预览，非流式历史消息完全不受影响。计时可选：ChatMessageModel 新增 `reasoningStartAt?: number`，onReasoningDelta 首帧记录，面板按秒显示，低成本高信息量。
  **Alternatives considered**: ①降低预览刷新频率（治标不治本）②流式期完全隐藏折叠行（用户失去"正在思考"感知）。

- **Decision 6（键盘横杠 = 取消悬浮样式 barFloatingStyle(undefined)）**：复勘实测锚定根因——barWidth(0)+barHeight(0) 后 TabBar 仍按最小尺寸渲染 104×28px 胶囊（dumpLayout `type:"TabBar", bounds:[598,1579][682,1607]`），且悬浮样式蒙层（maskColor 渐变 = dumpLayout `BackgroundMask [0,1523][1280,1733]`）形成暗带；官方 Tabs 文档明确 `barFloatingStyle(style: Optional<FloatingTabBarStyle>)` **传 undefined 取消悬浮样式恢复默认样式**。故 kbHeight>0 时 `.barFloatingStyle(undefined)`（配合既有 barHeight 0/barWidth 0）一次性消除 pill 与蒙层。
  **Rationale**: 横杠与暗带均为悬浮样式装饰物，取消悬浮样式是文档背书的正解；非悬浮默认 TabBar 在 barHeight 0/barWidth 0 下无可渲染内容。
  **Alternatives considered**: ①barWidth(0) 单独（T011 已实证不足，仍剩 104px 最小胶囊）②键盘期 fallback 无 systemMaterial 样式（pill 容器仍渲染）③负 barBottomMargin 推出视口（第十一批实测钳制 28vp 最小值，仍可见）④barModifier 施加 visibility（API 可行但绕远，undefined 为直解）。
  **候选升级序（若 undefined 实测不生效）**: ①FloatingTabBarStyle 键盘期全字段归零（barWidth 三档 0/barSideMargin 0/barBottomMargin 0/maskColor Transparent）②barModifier visibility(None) ③其他等效；验收以截屏亮度分析为准。

- **Decision 7（键盘期间距收缩 = kbHeight 传导 + inputBottomInset 统一入口）**：MainPage 将 `kbHeight` 以 @Prop 传导至 ChatHomeTab；ChatHomeTab 抽取 `inputBottomInset(): number`——kbHeight>0 返回 10（vp，约 35px，缩减 91%，满足"起码缩小三分之二"），否则 `bottomPad + 10`（现状 114.6vp=401px）；输入卡 `margin.bottom` 与 `contentEndOffset`（= inputBottomInset() + flowH + 22）同步改用该入口，气泡停止位随卡片联动收缩，22vp 对称间隙保持。
  **Rationale**: 键盘期 TabBar 已隐藏，为悬浮 TabBar 预留的 bottomPad 底边距失去意义，收缩至小间距是主流 IM 键盘态标准布局；单一入口保证卡片与列表停止位永远一致。
  **Alternatives considered**: ①ChatHomeTab 自行监听键盘高度（重复监听，MainPage 已有 Callback<number> 链路）②键盘期收缩 bottomPad 本身（影响面外溢到其他 Tab，无必要）。

## Data Model

### 状态与字段

- **ChatHomeTab（@State）**
  - `stickBottom: boolean = true`——用户是否愿意贴底（false 时暂停自动滚底）
- **ChatMessageModel（新增可选字段）**
  - `reasoningStartAt?: number`——推理首帧时间戳（Date.now()，onReasoningDelta 首帧记录；可选计时展示用）
- **TodoListItem（ParseWriteTodos.ets 导出）**
  - `id: string`——清单项 id（合并键）
  - `content: string`——项内容
  - `status: 'pending' | 'in_progress' | 'completed' | 'cancelled'`——归一化状态
- **TodoProgressPanel 入参**
  - `items: TodoListItem[]`（@Prop/普通入参，按 id 合并数字序排序后的清单）
  - `streaming: boolean`（流式标记，可选视觉反馈）

### 状态转换

- stickBottom：`true →（用户手势上滑）→ false →（点击"回到最新" / onReachEnd / force 调用点）→ true`
- TodoListItem.status：原始 done/complete → completed；running/active → in_progress；其余原样；后写同 id 覆盖先写

## Contracts & Interfaces

### ParseWriteTodos.ets（utils/，桌面 parseWriteTodos.ts 的 ArkTS 移植）

- `isWriteTodosToolName(name: string): boolean`——'/' 后缀等于 `write_todos` 命中（如 `deepagents/write_todos`）
- `collectTodoItems(argsText: string): TodoListItem[]`——完整解析：payload 键兼容 `todos`/`items`/`tasks`；数组项兼容字符串与 `{id, content, status}` 对象；状态归一化；解析失败返回 `[]`
- `parsePartialTodoItems(argsText: string): TodoListItem[]`——截断 args 部分解析：逐字符扫描提取完整 `{...}` 对象逐个解析，失败项静默跳过
- `mergeTodoItems(prev: TodoListItem[], next: TodoListItem[]): TodoListItem[]`——按 id 合并（后写覆盖）+ 数字 id 升序排序（非数字 id 保持稳定序）
- 面板侧调用约定：流式中每次 onToolCall/write_todos 更新时，取该消息全部 write_todos 调用的 argsText 依次 `parsePartialTodoItems`（或完整时 `collectTodoItems`）→ `mergeTodoItems` 链式合并 → 渲染

### TodoProgressPanel.ets（components/）

- 入参：`items: TodoListItem[]`、`streaming: boolean`
- 展示：标题"任务进度" + 摘要"已完成 x/y"（x=completed 数，y=总数）+ 逐项状态图标与文案（待处理/进行中/已完成/已取消）；completed/cancelled 项内容删除线；面板置于 MessageBubble 内 reasoning/text 块之前

### ChatHomeTab.ets（改动契约）

- `scrollToBottom(force: boolean)`：门禁前置——`!force && !this.stickBottom` 直接 return（150ms 节流之前）
- List：`.onScroll(...)` 仅 Dragging/Fling 态处理上滑判定；`.onReachEnd(...)` 置 stickBottom=true
- force 调用点（send/sendSteer/onUserEcho/onHitlRequired/loadHistory）：调用时显式置 stickBottom=true
- "回到最新"悬浮胶囊：`stickBottom===false && streaming` 时显示于输入卡上方，点击 `scrollToBottom(true)` + stickBottom=true
- onReasoningDelta 首帧：`msg.reasoningStartAt ??= Date.now()`

### MessageBubble.ets（改动契约）

- reasoningBlock 折叠分支：`msg.streaming` 时不渲染 reasoning 实时预览，显示"深度思考中…"（若 reasoningStartAt 非空可显示"深度思考中… Ns"）；`streaming=false` 恢复现状单行省略预览
- reasoningBlock 展开态：内容区外套 Scroll + `constraintSize({ maxHeight: 240 })`
- toolCallBlock：write_todos 调用（isWriteTodosToolName 命中）剔除通用折叠卡，改渲染 TodoProgressPanel（同消息多次调用合并为单面板）；其余工具通用卡不变
- fresh 入场动画（L385 区域）零破坏

### MainPage.ets（改动契约）

- `.barFloatingStyle(...)`：`kbHeight > 0 ? undefined : this.floatingBarStyle()`——键盘期取消悬浮样式（消 104×28px 胶囊横杠 + maskColor 蒙层暗带），收起恢复；kbHeight>0 仍保持 `.barHeight(0)`/`.barWidth(0)`
- `ChatHomeTab({...})` 构造增补 `kbHeight: this.kbHeight`（@Prop 传导）
- kbHeight>0 时 ExpertListPage/WorkspaceTab/MeTab 的 bottomPad 传导零改动（仅 Chat 页收缩，最小影响面）
- 键盘监听（Callback<number>）、floatingBarStyle 方法本体、floatingBarBottomMargin、contentBottomPad、aboutToDisappear 注销：零改动
- 键盘收起态（kbHeight===0）视觉零变化（FR-014）

### ChatHomeTab.ets（US4b 增量契约）

- 新增 `@Prop kbHeight: number = 0`
- 新增私有方法 `inputBottomInset(): number`——`kbHeight > 0 ? 10 : this.bottomPad + 10`
- 输入卡 `.margin({ ..., bottom: this.inputBottomInset() })`（原 bottomPad + 10）
- `.contentEndOffset(this.inputBottomInset() + this.flowH + 22)`（原 bottomPad + 10 + flowH + 22）
- US1 stickBottom/onScroll/onReachEnd/回到最新、US2 集成、US3 reasoningStartAt 接线：与本项无冲突，键盘期行为联动（卡片下移后回到最新胶囊/思考胶囊/附件行随底部沉浸层整体下移）

### 零改动契约

- ChatStreamController.ets（upsertToolCall/fromHistoryRecord 保持现状）
- 服务端、OctopThinkingIndicator、InputFlowBorder、AppPrefs/SessionStore 专家恢复链
