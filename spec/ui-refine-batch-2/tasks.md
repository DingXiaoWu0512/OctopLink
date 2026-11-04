# Tasks: UI 精修第三批（弹窗统一/模型配置/气泡精修/键盘避让/我的页增强/QR 修复）

**Input**: Design documents from `spec/ui-refine-batch-2/`
**Prerequisites**: plan.md (required), spec.md (required for user stories)

**Tests**: 无独立测试任务（验证走 Verification 阶段 build + 模拟器 UI 验收）。

**Organization**: 任务按用户故事分组（US1 菜单统一 / US2 模型配置页 / US3 气泡操作行 / US4 token 右侧 / US5 键盘导航栏 / US6 支持入口 / US7 外观胶囊 / US8 沉浸光感 / US9 QR 修复），每条故事可独立实施与验收。

## Format: `[ID] [P?] [Story] Description`

- **[P]**: 可并行（不同文件、无未完成依赖）
- **[Story]**: 所属用户故事
- 描述含精确文件路径（相对 `C:\Users\13775\OctopLink\`）

## Path Conventions

- 单工程根：`C:\Users\13775\OctopLink\`（HarmonyOS 工程，`entry/` 模块）
- ArkTS 源码：`entry/src/main/ets/`（pages/components/model/service/store 分层）
- 资源：`entry/src/main/resources/`（base/element/color.json 与 dark 对称维护）
- 规格工件：`spec/ui-refine-batch-2/`（本文档所在目录）
- 所有任务描述中的相对路径均相对工程根 `C:\Users\13775\OctopLink\`

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: 环境与上下文准备

- [X] T001 加载 `hmos-arkui-develop-skill` skill；通读 `spec/ui-refine-batch-2/spec.md` 与 `plan.md`；确认工程构建基线存在（`entry/build-profile.json5`），无需新建项目、无新增依赖

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: 所有菜单类故事依赖的通用组件

- [X] T002 [P] 新建通用菜单半模态组件：`entry/src/main/ets/components/MenuSheet.ets` —— 导出纯数据类 `MenuSheetOption`（icon: Resource|null、label、subtitle（''=无）、danger）+ 内容组件 `MenuSheetContent`（@Prop title/message/options、onSelect(index)、onDismiss）；样式基准 = MemoryPage 迁移弹窗（Column space16、padding{20,20,20,30}、标题 17 Medium/副题 12、44×44 图标容器 radius14、行 padding14 radius16 bg_card+card_stroke、danger 态红色警示配色、SymbolGlyph 20、整行可点先关后执行）

**Checkpoint**: MenuSheet 组件就绪，24 处菜单替换与 ProvidersPage 操作菜单可开始

---

## Phase 3: User Story 1 - 全部列表选择弹窗统一 (Priority: P1) 🎯 MVP

**Goal**: 全工程 24 处系统 ActionSheet 全部替换为 MenuSheet 统一样式
**Independent Test**: 逐处触发菜单验证新样式呈现且原动作等价

- [X] T003 [P] [US1] 菜单替换组A（5 处）：`entry/src/main/ets/pages/expert/AgentEditPage.ets`（头像菜单）、`entry/src/main/ets/pages/chat/TrajectoryPage.ets`（导出格式）、`entry/src/main/ets/pages/chat/ChatTab.ets`（会话长按菜单）、`entry/src/main/ets/pages/expert/ExpertListPage.ets`（专家长按菜单）、`entry/src/main/ets/pages/expert/TeamsPage.ets`（团队长按菜单）——每处删 showActionSheet，加 menuOpen/menuTitle/menuMessage/menuOptions/menuActions 状态 + bindSheet(FIT_CONTENT, UiMaterialKit.sheet()) + MenuSheetContent
- [X] T004 [P] [US1] 菜单替换组B（5 处）：`entry/src/main/ets/pages/workspace/BridgePage.ets`、`entry/src/main/ets/pages/workspace/ChannelPage.ets`（渠道长按菜单）、`entry/src/main/ets/pages/workspace/ConnectorPage.ets`、`entry/src/main/ets/pages/workspace/InvitesPage.ets`、`entry/src/main/ets/pages/workspace/CronPage.ets` —— 同 T003 替换模式
- [X] T005 [P] [US1] 菜单替换组C（7 处）：`entry/src/main/ets/pages/workspace/KnowledgePage.ets`、`entry/src/main/ets/pages/workspace/KnowledgeDocsPage.ets`（添加内容菜单 + 文档长按菜单 2 处）、`entry/src/main/ets/pages/workspace/MemoryPage.ets`（记忆长按菜单）、`entry/src/main/ets/pages/workspace/PluginPage.ets`（安装插件菜单）、`entry/src/main/ets/pages/workspace/SkillsPage.ets`（技能长按菜单 + 添加技能菜单 2 处）—— 同 T003 替换模式
- [X] T006 [P] [US1] 菜单替换组D（7 处）：`entry/src/main/ets/pages/workspace/UserGroupsPage.ets`、`entry/src/main/ets/pages/workspace/WorkspaceFilesPage.ets`、`entry/src/main/ets/pages/workspace/UsersPage.ets`（用户长按菜单 + 批量操作菜单 + 角色长按菜单 3 处，批量操作含动态选项）、`entry/src/main/ets/pages/me/AdminPage.ets`（修改角色菜单 + 用户操作菜单 2 处，角色菜单为动态选项列表）—— 同 T003 替换模式
- [X] T007 [US1] `entry/src/main/ets/pages/chat/ChatHomeTab.ets` attachSheetBuilder（原 2112-2165 区域）改为 MenuSheet 统一样式（添加附件：选择图片/选择文件两选项行，动作不变）

**Checkpoint**: 全部列表选择弹窗统一为新样式，原动作逐处等价

---

## Phase 4: User Story 2 - 移动端模型配置页 (Priority: P1) 🎯 MVP

**Goal**: 新建 ProvidersPage：全局默认模型切换 + provider 列表/启停/删除/测试/拉取/新建/编辑
**Independent Test**: 我的页进入模型配置页，默认模型切换与 provider 管理全流程可用

- [X] T008 [US2] `entry/src/main/ets/model/WorkspaceModels.ets` 增 `ProviderPresetModel`（presetsRaw 防御性解析）；新建 `entry/src/main/ets/pages/me/ProvidersPage.ets` 主体：全局默认模型卡（activeModelGet 回显 + ModelPickerSheet(allowAuto:false) + activeModelPut）、provider 列表（有 providers 权限 adminList/无权限 list 只读；卡片名称/kind/启停徽标/模型数/密钥标记）、权限门控与只读降级、loading/error/重试三态
- [X] T009 [US2] `entry/src/main/ets/pages/me/ProvidersPage.ets` 管理操作：长按/更多弹 MenuSheet（测试连通 adminTest 结果提示、拉取模型 adminFetchModels 结果展示、启用/停用 adminPatch(enabled)、删除 adminRemove+二次确认、编辑 adminPatch 表单回填）+ 新建 provider bindSheet 表单（presetsRaw 预设选择预填 → 名称/接口地址/密钥/模型列表/启用开关 → adminTestDraft 试连 → adminCreate 保存）；`entry/src/main/ets/pages/me/MeTab.ets` 账号节增"模型配置"SettingsRow（pushPath 'providers'）；`entry/src/main/ets/pages/Index.ets` pageMap 增 'providers' 路由

**Checkpoint**: 模型配置页全流程可用，无权限只读降级

---

## Phase 5: User Story 9 - 修复平台二维码收不到 (Priority: P1) 🎯 MVP

**Goal**: 四平台扫码接入正常出码（本地编码渲染替代 Image 下载）
**Independent Test**: 渠道页依次选择钉钉/企微/微信/QQ，四平台均显示二维码并进入轮询

- [X] T010 [US9] `entry/src/main/ets/model/WorkspaceModels.ets` QrSessionModel.parse 二维码内容取值链补 `auth_url` 兜底（企微 generate 响应无 qrcode_url 场景；token 三态容错保持不变）
- [X] T011 [US9] `entry/src/main/ets/pages/workspace/ChannelPage.ets` qrSheetBuilder（原 737-775 区域）改 ArkUI 内置 `QRCode(value)` 本地编码渲染：弃用 Image 下载与 onError 解码链、移除扫码场景 qrFullUrl 的 baseUrl+access_token 拼接（MeTab avatarFullUrl 不动）、加载态简化为"有内容即渲染"、深色码点浅色底固定搭配保证可扫、四态轮询状态机（waiting/expired/failed/success）保留

**Checkpoint**: 四平台扫码接入全部正常出码

---

## Phase 6: User Story 3 - 气泡操作行变窄去横线 (Priority: P2)

**Goal**: 助手/用户气泡去分隔线、操作行收紧变窄、上下间距对称
**Independent Test**: 聊天页查看任意已完成气泡验证样式

- [X] T012 [US3] `entry/src/main/ets/components/MessageBubble.ets`：删助手气泡 Divider（原 432-434）与用户气泡半透明分隔线（原 338-340）；操作行按钮 30×30→20×20、图标 15→12、LoadingProgress 14→12、stop_circle 16→13、Row space 8→6；操作行与正文间距（14）= 与气泡底边间距（容器 padding.bottom 14）对称；用户复制图标 13→12；TTS 三态与 onClick 链路（原 450-474）逐行保留不动

**Checkpoint**: 气泡无横线、操作行变窄、间距对称，TTS 三态正常

---

## Phase 7: User Story 4 - Token 用量显示在气泡右侧 (Priority: P2)

**Goal**: 用量从操作行移至气泡右侧紧凑胶囊
**Independent Test**: 新一轮对话气泡右侧出现用量标识，历史消息有数据者显示

- [X] T013 [US4] `entry/src/main/ets/components/MessageBubble.ets`（依赖 T012）：移除操作行内用量文本（原 490-496），助手气泡外右侧加竖排两行紧凑胶囊（"↑N"/"↓N" 10fp、bg_card 背景 radius8、card_stroke 描边、深浅色主题色资源可读），仅 usageIn+usageOut>0 渲染；气泡 maxWidth 88%→84%；实时（setUsage）与历史（fromHistoryRecord）两条数据路径零改动复用

**Checkpoint**: 用量标识位置与渲染条件正确

---

## Phase 8: User Story 5 - 键盘弹出导航栏缩放隐藏 (Priority: P2)

**Goal**: 自绘底部导航栏 + 键盘缩放动画隐藏/恢复 + 内容留白联动
**Independent Test**: 聊天输入框唤起/收起键盘观察导航栏动画与内容空间变化

- [X] T014 [US5] `entry/src/main/ets/pages/MainPage.ets`：Tabs 去系统悬浮 bar（去 barFloatingStyle、barHeight(0)，保留 index 绑定与滑动切换、onChange 写回与红点清零），Tabs 外 Stack(Bottom) 自绘悬浮导航栏（高 56、胶囊 radius28、glassBg(bar_glass)+systemMaterial(UiMaterialKit.navBarMaterial())+card_stroke+软影、四项复用 tabBarItem 图标 21/文字 10/聊天红点、layoutWeight 等分、点击写 mainTab @StorageLink）
- [X] T015 [US5] `entry/src/main/ets/pages/MainPage.ets`（依赖 T014）：aboutToAppear 在既有 window 实例上注册 `on('keyboardHeightChange')`（px>0 即弹出、状态去抖），animateTo({duration:250, curve:Curve.EaseOut}) 切换 keyboardOn；导航栏 keyboardOn 态 scale({x:0.85,y:0.6})+translate({y:90})+opacity(0)；contentBottomPad() 键盘态返回 8、常态原值（bottomPad prop 链自动传导）；aboutToDisappear 注销监听

**Checkpoint**: 键盘弹出导航栏缩放隐藏、收起恢复、四 tab 内容留白联动

---

## Phase 9: User Story 6 - 我的页支持入口组 (Priority: P3)

**Goal**: 使用说明页 / 反馈与建议面板 / 关于页三个入口
**Independent Test**: 我的页依次打开三个入口验证内容与返回

- [X] T016 [P] [US6] 新建 `entry/src/main/ets/pages/me/HelpPage.ets`（路由 'help'）：PageHeader + 静态中文使用说明分节卡片（快速开始/聊天/专家/工作台/我的五节，纯本地内容无网络依赖）
- [X] T017 [P] [US6] 新建 `entry/src/main/ets/pages/me/AboutPage.ets`（路由 'about'）：PageHeader + 居中 logo/应用名/slogan + 版本卡（bundleManager.getBundleInfoForSelf(GET_BUNDLE_INFO_DEFAULT) 动态 versionName，失败回退静态文本不空白）
- [X] T018 [US6]（依赖 T016/T017）`entry/src/main/ets/pages/me/MeTab.ets`：账号节下新增"支持"节（sectionHeader+玻璃卡片+SettingsRow×3：使用说明/反馈与建议/关于+Divider(left 62)，pushPath help/about）+ 反馈与建议 bindSheet 面板（说明文案+"复制反馈信息"按钮：粘贴板写入含动态版本号的反馈模板，仿 copyServerUrl 模式）+ 底部硬编码 "v0.2.0"（原 702-705）改与 AboutPage 同源动态版本；`entry/src/main/ets/pages/Index.ets` pageMap 增 'help'/'about' 路由

**Checkpoint**: 三个支持入口全部可达且内容完整

---

## Phase 10: User Story 7 - 外观选项滑动胶囊 (Priority: P3)

**Goal**: 浅色/深色/跟随系统改 CapsuleSegmentBar，外观节卡片化
**Independent Test**: 外观节三模式切换滑块动画与即时生效

- [X] T019 [US7] `entry/src/main/ets/pages/me/MeTab.ets`（依赖 T018 同文件顺序）：外观节包进玻璃卡片（radius16+card_glass+COMPONENT_THIN+card_stroke+软影，对齐连接/账号节）；三模式按钮行替换为 CapsuleSegmentBar 3 段（浅色/深色/跟随系统，selectedIndex 由 appearanceMode 映射 light=0/dark=1/auto=2，onSelect 反向映射调既有 setAppearance 去重逻辑保留）

**Checkpoint**: 外观胶囊切换即时生效并持久化

---

## Phase 11: User Story 8 - 沉浸光感开关状态优化 (Priority: P3)

**Goal**: 沉浸光感行升级：说明副标题+状态徽标+Toggle 材质试点
**Independent Test**: 切换开关验证状态标识与材质效果联动

- [X] T020 [US8] `entry/src/main/ets/pages/me/MeTab.ets`（依赖 T019 同文件顺序）：沉浸光感行升级为图标盒+标题+功能说明副标题+右侧状态徽标（已开启/已关闭小胶囊双态）+Toggle（isOn: $$this.immersiveOn 双向绑定、selectedColor brand、systemMaterial UiMaterialKit.button() 试点、材质不可用自动降级）；开关状态变化副标题与徽标即时更新，UiMaterialKit.setImmersiveLight 既有链路不变

**Checkpoint**: 沉浸光感状态可视化完成，我的页改造收尾

---

## Phase 12: Polish & Cross-Cutting Concerns

**Purpose**: 全量静态检查与清理

- [X] T021 `arkts_check` 全量检查本批全部改动 .ets 文件并修复全部诊断；核对新增 sys.symbol 图标均存在于 SDK id_defined.json（用前查证，不存在则换既有符号）；确认无裸对象字面量传参、无 any/断言滥用、ForEach 带 key；确认 TTS 保护红线未被触碰（LocalTtsService/TtsModels/AppPrefs tts_*/VoiceSettingsPage/LocalTtsConfigDialog 零改动，MessageBubble 仅动样式与用量位置）

---

## Phase 13: Verification

<!-- verification_scope: build+ui -->

**Purpose**: 构建、部署模拟器并逐条 UI 验收 9 个用户故事

- [ ] T022 Build：`devecocli build`（workdir=工程根），编译错误修复循环直至成功
- [ ] T023 部署模拟器（127.0.0.1:5555）：`devecocli run --skip-build`（若零输出挂死则重启模拟器"Mate 90 Pro"后重试），应用启动正常
- [ ] T024 UI 验收菜单统一：抽验 24 处菜单（每组至少 2 处：长按专家/会话/渠道/技能/用户、添加内容/添加技能/安装插件/接入渠道导出格式、AdminPage 角色、UsersPage 批量操作），验证新样式呈现、危险项红色态、每处动作等价、取消不误触发
- [ ] T025 UI 验收模型配置页：我的页入口进入，默认模型卡回显与切换、provider 列表展示、长按操作菜单（测试/启停/删除二次确认/拉取模型/编辑）、新建 provider 表单全流程、无权限账号只读降级
- [ ] T026 UI 验收气泡精修：助手气泡无分隔线、操作行变窄、上下间距相等；用户气泡无分隔线；复制/朗读/重发动作正常（朗读三态完整）；新对话气泡右侧用量胶囊显示、历史有数据气泡显示、0 用量不显示、深浅色可读
- [ ] T027 UI 验收键盘导航栏：聊天输入框唤起键盘→导航栏 250ms 级缩放动画隐藏、内容留白收紧；收起→缩放恢复；专家列表搜索框同验；键盘弹出时切 tab 不闪烁；二级页返回后状态一致
- [ ] T028 UI 验收我的页：支持节三入口（使用说明分节内容/反馈面板复制反馈信息含版本/关于页动态版本号）+ 底部版本与关于页同源；外观节卡片化+三段胶囊切换滑块动画即时生效；沉浸光感副标题/状态徽标/材质开关切换联动
- [ ] T029 UI 验收 QR 修复：渠道页扫码接入依次选钉钉/企微/微信/QQ，四平台均显示二维码（企微不再永久等待）、进入轮询、深浅色二维码均深码点浅底可扫；轮询过期/重试路径正常

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: 无依赖，立即开始
- **Foundational (Phase 2)**: 依赖 Setup；**阻塞全部菜单类任务（T003-T007、T009 的操作菜单、T007）**
- **User Stories (Phase 3-11)**: 依赖 Foundational（T002）完成；P1（US1/US2/US9）→ P2（US3/US4/US5）→ P3（US6/US7/US8）顺序推进
- **Polish (Phase 12)**: 依赖全部实现任务完成
- **Verification (Phase 13)**: 依赖 Polish 完成；由 spec-verify 子代理执行

### User Story Dependencies

- **US1 (T003-T007)**: 仅依赖 T002；四组菜单替换（T003-T006）文件集互斥可并行，T007 依赖 T002
- **US2 (T008-T009)**: T008 → T009（同文件顺序）；T009 的操作菜单依赖 T002
- **US9 (T010-T011)**: 仅依赖 T002（ChannelPage 长按菜单在 T004 改造，qrSheetBuilder 改造在 T011，同文件不同区域，顺序执行）
- **US3 (T012) → US4 (T013)**: 同文件 MessageBubble.ets，必须顺序
- **US5 (T014 → T015)**: 同文件 MainPage.ets，必须顺序
- **US6 (T016/T017 可并行 → T018)**: T018 依赖页面存在；T018 → T019 → T020 同文件 MeTab.ets 必须顺序
- **跨故事同文件注意**: WorkspaceModels.ets（T008 与 T010）顺序执行；ChannelPage.ets（T004 与 T011）顺序执行；MeTab.ets（T009/T018/T019/T020）顺序执行；Index.ets（T009 与 T018）顺序执行

### Within Each User Story

- 组件/模型先于页面装配；页面先于入口接线；入口先于路由注册

### Parallel Opportunities

- T003/T004/T005/T006 四组菜单替换文件集互斥，可并行
- T016/T017 两个新页面可并行
- T002、T012、T014、T016/T017 彼此文件互斥，可并行

---

## ⚡ Parallel Execution Guide

| Phase | Tasks | Required Files | Execution Notes |
|---|---|---|---|
| Foundational | T002 | components/MenuSheet.ets（新建） | 阻塞所有菜单任务，最先做 |
| US1 菜单替换 | T003, T004, T005, T006 | 四组文件集互斥 | 可四路并行；每组严格按替换模式 |
| US1 收尾 | T007 | pages/chat/ChatHomeTab.ets | 依赖 T002 |
| US2 | T008 → T009 | model/WorkspaceModels.ets、pages/me/ProvidersPage.ets、pages/me/MeTab.ets、pages/Index.ets | T008 完成后 T009；与 T010 注意 WorkspaceModels.ets 顺序 |
| US9 | T010 → T011 | model/WorkspaceModels.ets、pages/workspace/ChannelPage.ets | T010 与 T008 顺序执行同文件 |
| US3+US4 | T012 → T013 | components/MessageBubble.ets | 顺序执行；保护 TTS 链路 |
| US5 | T014 → T015 | pages/MainPage.ets | 顺序执行 |
| US6 | T016 ∥ T017 → T018 | pages/me/HelpPage.ets、pages/me/AboutPage.ets、pages/me/MeTab.ets、pages/Index.ets | 两新页可并行 |
| US7 → US8 | T019 → T020 | pages/me/MeTab.ets | 依赖 T018（同文件顺序链） |
| Polish | T021 | 全部改动文件 | arkts_check 全量 + 红线核对 |
| Verification | T022-T029 | — | spec-verify 子代理执行 |

---

## Parallel Example

```bash
# 四组菜单替换并行（文件集互斥）：
Task: "T003 [US1] 菜单替换组A（AgentEditPage/TrajectoryPage/ChatTab/ExpertListPage/TeamsPage）"
Task: "T004 [US1] 菜单替换组B（BridgePage/ChannelPage/ConnectorPage/InvitesPage/CronPage）"
Task: "T005 [US1] 菜单替换组C（KnowledgePage/KnowledgeDocsPage×2/MemoryPage/PluginPage/SkillsPage×2）"
Task: "T006 [US1] 菜单替换组D（UserGroupsPage/WorkspaceFilesPage/UsersPage×3/AdminPage×2）"
```

---

## Implementation Strategy

### MVP First (P1 Stories)

1. T002 MenuSheet 组件
2. T003-T007 US1 菜单统一（全应用一致性）
3. T008-T009 US2 模型配置页
4. T010-T011 US9 QR 修复（功能故障）

### Incremental Delivery

1. P1 三故事（US1/US2/US9）→ 逐故事验收
2. P2 三故事（US3/US4/US5）→ 逐故事验收
3. P3 三故事（US6/US7/US8）→ 逐故事验收
4. T021 Polish → T022-T029 Verification

---

## Notes

- [P] = 不同文件、无未完成依赖
- 同文件多任务必须顺序（MessageBubble/MainPage/MeTab/WorkspaceModels/ChannelPage/Index）
- MessageBubble 改动红线：toggleSpeak/BubbleTtsCallbacks/speaking/speakingBusy 链路逐行保留
- 服务器端零改动；KeyboardAvoidMode.RESIZE（Index.ets:42）不动
- 新增 sys.symbol 图标用前查 SDK id_defined.json；禁止裸对象字面量传参（arkts_check 查不出但 build 失败）
- 部署/验证一律模拟器 127.0.0.1:5555；真机仅在用户明确要求时推送
