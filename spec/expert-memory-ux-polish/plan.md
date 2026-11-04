# Implementation Plan: expert-memory-ux-polish

**Input**: Feature specification from `spec/expert-memory-ux-polish/spec.md`

## Summary

四项聊天页 UX 改进：**(1) 专家记忆**——`SessionStore.setCurrentAgent` 持久化 agentId 到 AppPrefs `last_agent_id`，`restore` 冷启动恢复 `KEY_AGENT_ID`，ChatHomeTab 首挂载 `AgentService.get` 回填名称/欢迎语（失败回退默认链），ExpertListPage 删除当前专家时清持久化；**(2) 气泡停止位对称**——contentEndOffset 改动态 `bottomPad + 10 + flowH + 22`（与输入卡↔TabBar 的 22vp 恒定间距对称）；**(3) 键盘时导航栏原地**——MainPage 监听 `window.on('keyboardHeightChange')`，悬浮 TabBar 的 barBottomMargin 增补键盘高度（仅 TabBar，严禁污染 bottomPad 链路）；**(4) 思考指示器升级**——思考行重构为品质玻璃胶囊（OctopThinkingIndicator + streamPhase 文本 + 柔和呼吸光晕）。服务端零改动。

## Technical Context

**Language/Version**: ArkTS（API 12+，DevEco 工具链）
**Primary Dependencies**: ArkUI（@Component V1、Tabs barFloatingStyle、List contentEndOffset、window keyboardHeightChange）、@kit.ArkData preferences（AppPrefs 既有封装）、@kit.ArkUI window
**State Management**: 状态管理 V1（项目既有，保持不变）
**Storage**: AppPrefs（preferences 'octop_link_prefs'）新增键 `last_agent_id`（logout clearAll 自动连带清除）
**Testing**: spec-verify 子代理构建 + 模拟器部署 + 逐条实测（杀 App 重启恢复/间距 dump 实测/键盘截屏/思考胶囊截屏）
**Target Platform**: HarmonyOS 模拟器 127.0.0.1:5555；真机仅按用户明确要求
**Project Type**: 既有 HarmonyOS 应用（OctopLink，com.octop.link）多点增强
**Performance Goals**: 无新增常驻开销；思考胶囊动画保持 LTPO 30Hz；键盘监听仅在 MainPage 注册一处
**Constraints**: InputFlowBorder 组件零改动；服务端零改动；kbHeight 不得进入 contentBottomPad/bottomPad 链路；ArkTS 严格模式
**Scale/Scope**: 5 文件定点改造、无新文件

## Project Structure

### Documentation (this feature)

```text
spec/expert-memory-ux-polish/
├── spec.md               # 本特性规格
├── plan.md               # 本文件
└── tasks.md              # 任务清单
```

### Source Code (repository root)

```text
entry/src/main/ets/
├── store/
│   ├── AppPrefs.ets              # T002: last_agent_id 键 + getter/setter
│   └── SessionStore.ets          # T003: setCurrentAgent 持久化 + restore 恢复
├── pages/
│   ├── MainPage.ets              # T007: kbHeight 监听 + TabBar barBottomMargin 增补
│   ├── chat/
│   │   └── ChatHomeTab.ets       # T005 回填 / T006 contentEndOffset / T008 思考胶囊
│   └── expert/
│       └── ExpertListPage.ets    # T004: deleteAgent 清持久化
└── components/
    └── OctopThinkingIndicator.ets  # 只读参考（InputFlowBorder 零改动）
```

**Structure Decision**: 遵循既有项目架构，零新文件，5 文件定点改造。

## Complexity Tracking

> 无 Constitution 违规。

## Research & Decisions

### 勘察结论（写入 spec 的依据）

1. **专家切换唯一写入口**：`SessionStore.setCurrentAgent()`（L101-107）写 4 个 AppStorage 键——三个 UI 调用点（ChatHomeTab.selectAgent L1617 / ExpertListPage 卡片 L345 / startChat L118）全部经过，在此持久化即全覆盖
2. **冷启动不恢复专家**：`SessionStore.restore()`（L32-53）只恢复 serverUrl/token/profile——`agentId === ''` → `pickDefaultAgent()`（L197-206）取 `agents[0]`，每次冷启动回到列表第一个
3. **持久化先例**：AppPrefs（preferences 'octop_link_prefs'，单例 + getString/putString + flush）；AppearanceStore 为"启动 restore → 写 AppStorage"最佳参照；logout 调 clearAll（新键自动连带清除，换账号不串专家）
4. **气泡停止位**：contentEndOffset 当前 `bottomPad + 115`（L2426）→ 气泡与输入卡间隙 ≈0vp；输入卡↔TabBar 间距恒 22vp（`(M+78)−(M+56)`）；scrollEdge 不受 offset 数值影响；RESIZE 键盘态间隙自动保持
5. **键盘**：Index.ets L45 `setKeyboardAvoidMode(KeyboardAvoidMode.RESIZE)` 全局压缩视口——输入卡随视口上来（即用户所要），悬浮 TabBar（MainPage barFloatingStyle barBottomMargin）也随压缩上浮到键盘正上方（用户不要的）
6. **思考指示器现状**：ChatHomeTab L2518-2528 思考行 = `OctopThinkingIndicator({ indSize: 44 })` + 12fp 灰字裸 Row；组件本体 = logo + 玫瑰/品牌蓝双弧线反向环绕（30Hz LTPO）

### 设计决策

- **专家记忆选持久化而非加按钮**（用户二选一自主决策）：零 UI 侵入、隐式覆盖"经常打开的专家"（常用谁，下次打开就是谁）；加按钮会挤占刚修好的输入卡布局
- **恢复链拆两段**：restore 只恢复 agentId（快、无网络依赖，不阻塞 EntryAbility 启动）；名称/欢迎语由 ChatHomeTab 首挂载 `AgentService.get` 回填（此时 HttpClient 已就绪）；失败回退 pickDefaultAgent（现状默认链保留为兜底）
- **对称间距动态公式** `bottomPad + 10 + flowH + 22`（静态 137 在输入卡多行撑高时失配）；flowH 初值 0→105 防首帧塌陷（onAreaChange 首帧即校正）
- **键盘方案**：保留 RESIZE（输入卡行为不变），MainPage 监听键盘高度把 barBottomMargin 增补 kbVp——TabBar 推回原屏幕位置（压缩视口外被裁剪，等效"原地被键盘覆盖"）；**kbHeight 严禁进入 contentBottomPad/bottomPad**（否则输入卡被二次推高、气泡停止位失真）；备选（裁剪伪影时）：键盘期隐藏 TabBar
- **思考胶囊**：保留 OctopThinkingIndicator（logo+双色弧线）作核心动效，外包玻璃胶囊 + 柔和玫瑰/品牌蓝低透明度呼吸光晕 + 13fp Medium 文本；若 octop_logo 呈方块感给 Image 加圆形裁剪

## Data Model

无新增模型。AppPrefs 新增字符串键 `last_agent_id`（'' 表无记录）；MainPage 新增 `@State kbHeight: number = 0`（vp）；ChatHomeTab `flowH` 初值 0→105。

## Contracts & Interfaces

- **AppPrefs**：`getLastAgentId(): string` / `setLastAgentId(id: string): void`（'' 表清除；put 后 flush；clearAll 自动连带）
- **SessionStore.setCurrentAgent**：签名不变，追加持久化副作用
- **SessionStore.restore**：签名不变，追加 KEY_AGENT_ID 恢复（不回填名称）
- **MainPage**：`barBottomMargin = floatingBarBottomMargin() + kbHeight`（仅 floatingBarStyle 内）；`contentBottomPad()` 保持不含 kbHeight
- **ChatHomeTab**：contentEndOffset 动态公式；思考行新结构（显示条件 `streaming && streamPhase !== ''` 与位置不变）；新增 backfillCurrentAgent 私有方法
- **对外契约不变**：InputFlowBorder/OctopThinkingIndicator 组件接口不变（indSize 传参可调）；服务端契约零改动
