---
description: "Task list for chat-receive-rewrite"
---

# Tasks: chat-receive-rewrite（消息接收链路重写）

**Input**: Design documents from `spec/chat-receive-rewrite/`
**Prerequisites**: plan.md (required), spec.md (required for user stories)

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- Include exact file paths in descriptions

## Path Conventions

- 项目根：`C:\Users\13775\OctopLink`
- 全部代码改动收敛于 `entry\src\main\ets\pages\chat\ChatHomeTab.ets`（单文件重构，零新文件）
- 只读参考：`entry\src\main\ets\model\MessageModels.ets`、`entry\src\main\ets\model\ThreadModels.ets`、`entry\src\main\ets\service\ChatStreamController.ets`、`entry\src\main\ets\components\MessageBubble.ets`
- 构建产物：`entry\build\default\outputs\default\entry-default-signed.hap`

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: 改动面确认，无新结构

- [X] T001 通读 `entry\src\main\ets\pages\chat\ChatHomeTab.ets` 接收链路现状（send L931/sendSteer L1003/onThreadChanged L208/loadHistory L294/loadEarlierMessages L381/wireCallbacks L537/merge 辅助 L335-378/ForEach L2383），列出全部 turnHadGap/fresh/mergeHistoryWithLocal/clearLocalFreshMarks/hasTailUserMessage 引用点清单，确认与 spec FR-005/SC-006 对齐的删除范围

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: 双层数组基建与生命周期三方法——后续所有 user story 依赖

**⚠️ CRITICAL**: No user story work can begin until this phase is complete

- [X] T002 [P] 双层数组基建：新增私有字段 `serverMsgs`/`liveMsgs`（`ChatHomeTab.ets`），实现 `recompose()`/`setServerMsgs()`/`pushLive()`/`removeLive()` 四方法，`@State messages` 全部既有直改点改为经 recompose 统一重赋值（本任务先落基建，直改点迁移与 T004-T012 联动完成）
- [X] T003 turn 生命周期三方法：实现 `beginTurn(phase)`（幂等占位：activeAssistant 已存在则复用不重复 push）/`endTurnMarked(failed, message)`（本地标记收尾）/`endTurnReconciled()`（historyFull 权威替换 + liveMsgs 同 tick 清空 + hitlPending/hasMore/摘要/上下文刷新 + 线程/新回合抢占守卫 + 失败回退 endTurnMarked）（`ChatHomeTab.ets`，依赖 T002）

**Checkpoint**: 基建就绪，user story 实现可开始

---

## Phase 3: User Story 1 - 双层消息架构重写 (Priority: P1) 🎯 MVP

**Goal**: 历史拉取整体替换 serverMsgs、offset 只数 serverMsgs、回合结束唯一 reconcile 收尾、删除全部文本判重冗余

**Independent Test**: 正常问答后翻页"加载更早的消息"无重复；连发两次"继续"两条都在且各有回复

### Implementation for User Story 1

- [X] T004 [US1] `loadHistory()` 改为 `setServerMsgs(result.messages)` 整体替换，liveMsgs 不动；删除 `mergeHistoryWithLocal()` 调用与定义、`clearLocalFreshMarks()` 调用与定义（`ChatHomeTab.ets`）
- [X] T005 [US1] `loadEarlierMessages()` offset 改 `this.serverMsgs.length`，结果 `setServerMsgs(result.messages.concat(this.serverMsgs))` 前插（`ChatHomeTab.ets`）
- [X] T006 [US1] `onTurnEnded` 改为一律 `endTurnReconciled()`（删除 turnHadGap 分支）；`send()` 的 sendUserTurn 失败路径改 endTurnMarked 语义（占位标记失败保留/或按 FR-008 移除恢复输入，与 T009 联动）（`ChatHomeTab.ets`，依赖 T003）
- [X] T007 [US1] `onUserEcho` 改为：清 steerPending 引用（消息本体留 liveMsgs）+ 仅 liveMsgs 尾部无同文本用户消息时补推 + `beginTurn('正在思考…')`；删除 `hasTailUserMessage()` 的 serverMsgs 语义判重（liveMsgs 尾部判重内联实现）（`ChatHomeTab.ets`，依赖 T003）
- [X] T008 [US1] ForEach key 改 `msg.id`：`(msg: ChatMessageModel) => msg.id`，移除 index 前缀与未用的 index 参数（`ChatHomeTab.ets` L2383-2395）

**Checkpoint**: US1 独立可测——翻页无重复、重复文本不消失、流式气泡持续刷新

---

## Phase 4: User Story 2 - 发送防重入与输入即时清空 (Priority: P2)

**Goal**: 双击只发一条；输入即时清空；失败恢复输入

**Independent Test**: 快速双击发送仅 1 条用户消息 + 1 个流式气泡；点击发送瞬间输入框清空

### Implementation for User Story 2

- [X] T009 [US2] `send()`：新增 `turnSending` 私有守卫（入口检查/finally 释放）；slash 命令分支外，在任何 `await`（ensureThread/connectWs）之前同步 `this.inputText = ''`；ensureThread/connectWs/sendUserTurn 各失败路径恢复 `inputText` 原文、`removeLive` 本轮用户消息与占位、toast 提示（`ChatHomeTab.ets`）
- [X] T010 [US2] `sendSteer()`：await（connectWs）前同步清空 `this.inputText`；`submitHitlRespond()` 保持既有先读后清时序核对（读 text 后立即清，无 await 窗口）（`ChatHomeTab.ets`）

**Checkpoint**: US2 独立可测——双击单发、即时清空、失败恢复

---

## Phase 5: User Story 3 - 会话切换同值守卫 (Priority: P2)

**Goal**: 流式中点击当前会话不拆流不重载

**Independent Test**: 流式生成中点击会话列表当前会话，流继续、光晕持续、无重载

### Implementation for User Story 3

- [X] T011 [US3] `onThreadChanged()`：新增 `lastHandledThreadId` 私有字段，入口同值（`this.activeThreadId === lastHandledThreadId`）直接 return；异值走既有全量重置并更新 lastHandledThreadId，重置中同步清空 serverMsgs/liveMsgs；`onAgentChanged()` 重置同步清空两层数组（agent 切换不加守卫）（`ChatHomeTab.ets`）

**Checkpoint**: US3 独立可测——同值点击零副作用

---

## Phase 6: User Story 4 - turn 生命周期收敛与续流/审批回归 (Priority: P3)

**Goal**: 全部占位创建/收尾点收敛到三方法；turnHadGap 全套删除；续流/审批/steer 回归通过

**Independent Test**: 杀 App 重启续流补齐；HITL 四种决策走通

### Implementation for User Story 4

- [X] T012 [US4] `submitHitl()` 改 `beginTurn('正在生成…')`；`onTurnStatus` 恢复续流分支改 `beginTurn('恢复续流中…')`、active=false 收尾改 `endTurnReconciled()`；`onHitlRequired`/`onResumeStreamEnd`/`onStreamError`/`abortHitlResume` 改 endTurnMarked 语义；`onTurnStarted`/`onConnectionClosed` 删除 turnHadGap 读写（`ChatHomeTab.ets`，依赖 T003）
- [X] T013 [US4] `retryLastTurn()`/`withdrawSteer()`/`removeSteerPending()`/`reconcileFinalMessage()` 适配双层数组（steer 移除只操作 liveMsgs；旧 reconcileFinalMessage 被 endTurnReconciled 取代后删除）；确认 `fresh` 字段仅剩模型定义无 UI 逻辑依赖（`ChatHomeTab.ets`）

**Checkpoint**: 全部生命周期点经三方法，无游离收尾

---

## Phase 7: Polish & Cross-Cutting Concerns

**Purpose**: 冗余清除收尾与静态检查

- [X] T014 [P] 全文清扫：`turnHadGap`/`mergeHistoryWithLocal`/`clearLocalFreshMarks`/`hasTailUserMessage` 引用数为 0（SC-006）；注释与代码一致（无过时 US 编号注释误导）；`arkts_check` 对 `ChatHomeTab.ets` 通过、无新增违例
- [X] T015 [P] 回归核对清单输出：对照 FR-011 逐项列出续流/HITL/steer/断线重连/TTS/录音/附件/命令面板在改动中未被破坏的证据（引用行号），供 Phase 8 验收引用

---

## Phase 8: Verification

<!-- verification_scope: build+ui -->

**Purpose**: Build, deploy, and UI-verify the implemented feature

- [X] T016 构建：`devecocli build`（workdir=项目根）修复循环直至成功
- [X] T017 部署模拟器：`devecocli run --skip-build --device 127.0.0.1:5555`
- [X] T018 UI 逐条验收（verify_ui 式）：按 spec User Story 1-4 验收场景逐条执行——US1 翻页无重复/重复文本不消失/流式刷新；US2 双击单发/即时清空；US3 同值点击不拆流光晕持续；US4 杀 App 续流补齐/HITL/steer；dumpLayout/截屏/hilog 取证

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: 无依赖，立即开始
- **Foundational (Phase 2)**: 依赖 Phase 1 引用点清单；阻塞全部 user story
- **User Stories (Phase 3-6)**: 均依赖 Phase 2 完成
  - US1（T004-T008）与 US2（T009-T010）改动同文件不同函数区，实现顺序执行（T006 与 T009 在 send 失败路径上联动，先后完成即可）
  - US3（T011）、US4（T012-T013）依赖 T003 三方法
- **Polish (Phase 7)**: 依赖全部 user story 完成
- **Verification (Phase 8)**: 依赖 Phase 7 完成

### User Story Dependencies

- **User Story 1 (P1)**: 依赖 Foundational（T002/T003）；MVP 主体
- **User Story 2 (P2)**: 依赖 Foundational；与 US1 的 T006 在 send 失败路径联动，顺序实现
- **User Story 3 (P3)**: 依赖 Foundational；独立于 US1/US2
- **User Story 4 (P3)**: 依赖 T003/T006；回归面最广，最后实现

### Within Each User Story

- 先基建（字段/方法）后调用点迁移
- 先删除旧路径后接入新路径（同函数内一次完成，不留双轨）
- 每 task 完成后确认无残留旧引用再进入下一 task

### Parallel Opportunities

- T002 与 T003 均在 ChatHomeTab.ets，逻辑上 T003 依赖 T002 的 pushLive/recompose，顺序执行
- T008（ForEach key）与 T004-T007 函数区不同，但同文件，实现时顺序执行避免合并冲突
- T014/T015（Polish）可并行核对

---

## Parallel Example: User Story 1

```bash
# 同文件任务按顺序执行（单文件重构无真正并行）：
Task: "T004 loadHistory 改 setServerMsgs 整体替换，删除 merge/clearFresh 辅助"
Task: "T005 loadEarlierMessages offset 改 serverMsgs.length 前插"
Task: "T006 onTurnEnded 一律 endTurnReconciled"
Task: "T007 onUserEcho 改 beginTurn + liveMsgs 尾部判重"
Task: "T008 ForEach key 改 msg.id"
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Setup（引用点清单）
2. Complete Phase 2: Foundational（双层数组 + 三方法）
3. Complete Phase 3: User Story 1（重复/消失主缺陷修复）
4. **STOP and VALIDATE**: 翻页无重复 + 重复文本不消失独立验证
5. Deploy if ready

### Incremental Delivery

1. Setup + Foundational → 基建就绪
2. US1 → 主缺陷修复 → 验证（MVP）
3. US2 → 双击/即时清空 → 验证
4. US3 → 同值守卫 → 验证
5. US4 → 生命周期收敛 + 回归 → 全量验证
6. Polish → 冗余清扫 → Verification（构建/部署/UI 验收）

---

## Notes

- [P] tasks = different files, no dependencies（本特性单文件，[P] 仅标注逻辑可并行核对项）
- [Story] label maps task to specific user story for traceability
- 服务端零改动；仅客户端 ChatHomeTab.ets
- ArkTS 硬规则：无 any/unknown、显式类型、build() 顶层无局部声明、禁止裸对象字面量、V1 状态管理
- 构建前必过 `arkts_check`（ChatHomeTab.ets）
- 验证环境：模拟器 127.0.0.1:5555，服务器 s3.z100.vip:35796；锁屏密码 Abc541755
