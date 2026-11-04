# Tasks: stream-freedom-todo-progress

**Input**: Design documents from `spec/stream-freedom-todo-progress/`
**Prerequisites**: plan.md (required), spec.md (required for user stories)

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- Include exact file paths in descriptions

## Path Conventions

- 项目根：`C:\Users\13775\OctopLink\`
- 源码根：`entry/src/main/ets/`
- 新建文件：`entry/src/main/ets/utils/ParseWriteTodos.ets`、`entry/src/main/ets/components/TodoProgressPanel.ets`
- 参照权威：`C:\Users\13775\AppData\Local\Temp\deveco\octop_src\TencentCloud-Octop-890111b\dashboard\src\utils\parseWriteTodos.ts`（只读参照，不修改）

---

## Phase 1: Setup

**Purpose**: 校准锚点——四批增量后行号漂移，实现前通读待改文件确认实际行号

- [x] T001 通读 4 个待改文件校准行号锚点（`entry/src/main/ets/pages/chat/ChatHomeTab.ets`、`entry/src/main/ets/components/MessageBubble.ets`、`entry/src/main/ets/pages/MainPage.ets`、`entry/src/main/ets/model/MessageModels.ets`），重点确认：scrollToBottom/force 调用点/textPacer onFlush/List 属性区、reasoningBlock/toolCallBlock/fresh 入场动画区、kbHeight/barHeight 键盘分支区、ChatMessageModel 字段区

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: 无跨故事阻塞项——ParseWriteTodos 属 US2 内部依赖，归入 US2 阶段；直接进入用户故事

---

## Phase 3: User Story 1 - 流式滚动自由 (Priority: P1) 🎯 MVP

**Goal**: 流式期间用户上滑视口不被拉回；"回到最新"入口回底；手势/主动操作恢复贴底；未上滑时自动跟随零变化

**Independent Test**: 流式生成中上滑停留：视口保持 ≥3 秒不被拉回，"回到最新"出现；点击回底恢复跟随

### Implementation for User Story 1

- [x] T002 [US1] ChatHomeTab 新增 `stickBottom: boolean = true`（@State，滚动状态区）；List 挂 `.onScroll`（仅 ScrollState.Dragging/Fling 手势态处理，上滑离开底部置 stickBottom=false，offset 方向符号以实现注释标注"待实测校准"；Idle 态直接返回过滤程序化滚动自反馈）与 `.onReachEnd`（置 stickBottom=true）——`entry/src/main/ets/pages/chat/ChatHomeTab.ets`
- [x] T003 [US1] `scrollToBottom(force)` 门禁前置：`!force && !this.stickBottom` 直接 return（置于 150ms 节流判断之前）；全部 force 调用点（send/sendSteer/onUserEcho/onHitlRequired/loadHistory）执行时显式置 `stickBottom=true`——`entry/src/main/ets/pages/chat/ChatHomeTab.ets`
- [x] T004 [US1] "回到最新"悬浮胶囊入口：`stickBottom===false && streaming` 时显示于输入卡上方（小巧胶囊，"↓ 最新"样式），点击 `scrollToBottom(true)` 并置 stickBottom=true；贴底时隐藏——`entry/src/main/ets/pages/chat/ChatHomeTab.ets`

**Checkpoint**: US1 独立可测：上滑自由阅读 + 回底入口 + 贴底行为零变化

---

## Phase 4: User Story 2 - 任务进度面板 (Priority: P1) 🎯 MVP

**Goal**: write_todos 清单在手机以"任务进度"面板呈现，流式实时更新（args 部分解析），历史回看生效；write_todos 剔除通用工具折叠卡

**Independent Test**: 诱导 agent 产出多步计划（如"帮我制定一个三步计划并逐步执行"）：流式中面板出现并实时更新"已完成 x/y"

### Implementation for User Story 2

- [x] T005 [P] [US2] 新建解析器 `entry/src/main/ets/utils/ParseWriteTodos.ets`：导出 `TodoListItem`（id/content/status）、`isWriteTodosToolName`（'/' 后缀等于 write_todos）、`collectTodoItems`（todos/items/tasks 键兼容、字符串项兼容、状态归一化 done/complete→completed、running/active→in_progress、失败返回空数组）、`parsePartialTodoItems`（截断 argsText 逐字符扫描完整 `{...}` 对象逐个解析、失败静默跳过）、`mergeTodoItems`（按 id 后写覆盖 + 数字 id 升序排序）；语义以桌面 parseWriteTodos.ts 为唯一权威参照；纯函数、无 this、ArkTS 严格类型（禁 any/unknown/裸对象字面量）
- [x] T006 [P] [US2] 新建面板组件 `entry/src/main/ets/components/TodoProgressPanel.ets`：入参 `items: TodoListItem[]`、`streaming: boolean`；标题"任务进度" + 摘要"已完成 x/y"（x=completed 数、y=总数）+ 逐项状态图标与文案（待处理/进行中/已完成/已取消）；completed/cancelled 项内容删除线；中文硬编码；样式与 MessageBubble 既有玻璃卡片语言一致
- [x] T007 [US2] MessageBubble 集成：assistant 消息 toolCalls 命中 `isWriteTodosToolName` 的调用剔除通用工具折叠卡，改渲染单个 TodoProgressPanel（同消息多次 write_todos 调用：依次取 argsText 做 parsePartialTodoItems→mergeTodoItems 链式合并）；面板置于 reasoning/text 块之前；其余工具通用折叠卡渲染不变；用户消息 fresh 入场动画区域零破坏——`entry/src/main/ets/components/MessageBubble.ets`

**Checkpoint**: US2 独立可测：write_todos 面板化实时更新 + 历史回看 + 其他工具不变

---

## Phase 5: User Story 3 - 思考态精修 (Priority: P2)

**Goal**: 流式期 reasoning 折叠行改静态"深度思考中…"（消除跳动预览），展开态限高 ≤240vp 可滚动；回合结束恢复现状单行预览

**Independent Test**: 深度推理模型流式中：折叠行显示"深度思考中…"无跳动文字；展开后内容区 ≤240vp 可滚

### Implementation for User Story 3

- [x] T008 [P] [US3] ChatMessageModel 新增可选字段 `reasoningStartAt?: number`（推理首帧时间戳，供可选计时展示）——`entry/src/main/ets/model/MessageModels.ets`
- [x] T009 [US3] ChatHomeTab `onReasoningDelta` 首帧接线：msg.reasoningStartAt 为空时记录时间戳——`entry/src/main/ets/pages/chat/ChatHomeTab.ets`
- [x] T010 [US3] MessageBubble reasoningBlock 精修：`msg.streaming` 折叠分支不渲染 reasoning 实时预览，改显示"深度思考中…"（reasoningStartAt 非空时显示"深度思考中… Ns"，N 按秒计算）；`streaming=false` 恢复现状单行省略预览；展开态内容区外套 Scroll + `.constraintSize({ maxHeight: 240 })` 内部可滚动；点击 toggle 展开行为不变——`entry/src/main/ets/components/MessageBubble.ets`

**Checkpoint**: US3 独立可测：流式折叠行静态文案 + 展开限高 + 非流式消息零变化

---

## Phase 6: User Story 4 - 键盘态彻底净化：横杠清除 + 间距收缩 (Priority: P1)

**Goal**: 键盘弹出时悬浮 TabBar 全部可见元素（104×28px 胶囊横杠 + maskColor 蒙层暗带）彻底消失；输入卡与键盘间距 401px 收缩至 ~35px（≥2/3 缩减）；收起完整恢复（视觉零变化）

**Independent Test**: 弹键盘截屏亮度分析：输入卡与键盘之间无横杠无暗带；间距 ≤134px（目标 ~35px）

### Implementation for User Story 4

- [x] T011 [US4] MainPage 键盘残留修复（第一轮）：kbHeight>0 时 Tabs `.barWidth(0)`（配合既有 barHeight 0）——`entry/src/main/ets/pages/MainPage.ets`【复勘结论：barWidth(0) 不足，TabBar 仍渲染 104×28px 最小胶囊 + 蒙层暗带，转 T017 候选序修复】
- [x] T017 [US4] MainPage 横杠彻底清除 + kbHeight 传导：`.barFloatingStyle(this.kbHeight > 0 ? undefined : this.floatingBarStyle())`（官方文档：undefined 取消悬浮样式恢复默认，pill 胶囊与蒙层随之消失；若实测不生效按 plan Decision 6 候选序升级：①FloatingTabBarStyle 键盘期全字段归零 ②barModifier visibility(None) ③其他等效）；`ChatHomeTab({...})` 构造增补 `kbHeight: this.kbHeight` 传导——`entry/src/main/ets/pages/MainPage.ets`
- [x] T018 [US4] ChatHomeTab 键盘期间距收缩：新增 `@Prop kbHeight: number = 0`；新增私有方法 `inputBottomInset(): number`（kbHeight>0 返回 10，否则 bottomPad+10）；输入卡 `.margin({ ..., bottom: this.inputBottomInset() })` 与 `.contentEndOffset(this.inputBottomInset() + this.flowH + 22)` 同步改用该入口（气泡停止位联动收缩，22vp 对称保持）——`entry/src/main/ets/pages/chat/ChatHomeTab.ets`
- [x] T019 [US4] 增量静态检查与回归自查：对 T017/T018 改动运行 `arkts_check`（MainPage.ets、ChatHomeTab.ets）修复全部诊断；diff 自查确认键盘收起态（kbHeight===0）视觉零变化（floatingBarStyle 方法本体/floatingBarBottomMargin/contentBottomPad 零改动；US1/US2/US3 已实现逻辑零触碰）

**Checkpoint**: US4 独立可测：键盘期无横杠无暗带 + 间距 ~35px + 收起视觉零变化

---

## Phase 7: Polish & Cross-Cutting Concerns

**Purpose**: 静态检查与回归守卫

- [x] T012 [P] 运行 `arkts_check` 静态检查 6 个涉及文件（ChatHomeTab.ets、MessageBubble.ets、MainPage.ets、MessageModels.ets、ParseWriteTodos.ets、TodoProgressPanel.ets），修复全部 strict-mode 诊断（重点：arkts-no-untyped-obj-literals、arkts-no-standalone-this、window 键盘回调显式类型沿用 Callback<number>）
- [x] T013 回归自查：第八~十一批行为守卫确认（TextPacer onFlush 改动仅加门禁不破坏打字机平滑；双击单发；流光包裹 Stack 结构零改动；专家恢复链 AppPrefs/SessionStore/ChatHomeTab backfill 零触碰；contentEndOffset 22vp 对称零触碰；OctopThinkingIndicator 零改动；fresh 入场动画 L385 区域零触碰）——以 diff 审查方式确认，无代码改动则直接勾选

---

## Phase 8: Verification

<!-- verification_scope: build+ui -->

**Purpose**: Build, deploy, and UI-verify the implemented feature

- [x] T014 Build project and fix any compilation errors (invoke `devecocli build`, workdir=`C:\Users\13775\OctopLink`, 上限 10 次；修复后重试直至成功)
- [x] T015 Deploy application to emulator (invoke `devecocli run --skip-build --device 127.0.0.1:5555`)
- [x] T016 Run UI verification against deployed application (invoke `verify_ui`；若工具失效按既定手动路径：uinput 触控 + dumpLayout + `hdc shell snapshot_display -f <path>.jpeg` 截屏亮度/多模态分析；模拟器锁屏密码 Abc541755)

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: T001 无依赖，先行
- **Foundational (Phase 2)**: 无跨故事阻塞项
- **US1 (Phase 3)**: T002 → T003 → T004 严格顺序（同文件 ChatHomeTab.ets 递进）
- **US2 (Phase 4)**: T005 ∥ T006 并行（不同新文件）→ T007（依赖 T005+T006 的接口）
- **US3 (Phase 5)**: T008 并行可起（独立文件）→ T009（依赖 T008 字段；与 US1 同文件注意在其后执行）→ T010（依赖 T008；与 T007 同文件 MessageBubble 注意顺序）
- **US4 (Phase 6)**: T011 已完成（barWidth(0) 实证不足）→ T017 → T018 → T019 顺序（T017/T018 不同文件可顺序执行，T019 收尾）
- **Polish (Phase 7)**: T012/T013 依赖全部实现任务完成
- **Verification (Phase 8)**: T014 → T015 → T016 严格顺序

### User Story Dependencies

- **US1 (P1)**: 无外部依赖，MVP 首发
- **US2 (P1)**: 无外部依赖，与 US1 仅在文件层交错（不同区域）
- **US3 (P2)**: T009 依赖 T008；实现顺序建议 US1→US3（同文件 ChatHomeTab 集中处理）再回 US2 集成
- **US4 (P1)**: T017/T018 基于 T011 复勘结论（用户实时反馈扩展：横杠清除 + 间距收缩）；T018 与 T009 同文件（ChatHomeTab.ets）在其后执行

### Within Each User Story

- 状态字段先行 → 行为接线 → UI 集成
- 同文件任务严格顺序执行，避免行号漂移冲突

### Parallel Opportunities

- T005 ∥ T006 ∥ T008 ∥ T011（四个不同文件，无依赖）
- 其余同文件任务顺序执行

---

## ⚡ Parallel Execution Guide

| Phase | Tasks | Required Files | Execution Notes |
|-------|-------|----------------|-----------------|
| Setup | T001 | 4 个待改文件 | 只读，校准锚点 |
| US1 | T002→T003→T004 | ChatHomeTab.ets | 同文件严格顺序 |
| US2 | T005 ∥ T006 | ParseWriteTodos.ets（新）/ TodoProgressPanel.ets（新） | 可并行；随后 T007 串行 |
| US2 集成 | T007 | MessageBubble.ets | 在 T005/T006 后 |
| US3 | T008 → T009 → T010 | MessageModels.ets / ChatHomeTab.ets / MessageBubble.ets | T008 可与其他并行；T009 在 US1 完成后做（同文件）；T010 在 T007 后做（同文件） |
| US4 | T011 → T017 → T018 → T019 | MainPage.ets / ChatHomeTab.ets | T017/T018 不同文件；T018 在 T009 后（同文件） |
| Polish | T012 ∥ T013 | 6 个涉及文件 / diff 审查 | 全部实现任务完成后 |

---

## 📊 Dependency Graph

```mermaid
graph TD
    T001[T001 锚点校准] --> T002[T002 stickBottom+onScroll/onReachEnd]
    T002 --> T003[T003 scrollToBottom 门禁+force 置位]
    T003 --> T004[T004 回到最新入口]
    T001 --> T005[T005 ParseWriteTodos.ets]
    T001 --> T006[T006 TodoProgressPanel.ets]
    T001 --> T008[T008 reasoningStartAt 字段]
    T001 --> T011[T011 MainPage barWidth 修复]
    T005 --> T007[T007 MessageBubble 面板集成]
    T006 --> T007
    T004 --> T009[T009 onReasoningDelta 首帧接线]
    T008 --> T009
    T008 --> T010[T010 reasoningBlock 精修]
    T007 --> T010
    T004 --> T010
    T009 --> T012[T012 arkts_check]
    T010 --> T012
    T011 --> T012
    T011 --> T017[T017 barFloatingStyle(undefined)+kbHeight 传导]
    T017 --> T018[T018 inputBottomInset 间距收缩]
    T009 --> T018
    T018 --> T019[T019 增量静态检查+回归自查]
    T019 --> T016
    T012 --> T013[T013 回归自查]
    T013 --> T014[T014 devecocli build]
    T014 --> T015[T015 部署模拟器]
    T015 --> T016[T016 UI 验证]
```

---

## Parallel Example: User Story 2

```bash
# Launch the two new-file tasks for User Story 2 together:
Task: "T005 [P] [US2] 新建解析器 entry/src/main/ets/utils/ParseWriteTodos.ets"
Task: "T006 [P] [US2] 新建面板组件 entry/src/main/ets/components/TodoProgressPanel.ets"

# Then integrate sequentially after both complete:
Task: "T007 [US2] MessageBubble 集成 entry/src/main/ets/components/MessageBubble.ets"
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Setup（锚点校准）
2. Complete Phase 3: US1（stickBottom 门禁滚动自由）
3. **STOP and VALIDATE**: 上滑停留 ≥3 秒不被拉回
4. Deploy/demo if ready

### Incremental Delivery

1. T001 Setup → Foundation 无阻塞
2. US1（T002-T004）→ 上滑自由独立验证
3. US2（T005-T007）→ 任务进度面板独立验证
4. US3（T008-T010）→ 思考态精修独立验证
5. US4（T011）→ 键盘残留独立验证
6. Polish（T012-T013）→ Verification（T014-T016）

### Parallel Team Strategy

单人顺序执行为主；仅 T005/T006/T008/T011 四个独立文件任务理论可并行。

---

## Notes

- [P] tasks = different files, no dependencies
- [Story] label maps task to specific user story for traceability
- onScroll offset 方向符号待实测校准：实现时以注释标注，验收轮（T016）允许翻转符号一次
- 以 argsText 为面板唯一数据源（resultText 500 字符截断 + 多工具并发错位风险规避）
- 服务端零改动；ChatStreamController.upsertToolCall/fromHistoryRecord 零改动
- 中文文案硬编码（与 App 现状一致）
- 构建上限 10 次（T014）；验证轮 per-story 修复构建不受此限
- 每任务完成即勾选 `- [x]`；T016 UI 验证若 verify_ui 工具失效，走既定手动路径（uinput+dumpLayout+snapshot_display .jpeg）
