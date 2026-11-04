# Feature Specification: stream-pace-turn-race（流式平滑输出 + 回合结束竞态根治）

**Created**: 2026-10-31
**Status**: Approved（用户长期指令：直接执行，不询问）
**Input**: 用户反馈："流式对了 但是是一堆一堆跳的，优化一下出的方式，尽量连续稳定的跳，可以跳的慢一点但是要舒服。出消息还是会出现两个，这个不知道如何解决"

## Overview

第八批重写后流式内容正确但呈现"整段跳跃"（delta 帧按网络批次到达即整批落盘），且"消息出两个"仍有残余：根因是 onTurnEnded→endTurnReconciled 在 await 拉历史期间未同步收敛回合状态，弱网下 1-3 秒竞态窗口内 streaming 仍为 true——窗口内点击被误路由进无防重入守卫的 sendSteer 分支，服务端回合已空闲将其记为新 user_turn，快速双点即产生两条相同消息。本特性交付：①TextPacer 打字机缓冲（定速平滑 + 自适应追赶）；②回合结束竞态窗口根治（同步收敛 + turnGen 代际守卫 + steer 分支防重入）。

## User Scenarios & Testing *(mandatory)*

### User Story 1 - 流式平滑输出（TextPacer 打字机节奏）(Priority: P1)

text/reasoning delta 帧不再直接落盘到气泡，而是进入 TextPacer 缓冲，由 40ms 定时 tick 小步落盘：每 tick 输出"基础 2 字 + 积压量的 1/8"，单 tick 上限 16 字——积压小时稳定慢速打字，积压大时渐进加速追赶，永不整段跳跃。回合收尾前 pacer 全量 flush（最终内容零丢失）。

**Why this priority**: 用户直接点名的不适体验（"一堆一堆跳"→"尽量连续稳定、可以慢但要舒服"），感知层最高优先。

**Independent Test**: 请求生成一段长文（如 300 字散文），观察流式输出应逐字/小步连续出现，无整段跳跃；结束后内容与服务端历史完全一致。

**Acceptance Scenarios**:

1. **Given** 助手正在流式输出长文，**When** delta 帧按网络批次（一次多帧）到达，**Then** 气泡文字以连续平滑的小步进逐段呈现，无"停顿后整段跳出"
2. **Given** 输出过程中网络瞬时积压（数百字未落盘），**Then** pacer 以受限速率（≤16 字/tick）渐进追赶，不瞬间跳完
3. **Given** 回合结束（含中断/审批暂停），**When** 收尾路径执行，**Then** pacer 在收尾前全量 flush，气泡最终内容与流式帧累计一致、与服务端历史一致
4. **Given** 断线重连续流，**When** 重连期间缓冲排空、重连后新帧继续到达，**Then** pacer 自动重启落盘，不丢不重

---

### User Story 2 - 回合结束竞态窗口根治（"出两个"修复）(Priority: P1)

endTurnReconciled 入口同步收敛回合状态（flush pacer → streaming=false / streamPhase='' / currentTurnId='' / activeAssistant=null，已完成的占位气泡保留在 liveMsgs 显示直到权威历史替换）；引入 turnGen 代际守卫（beginTurn 新建占位时自增，过期 reconcile 完成前发现代际变化即中止）；send() 的 steer 分支补齐 turnSending 防重入守卫 + await 前同步清空 inputText（与常规发送分支对齐）。

**Why this priority**: 用户报告的"出消息还是会出现两个"直接根因；弱网真机高频可复现（回复刚结束的瞬间连点）。

**Independent Test**: 回复刚结束的瞬间（<1 秒内）快速双击发送下一条消息，应只出现一条用户消息并正常开启新回合。

**Acceptance Scenarios**:

1. **Given** 回复刚结束（reconcile 拉历史进行中），**When** 立即点击发送，**Then** 因 streaming 已同步置 false，走常规发送路径（turnSending 守卫 + 同步清输入），消息作为新回合正常处理
2. **Given** 同上窗口内，**When** 快速双击发送，**Then** 仅 1 条用户消息落库与显示（修复前：两次点击均进入无守卫的 sendSteer，服务端空闲各记一条新 user_turn → 出两个）
3. **Given** 竞态窗口内已有新回合开始（新占位创建），**When** 旧回合的 endTurnReconciled 完成拉取，**Then** turnGen 代际守卫中止过期 reconcile，不覆盖/不清空新回合的 liveMsgs
4. **Given** reconcile 拉取失败，**When** 回退本地标记，**Then** 对捕获的占位 markEnded(true,'回复中断') 保留显示，新回合状态不受影响
5. **Given** 流式真正进行中（回合活跃），**When** 用户发送追问，**Then** 仍走 steer 排队路径（此分支现有行为回归不破坏）

---

### User Story 3 - 收尾清理与全量回归 (Priority: P2)

pacer 生命周期完整（aboutToDisappear / 切线程 / 切专家时 cancel 防泄漏与串写；teardownStream 不清缓冲以支持重连续流；beginTurn 新建占位时 cancel 陈旧缓冲）；reconcile 清空 liveMsgs 时同步清 dangling steerPending；第八批全部既有能力回归（杀 App 续流、HITL、steer、双击单发、切会话同值守卫）。

**Why this priority**: 打字机与竞态修复必须不引入定时器泄漏/跨会话串写等新缺陷，且不回归第八批已验收能力。

**Independent Test**: 流式输出中切换会话再切回、杀 App 重启续流，均无残留打字、无内容串写、续流补齐一致。

**Acceptance Scenarios**:

1. **Given** 流式输出中（pacer 缓冲非空），**When** 切换会话，**Then** pacer cancel，旧会话缓冲文字不写入新会话气泡
2. **Given** 流式中杀 App 重启，**When** 重新进入同一会话，**Then** 恢复续流 + 回合结束 reconcile 补齐（第八批 US4 行为回归）
3. **Given** 流式中切专家/退出页面，**When** aboutToDisappear/onAgentChanged 执行，**Then** 定时器清零无泄漏
4. **Given** reconcile 完成清空 liveMsgs，**When** steerPending 引用的消息已不在 liveMsgs，**Then** steerPending 置 null，后续 echo 不被 steer 分支误吞

### Edge Cases

- 超长回复（>1000 字）+ 网络瞬时倾泻：单 tick 16 字上限保证追赶渐进不跳跃，回合结束 finish 兜底完整
- pacer 缓冲非空时回合结束：finish 先于 activeAssistant 置空（顺序保证最终内容完整写入占位）
- 竞态窗口极短（模拟器快网）时行为与正常路径一致（同步收敛无副作用）
- steer 发送网络失败：输入恢复、排队消息移除（既有行为保持）
- reconcile 与 loadEarlier 并发：loadingEarlier 守卫保持
- turnStatus 的"恢复续流中…"收尾路径同样走同步收敛 + 代际守卫

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: 新增 `entry/src/main/ets/utils/TextPacer.ets`：push(delta) 入缓冲并确保定时器运行；finish() 停止定时器并同步全量落盘剩余缓冲；cancel() 停止定时器并丢弃缓冲；tick 落盘量 = min(16, 2 + ceil(积压量/8))，间隔 40ms
- **FR-002**: onTextDelta/onReasoningDelta MUST 经 textPacer/reasoningPacer 缓冲落盘（不直连 appendText/appendReasoning）；flush 回调内更新 streamPhase('正在生成…') 与节流滚动
- **FR-003**: endTurnMarked 与 endTurnReconciled 入口 MUST 先 finish 两个 pacer（收尾内容零丢失），再执行后续状态变更
- **FR-004**: pacer 生命周期：beginTurn 创建**新**占位时 cancel；aboutToDisappear/onThreadChanged（异值重置）/onAgentChanged cancel；teardownStream MUST NOT 清缓冲（断线重连续流期间缓冲保留续排）
- **FR-005**: endTurnReconciled 入口 MUST 同步（任何 await 之前）收敛回合状态：finish pacer → streaming=false、streamPhase=''、currentTurnId=''、activeAssistant=null；已完成的占位气泡保留在 liveMsgs 显示直到权威历史替换
- **FR-006**: turnGen 代际守卫：ChatHomeTab 新增 turnGen 计数，beginTurn 仅在创建新占位时自增；endTurnReconciled 捕获入口代际，拉取完成后线程未变且代际未变才执行"清空 liveMsgs + setServerMsgs + 状态刷新"；否则中止不覆盖
- **FR-007**: endTurnReconciled 拉取失败回退：对入口捕获的占位 markEnded(true,'回复中断')（保留 liveMsgs 显示），不影响新回合状态
- **FR-008**: send() 的 steer 分支（含 connectWs 等待期转 steer 分支）MUST 纳入 turnSending 防重入守卫，且在任何 await 之前同步清空 inputText，失败路径恢复原文（与常规发送分支对齐）
- **FR-009**: endTurnReconciled 成功清空 liveMsgs 时，MUST 同步清 dangling steerPending（其引用消息已不在 liveMsgs 则置 null）
- **FR-010**: 第八批既有能力 MUST 回归通过：杀 App 重启续流补齐、HITL 四种决策、活跃回合 steer 排队/ack/撤回、双击单发、切会话同值守卫、ForEach key msg.id、双层架构不变
- **FR-011**: 服务端 MUST 零改动（客户端单侧）

### Key Entities

- **TextPacer**: 通用打字机缓冲器（intervalMs + onFlush 回调构造），push/finish/cancel 三入口，自适应追赶落盘
- **turnGen**: 回合代际计数器，用于 reconcile 完成时识别"期间是否已开始新回合"
- **竞态窗口**: turn.ended 帧到达至 endTurnReconciled 历史拉取完成之间的异步间隙（修复前 streaming/currentTurnId 残留旧值）

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: 长文流式输出全程无整段跳跃（连续小步进），回合结束内容与服务端历史一致（零丢失可核对）
- **SC-002**: 回复结束后 1 秒内快速双击发送：仅 1 条用户消息（服务端落库 2 条会话消息：1 用户 + 后续回复，而非 2 条相同用户消息）
- **SC-003**: 回复结束后的发送窗口内单发：消息作为新回合正常处理，不丢失、不重复、不被误路由为 steer
- **SC-004**: 流式中切会话/切专家/杀 App：无定时器泄漏（hilog 无残留 tick 活动）、无跨会话串写、续流补齐一致
- **SC-005**: 第八批 4 个用户故事回归全部通过

## Assumptions

- 40ms tick（≈25 次/秒落盘）+ 每 tick 2-16 字的速率区间在观感上"连续稳定、慢而舒服"（用户明确表示可接受更慢）
- 服务端 delta 帧到达节奏不受客户端控制，平滑只能由客户端缓冲实现
- 模拟器快网下竞态窗口极短难以实测复现，US2 以代码级验证（同步收敛无 await 前置间隙）+ 行为回归（双击单发）双重保障
- TextPacer 为纯逻辑类（无 ArkUI 依赖），可放 utils/ 目录
- 测试环境：模拟器 127.0.0.1:5555，服务器 s3.z100.vip:35796，与第八批一致

## Open Questions

- （无——用户长期指令要求不询问直接执行；速率参数以 Assumptions 为准，验收观感不达标可在验证轮微调 tick 参数）
