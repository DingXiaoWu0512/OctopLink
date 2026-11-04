# Feature Specification: chat-receive-rewrite（消息接收链路重写）

**Created**: 2026-10-31
**Status**: Approved（用户长期指令：直接执行，不询问）
**Input**: 用户反馈："1.2.3还存在" + "检查一下构建的接受消息方式，查一下api把接受消息重写一下，不知道是不是太冗余的问题"

## Overview

第七批交付后用户报告三个残留缺陷（①消息重复 ②流式消息消失 ③光晕不转）并指出消息接收实现疑似过度冗余。经对照服务端 API（ws.py subscribe→turn_status、history.py 全量历史）逐行勘察，确认根因：当前 `messages` 单一扁平数组混装"服务端历史 + 本地进行中消息"，靠 fresh 标记、文本判重、turnHadGap 缺口追踪等启发式拼接，产生三类真实缺陷。本特性将接收链路重写为**双层消息架构**（服务端消息层 + 本地进行中 overlay 层），turn 结束一律以服务端权威历史 reconcile 收尾，删除全部文本判重与缺口追踪冗余，并修复发送防重入与会话切换同值重置。

## User Scenarios & Testing *(mandatory)*

### User Story 1 - 双层消息架构重写（P1）

消息数组拆为两层：`serverMsgs`（服务端独占，历史拉取整体替换）与 `liveMsgs`（本地进行中 overlay：刚发出的用户消息、流式占位、steer 排队消息），渲染数组 = serverMsgs.concat(liveMsgs)。历史拉取（进入会话/loadEarlier/turn 结束 reconcile）永不做文本判重合并；turn 结束一律拉全量历史替换 serverMsgs 并清空 liveMsgs（唯一收尾路径）；loadEarlier 的 offset 只数 serverMsgs。

**Why this priority**: 直接消灭 ①重复（offset 含 live 副本偏高 → 重叠窗口重复）与 ②消失（文本判重误伤重复文本）两个用户报告的主缺陷，是本次重写的核心价值。

**Independent Test**: 会话内完成一次正常问答后点击"加载更早的消息"应无重复；连续两次发送相同文本（如"继续"）两条消息都应显示且各有回复。

**Acceptance Scenarios**:

1. **Given** 一轮正常问答结束（无断线），**When** 点击"加载更早的消息"翻页，**Then** 列表无任何一模一样的重复消息（修复前：本地 userMsg+assistant 副本永久滞留致 offset 偏高 2，翻页返回重叠窗口）
2. **Given** 会话中曾发过"继续"，**When** 再次发送"继续"，**Then** 刚发的消息立即可见且不消失（修复前：mergeHistoryWithLocal 文本判重误判"已落库"跳过本地副本）
3. **Given** 流式回复进行中，**When** 持续接收 text_delta 帧，**Then** 气泡内容持续增长、光晕动画持续旋转（占位对象引用稳定，不被数组重排打断）
4. **Given** 一轮问答结束，**When** 查看消息列表，**Then** 用户消息与助手回复各仅一条，内容与服务端历史一致（reconcile 权威替换）

---

### User Story 2 - 发送防重入与输入即时清空（P2）

发送按钮点击后：输入框内容在任何 await 之前同步清空（即时反馈）；turnSending 守卫阻止连接握手等待期的二次重入；发送失败时恢复输入内容并移除本地占位。

**Why this priority**: 消灭慢网双击重入导致的 ①重复（用户报告的高频真机场景），同时给出即时的输入清空反馈。

**Independent Test**: 快速连点两次发送按钮，消息列表只应出现一条用户消息与一个流式气泡；点击发送瞬间输入框立即清空。

**Acceptance Scenarios**:

1. **Given** 网络较慢（WS 握手未完成），**When** 快速双击发送按钮，**Then** 仅推送一条用户消息与一个流式占位（修复前：inputText 在握手 await 之后才清空，二次点击重新进入 send 双重推送）
2. **Given** 输入框有文字，**When** 点击发送，**Then** 输入框同步立即清空、发送按钮立即置灰，无需等待网络往返
3. **Given** 发送失败（WS 发送异常），**When** catch 到异常，**Then** 输入框恢复原文字、本地用户消息与占位气泡移除、提示发送失败

---

### User Story 3 - 会话切换同值守卫（P2）

onThreadChanged 记录上次已处理的线程 id，活跃线程 id 未变化时跳过全量重置（不拆流、不重载历史、不清界面）。

**Why this priority**: 会话列表点击当前会话（同值 setOrCreate 亦触发 @Watch）会 teardownStream 拆断正在进行的流式——这是 ③光晕不转/流中断的触发路径之一；流式中误触当前会话是常见操作。

**Independent Test**: 流式生成中打开会话列表点击当前正在聊天的会话，流应继续、光晕持续旋转、界面无重载闪烁。

**Acceptance Scenarios**:

1. **Given** 流式回复生成中，**When** 点击会话列表中当前活跃的会话，**Then** 流不中断、streamPhase 与光晕动画保持、列表不重新加载
2. **Given** 流式生成中，**When** 切换到另一条会话再切回，**Then** 重连后按 turn_status 恢复续流（既有 US2 续流能力回归通过）

---

### User Story 4 - turn 生命周期收敛与续流/审批回归（P3）

占位创建收敛为 beginTurn()（幂等：已有占位则复用），收尾收敛为 endTurnMarked()（纯本地标记，仅用于审批暂停/中断兜底）与 endTurnReconciled()（拉权威历史收尾，唯一常规收尾路径）；删除 turnHadGap 全套缺口追踪。杀 App 重启续流、HITL 审批（approve/reject/respond/edit）、steer 追问与撤回、断线重连续流全部回归通过。

**Why this priority**: 重写收尾在消除冗余的同时必须不回归第七批已验证的能力；收敛生命周期方法使 6+ 个结束点与 5 个占位创建点共享同一实现，是"减冗余"诉求的直接交付。

**Independent Test**: 流式中杀 App 重启，应自动恢复续流并最终与服务端内容一致；HITL 审批卡流程走通。

**Acceptance Scenarios**:

1. **Given** 流式回复生成中，**When** 强杀 App 后重新打开进入同一会话，**Then** 订阅应答 active=true 时重建占位接续实时帧，回合结束 reconcile 补齐全量内容
2. **Given** 助手发起 HITL 审批请求，**When** 用户点击批准/拒绝/人工回复/编辑参数任一决策，**Then** 恢复流正常生成、结束 reconcile 后审批卡消失、结果与服务端一致
3. **Given** 流式生成中，**When** 输入框发送追问（steer），**Then** 排队消息入列、ack/撤回/丢弃路径行为与第七批一致
4. **Given** 弱网导致 WS 断线，**When** 自动重连成功，**Then** 恢复续流并在回合结束补齐缺口内容

### Edge Cases

- reconcile 拉取历史失败（网络异常）时回退 endTurnMarked 本地标记"回复中断"，本地气泡保留至下次 reconcile/切会话，不白屏不丢流
- reconcile 进行中用户又发起 steer/新 turn：以 currentTurnId/activeAssistant 变化守卫，中止过期 reconcile 不覆盖新回合状态
- liveMsgs 中被 endTurnMarked 的中断气泡在下次成功 reconcile 时随 liveMsgs 清空被服务端权威内容取代（中断回合若服务端有落库则呈现权威内容，未落库则自然消失，输入框此前已恢复）
- 首条消息即触发 HITL（无任何助手输出）时审批卡正常展示
- loadEarlier 与 reconcile 并发：loadingEarlier 守卫保持，reconcile 替换 serverMsgs 后 hasMore 以 reconcile 结果为准
- 发送时 slash 命令（/new、/stop）仍本地执行不入 liveMsgs
- 空输入、纯空白输入仍不发（按钮置灰行为保持）

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: 消息数组 MUST 拆分为 serverMsgs（服务端层）与 liveMsgs（本地 overlay 层）两个私有数组，渲染用 @State messages MUST 由两者 concat 统一重赋值（recompose），liveMsgs 内对象引用在回合进行期间保持稳定
- **FR-002**: 历史拉取（loadHistory/loadEarlier/endTurnReconciled）MUST 仅整体替换 serverMsgs，MUST NOT 触碰 liveMsgs，MUST NOT 做任何基于文本/时间的判重合并
- **FR-003**: loadEarlier 的分页 offset MUST 只统计 serverMsgs 数量（修复 offset 含 live 副本偏高导致的重叠重复）
- **FR-004**: 回合结束（turn.ended）MUST 走 endTurnReconciled：拉全量历史→替换 serverMsgs→清空 liveMsgs（同一 tick 内完成切换）→刷新 hitlPending/hasMore/摘要/上下文用量；拉取失败回退 endTurnMarked
- **FR-005**: 系统 MUST 删除 mergeHistoryWithLocal、clearLocalFreshMarks、hasTailUserMessage（serverMsgs 语义）及 turnHadGap 全套缺口追踪逻辑
- **FR-006**: onUserEcho MUST 以 beginTurn 幂等复用/创建流式占位；用户文本仅当 liveMsgs 尾部不存在同文本未落库消息时才补推
- **FR-007**: ForEach 渲染 key MUST 改为 msg.id（去除 index 前缀，消除重组后 key 漂移）
- **FR-008**: send() MUST 在任何 await 之前同步清空 inputText；turnSending 守卫 MUST 阻止重入；发送失败 MUST 恢复 inputText 并移除本轮 liveMsgs 占位
- **FR-009**: onThreadChanged MUST 记录上次处理线程 id，同值跳过全量重置（不拆流不重载）；异值路径行为保持现状
- **FR-010**: beginTurn/endTurnMarked/endTurnReconciled MUST 被 send、onUserEcho、submitHitl、onTurnStatus 续流、onHitlRequired、onResumeStreamEnd、abortHitlResume、send 失败等全部生命周期点复用
- **FR-011**: 既有能力 MUST 回归通过：杀 App 重启续流补齐、HITL 四种决策、steer 追问/ack/撤回/丢弃、断线自动重连续流、TTS/录音/附件/命令面板不受影响
- **FR-012**: 服务端 MUST 零改动（仅对照 ws.py/history.py 契约，客户端单侧重写）

### Key Entities

- **serverMsgs**: 服务端权威消息层（历史窗口内的全部消息），只被"整体替换"或"前插翻页"两种操作变更
- **liveMsgs**: 本地进行中 overlay（fresh 用户消息、流式占位 activeAssistant、steer 排队消息、被标记中断的本地气泡），回合 reconcile 成功后清空
- **beginTurn()/endTurnMarked()/endTurnReconciled()**: turn 生命周期三方法，收敛全部占位创建与收尾路径
- **turnSending**: 发送重入守卫布尔量

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: 正常回合结束后连续翻页加载更早消息 ≥2 页，全列表 0 条重复（按 id 去重统计）
- **SC-002**: 连续发送相同文本 2 次及以上，每次发送后消息立即可见且不消失
- **SC-003**: 快速双击发送（<300ms 间隔）仅产生 1 条用户消息 + 1 个流式气泡
- **SC-004**: 流式生成中点击当前会话，流无中断（hilog 无 teardown/重连记录，光晕动画持续）
- **SC-005**: 杀 App 重启续流场景回合结束内容与 historyFull 最终态一致（既有 US2 验证方式回归）
- **SC-006**: ChatHomeTab.ets 中 turnHadGap/mergeHistoryWithLocal/clearLocalFreshMarks/hasTailUserMessage 引用数为 0（冗余清除可度量）

## Assumptions

- 服务端全量历史接口（history.py L391-411）在回合结束后能立即返回含本轮的完整消息（第七批 reconcileFinalMessage 已验证该契约）
- 每 turn 结束多一次 GET historyFull 的代价可接受（换取唯一收尾路径与权威数据）
- 服务端 user_echo 与本地先行推送可能重复表达同一条消息，仅靠 liveMsgs 尾部判重足够（不再做全量文本判重）
- ChatMessageModel.id 在服务端消息与本地消息间天然不冲突（服务端 id 与 local_N 种子），可直接作 ForEach key
- 测试环境为模拟器 127.0.0.1:5555，服务器 s3.z100.vip:35796，与第七批验证环境一致

## Open Questions

- （无——用户长期指令要求不询问直接执行；全部歧义已按服务端契约与第七批验证证据裁定）
