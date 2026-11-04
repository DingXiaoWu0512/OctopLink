# Implementation Plan: chat-receive-rewrite

**Input**: Feature specification from `spec/chat-receive-rewrite/spec.md`

## Summary

将 ChatHomeTab 的消息接收链路从"单一扁平 messages 数组 + fresh 标记/文本判重/turnHadGap 缺口追踪"重写为"serverMsgs（服务端权威层）+ liveMsgs（本地进行中 overlay 层）"双层架构：历史拉取只整体替换 serverMsgs，回合结束一律以 historyFull 权威 reconcile 收尾（唯一收尾路径），turn 生命周期收敛为 beginTurn/endTurnMarked/endTurnReconciled 三方法；同时修复 send 双击重入（await 前同步清输入 + turnSending 守卫）与 onThreadChanged 同值重置（同值守卫）。服务端零改动。

## Technical Context

**Language/Version**: ArkTS（API 12+，DevEco 工具链）
**Primary Dependencies**: ArkUI（@Component V1 状态管理）、@kit.ArkTS、@kit.CoreFileKit、@kit.ArkUI（window/LengthMetrics）
**State Management**: 状态管理 V1（项目既有，@State/@StorageLink/@StorageProp/@Consume/@Watch/@Prop，保持不变）
**Storage**: 无新增持久化；沿用 AppStorage（SessionStore keys）与 ThreadDigestCache
**Testing**: spec-verify 子代理构建 + 模拟器部署 + dumpLayout/截屏/hilog 逐条验收（用户长期指令：执行完验收每一个要求）
**Target Platform**: HarmonyOS 模拟器 127.0.0.1:5555（验证环境）；真机 192.168.3.190:44541 仅按用户明确要求
**Project Type**: 既有 HarmonyOS 应用（OctopLink，com.octop.link）增量改造
**Performance Goals**: 流式帧到达即渲染（既有能力保持）；reconcile 同 tick 完成数组切换无闪烁
**Constraints**: 服务端零改动；ArkTS 严格模式（无 any/unknown、显式类型、build() 无局部声明、禁止裸对象字面量）
**Scale/Scope**: 单文件主改造（ChatHomeTab.ets ~2839 行），触及渲染 key 与生命周期方法，无新文件

## Project Structure

### Documentation (this feature)

```text
spec/chat-receive-rewrite/
├── spec.md               # 本特性规格（/spec-specify 输出）
├── plan.md               # 本文件（/spec-plan 输出）
└── tasks.md              # 任务清单（/spec-tasks 输出）
```

### Source Code (repository root)

```text
entry/src/main/ets/
├── pages/chat/
│   └── ChatHomeTab.ets        # 主战场：双层数组、生命周期三方法、send 防重入、同值守卫、ForEach key
├── model/
│   └── MessageModels.ets      # 只读参考（ChatMessageModel.id/local_N 种子/fromUserText/streamingAssistant；不改动）
├── model/
│   └── ThreadModels.ets       # 只读参考（HistoryResult{messages,hitlPending,hasMore}；不改动）
├── service/
│   └── ChatStreamController.ets  # 只读参考（callbacks 契约；不改动）
└── components/
    └── MessageBubble.ets / MarkdownText.ets  # 只读参考（@ObjectLink msg 已修复；不改动）
```

**Structure Decision**: 遵循既有项目架构，零新文件。本特性是单页接收链路的内部重构 + 缺陷修复，全部改动收敛于 `ChatHomeTab.ets`，模型/服务/组件层契约不变。

## Complexity Tracking

> 无 Constitution 违规。双层数组为类内私有字段 + 统一 recompose 重赋值，不引入新文件、新类、新状态管理代际。

## Research & Decisions

### 服务端契约对照（源码已逐行核对）

- `ws.py L105-132`：`subscribe{thread_id}` → 校验线程归属 → `subscribe_with_member_catchup`（仅团队房间回放）→ 立即回 `turn_status {thread_id, active}`；活跃 turn 后续帧实时广播，普通线程不回放重启前帧 → 客户端必须靠 `historyFull` reconcile 补齐缺口（重启续流语义保持第七批设计）
- `history.py L391-411`：全量历史响应含 `messages/has_more/turn_active/hitl_pending` 等 → 回合结束后一次 GET 即得权威终态，支撑"结束必 reconcile"
- `team_manager.py L116-130`：catchup 仅团队房间 → 普通线程 turn_status active=false 不代表有回放，中断内容必须走 REST 拉取

### 根因裁定（勘察结论，写入 spec 的依据）

1. **①重复-翻页**：turn 无 gap 结束走本地 markEnded，userMsg+assistant 副本永久滞留 `messages`；loadEarlier 以 `this.messages.length` 为 offset（含 2 条 live 副本）偏高 → 服务端返回重叠窗口 → concat 重复
2. **②消失**：mergeHistoryWithLocal 按文本判重，历史中旧的同文本消息（"继续"）误判刚发 fresh 副本"已落库"而跳过
3. **①重复-双击**：inputText 在 send() L971 才清（ensureThread/connectWs await 之后），慢网握手期二次点击重入 send 双重推送
4. **③光晕/拆流**：@StorageLink 上同值 setOrCreate 亦触发 @Watch，流式中点击列表当前会话 → onThreadChanged 全量重置 teardownStream 拆流

## Data Model

### 双层消息数组（ChatHomeTab 类内私有字段，非 @State）

- `serverMsgs: Array<ChatMessageModel>`：服务端权威层。仅两种变更方式：`setServerMsgs(list)` 整体替换（loadHistory/endTurnReconciled）；`loadEarlierMessages` 前插翻页（`result.messages.concat(serverMsgs)`）
- `liveMsgs: Array<ChatMessageModel>`：本地 overlay 层。持有：刚发出的 fresh 用户消息、流式占位（activeAssistant 引用同源）、steer 排队消息、被 endTurnMarked 标记的本地中断气泡。回合 reconcile 成功后整体清空
- 渲染数组保持 `@State messages`，由 `recompose(): void` 以 `serverMsgs.concat(liveMsgs)` 统一重赋值；回合进行期间 liveMsgs 内对象引用不变（appendText 等就地写入由 @Observed/@ObjectLink 链路驱动刷新，光晕动画不被打断）

### 生命周期三方法（类内私有方法）

- `beginTurn(phase: string): void`：幂等创建/复用流式占位——activeAssistant 为 null 时 push streamingAssistant 至 liveMsgs 并绑定；activeAssistant 已存在则复用不重复 push；统一置 streaming=true、streamPhase=phase、turnHadGap 语义删除
- `endTurnMarked(failed: boolean, message: string): void`：纯本地收尾——activeAssistant.markEnded 后保留在 liveMsgs（中断/审批暂停兜底），清 currentTurnId/streaming/streamPhase，不拉历史
- `endTurnReconciled(): Promise<void>`：唯一常规收尾——historyFull 拉取（守卫线程未切换、activeAssistant/currentTurnId 未被新回合抢占）→ setServerMsgs(result.messages) + liveMsgs 清空 + recompose（同 tick 原子切换）→ 刷新 hitlPending/hasMore/syncDigest/refreshContextUsage/THREADS_DIRTY；拉取失败回退 endTurnMarked(true, '回复中断')

### 接收链路回调重绑（wireCallbacks 内）

- onTextDelta/onReasoningDelta/onToolActivity/onToolCall/onToolResult/onUsage/onAttachment/onSpeaker：仅写 activeAssistant，不变
- onUserEcho：清 steerPending 引用（消息本体留在 liveMsgs）；仅当 liveMsgs 尾部不存在同文本用户消息时补推；beginTurn('正在思考…')
- onTurnStarted：currentTurnId 记录；streamPhase '恢复续流中…'→'正在生成…'（保留续流语义），否则 '正在思考…'
- onTurnEnded：一律 endTurnReconciled（不再有 turnHadGap 分支）
- onTurnStatus：active=false 且本地在恢复续流 → endTurnReconciled；active=true 且本地无占位（App 重启订阅）→ beginTurn('恢复续流中…')；其余相位文案逻辑保持
- onConnectionClosed：streaming 时 phase='恢复续流中…'（不再置 turnHadGap）；重连成功后靠 turn_status/续流帧 + 回合结束 reconcile 补齐
- onStreamError/onResumeStreamEnd：endTurnMarked 语义（本地标记），保持既有行为
- onHitlRequired：endTurnMarked(false,'') + hitlPending 设置，保持既有行为

### 发送与切换

- `send()`：读 text → slash 命令（保持本地执行）→ streaming 时 sendSteer → **turnSending 守卫** → **任何 await 之前同步 this.inputText=''** → ensureThread/connectWs → 失败路径恢复 inputText 原文并移除本轮 liveMsgs 占位 + toast；成功路径 push 用户消息（liveMsgs）+ beginTurn('正在思考…') + sendUserTurn，sendUserTurn 异常时同失败路径
- `sendSteer()`：同样 await 前清输入；pending 用户消息入 liveMsgs；ack 拒绝/移除路径只操作 liveMsgs
- `submitHitl`：beginTurn('正在生成…') 复用占位创建
- `onThreadChanged()`：新增 `lastHandledThreadId` 私有字段，函数入口比对 `this.activeThreadId`，同值直接 return（不拆流不重载）；异值走既有全量重置（重置时同步清空 serverMsgs/liveMsgs/两数组相关状态）
- `onAgentChanged()`：重置时同步清空 serverMsgs/liveMsgs（agent 切换必重置，无同值问题，不加守卫）
- `retryLastTurn()`：从渲染数组取最后一条用户消息，语义不变（新 turn 保留两条用户消息为设计）

## Contracts & Interfaces

- `recompose(): void` → `this.messages = this.serverMsgs.concat(this.liveMsgs)`
- `setServerMsgs(list: Array<ChatMessageModel>): void` → serverMsgs 替换 + recompose
- `pushLive(m: ChatMessageModel): void` / `removeLive(m: ChatMessageModel): void` → liveMsgs 增删 + recompose
- `beginTurn(phase: string): void`（幂等占位）
- `endTurnMarked(failed: boolean, message: string): void`
- `endTurnReconciled(): Promise<void>`（失败回退 endTurnMarked）
- 删除项：`mergeHistoryWithLocal`、`clearLocalFreshMarks`、`hasTailUserMessage`、`turnHadGap` 字段及其全部读写点
- ForEach key：`(msg: ChatMessageModel) => msg.id`（index 前缀移除；MarkdownText 嵌套 ForEach 的 `${block.content.length}` key 保持）
- 对外 UI 契约不变：MessageBubble/MarkdownText/WelcomeCard/StreamingOrbit/命令面板/TTS/录音/附件接口零改动
