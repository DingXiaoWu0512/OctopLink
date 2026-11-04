# Implementation Plan: stream-pace-turn-race

**Input**: Feature specification from `spec/stream-pace-turn-race/spec.md`

## Summary

两个交付：①TextPacer 打字机缓冲（utils/TextPacer.ets 新文件 + ChatHomeTab 接线），把 onTextDelta/onReasoningDelta 的批次到达改为 40ms 定频小步落盘、自适应追赶、收尾全量 flush；②回合结束竞态窗口根治——endTurnReconciled 入口同步收敛回合状态（任何 await 之前），turnGen 代际守卫防过期 reconcile 覆盖新回合，send() 的 steer 分支补齐 turnSending 守卫与同步清输入，reconcile 清空 liveMsgs 时清 dangling steerPending。服务端零改动。

## Technical Context

**Language/Version**: ArkTS（API 12+，DevEco 工具链）
**Primary Dependencies**: ArkUI（@Component V1 状态管理）、@kit.ArkTS（setInterval/clearInterval 全局定时器）
**State Management**: 状态管理 V1（项目既有，保持不变）
**Storage**: 无新增持久化
**Testing**: spec-verify 子代理构建 + 模拟器部署 + dumpLayout/截屏/hilog 逐条验收（用户长期指令）
**Target Platform**: HarmonyOS 模拟器 127.0.0.1:5555；真机仅按用户明确要求
**Project Type**: 既有 HarmonyOS 应用（OctopLink，com.octop.link）增量改造
**Performance Goals**: 流式落盘 25 次/秒（40ms tick）连续平滑；定时器零泄漏
**Constraints**: 服务端零改动；ArkTS 严格模式；TextPacer 为纯逻辑类无 ArkUI 依赖
**Scale/Scope**: 1 个新文件（~80 行）+ ChatHomeTab.ets 定点改造

## Project Structure

### Documentation (this feature)

```text
spec/stream-pace-turn-race/
├── spec.md               # 本特性规格
├── plan.md               # 本文件
└── tasks.md              # 任务清单
```

### Source Code (repository root)

```text
entry/src/main/ets/
├── utils/
│   └── TextPacer.ets         # 新增：通用打字机缓冲器（push/finish/cancel + 自适应 tick）
├── pages/chat/
│   └── ChatHomeTab.ets       # 接线与竞态根治：pacer 字段与回调、onTextDelta/onReasoningDelta 改缓冲、
│                              # endTurnReconciled 同步收敛 + turnGen 守卫、send() steer 分支防重入、
│                              # steerPending 清理、生命周期 cancel
└── model/
    └── MessageModels.ets     # 只读参考（appendText/appendReasoning/markEnded；不改动）
```

**Structure Decision**: 遵循既有项目架构。新增 1 个纯逻辑工具类（utils/ 目录与 TimeFormat/Logger/ThreadDigestCache 同级），1 个页面文件定点改造，不引入新层级。

## Complexity Tracking

> 无 Constitution 违规。TextPacer 单一职责小类；ChatHomeTab 为定点增量改造。

## Research & Decisions

### 勘察结论（写入 spec 的依据）

1. **"一堆一堆跳"根因**：onTextDelta/onReasoningDelta 直连 m.appendText(delta)/m.appendReasoning(delta)——服务端 delta 帧按网络批次到达（TCP 粘包/服务端聚合），一次到达多帧即整批落盘，视觉上停顿后整段跳出
2. **"出两个"根因链（实锤）**：onTurnEnded → endTurnReconciled 的 `await ThreadService.historyFull(...)` 之前未收敛任何回合状态——弱网真机该窗口 1-3 秒，期间 `streaming===true`、`currentTurnId` 非空：
   - 窗口内点击发送 → send() 的 `if (this.streaming)` 分支误路由进 sendSteer → 服务端回合已空闲（ws.py `_maybe_admit_steer` 对非活跃回合返回 False）→ 该帧被当作常规 user_turn 开新回合
   - sendSteer 分支**无 turnSending 守卫、未同步清空 inputText**（send() 的守卫与清输入只覆盖非流式分支）→ 回复刚结束瞬间快速双点：两次都进 sendSteer → 服务端各记一条 user_turn → **两条相同消息**
   - 次生问题：sendSteer 排队消息 + beginTurn 复用旧占位 → 旧 reconcile 的 `nowAssistant !== turnAssistant` 同一性守卫被复用占位骗过 → 过期 reconcile 清空 liveMsgs 抹掉新回合消息
3. **服务端契约（源码核对）**：ws.py L591-669 `_maybe_admit_steer`——回合非活跃时 delivery=auto 的 steer 帧回落为常规 user_turn（开新回合）；回合活跃时排队（steer.queued）。客户端修复后此回落路径仅剩"回合活跃"内的正当 steer

### 设计决策

- **打字机参数**：tick 40ms（25fps 落盘）；每 tick 落盘 `min(16, 2 + ceil(积压/8))` 字——积压小（<16 字）时每 tick 2-4 字（约 50-100 字/秒的稳定慢打），积压大时渐进加速至上限 16 字/tick（400 字/秒）追赶，永不整段跳
- **同步收敛时序（endTurnReconciled 入口，严格顺序）**：①finish textPacer/reasoningPacer（缓冲写入尚在显示的占位）②捕获 turnGen/turnAssistant ③置 streaming=false、streamPhase=''、currentTurnId=''、activeAssistant=null（占位对象保留在 liveMsgs 显示）④await 拉历史——此后任何点击都命中 send() 常规分支（turnSending 守卫 + 同步清输入）
- **turnGen 代际守卫替代对象同一性守卫**：beginTurn 仅在**创建新占位**时 turnGen++（复用占位不++）；endTurnReconciled 入口捕获代际，拉取完成后"线程未变 && 代际未变"才执行清空 liveMsgs + setServerMsgs + 状态刷新；否则中止。修复"复用占位骗过同一性守卫"的次生问题
- **失败回退**：拉取失败 → 对入口捕获的 turnAssistant（可能为 null）markEnded(true,'回复中断')，保留 liveMsgs 显示；不影响已开始的新回合（代际已变则连标记也跳过，新回合自会 reconcile）
- **steer 分支对齐**：send() 中 streaming→sendSteer 分支纳入 turnSending 守卫覆盖（入口检查/finally 释放），分支内在 await 前同步清空 inputText；sendSteer 内部既有 reconnect 失败恢复输入逻辑保持
- **pacer 生命周期**：teardownStream 不动 pacer（断线重连期间缓冲继续排空、新帧续排）；beginTurn 创建新占位时 cancel 陈旧缓冲；aboutToDisappear/onThreadChanged（异值）/onAgentChanged cancel（防泄漏与跨会话串写）
- **dangling steerPending**：endTurnReconciled 成功清空 liveMsgs 后，若 steerPending 引用的对象不在 liveMsgs 则置 null——防后续 user_echo 被 steer 分支误吞

## Data Model

### TextPacer（entry/src/main/ets/utils/TextPacer.ets，新文件）

- 构造：`constructor(intervalMs: number, onFlush: (chunk: string) => void)`
- 字段：`buffer: string`、`timerId: number`（-1 表示未运行）、`intervalMs: number`、`onFlush: (chunk: string) => void`
- `push(delta: string): void`——空串直接返回；buffer += delta；timerId===-1 时 setInterval 启动 tick
- `finish(): void`——clearInterval；buffer 非空则整体一次性 onFlush 并清空（收尾全量落盘）
- `cancel(): void`——clearInterval；buffer 清空丢弃（防串写）
- `tick`（私有）：落盘 `n = min(16, 2 + ceil(buffer.length/8))`，n = min(n, buffer.length)；buffer 减去前 n 字；onFlush(前 n 字)；buffer 排空后 clearInterval 停表
- 定时器：ArkTS 全局 `setInterval/clearInterval`（返回 number）；onFlush 回调抛出异常不捕获（调用方保证安全）

### ChatHomeTab 增量字段与方法

- `private textPacer: TextPacer`、`private reasoningPacer: TextPacer`——aboutToAppear 构造：
  - textPacer onFlush：activeAssistant 非空时 appendText(chunk)；streamPhase 置 '正在生成…'；scrollToBottom(false)
  - reasoningPacer onFlush：activeAssistant 非空时 appendReasoning(chunk)
- `private turnGen: number = 0`——回合代际计数
- beginTurn：创建新占位分支内 `this.turnGen++` 且 cancel 两 pacer；复用分支不动
- endTurnMarked：入口 finish 两 pacer（既有逻辑不变）
- endTurnReconciled：入口按设计决策时序①②③④；拉取失败回退对 turnAssistant markEnded；成功路径（代际未变）清空 liveMsgs + setServerMsgs + 既有刷新 + steerPending 清理
- send()：streaming→sendSteer 分支纳入 turnSending 守卫 + await 前同步清 inputText（失败恢复原文）
- onTextDelta/onReasoningDelta：改 `this.textPacer.push(delta)` / `this.reasoningPacer.push(delta)`（删除直连 append）
- aboutToDisappear/onThreadChanged（异值重置）/onAgentChanged：cancel 两 pacer
- teardownStream：不触碰 pacer

## Contracts & Interfaces

- `TextPacer.push(delta: string): void` / `finish(): void` / `cancel(): void`——三入口语义见 Data Model
- ChatHomeTab 对外 UI 契约不变：MessageBubble/MarkdownText/WelcomeCard/StreamingOrbit/ChatStreamController/模型层零改动
- 第八批双层架构（serverMsgs/liveMsgs/recompose）与三方法（beginTurn/endTurnMarked/endTurnReconciled）语义保持，仅按本计划增强
- 服务端契约不变（ws.py/history.py 零改动）
