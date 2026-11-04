---
description: "Task list for stream-pace-turn-race"
---

# Tasks: stream-pace-turn-race（流式平滑输出 + 回合结束竞态根治）

**Input**: Design documents from `spec/stream-pace-turn-race/`
**Prerequisites**: plan.md (required), spec.md (required for user stories)

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- Include exact file paths in descriptions

## Path Conventions

- 项目根：`C:\Users\13775\OctopLink`
- 新文件：`entry\src\main\ets\utils\TextPacer.ets`（纯逻辑工具类，与 TimeFormat/Logger/ThreadDigestCache 同级）
- 主改造：`entry\src\main\ets\pages\chat\ChatHomeTab.ets`
- 只读参考：`entry\src\main\ets\model\MessageModels.ets`（appendText/appendReasoning/markEnded）
- 构建产物：`entry\build\default\outputs\default\entry-default-signed.hap`

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: 现状锚点确认

- [X] T001 通读 `ChatHomeTab.ets` 流式回调（onTextDelta/onReasoningDelta，约 L597-620）与收尾链（endTurnMarked L349/endTurnReconciled L363/beginTurn L337/send L887/sendSteer L975），核对 `MessageModels.ets` 的 appendText/appendReasoning/markEnded 契约，确认改动锚点行号

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: TextPacer 基建——US1/US3 依赖

**⚠️ CRITICAL**: No user story work can begin until this phase is complete

- [X] T002 [P] 新建 `entry\src\main\ets\utils\TextPacer.ets`：通用打字机缓冲器——constructor(intervalMs, onFlush)、push/finish/cancel 三入口、tick 自适应落盘 `min(16, 2 + ceil(积压/8))`、setInterval/clearInterval 定时器（-1 表未运行）、finish 全量落盘、cancel 丢弃清空；纯 ArkTS 类（显式类型、无 any、无 ArkUI 依赖）
- [X] T003 ChatHomeTab 接线：新增 `textPacer`/`reasoningPacer` 私有字段并在 aboutToAppear 构造（text onFlush：activeAssistant 非空 appendText + streamPhase='正在生成…' + scrollToBottom(false)；reasoning onFlush：activeAssistant 非空 appendReasoning）；onTextDelta/onReasoningDelta 改为 push 进缓冲（删除直连 appendText/appendReasoning）

**Checkpoint**: pacer 基建就绪

---

## Phase 3: User Story 1 - 流式平滑输出 (Priority: P1) 🎯 MVP

**Goal**: 收尾全量落盘 + 生命周期 cancel，平滑输出不丢内容

**Independent Test**: 长文生成观察逐字小步连续输出；结束后内容与服务端一致

### Implementation for User Story 1

- [X] T004 [US1] 收尾 flush 语义：endTurnMarked 与 endTurnReconciled 入口先 `finish()` 两 pacer（FR-003，在状态变更之前）；确保收尾内容零丢失
- [X] T005 [US1] 生命周期 cancel：beginTurn 创建**新**占位时 cancel 两 pacer；aboutToDisappear/onThreadChanged（异值重置分支）/onAgentChanged cancel 两 pacer；**teardownStream 不触碰 pacer**（断线重连续流期间缓冲保留续排）（FR-004）

**Checkpoint**: US1 独立可测——平滑输出、收尾完整、切会话无串写

---

## Phase 4: User Story 2 - 回合结束竞态窗口根治 (Priority: P1)

**Goal**: 同步收敛回合状态 + turnGen 代际守卫 + steer 分支防重入，根治"出两个"

**Independent Test**: 回复刚结束瞬间快速双击发送：仅 1 条用户消息并正常开新回合

### Implementation for User Story 2

- [X] T006 [US2] endTurnReconciled 入口同步收敛（严格时序）：①finish 两 pacer ②捕获 turnGen/turnAssistant ③置 streaming=false、streamPhase=''、currentTurnId=''、activeAssistant=null（占位保留 liveMsgs 显示）④await 拉历史——任何 await 之前完成①②③（FR-005）
- [X] T007 [US2] turnGen 代际守卫：新增 `turnGen` 字段，beginTurn 仅在创建新占位时自增（复用不++）；endTurnReconciled 拉取完成后"线程未变 && 代际未变"才执行清空 liveMsgs + setServerMsgs + 既有刷新；否则中止不覆盖；拉取失败回退对捕获 turnAssistant markEnded(true,'回复中断')（null 安全），代际已变则跳过标记（FR-006/FR-007）
- [X] T008 [US2] send() steer 分支防重入对齐：streaming→sendSteer 分支纳入 turnSending 守卫（入口检查/finally 释放）+ await 前同步清空 inputText + 失败路径恢复原文；connectWs 等待期转 steer 分支同覆盖；sendSteer 内部 reconnect 失败恢复输入逻辑保持（FR-008）
- [X] T009 [US2] dangling steerPending 清理：endTurnReconciled 成功清空 liveMsgs 后，steerPending 引用对象不在 liveMsgs 则置 null（FR-009）

**Checkpoint**: US2 独立可测——双击单发、窗口内单发走常规路径、过期 reconcile 不覆盖新回合

---

## Phase 5: User Story 3 - 全量回归核对 (Priority: P2)

**Goal**: 第八批既有能力零回归，无定时器泄漏

**Independent Test**: 杀 App 重启续流、切会话、HITL、steer 回归

### Implementation for User Story 3

- [X] T010 [US3] 回归核对清单：对照 FR-010 逐项输出证据（引用行号）——杀 App 重启续流（onTurnStatus 恢复分支与 turnGen 兼容）、HITL 四决策（endTurnMarked/onResumeStreamEnd 与 finish 顺序）、活跃回合 steer 排队（sendSteer 正常路径未破坏）、双击单发、切会话同值守卫（onThreadChanged cancel 不影响同值 return）、ForEach key msg.id 与双层架构未变
- [X] T011 [P] `arkts_check` 对 `TextPacer.ets` 与 `ChatHomeTab.ets` 通过（无新增违例）；全文无残留直连 appendText 的 onTextDelta（grep 证据）

**Checkpoint**: 全量回归证据就绪

---

## Phase 6: Verification

<!-- verification_scope: build+ui -->

**Purpose**: Build, deploy, and UI-verify the implemented feature

- [X] T012 构建：`devecocli build`（workdir=项目根）修复循环直至成功
- [X] T013 部署模拟器：`devecocli run --skip-build --device 127.0.0.1:5555`
- [X] T014 UI 逐条验收：按 spec User Story 1-3 验收场景逐条执行——US1 长文平滑输出/收尾一致；US2 回复结束瞬间双击单发/窗口内单发新回合正常；US3 杀 App 续流/切会话无串写/HITL/steer 回归；截屏（.jpeg）+dumpLayout（UTF8）+hilog 取证

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: 无依赖，立即开始
- **Foundational (Phase 2)**: T002（新文件）与 T003（接线）顺序执行（T003 依赖 T002 的类）；阻塞 US1/US3
- **US1 (Phase 3)**: 依赖 T002/T003；T004/T005 顺序执行
- **US2 (Phase 4)**: T006/T007/T008/T009 顺序执行（T007 依赖 T006 的时序重构；T008 独立于 T006/T007 但同文件顺序改）
- **US3 (Phase 5)**: 依赖 Phase 3/4 完成
- **Verification (Phase 6)**: 依赖 Phase 5 完成

### User Story Dependencies

- **User Story 1 (P1)**: 依赖 Foundational；MVP 主体（用户最直接的不适体验）
- **User Story 2 (P1)**: 与 US1 同文件不同函数区，顺序实现；竞态窗口修复依赖 endTurnMarked/endTurnReconciled 入口重构（T004 完成后 T006 在同一入口继续改）
- **User Story 3 (P2)**: 依赖 US1/US2 完成；纯回归核对

### Within Each User Story

- 先基建（类/字段）后接线（回调改造）
- endTurnReconciled 的 T004（finish）与 T006（同步收敛）作用于同一入口：按"finish→捕获→收敛→await"最终时序一次改到位
- 每 task 完成确认无残留旧路径

### Parallel Opportunities

- T002（新文件 TextPacer.ets）可与 T001 并行
- T010/T011（核对/静态检查）可并行
- 其余同文件任务顺序执行

---

## Parallel Example: User Story 1

```bash
# 不同文件可并行：
Task: "T002 新建 entry/src/main/ets/utils/TextPacer.ets（纯逻辑类）"
Task: "T001 通读 ChatHomeTab.ets 锚点核对"

# 同文件接线顺序执行：
Task: "T003 ChatHomeTab pacer 字段构造 + onTextDelta/onReasoningDelta 改缓冲"
Task: "T004 endTurnMarked/endTurnReconciled 入口 finish"
Task: "T005 beginTurn/生命周期 cancel"
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Setup（锚点）
2. Complete Phase 2: Foundational（TextPacer + 接线）
3. Complete Phase 3: User Story 1（平滑输出 MVP）
4. **STOP and VALIDATE**: 长文流式观感 + 收尾一致性独立验证
5. Deploy if ready

### Incremental Delivery

1. Setup + Foundational → pacer 基建
2. US1 → 平滑输出 → 验证（MVP）
3. US2 → 竞态根治（双击单发）→ 验证
4. US3 → 全量回归 → 验证
5. Verification（构建/部署/UI 验收）

---

## Notes

- [P] tasks = different files, no dependencies
- [Story] label maps task to specific user story for traceability
- 服务端零改动；客户端 1 新文件 + 1 文件改造
- ArkTS 硬规则：无 any/unknown、显式类型、build() 顶层无局部声明、禁止裸对象字面量、V1 状态管理、setInterval/clearInterval 全局 API（返回 number）
- 构建前必过 `arkts_check`（TextPacer.ets + ChatHomeTab.ets）
- 验证环境：模拟器 127.0.0.1:5555，服务器 s3.z100.vip:35796；锁屏密码 Abc541755
- 打字机参数（40ms/2+1/8/上限16）如验收观感不达标，验证轮可微调 tick 参数（spec Assumptions 授权）
