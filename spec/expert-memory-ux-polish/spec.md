# Feature Specification: expert-memory-ux-polish（专家记忆 + 聊天页 UX 打磨四项）

**Created**: 2026-10-31
**Status**: Approved（用户长期指令：直接执行，不询问）
**Input**: 用户四项指令：①"要不加一个按钮可以选择聊天界面经常打开的专家是哪个，要不就设定保留上次关闭时候使用的专家"（二选一，自主决策选持久化方案）②"把聊天气泡停止的位置再放高点，距离和导航栏到输入消息栏之间的距离一样"③"聊天页面弹出输入法的时候只让输入消息框上来 导航栏还保持在原地"④"优化正在思考的过程，现在在左下角一个小方块 周围颜色环绕，有点太小气了"

## Overview

四项聊天页 UX 改进：**(1) 专家记忆**——切换专家时持久化 agentId（AppPrefs `last_agent_id`），冷启动自动恢复上次使用的专家（用户二选一需求，自主决策选"保留上次专家"而非加按钮：零 UI 侵入、隐式覆盖"经常打开的专家"）；**(2) 气泡停止位对称**——最后一条气泡与输入卡顶边的间距 = 输入卡底边与底部悬浮 TabBar 顶边的间距（实测恒 22vp），`contentEndOffset` 改动态公式；**(3) 键盘时导航栏原地**——保留 RESIZE 避让（输入卡随视口上来，即用户所要），仅让底部悬浮 TabBar 不随视口压缩上浮，保持原屏幕位置（被键盘覆盖）；**(4) 思考指示器升级**——流式思考态从"左下小方块+环绕"升级为更有品质感的玻璃胶囊（品牌双色弧线环绕 logo + 状态文本 + 柔和呼吸光晕）。服务端零改动。

## User Scenarios & Testing *(mandatory)*

### User Story 1 - 专家记忆：冷启动恢复上次使用的专家 (Priority: P1)

切换专家的唯一入口 `SessionStore.setCurrentAgent` 末尾持久化 agentId；冷启动 `SessionStore.restore` 读取并恢复 `KEY_AGENT_ID`；名称/欢迎语由 ChatHomeTab 首次挂载时 `AgentService.get` 回填（避免 EntryAbility 阻塞网络）；恢复的 id 无效（已删除）时回退现有默认链（列表第一个）。

**Why this priority**: 用户点名需求；当前每次冷启动都回到列表第一个专家，常用专家需手动重选。

**Independent Test**: 切换到某专家 → 杀 App → 重启 → 聊天页自动选中该专家。

**Acceptance Scenarios**:

1. **Given** 已切换到专家 X，**When** 杀 App 后重启进入聊天页，**Then** 自动选中专家 X（标题胶囊显示其名字，最近会话正常加载）
2. **Given** 删除当前正在使用的专家，**When** 重启，**Then** 回退列表第一个专家，无空名/报错/空白
3. **Given** 恢复的专家 id 在服务端已失效，**When** ChatHomeTab 回填失败，**Then** 回退 pickDefaultAgent（默认链保持）
4. **Given** 首次安装/无记录（logout 已 clearAll），**When** 启动，**Then** 行为与现状一致（默认第一个）
5. **Given** 恢复成功，**When** 发起对话，**Then** WS 连接/订阅/发送正常（agentId 参与连接链路）

---

### User Story 2 - 气泡停止位与导航间距对称 (Priority: P2)

最后一条气泡底边与输入卡顶边的间距等于输入卡底边与 TabBar 顶边的间距（推导恒 22vp：`(M+78)−(M+56)`）。`contentEndOffset` 由静态 `bottomPad + 115` 改动态 `bottomPad + 10 + flowH + 22`（flowH 为输入卡实测高，多行撑高时仍对称）。

**Why this priority**: 用户点名视觉需求；当前气泡贴合输入卡顶边（间距≈0），与下方 22vp 间距不对称。

**Independent Test**: 滚到底：dumpLayout 实测两段间距相等（22vp ±2）。

**Acceptance Scenarios**:

1. **Given** 消息较多滚到底部，**When** dumpLayout 实测，**Then** 气泡↔输入卡间距 ≈ 输入卡↔TabBar 间距（22vp，误差 ≤2vp）
2. **Given** 输入多行文字撑高输入卡（TextArea 最高 128），**When** 再滚到底，**Then** 间距仍保持对称（flowH 动态跟随）
3. **Given** 键盘弹出（RESIZE 压缩视口），**When** 观察，**Then** 气泡仍锚定输入卡上方、间隙保持（现状行为零回归）
4. **Given** scrollToBottom/加载历史，**When** 触发，**Then** 滚动到底逻辑正常（scrollEdge 不受影响）

---

### User Story 3 - 键盘弹出时导航栏保持在原地 (Priority: P1)

保留 RESIZE 键盘避让（输入卡随压缩视口上来，键盘上方可用——现状即用户所要）；MainPage 监听键盘高度，把悬浮 TabBar 的 `barBottomMargin` 增补键盘高度——TabBar 被推回原屏幕位置（键盘后方，不再随视口压缩上浮到键盘上方）。键盘收起后恢复。

**Why this priority**: 用户点名需求；当前键盘弹出时悬浮 TabBar 随压缩视口上浮到键盘正上方，观感跳脱。

**Independent Test**: 聊天页点输入框弹键盘：TabBar 不出现在键盘上方；收起后 TabBar 原位恢复。

**Acceptance Scenarios**:

1. **Given** 聊天页，**When** 点 TextArea 弹出键盘，**Then** 输入卡在键盘上方正常可用，TabBar 不随键盘上浮（不在键盘上方出现，保持原屏幕位置被键盘覆盖）
2. **Given** 键盘弹出，**When** 收起键盘，**Then** TabBar 回到原位、正常可点、无残影
3. **Given** 其他 Tab（专家页搜索等），**When** 弹键盘，**Then** TabBar 行为一致（全局统一）
4. **Given** 键盘弹出，**When** 观察气泡与输入卡，**Then** 两者位置关系零回归（气泡仍锚定输入卡上方）
5. **Given** 键盘高度变化（收起=0），**When** kbHeight 更新，**Then** contentBottomPad()/bottomPad 链路不受污染（输入卡不被二次推高）

---

### User Story 4 - 思考指示器升级（更大气） (Priority: P2)

流式思考态指示（ChatHomeTab 思考行，streaming && streamPhase !== '' 时显示）从"44vp 小方块+弧线环绕+12fp 灰字"升级为品质玻璃胶囊：OctopThinkingIndicator（品牌双色弧线环绕 logo，可调 40-48）+ streamPhase 文本（13fp Medium）+ 玻璃胶囊容器（全圆角、轻背景、舒适留白）+ 柔和玫瑰/品牌蓝低透明度呼吸光晕。位置（底部左侧、输入卡上方）与显示条件不变。

**Why this priority**: 用户点名观感需求（"有点太小气了"）；现状单薄小气。

**Independent Test**: 流式中截屏对比：思考态观感明显提升（截屏取证）。

**Acceptance Scenarios**:

1. **Given** 流式生成中，**When** 截屏，**Then** 底部左侧显示升级后思考胶囊（双色弧线环绕 logo + 状态文本 + 玻璃胶囊 + 柔和光晕），观感大气精致（对比旧小方块截屏取证）
2. **Given** streamPhase 变化（"正在思考…"→"正在生成…"），**When** 观察，**Then** 文本正常更新
3. **Given** 回合结束/空闲，**When** 观察，**Then** 胶囊消失无残留、无动画泄漏
4. **Given** octop_logo 渲染呈方块感，**When** 排查，**Then** 给 Image 加圆形裁剪或等效处理，消除方块感

### Edge Cases

- 恢复的专家 id 已在服务端删除：AgentService.get 失败 → 清 KEY_AGENT_ID + pickDefaultAgent 回退
- logout：AppPrefs.clearAll 连带清 last_agent_id（换账号不串专家）
- flowH 初值 105（首帧预估）与实测差异：onAreaChange 首帧即校正（旧值 0 会首帧塌陷）
- kbHeight 严禁进入 contentBottomPad/bottomPad 链路（否则输入卡被双重推高、气泡停止位失真）
- 键盘高度为 px 需 px2vp 转换；监听在 MainPage aboutToAppear 注册、aboutToDisappear 注销
- 思考胶囊仅 streaming && streamPhase !== '' 显示（条件不变）；LTPO 30Hz 动画模式保持
- 专家记忆与八/九/十批行为正交：恢复的 agentId 走既有 onAgentChanged/onThreadChanged 链路

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: AppPrefs 新增字符串键 `last_agent_id` + `getLastAgentId(): string` / `setLastAgentId(id: string): void`（仿现有 getString/putString 封装，put 后 flush；'' 表无记录/清除）
- **FR-002**: SessionStore.setCurrentAgent 末尾追加持久化 `AppPrefs.getInstance().setLastAgentId(agent.agentId)`（签名不变；三个调用点自动全覆盖）
- **FR-003**: SessionStore.restore 在登录恢复后读取 last_agent_id，非空则 `AppStorage.setOrCreate(KEY_AGENT_ID, lastId)`（不在此回填名称/欢迎语——由 FR-004 回填）
- **FR-004**: ChatHomeTab.aboutToAppear：`agentId !== '' && agentName === ''` 时回填——AgentService.get(agentId) 成功 → SessionStore.setCurrentAgent(agent)（回填名称/欢迎语/模型四键）；失败 → AppStorage 清 KEY_AGENT_ID + pickDefaultAgent()；`agentId === ''` 保持现有 pickDefaultAgent 路径
- **FR-005**: ExpertListPage.deleteAgent 删除当前专家时同步清持久化（`setLastAgentId('')`）
- **FR-006**: ChatHomeTab contentEndOffset 由 `this.bottomPad + 115` 改 `this.bottomPad + 10 + this.flowH + 22`；flowH 声明初值 0→105；flowW 不动
- **FR-007**: MainPage 新增 `@State kbHeight: number = 0`；window.on('keyboardHeightChange') 监听（px2vp 转换，aboutToDisappear 注销）；floatingBarStyle 的 barBottomMargin = floatingBarBottomMargin() + kbHeight（仅 TabBar）；contentBottomPad()/bottomPad 链路 MUST 不含 kbHeight
- **FR-008**: 思考行重构为品质玻璃胶囊（保留 OctopThinkingIndicator spinner 与 streamPhase 文本；显示条件/位置不变；LTPO 30Hz 保持）
- **FR-009**: InputFlowBorder 组件（components/OctopThinkingIndicator.ets 内）MUST 零改动
- **FR-010**: 第八/九/十批已验收行为 MUST 零回归（流光触摸、打字机平滑、双击单发、续流、HITL）
- **FR-011**: 服务端 MUST 零改动

### Key Entities

- **last_agent_id**：AppPrefs 持久化键（字符串，'' 表无记录）——上次使用的专家 agentId
- **kbHeight**：MainPage @State（vp）——当前软键盘高度，仅作用于悬浮 TabBar 的 barBottomMargin
- **flowH**：复用既有输入卡实测高度 @State（初值 0→105），新增参与气泡停止位动态公式
- **思考胶囊**：思考行新容器（玻璃胶囊 + 光晕 + spinner + 文本），取代旧"裸 Row + 小方块"

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: 切换到专家 X → 杀 App → 重启：聊天页自动选中 X（标题胶囊名字截屏取证）
- **SC-002**: 删除当前专家 → 重启：回退列表第一个、无空名报错（截屏取证）
- **SC-003**: 滚到底 dumpLayout 实测：气泡↔输入卡间距 ≈ 输入卡↔TabBar 间距（22vp ±2）
- **SC-004**: 弹键盘：TabBar 不上浮（截屏/dump 取证，不在键盘上方出现）；收起后原位恢复可点
- **SC-005**: 流式截屏：思考胶囊升级后观感取证（大气精致，对比旧态）；streamPhase 文本正常更新；结束消失
- **SC-006**: hilog FATAL=0；八/九/十批行为回归抽查（平滑输出/双击单发/流光期间输入卡触摸）全过

## Assumptions

- 用户二选一需求（加按钮 vs 持久化）自主决策选持久化方案（零 UI 侵入）
- 22vp 对称目标来自勘察推导（`M+78 − (M+56)`）；验证实测若有出入以实测为准微调公式常数
- AppPrefs 同步读写风格沿用现有封装；restore 时 AppPrefs 单例已初始化（restore 链内部顺序以实测为准）
- 键盘 RESIZE 模式保持不变（只调 TabBar 行为）；TabBar 被推至压缩视口外即被裁剪（等效"原地被键盘覆盖"）；若验证发现裁剪伪影，备选方案为键盘期隐藏 TabBar
- 测试环境：模拟器 127.0.0.1:5555，服务器 s3.z100.vip:35796，与前批一致

## Open Questions

- （无——用户长期指令要求不询问直接执行）
