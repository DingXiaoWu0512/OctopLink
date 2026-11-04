---
description: "Task list for expert-memory-ux-polish"
---

# Tasks: expert-memory-ux-polish（专家记忆 + 聊天页 UX 打磨四项）

**Input**: Design documents from `spec/expert-memory-ux-polish/`
**Prerequisites**: plan.md (required), spec.md (required for user stories)

**Organization**: 按 User Story 分组。US1 专家记忆跨 4 文件顺序改；US2/US3/US4 相互独立（不同文件/区域）。

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: US1 专家记忆 / US2 气泡停止位 / US3 键盘导航栏 / US4 思考胶囊
- Include exact file paths in descriptions

## Path Conventions

- 项目根：`C:\Users\13775\OctopLink`
- 改动文件：`entry\src\main\ets\store\AppPrefs.ets`、`entry\src\main\ets\store\SessionStore.ets`、`entry\src\main\ets\pages\expert\ExpertListPage.ets`、`entry\src\main\ets\pages\chat\ChatHomeTab.ets`、`entry\src\main\ets\pages\MainPage.ets`
- 只读参考（零改动）：`entry\src\main\ets\components\OctopThinkingIndicator.ets`（InputFlowBorder 禁改；OctopThinkingIndicator 仅在调用方调 indSize 传参，组件本体不改）
- 服务端：零改动
- 构建产物：`entry\build\default\outputs\default\entry-default-signed.hap`

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: 现状锚点确认

- [X] T001 勘察锚点：核对 AppPrefs.ets（键常量 L4-16、单例 L36-41、clearAll L168-179、getString/putString L181-208）、SessionStore.ets（restore L32-53、applyLogin L65-68、logout L97、setCurrentAgent L100-107、handleUnauthorized L78-90）、ExpertListPage.ets（load L71-73、startChat L118-124、deleteAgent L189-194、卡片点击 L345-350）、ChatHomeTab.ets（aboutToAppear L164-176、pickDefaultAgent L197-206、flowH L105、contentEndOffset L2426、思考行 L2518-2528）、MainPage.ets（aboutToAppear L26-43、floatingBarBottomMargin L59-61、contentBottomPad L64-66、floatingBarStyle L71-84）、AgentService.ets（get L36-39）。行号漂移以实际内容为准；结构与上述语义不符则停止上报

---

## Phase 2: User Story 1 - 专家记忆 (Priority: P1) 🎯 MVP

**Goal**: 切换专家持久化，冷启动自动恢复上次专家，无效/已删 id 回退默认

**Independent Test**: 切专家 → 杀 App → 重启：自动恢复该专家

### Implementation for User Story 1

- [X] T002 [US1][P] AppPrefs.ets：新增键 `last_agent_id`（L4-16 键常量区域）+ `getLastAgentId(): string` / `setLastAgentId(id: string): void`（仿现有 getString/putString 封装，put 后 flush；'' 表无记录/清除）
- [X] T003 [US1] SessionStore.ets：①setCurrentAgent（L101-107）末尾追加 `AppPrefs.getInstance().setLastAgentId(agent.agentId)`；②restore（L32-53）在登录/token 恢复后读 last_agent_id，非空则 `AppStorage.setOrCreate(KEY_AGENT_ID, lastId)`（不回填名称/欢迎语）
- [X] T004 [US1] ExpertListPage.ets deleteAgent（L189-194）：删除的是当前专家时同步 `AppPrefs.getInstance().setLastAgentId('')` 清持久化（防下次启动恢复已删 id）
- [X] T005 [US1] ChatHomeTab.ets aboutToAppear（L164-176）：`agentId !== '' && agentName === ''` 时新增 backfillCurrentAgent()——`AgentService.get(this.agentId)` 成功 → `SessionStore.setCurrentAgent(agent)` 回填四键；失败 → `AppStorage.setOrCreate(SessionStore.KEY_AGENT_ID, '')` + `this.pickDefaultAgent()`；`agentId === ''` 保持现有 pickDefaultAgent 路径不变

**Checkpoint**: US1 独立可测——杀 App 重启恢复；删除/无效 id 回退默认

---

## Phase 3: User Story 2 - 气泡停止位对称 (Priority: P2)

**Goal**: 最后气泡↔输入卡间距 = 输入卡↔TabBar 间距（22vp，动态）

**Independent Test**: 滚到底 dumpLayout 实测两段间距相等

- [X] T006 [US2] ChatHomeTab.ets：contentEndOffset（L2426）由 `this.bottomPad + 115` 改动态 `this.bottomPad + 10 + this.flowH + 22`；flowH 声明初值 0→105（L105，首帧预估防塌陷）；flowW 初值不动；注释同步更新

---

## Phase 4: User Story 3 - 键盘时导航栏原地 (Priority: P1)

**Goal**: 键盘弹出时输入卡上来（RESIZE 保持），悬浮 TabBar 不随视口上浮、保持原屏幕位置

**Independent Test**: 点输入框弹键盘：TabBar 不在键盘上方出现；收起后原位恢复

- [X] T007 [US3][P] MainPage.ets：①新增 `@State kbHeight: number = 0` 与 win 字段；②aboutToAppear 的 getLastWindow().then 内注册 `win.on('keyboardHeightChange', (data: window.KeyboardHeightChangeData) => { this.kbHeight = this.getUIContext().px2vp(data.height); })`；aboutToDisappear 内 `win.off('keyboardHeightChange')` 注销；③floatingBarStyle 的 barBottomMargin 改 `this.floatingBarBottomMargin() + this.kbHeight`（仅 TabBar 样式）；④contentBottomPad()/floatingBarBottomMargin() 公共链路严禁包含 kbHeight；⑤若验证发现推下产生裁剪伪影，备选方案：kbHeight>0 时隐藏 TabBar

---

## Phase 5: User Story 4 - 思考指示器升级 (Priority: P2)

**Goal**: 思考态从"左下小方块+环绕"升级为大气品质玻璃胶囊

**Independent Test**: 流式中截屏对比：观感明显提升

- [X] T008 [US4] ChatHomeTab.ets 思考行（L2518-2528）重构为品质胶囊：保留 `OctopThinkingIndicator`（indSize 可调 40-48）+ streamPhase 文本（13fp、Medium、text_secondary），外包玻璃胶囊容器（全圆角、轻背景/轻模糊、舒适 padding）+ 柔和玫瑰/品牌蓝低透明度呼吸光晕（呼吸动画 LTPO 30Hz）；位置（底部左侧、输入卡上方）与显示条件（`this.streaming && this.streamPhase !== ''`）不变；排查 `resources\base\media\octop_logo.*` 渲染，若 logo 呈方块感则给 Image 加圆形裁剪（borderRadius）

---

## Phase 6: 静态检查

- [X] T009 [P] `arkts_check` 对全部 5 个改动文件通过（无新增违例；已知坑：arkts-no-untyped-obj-literals、window 事件回调参数显式类型、禁 any）；grep 确认 contentEndOffset 新公式生效、kbHeight 未出现在 contentBottomPad 链路

---

## Phase 7: Verification

<!-- verification_scope: build+ui -->

**Purpose**: Build, deploy, and UI-verify the implemented feature

- [X] T010 构建：`devecocli build`（workdir=项目根）修复循环直至成功（上限 10 次）
- [X] T011 部署模拟器：`devecocli run --skip-build --device 127.0.0.1:5555`（锁屏先解锁，密码 Abc541755）
- [X] T012 UI 逐条验收（US3/SC-004 FAIL：键盘上方 28px 空胶囊残留，转第十二批修复；其余 10 项全 PASS）：US1 切专家→杀 App→重启自动恢复（标题胶囊截屏）+ 删除当前专家→重启回退默认；US2 滚到底 dumpLayout 实测气泡↔输入卡 ≈ 输入卡↔TabBar 间距（22vp ±2）+ 多行撑高仍对称；US3 弹键盘 TabBar 不上浮（截屏/dump）+ 收起恢复可点 + 其他 Tab 一致 + 输入卡/气泡键盘态零回归；US4 流式思考胶囊截屏取证（观感大气）+ streamPhase 文本更新 + 回合结束消失；SC-001~SC-006 逐条；hilog FATAL=0；截屏 .jpeg + dumpLayout UTF8 取证

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: T001 先行，无依赖
- **US1 (Phase 2)**: T002 → T003 → T004 → T005（T003-T005 依赖 T002 的 AppPrefs API）
- **US2 (Phase 3)**: T006 依赖 T001（与 US1 同文件不同区域，在 T005 之后执行避免冲突）
- **US3 (Phase 4)**: T007 依赖 T001（独立文件，可与 US1 并行）
- **US4 (Phase 5)**: T008 依赖 T006（同文件思考行区域，顺序执行）
- **静态检查 (Phase 6)**: T009 依赖全部实现完成
- **Verification (Phase 7)**: 依赖 T009

### User Story Dependencies

- **US1 (P1)**: MVP 主体（用户点名的核心功能）；AppPrefs API 先行
- **US2 (P2)**: 与 US1/US4 同文件（ChatHomeTab.ets），统一在 T005 之后顺序改
- **US3 (P1)**: 独立文件（MainPage.ets），随时可做
- **US4 (P2)**: 依赖 US2 完成后同文件继续

### Within Each User Story

- 先存储 API 后接线（US1：AppPrefs → SessionStore → 调用点）
- kbHeight 只进 floatingBarStyle，不碰公共 bottomPad 链路
- 每 task 完成确认无残留旧路径

### Parallel Opportunities

- T002（AppPrefs.ets）可与 T007（MainPage.ets）并行
- T009 静态检查收口全部

---

## Parallel Example: User Story 1

```bash
# 不同文件可并行：
Task: "T002 AppPrefs last_agent_id 键 + getter/setter"
Task: "T007 MainPage 键盘高度监听 + TabBar barBottomMargin 增补"

# 同文件顺序执行：
Task: "T003 SessionStore setCurrentAgent 持久化 + restore 恢复"
Task: "T004 ExpertListPage deleteAgent 清持久化"
Task: "T005 ChatHomeTab backfillCurrentAgent 回填"
Task: "T006 ChatHomeTab contentEndOffset 动态公式"
Task: "T008 ChatHomeTab 思考胶囊重构"
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Setup（锚点）
2. Complete Phase 2: US1 专家记忆（T002-T005）
3. **STOP and VALIDATE**: 切专家 → 杀 App → 重启恢复独立验证
4. T007 US3 键盘导航栏（独立文件）
5. T006 + T008 ChatHomeTab 收尾两改
6. T009 静态检查 → Phase 7 验证

### Incremental Delivery

1. US1 专家记忆 → 验证（MVP）
2. US3 键盘导航栏 → 验证
3. US2 对称间距 → 验证
4. US4 思考胶囊 → 验证
5. Verification（构建/部署/UI 逐条验收 + 八/九/十批回归抽查）

---

## Notes

- [P] tasks = different files, no dependencies
- [Story] label maps task to specific user story for traceability
- 服务端零改动；客户端 5 文件改造、无新文件
- ArkTS 硬规则：无 any/unknown、显式类型、build() 顶层无局部声明、禁止裸对象字面量传参、V1 状态管理、window 事件回调参数显式类型（window.KeyboardHeightChangeData）
- 构建前必过 `arkts_check`（5 个改动文件）
- 验证环境：模拟器 127.0.0.1:5555，服务器 s3.z100.vip:35796；锁屏密码 Abc541755
- 触控：`hdc -t 127.0.0.1:5555 shell "uinput -T -c <x> <y>"`；返回键：`hdc -t 127.0.0.1:5555 shell "uinput -K -d 2 -u 2"`；文本输入可试 `uitest uiInput inputText`
- 坐标（模拟器 1280×2832，以 dumpLayout 实测为准）：发送 (1092,2325)；操作行 y≈2325；聊天 Tab (496,2608)
- 杀 App：`hdc -t 127.0.0.1:5555 shell aa force-stop com.octop.link`
- 仅模拟器部署；真机（192.168.3.190:44541）仅用户明确要求时推送
