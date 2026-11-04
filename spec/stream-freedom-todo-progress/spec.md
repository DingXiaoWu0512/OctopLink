# Feature Specification: stream-freedom-todo-progress（流式滚动自由 + 任务进度面板 + 思考态精修 + 键盘残留修复）

**Created**: 2026-10-31
**Status**: Approved（用户长期指令：直接执行，不询问）
**Input**: 用户指令四项：①"这个正在思考太夸张了，而且占满了整个屏幕，如果想看其他的都没办法看，还得等生成完才能看到"②"任务进度我在手机上是看不到的，电脑上就可以，如何增加能看到任务进度的方法"③第十一批 US3 遗留：键盘弹出时 TabBar 已不上浮但残留 28px 空玻璃胶囊④（OctopPet GitHub 调研为独立研究项，结论在批次汇报中说明，不在本批实现范围）

## Overview

四项聊天页改进：**(1) 流式滚动自由**——勘察证实"占满整个屏幕"非全屏组件，根因是每个流式 delta 落盘后强制 `scrollEdge(Bottom)`（用户上滑 150ms 内必被拉回）+ 视口底端锚定；修复：`stickBottom` 状态 + List `onScroll`/`onReachEnd` 手势感知 + `scrollToBottom` 门禁 + "回到最新"悬浮入口，流式期间用户可自由上滑阅读历史。**(2) 任务进度面板**——桌面 Web 的"任务进度"= `write_todos` 工具清单面板（i18n `chatUsage.todoListTitle`）；数据已完整到达手机（WS `tool_call_chunk` args 累积 + history `tool_use` 解析均就位），差距纯在展示层；移植桌面 `parseWriteTodos.ts` 解析器 + 新建 `TodoProgressPanel` 组件，零服务端改动。**(3) 思考态精修**——流式期 reasoning 折叠行不显示跳动的实时预览（改"深度思考中…"），展开态限高防满屏。**(4) 键盘残留修复**——第十一批 barHeight=0 后 pill 容器 28px 残留，按候选方案彻底隐藏。

## User Scenarios & Testing *(mandatory)*

### User Story 1 - 流式滚动自由 (Priority: P1)

流式生成期间用户上滑阅读历史消息时，视口不再被强制拉回底部；出现"回到最新"悬浮入口可一键回底；回底后恢复自动跟随；用户主动行为（发送消息/切换会话/steer）仍强制贴底。

**Why this priority**: 用户点名核心痛点（"想看其他的都没办法看，还得等生成完才能看到"）；流式全程视口被钉死，功能性阻断阅读。

**Independent Test**: 流式生成中上滑停留：视口保持 ≥3 秒不被拉回。

**Acceptance Scenarios**:

1. **Given** 流式生成中，**When** 用户上滑离开底部，**Then** 视口停留在历史位置（不被 scrollEdge 拉回），且"回到最新"悬浮入口出现
2. **Given** 已上滑停留，**When** 流式内容继续生成，**Then** 视口位置保持、生成不中断不丢内容
3. **Given** 已上滑停留，**When** 点击"回到最新"，**Then** 平滑回到底部并恢复自动跟随
4. **Given** 用户上滑后自然滑回底端（onReachEnd），**Then** 自动恢复贴底跟随（无需点按钮）
5. **Given** 发送新消息/切换会话/steer 追问，**Then** 强制贴底行为不变（现状）
6. **Given** 未上滑（贴底状态），**Then** 自动跟随行为与现状完全一致

---

### User Story 2 - 任务进度面板（write_todos 清单化） (Priority: P1)

agent 执行多步任务时通过内置编排工具 `write_todos` 写出的计划清单（`{id, content, status}`），在手机上以"任务进度"面板呈现（与桌面 Web 同构）：标题"任务进度" + "已完成 x/y" + 逐项状态（待处理/进行中/已完成/已取消）；流式中实时更新（args 分片部分解析），历史会话回看同样生效；`write_todos` 不再显示为通用工具 JSON 折叠卡。

**Why this priority**: 用户点名需求（"任务进度手机上看不到"）；数据已在端上，纯展示层补齐。

**Independent Test**: 诱导 agent 产出多步计划（如"帮我制定一个三步计划并逐步执行"）：流式中面板出现并实时更新状态。

**Acceptance Scenarios**:

1. **Given** 流式中 agent 调用 write_todos，**When** args 分片到达，**Then** 面板出现并随分片部分解析实时渲染（先显示已完整的项目）
2. **Given** agent 多次调用 write_todos 更新状态，**When** 后写覆盖先写，**Then** 面板按 id 合并显示最新状态（"已完成 x/y"变化）
3. **Given** 回合结束，**When** 重新打开该会话（history 解析 tool_use），**Then** 面板仍完整显示最终清单
4. **Given** 非 write_todos 的其他工具调用，**When** 渲染，**Then** 通用工具折叠卡行为不变
5. **Given** 工具名带命名空间前缀（如 `deepagents/write_todos`），**Then** 仍命中面板（'/' 后缀匹配）

---

### User Story 3 - 思考态精修 (Priority: P2)

流式期间 reasoning 折叠行不再显示持续跳动的实时预览文字（改静态"深度思考中…"文案），消除"太夸张/文字乱跳"观感；回合结束后恢复现状单行预览；reasoning 展开态限高（≤240vp）可滚动，防超长推理占满全屏。

**Why this priority**: 用户点名观感（"太夸张""占满整个屏幕"）；滚动自由（US1）解决"被钉死"，本项解决"展示本身喧宾夺主"。

**Independent Test**: 深度推理模型流式中：折叠行显示"深度思考中…"无跳动文字；展开后内容区 ≤240vp 可滚。

**Acceptance Scenarios**:

1. **Given** 流式中 msg.streaming 且 reasoning 非空，**When** 折叠行渲染，**Then** 显示"深度思考中…"静态文案（不显示跳动的实时预览）
2. **Given** 回合结束（streaming=false），**When** 折叠行渲染，**Then** 恢复现状单行省略预览 + 可点击展开
3. **Given** reasoning 超长，**When** 点击展开，**Then** 展开区限高 ≤240vp 内部可滚动，不占满全屏
4. **Given** MessageBubble 用户消息 fresh 入场动画，**Then** 零回归（不破坏）

---

### User Story 4 - 键盘态彻底净化：横杠清除 + 间距收缩 (Priority: P1)

第十一批 barHeight=0 隐藏四 Tab 后残留 28px 空玻璃胶囊；本批 T011 加 barWidth(0) 后实测复勘：**TabBar 仍按最小尺寸 104×28px 渲染胶囊横杠**（dumpLayout `type:"TabBar", bounds:[598,1579][682,1607]`，居中悬于输入卡与键盘之间，暗底亮描边 RGB(77,78,80)）+ **悬浮样式蒙层暗带**（`BackgroundMask [0,1523][1280,1733]`，maskColor 渐变）+ **输入卡与键盘间距 401px（114.6vp，= bottomPad+10 键盘期未收缩）**。修复：①键盘期 `barFloatingStyle(undefined)` 取消悬浮样式（官方文档：undefined 恢复默认样式，pill 与蒙层随之消失）配合既有 barHeight(0)/barWidth(0)；②kbHeight 传导至 ChatHomeTab，输入卡底边距键盘期收缩至 ~10vp（约 35px，缩减 91%，满足用户"起码缩小三分之二"）；contentEndOffset 联动。键盘收起后完整恢复。

**Why this priority**: 用户实时反馈点名两项："输入框和输入法之间有一个横杠，不知道是什么东西"+"输入框和输入法之间距离太大，起码缩小三分之二"。

**Independent Test**: 弹键盘截屏亮度分析：输入卡与键盘之间无胶囊横杠、无蒙层残留；间距 ≤134px（2/3 达标线，目标 ~35px）。

**Acceptance Scenarios**:

1. **Given** 键盘弹出（kbHeight>0），**When** 截屏亮度分析输入卡与键盘之间区域，**Then** 无 104×28px 胶囊横杠（dumpLayout TabBar 节点无可渲染可见像素或亮度与背景无差异）、无蒙层暗带
2. **Given** 键盘收起，**When** 观察，**Then** TabBar 完整恢复（四 Tab 可点、玻璃胶囊、悬浮蒙层现状视觉零变化）
3. **Given** 键盘弹出，**When** 测量输入卡底边到键盘顶边，**Then** 间距 ≤134px（目标 ~35-42px，即 ≥2/3 缩减达成）
4. **Given** 键盘弹出，**When** 查看消息列表停止位，**Then** 气泡停止位随 contentEndOffset 联动收缩（仍在输入卡上方 22vp 对称）
5. **Given** 键盘弹出，**When** 使用输入卡，**Then** 输入卡/操作行键盘态行为零回归

### Edge Cases

- onScroll 的 offset 方向符号需实测校准（验收轮允许翻转符号）；程序化 scrollEdge 触发的 onScroll 以 Idle 态过滤，避免自反馈
- stickBottom 与 force 复位：force 调用点（send/sendSteer/onUserEcho/onHitlRequired/loadHistory）执行时显式置 stickBottom=true
- write_todos 部分解析：截断 JSON 逐字符扫描完整 `{...}` 对象，解析失败静默跳过（不崩、不显示半截）
- 以 argsText 为主数据源（tool_result 的 resultText 有 500 字符截断且多工具并发可能错位）
- reasoning 计时（可选）：ChatMessageModel 新增 reasoningStartAt（onReasoningDelta 首帧记录），显示"深度思考中… Ns"
- TodoProgressPanel 仅 assistant 消息渲染；用户消息/系统消息不渲染
- 键盘隐藏候选方案若 barWidth 不生效，依次尝试备选（详见 FR-010）
- 第八~十一批已验收行为零回归（打字机平滑/双击单发/流光触摸/专家恢复/间距对称/思考胶囊）

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: ChatHomeTab 新增 `stickBottom` 状态（默认 true，位于滚动状态区）
- **FR-002**: List 挂 `onScroll`（仅 ScrollState.Dragging/Fling 手势态处理，上滑离开底部置 stickBottom=false，方向符号以实测校准）与 `onReachEnd`（置 true）；程序化滚动（Idle 态）不改变 stickBottom
- **FR-003**: scrollToBottom 门禁：`!force && !this.stickBottom` 直接 return（置于 150ms 节流之前）；全部 force=true 调用点（send/sendSteer/onUserEcho/onHitlRequired/loadHistory）执行时显式置 stickBottom=true
- **FR-004**: "回到最新"悬浮入口：stickBottom===false && streaming 时显示于输入卡上方（小巧胶囊样式，如"↓ 最新"），点击 scrollToBottom(true) 并复位 stickBottom=true；贴底时隐藏
- **FR-005**: 新增 `utils/ParseWriteTodos.ets`：移植桌面 parseWriteTodos.ts——`TodoListItem`（id/content/status: pending|in_progress|completed|cancelled）、`isWriteTodosToolName`（'/' 后缀等于 write_todos）、payload 解析（todos/items/tasks 键兼容、字符串项兼容）、状态归一化（done/complete→completed、running/active→in_progress）、截断 args 部分解析（逐字符扫描完整对象）、按 id 合并（后写覆盖）与数字序排序；输入 `ToolCallModel.argsText`
- **FR-006**: 新增 `components/TodoProgressPanel.ets`：标题"任务进度" + "已完成 x/y" 摘要 + 逐项状态图标与文案（待处理/进行中/已完成/已取消），完成/取消项删除线；`items: TodoListItem[]` + `streaming: boolean` 入参
- **FR-007**: MessageBubble 集成：assistant 消息 toolCalls 命中 write_todos 时渲染 TodoProgressPanel（同消息多次调用合并），面板置于 reasoning/text 块之前；write_todos 调用不再渲染通用工具折叠卡；其余工具渲染不变；用户消息 fresh 入场动画（L385 区域）零破坏
- **FR-008**: MessageBubble reasoningBlock 流式期（msg.streaming）折叠分支：不显示实时 reasoning 预览，显示"深度思考中…"（可选计时 Ns：ChatMessageModel 新增 reasoningStartAt 字段，ChatHomeTab onReasoningDelta 首帧记录）；streaming=false 后恢复现状单行预览
- **FR-009**: reasoning 展开态限高：constraintSize({ maxHeight: 240 }) 外套 Scroll，内部可滚动
- **FR-010**: MainPage 键盘残留修复：kbHeight>0 时彻底隐藏悬浮 TabBar 全部可见元素——实测锚定 `barFloatingStyle(undefined)`（官方文档：style 传 undefined 取消悬浮样式恢复默认，pill 容器与 maskColor 蒙层随之消失）配合既有 barHeight(0)/barWidth(0)；若实现期发现 undefined 不生效，候选序：①FloatingTabBarStyle 键盘期全字段归零（barWidth 三档 0/barSideMargin 0/barBottomMargin 0/maskColor Color.Transparent）②barModifier 对 TabBar 施加 visibility(None) ③其他等效；验收以截屏亮度分析无横杠无暗带为准；键盘收起完整恢复（悬浮样式/四 Tab 复原）
- **FR-013**: 键盘期输入卡间距收缩：MainPage 将 kbHeight 传导至 ChatHomeTab（@Prop）；ChatHomeTab 抽取 inputBottomInset()：kbHeight>0 时返回 ~10（vp，目标间距 ~35px，≥2/3 缩减），否则 bottomPad+10（现状）；输入卡 margin.bottom 与 contentEndOffset 公式同步改用 inputBottomInset()（contentEndOffset = inputBottomInset() + flowH + 22），气泡停止位联动收缩
- **FR-011**: 第八~十一批已验收行为 MUST 零回归（打字机平滑、双击单发、流光期间触摸、专家恢复、22vp 间距对称、思考胶囊、TextPacer/turnGen/竞态守卫）
- **FR-012**: 服务端 MUST 零改动
- **FR-014**: 键盘收起态（kbHeight===0）视觉 MUST 零变化：悬浮 TabBar 玻璃胶囊、蒙层、四 Tab、输入卡底边距全部保持现状

### Key Entities

- **stickBottom**：ChatHomeTab 状态——用户是否愿意贴底（false 时暂停自动滚底）
- **TodoListItem**：`{ id: string, content: string, status: 'pending'|'in_progress'|'completed'|'cancelled' }`（write_todos 清单项）
- **ParseWriteTodos**：解析器（isWriteTodosToolName/collectTodoItems/部分解析/合并排序），桌面 parseWriteTodos.ts 的 ArkTS 移植
- **TodoProgressPanel**：任务进度面板组件（标题+摘要+逐项状态）
- **reasoningStartAt**：ChatMessageModel 新增字段（可选计时，推理开始时间戳）

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: 流式中上滑：视口停留 ≥3 秒不被拉回（连续截屏/dumpLayout 位置对比取证）；"回到最新"入口出现；点击回底
- **SC-002**: 上滑期间生成不中断不丢内容；滑回底端自动恢复跟随；发送/切会话强制贴底不变
- **SC-003**: write_todos 任务流式中"任务进度"面板实时更新（已完成 x/y 变化、状态图标变化截屏）；历史回看面板保留
- **SC-004**: 非 write_todos 工具折叠卡渲染不变
- **SC-005**: 键盘弹出截屏亮度分析：输入卡与键盘之间无 104×28px 胶囊横杠、无蒙层暗带；输入卡底边到键盘顶边 ≤134px（目标 ~35-42px）；收起完整恢复（视觉零变化）
- **SC-006**: 流式折叠行"深度思考中…"无跳动预览；展开区 ≤240vp 可滚动；结束后恢复单行预览
- **SC-007**: hilog FATAL=0；回归抽查（平滑输出/双击单发/流光触摸/专家恢复/间距对称）全过

## Assumptions

- onScroll offset 方向符号以实测校准（验收轮允许翻转）；ScrollState Idle 过滤程序化滚动
- 现有 WS tool_call_chunk 累积（upsertToolCall）与 history tool_use 解析（fromHistoryRecord）无需改动，面板数据直接取 toolCalls
- TodoProgressPanel 文案中文硬编码（与 App 现有硬编码中文一致，如"上传中..."）
- 部分解析的字符扫描在 ArkTS 可实现（逐对象 try/catch JSON.parse，失败静默跳过）
- 桌面 parseWriteTodos.ts 语义为唯一权威参照（同 id 后写覆盖、数字序排序、output>args 优先但移动端以 argsText 为主规避 resultText 500 截断与错位）
- 测试环境：模拟器 127.0.0.1:5555，服务器 s3.z100.vip:35796，与前批一致

## Open Questions

- （无——用户长期指令要求不询问直接执行）
