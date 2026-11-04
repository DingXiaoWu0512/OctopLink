# Implementation Plan: 聊天核心缺陷修复与交互改造（第七批 ui-refine-batch-6）

**Input**: Feature specification from `spec/ui-refine-batch-6/spec.md`

## Summary

修复聊天流式链路核心缺陷并改造发送交互。四类修复共享同一根因分析：(a) 新会话/切会话时 `@Watch onThreadChanged` 同步触发异步历史加载，与 `send()` 本地消息插入形成竞态——历史响应整体替换 `this.messages` 导致本地 fresh 用户消息与流式占位脱钩（消息消失/流式增量不可见），以及 steer echo 重复插入（消息重复）；(b) App 重启后 `onTurnStatus` 回调仅处理 `streaming===true` 分支，活跃回合的订阅应答被忽略，流式气泡与输入卡流光边框均不恢复；(c) `scrollToBottom` 使用 `scrollToIndex(this.messages.length - 1)`，而 List 前置标题栏占位项（index 0）、条件性"加载更早"项使消息实际列表索引整体偏移 +1/+2，滚动落在倒数第二/三条消息上；(d) 输入区交互缺少发送后收键盘、空输入置灰、聚焦边框加粗。全部改动限于客户端 `ChatHomeTab.ets`、`WelcomeCard.ets` 及既有组件复用，服务器零改动。

## Technical Context

**Language/Version**: ArkTS（HarmonyOS，API 12+，DevEco 工具链 `devecocli build`）
**Primary Dependencies**: 既有项目结构——HdsNavigation/HdsEffectKit（@kit.UIDesignKit）、WsClient/SseClient、ChatStreamController、ThreadService、MessageModels（V1 @Observed）
**State Management**: 保留项目现有 State Management V1（@Component/@State/@StorageLink/@Watch/@Observed），本批不引入 V2
**Storage**: 无新增持久化；复用 AppStorage 键（KEY_ACTIVE_THREAD_ID 等）
**Testing**: `devecocli build` 编译验证 + 模拟器（127.0.0.1:5555）部署 + `uitest dumpLayout`/`snapshot_display`/hilog 逐条验收
**Target Platform**: HarmonyOS 手机（模拟器 1280×2832 验证，真机可选）
**Project Type**: 移动应用（既有 OctopLink HarmonyOS 客户端增量改动）
**Performance Goals**: 流式增量渲染帧率不受影响；滚动修正不引入额外布局开销
**Constraints**: 服务器端零改动；ArkTS 严格模式（无 any/裸对象字面量/解构）；build() 顶层无局部声明；ForEach 必须带 key
**Scale/Scope**: 2 个 .ets 文件改动（ChatHomeTab.ets、WelcomeCard.ets），无新文件

## Project Structure

### Documentation (this feature)

```text
spec/ui-refine-batch-6/
├── spec.md              # 需求规格
├── plan.md              # 本文件
└── tasks.md             # 任务分解
```

### Source Code (repository root)

```text
entry/src/main/ets/
├── pages/chat/
│   └── ChatHomeTab.ets        # 主战场：竞态修复/续流/滚动/输入交互/空态
├── components/
│   └── WelcomeCard.ets        # 空态文案替换
└── （其余文件零改动：MessageModels/ThreadService/ChatStreamController/WsClient/
     OctopThinkingIndicator/StreamingOrbit/MessageBubble 均复用现状）
```

**Structure Decision**: 遵循既有项目架构（页面 pages/chat + 组件 components + 服务 service/net + 模型 model 分层），无新增目录或文件；全部改动收敛在 `ChatHomeTab.ets`（流式/滚动/交互逻辑所在地）与 `WelcomeCard.ets`（空态视图）。不引入 MVVM 迁移。

## Complexity Tracking

（无宪法违规——增量改动，无新项目/新模式引入）

## Research & Decisions

### R1: 消息重复+流式消失根因（同源竞态）

- **Decision**: `loadHistory()` 历史响应到达时不再直接整体替换 `this.messages`，改为"服务端结果 + 本地进行中消息"合并：服务端消息为准，其后若本地存在尚未落库的 fresh 用户消息（服务端结果尾部无同角色同文本者）则追加；若 `this.activeAssistant` 非 null（流式占位）则追加回列表尾部，保证流式增量始终写入可见气泡。steer echo（`onUserEcho`）在 push 前检查尾部是否已存在同文本用户消息，存在则跳过 push。
- **Rationale**: `ensureThread()` 内 `AppStorage.setOrCreate(KEY_ACTIVE_THREAD_ID)` 同步触发 `@Watch onThreadChanged` → 异步 `loadHistory()`；`send()` 随后本地 push 用户消息+流式占位。历史响应晚到时整体替换 `this.messages` 使占位脱钩（`activeAssistant` 引用仍在，增量写入不可见对象——"流式到一半消失、重启才能看到"）；若响应含已落库用户消息而本地副本又幸存则重复。合并策略使任意时序（响应先到/后到）均收敛到正确状态。
- **Alternatives considered**: ① `ensureThread` 置自切换标志让 `onThreadChanged` 跳过 `loadHistory`（只堵新会话一条路径，其他替换点如 reconcile/切会话仍裸露）；② 串行化 loadHistory 与 send（引入队列复杂度，破坏现有并发模型）。均否决。

### R2: 重启续流方案（服务端能力已验证）

- **Decision**: 利用既有 WS 订阅应答：`onTurnStatus(active=true)` 且本地 `streaming===false`、无 `activeAssistant`、会话未处于 HITL 等待时，重建流式占位（`streaming=true`、`streamPhase='恢复续流中…'`、`turnHadGap=true`），后续 token/reasoning/tool 帧经既有回调写入；回合结束帧到达时因 `turnHadGap=true` 走既有 `reconcileFinalMessage()` 拉取服务端权威最终消息补齐（覆盖重启前漏帧）。与 `loadHistory` 的时序竞态由 R1 合并策略兜底（先建气泡后被历史替换→合并保留；先历史后建→直接追加）。
- **Rationale**: 服务端 `ws.py` 订阅即回 `turn_status {active: hub.is_turn_active(thread_id)}`（`src/octop/api/routers/chat/ws.py:126-132`），活跃回合后续帧实时广播给订阅者；普通线程不回放重启前历史帧（仅团队房间有 catchup，`team_manager.py:116-130`），缺失部分由回合结束时的落库消息补齐——`reconcileFinalMessage` 已实现且经过验证。输入卡流光边框 `InputFlowBorder` 挂载条件即 `this.streaming`（shader autoPlay，`OctopThinkingIndicator.ets:74-125`），续流置真后自动恢复旋转。
- **Alternatives considered**: ① 轮询 REST 判断活跃（延迟高、耗电）；② 服务端加回放（违反服务器零改动约束）。均否决。

### R3: 滚动索引错位修复

- **Decision**: `scrollToBottom()` 放弃 `scrollToIndex(this.messages.length - 1)`，改用 `scroller.scrollEdge(Edge.Bottom)`（列表真实底端，天然免疫前置 spacer/加载更早项/尾部审批卡的索引偏移）；`loadHistory()` 完成后的初始定位（现 `scrollToIndex(..., true)` 动画滚动）同样改为 `scrollEdge(Edge.Bottom)`。保留 150ms 节流与 `force` 语义。工具调用相关回调（`onToolCall`/`onToolActivity`/`onAttachment`）既有 `scrollToBottom` 调用随实现修正自动生效；`onToolActivity` 补充触发滚动（现仅改 phase 不滚）。
- **Rationale**: List 结构 = [标题栏占位(idx0)] + [加载更早(条件)] + [消息×N] + [审批卡(条件)]，`scrollToIndex(messages.length-1)` 实际落在倒数第 1+offset 条消息上——"工具调用时跳到最近上一条"的根因。`scrollEdge(Edge.Bottom)` 是语义正确的"滚到底"。
- **Alternatives considered**: 按 `1+(historyHasMore?1:0)` 修正索引（需同步维护两个调用点与条件项状态，脆弱）。否决。

### R4: 发送交互（收键盘/置灰/聚焦边框）

- **Decision**: ① `TextArea` 挂 `TextAreaController`，`send()` 成功路径（含 slash 命令、steer 追问、hitl respond 提交）调用 `stopEditing()` 收起软键盘；② 空闲态发送按钮增加空输入判断：`inputText.trim()===''` 时呈置灰禁用态（降低前景/背景对比、`enabled(false)`），有内容恢复现有品牌态；③ 输入卡边框宽度绑定聚焦状态：`@State inputFocused`，TextArea `onFocus`/`onBlur` 切换，边框 `width: inputFocused ? 2 : 1`（颜色沿用 card_stroke）。流式中的停止/追问按钮行为保持现状。
- **Rationale**: 用户明确要求发送后键盘与输入一起收起、空输入置灰、聚焦边框 1dp→2dp。`TextAreaController.stopEditing()` 为官方收键盘途径。不重构输入卡布局（保持既有打磨设计），仅增补三个交互点。
- **Alternatives considered**: 重构 TextArea+发送按钮同行布局（用户建议参考项之一）——会推翻第六批已打磨的输入卡结构且非必需，否决。

### R5: 空态文案替换

- **Decision**: `WelcomeCard` 中间区域（logo 装饰 + 快捷提示 chips 元素群）替换为居中文案"开启一段新对话吧，什么都可以说。"（沿用现有空态字号/颜色规范：15fp、text_primary、居中）。`prompts` 数据与点击填充输入能力不再渲染（组件参数保留以兼容其他调用方；经查 WelcomeCard 仅 ChatHomeTab 一处使用，空态渲染直接简化）。欢迎语 message 字段保留渲染。
- **Rationale**: 用户原文"新建会话页面中间一堆小图标换成『开启一段新对话吧，什么都可以说。』"；"一堆小图标"即快捷提示 chips 群（每枚含纸飞机小图标）。WelcomeCard 仅 ChatHomeTab 使用，改动无外溢。
- **Alternatives considered**: 保留 chips 仅换图标——与"换成文案"的明确要求不符，否决。

## Data Model

（无新增实体；涉及既有模型的状态语义修订）

- **ChatMessageModel（@Observed，MessageModels.ets）**: 复用现状。`streaming`/`fresh`/`clientPendingId` 字段语义不变；本批仅修订其所在数组 `messages` 的替换策略（合并而非覆盖）与 steer echo 判重规则。
- **历史合并结果（loadHistory 内部局部语义，不新增类）**: 服务端消息数组 + 条件追加 [本地 fresh 用户消息（尾部无同角色同文本）] + [activeAssistant 流式占位（非 null 时）]。
- **ChatHomeTab 新增 UI 状态**:
  - `inputFocused: boolean`（输入框聚焦态，边框宽度 1dp/2dp 切换）
  - `TextAreaController` 实例（收键盘控制）
- **续流状态机（既有字段复用）**: `streaming=true` + `streamPhase='恢复续流中…'` + `turnHadGap=true` 三元组标记重启续流；结束走 `reconcileFinalMessage` 归位。

## Contracts & Interfaces

（服务器零改动；WS/REST 契约全部复用，此处记录本批依赖的契约要点）

- **WS 订阅应答**: `subscribe {thread_id}` → 服务端回 `{"type":"turn_status","thread_id":T,"active":bool}`（`api/routers/chat/ws.py:126-132`）。客户端 `ChatStreamController.callbacks.onTurnStatus(active)` 已解析（`ChatStreamController.ets:350-352`），本批仅修改 ChatHomeTab 侧处理逻辑。
- **活跃回合帧广播**: 活跃 turn 的 token/reasoning/tool_call_chunk/tool_result/usage/turn.ended 帧实时广播给订阅者（既有 handleFrame 路由，无需改动）。
- **历史消息 REST**: `ThreadService.historyFull(agentId, threadId, offset)` 返回 `HistoryResult{messages, hitlPending, hasMore}`（`ThreadService.ets:19-31`）——续流结束补齐复用（`reconcileFinalMessage` 既有实现）。
- **UI 内部契约**:
  - `scrollToBottom(force: boolean)` 语义不变（force 绕过 150ms 节流），实现改为 `scrollEdge(Edge.Bottom)`。
  - `WelcomeCard` 对外参数签名不变（message/prompts/onPromptClick），渲染简化。
  - `InputFlowBorder`/`OctopThinkingIndicator`/`StreamingOrbit`/`MessageBubble` 零改动。
