# Implementation Plan: UI 精修第三批（ui-refine-batch-2）

**Input**: Feature specification from `spec/ui-refine-batch-2/spec.md`

## Summary

9 项 UI/UX 精修与修复：① 新建通用菜单半模态组件 MenuSheet（记忆迁移弹窗样式），替换全工程 24 处系统 ActionSheet（勘察穷举表编号 1-24；spec 初稿概数 25 为含"添加附件"面板的近似口径，以 tasks 清单为准）并统一聊天页添加附件面板；② 新建模型配置页 ProvidersPage（全局默认模型切换 + provider 列表/启停/删除/测试/拉取模型/新建/编辑，服务层 API 全部现成零 UI）；③ MessageBubble 去横线、操作行收紧变窄、上下间距对称；④ token 用量从操作行移至气泡右侧紧凑标识；⑤ MainPage 底部导航栏改自绘悬浮栏 + 键盘高度监听 + 缩放隐藏动画 + 内容底部留白联动；⑥ 我的页新增"支持"入口组（使用说明页 HelpPage / 反馈与建议 bindSheet 面板 / 关于页 AboutPage 动态版本号）；⑦ 我的外观节改 CapsuleSegmentBar 三段滑动胶囊 + 卡片化；⑧ 沉浸光感开关行升级（图标+副标题+状态徽标+Toggle 材质试点）；⑨ 修复渠道扫码接入平台二维码收不到（QR 改客户端本地编码渲染 + 企微 auth_url 解析兜底）。

## Technical Context

**Language/Version**: ArkTS（HarmonyOS，工程已有 API 26 目标：barFloatingStyle/systemMaterial 均为 26 级 API）  
**Primary Dependencies**: @kit.ArkUI、@kit.AbilityKit（bundleManager/window）、@kit.UIDesignKit（HdsNavigation/hdsMaterial）、既有工程组件（CapsuleSegmentBar/ModelPickerSheet/SettingsRow/PageHeader/UiMaterialKit）  
**State Management**: 既有工程 State Management V1（@Component/@State/@Prop/@StorageLink/@Consume），本批全部沿用 V1，不引入 V2  
**Storage**: AppStorage + AppPrefs（外观模式/沉浸光感既有键复用，无新增持久化键）  
**Testing**: devecocli build + 模拟器（127.0.0.1:5555）UI 验收 + 逐条需求核验；真机仅在用户明确要求时推送  
**Target Platform**: HarmonyOS 手机（模拟器 1280×2832 / 真机 1320×2848）  
**Project Type**: 既有 HarmonyOS 应用增量改造（com.octop.link），服务器端零改动  
**Performance Goals**: 键盘动画 250ms 级、不阻塞输入；菜单打开即渲染（无网络依赖）  
**Constraints**: ArkTS 严格模式（无 any/裸对象字面量/解构）；MessageBubble 改动不得破坏 TTS 链路（toggleSpeak/BubbleTtsCallbacks/speaking 三态）；不破坏 message-tts 批次文件  
**Scale/Scope**: 改造 24 个页面的菜单调用点 + 4 个新文件 + 4 个核心页面改造（MainPage/MeTab/MessageBubble/ChatHomeTab 附件面板）+ QR 修复（ChannelPage 本地编码渲染 + QrSessionModel 解析兜底）

## Project Structure

### Documentation (this feature)

```text
spec/ui-refine-batch-2/
├── spec.md              # 需求规格
├── plan.md              # 本文件
└── tasks.md             # 任务清单（/spec-tasks 产出）
```

### Source Code (repository root)

```text
entry/src/main/ets/
├── components/
│   ├── MenuSheet.ets                 # [新建] 通用菜单半模态内容组件（MenuSheetOption + MenuSheetContent）
│   ├── CapsuleSegmentBar.ets         # [复用] 外观三段胶囊（零改造）
│   ├── ModelPickerSheet.ets          # [复用] 模型配置页默认模型切换
│   └── MessageBubble.ets             # [修改] 去横线/操作行变窄/token 右侧标识
├── pages/
│   ├── MainPage.ets                  # [修改] 自绘底部导航栏 + 键盘缩放隐藏动画 + 底部留白联动
│   ├── Index.ets                     # [修改] pageMap 增 providers/help/about 三个路由
│   ├── me/
│   │   ├── MeTab.ets                 # [修改] 外观节胶囊化+卡片化/沉浸光感行升级/支持入口组/反馈面板/版本号动态化
│   │   ├── ProvidersPage.ets         # [新建] 模型配置页（路由 'providers'）
│   │   ├── HelpPage.ets              # [新建] 使用说明页（路由 'help'）
│   │   └── AboutPage.ets             # [新建] 关于页（路由 'about'）
│   ├── chat/
│   │   ├── ChatHomeTab.ets           # [修改] attachSheetBuilder 改 MenuSheet 样式
│   │   └── ChatTab.ets               # [修改] 会话长按菜单 → MenuSheet
│   ├── chat/TrajectoryPage.ets       # [修改] 导出格式菜单 → MenuSheet
│   ├── expert/AgentEditPage.ets      # [修改] 头像菜单 → MenuSheet
│   ├── expert/ExpertListPage.ets     # [修改] 专家长按菜单 → MenuSheet
│   ├── expert/TeamsPage.ets          # [修改] 团队长按菜单 → MenuSheet
│   ├── workspace/
│   │   ├── BridgePage.ets            # [修改] 长按菜单 → MenuSheet
│   │   ├── ChannelPage.ets           # [修改] 渠道长按菜单 → MenuSheet；扫码接入 QR 改客户端本地二维码编码渲染（修复收不到）
│   │   ├── ConnectorPage.ets         # [修改] 连接器长按菜单 → MenuSheet
│   │   ├── CronPage.ets              # [修改] 任务长按菜单 → MenuSheet
│   │   ├── InvitesPage.ets           # [修改] 邀请码菜单 → MenuSheet
│   │   ├── KnowledgePage.ets         # [修改] 知识库长按菜单 → MenuSheet
│   │   ├── KnowledgeDocsPage.ets     # [修改] 添加内容菜单 + 文档长按菜单 → MenuSheet（2 处）
│   │   ├── MemoryPage.ets            # [修改] 记忆长按菜单 → MenuSheet（迁移弹窗本身已是基准样式，仅长按菜单替换）
│   │   ├── PluginPage.ets            # [修改] 安装插件菜单 → MenuSheet
│   │   ├── SkillsPage.ets            # [修改] 技能长按菜单 + 添加技能菜单 → MenuSheet（2 处）
│   │   ├── UserGroupsPage.ets        # [修改] 用户组长按菜单 → MenuSheet
│   │   ├── WorkspaceFilesPage.ets    # [修改] 文件长按菜单 → MenuSheet
│   │   └── UsersPage.ets             # [修改] 用户长按菜单 + 批量操作菜单 + 角色长按菜单 → MenuSheet（3 处）
│   └── me/AdminPage.ets              # [修改] 修改角色菜单 + 用户操作菜单 → MenuSheet（2 处）
└── model/WorkspaceModels.ets         # [修改] 增 ProviderPresetModel（预设模板解析模型）；QrSessionModel.parse 二维码内容取值链补 auth_url 兜底（企微场景）；ProviderModel 已存在复用
```

**Structure Decision**: 完全遵循既有工程架构（pages/me 分域 + components 通用组件 + model/service 分层），不引入 MVVM 迁移。新文件 4 个（1 通用组件 + 3 页面）均为独立功能单元；24 个页面的改动是"同一替换模式的批量应用"（每页：删 showActionSheet 调用 + 加菜单状态与 bindSheet + 组装 MenuSheetOption 数组），不产生新架构层级。状态管理沿用 V1。

## Complexity Tracking

| Violation | Why Needed | Simpler Alternative Rejected Because |
|-----------|------------|-------------------------------------|
| 跨 24 页面批量改造 | 用户要求"全部列表选择弹窗统一" | 只改高频页面会留下样式割裂，违背"统一"目标 |
| MainPage 自绘导航栏（替换系统悬浮 TabBar） | 系统悬浮 TabBar 样式对象不支持显隐/缩放动画（API 文档实查确认无 hide/scale 字段） | 保留系统 bar 仅跳变切 margin，无动画，不满足"缩放动画隐藏"需求 |

## Research & Decisions

### D1: 统一菜单组件的形态与回调契约

- **Decision**: 新建 `components/MenuSheet.ets`，导出纯数据类 `MenuSheetOption`（icon: Resource|null、label、subtitle（''=无）、danger）+ 内容组件 `MenuSheetContent`（@Prop title/message/options + 回调 `onSelect: (index: number) => void`、`onDismiss: () => void`）。各页面自持 4 个 @State：menuOpen/menuTitle/menuMessage/menuOptions + 与 options 等长的 `menuActions: Array<() => void>`，onSelect(index) 先关后执行 menuActions[index]。
- **Rationale**: V1 @Prop 深拷贝会丢失类实例上的函数字段，回调放数据类里不可靠；"数据（可 @Prop）+ 动作数组（页面私有）+ index 回调"规避该坑。样式完全复刻 MemoryPage 迁移弹窗（Column space16、padding{20,20,20,30}、标题 17 Medium/副题 12、44×44 图标容器 radius14 brand_light + SymbolGlyph 20 brand、行标题 15/说明 12 maxLines2、行 padding14 radius16 bg_card+card_stroke、detents FIT_CONTENT、systemMaterial UiMaterialKit.sheet()）。
- **Alternatives considered**: ① MenuSheetOption 内嵌 action 回调（被 @Prop 深拷贝风险否决）；② 全局单例菜单服务（过度设计，各页上下文不同）；③ 保留 ActionSheet 仅调样式（系统 ActionSheet 无自定义行结构能力，否决）。

### D2: 24 处菜单替换的范围界定

- **Decision**: 勘察表 24 处 showActionSheet 全部替换；ChatHomeTab attachSheetBuilder（添加附件：图片/文件）改为 MenuSheet 样式；MeTab profileMenu、CommandPalette、ModelPickerSheet、各表单 bindSheet/CustomDialog 不动。动态菜单（AdminPage 角色列表、UsersPage 批量操作）用运行时构造 options 数组支持。
- **Rationale**: 用户口径"全部列表选择弹窗"；已接近目标样式的专用面板（资料菜单含头像预览、命令面板是搜索型）不属于"列表选择弹窗"，避免过度改造。
- **Alternatives considered**: 连 profileMenu/CommandPalette 一起统一（否决：非菜单形态，收益低风险高）。

### D3: 模型配置页能力面与权限降级

- **Decision**: 新建 ProvidersPage（路由 'providers'），三区结构：① 全局默认模型卡（activeModelGet 回显 + 点击弹 ModelPickerSheet(allowAuto:false) + activeModelPut 保存）；② provider 列表（有 providers 权限走 adminList、无权限走 list 只读；卡片显示名称/kind/启停徽标/模型数/密钥标记；长按弹 MenuSheet 操作菜单：测试连通、拉取模型、启用/停用、编辑、删除(danger+二次确认)）；③ 有权限时顶部"新建 Provider"入口（bindSheet 表单：presetsRaw 预设选择预填 → 名称/接口地址/密钥/模型列表/启用开关 → adminTestDraft 试连 → adminCreate 保存；编辑用 adminPatch 同表单回填）。Codex OAuth 不在本批。
- **Rationale**: ProviderService 全部方法现成零调用（勘察确认）；ProviderModel.enabled 字段存在表明启停可经 PATCH 实现；权限门控沿用 MeTab 既有 canManageUsers 模式（读 SessionStore permissions）。删除是破坏性操作必须二次确认。
- **Alternatives considered**: ① 只做默认模型切换（否决：用户要"配置"，服务面支持完整管理）；② 含 Codex OAuth（否决：独立复杂流程，留后续批次）。

### D4: 气泡操作行变窄与去横线的具体参数

- **Decision**: 删除助手气泡 Divider（#26 divider，原 432-434）与用户气泡半透明分隔线（原 338-340）；助手操作行按钮 30×30→20×20、图标 15→12、LoadingProgress 14→12、stop_circle 16→13、Row space 8→6；操作行与正文间距（margin top）=14 = 气泡容器 padding.bottom（对称）；用户复制图标 13→12。TTS 三态渲染与 onClick 链路（450-474 行）原样保留，只改尺寸样式。
- **Rationale**: "变窄"按约 1/3 收缩（30→20）；"上和文字的距离等于下和边缘的距离"以容器 padding 14 为基准对称。
- **Alternatives considered**: 按钮缩到 24（收缩不足 1/3，观感变化弱）。

### D5: token 用量气泡右侧标识

- **Decision**: 从操作行移除用量文本（原 490-496），改为气泡级右侧标识：助手气泡外右侧竖排两行小字（"↑N" / "↓N"，10fp、text_tertiary、行距紧凑），外包紧凑胶囊（bg_card 背景 radius 8、padding 4×6、card_stroke 描边），仅 usageIn+usageOut>0 时渲染；气泡 maxWidth 88%→84% 为标识留位。实时（WS usage 帧→setUsage）与历史（fromHistoryRecord usage 字段）两条数据路径已闭环，零数据层改动。
- **Rationale**: 用户原话"token 用量显示在气泡右侧（优化数字或胶囊）"；竖排胶囊最省横向空间且不与相邻消息冲突。
- **Alternatives considered**: ① 单行横排小字（横向占用大，长数字挤气泡）；② 保留在操作行只优化样式（违背"右侧"位置要求）。

### D6: 键盘弹出导航栏缩放隐藏的实现路径

- **Decision**: MainPage 改造：Tabs 隐藏系统 bar（去 barFloatingStyle、barHeight(0)，保留 index 双向绑定与左右滑切换），Tabs 外包 Stack(Bottom)，自绘悬浮导航栏（高 56、胶囊 radius 28、glassBg(bar_glass)+systemMaterial(UiMaterialKit.navBarMaterial())+card_stroke+软影，四项复用 tabBarItem：图标 21/文字 10/聊天红点，layoutWeight 等分，点击写 mainTab @StorageLink）。键盘监听：aboutToAppear 在已有 window 实例上 `on('keyboardHeightChange')`（API 7+，高度 px>0 即弹出），状态去抖后 `getUIContext().animateTo({duration:250, curve:Curve.EaseOut})` 切换 keyboardOn；导航栏 transform：keyboardOn 时 scale({x:0.85,y:0.6})+translate({y:90})+opacity(0)，恢复为 1/0。contentBottomPad()：keyboardOn 时返回小值（8），否则原值（floatingBarBottomMargin()+68），经既有 bottomPad prop 链自动传导四 tab（ChatHomeTab 输入卡/列表 contentEndOffset、ExpertListPage 尾占位等全部自动适配）。aboutToDisappear 注销监听。
- **Rationale**: 系统悬浮 bar 样式对象无显隐/动画字段（API 文档实查），自绘是唯一可动画路径；RESIZE 键盘避让模式保持不动（Index.ets:42），压缩窗口下藏 bar 即让输入区直接贴近键盘；keyboardHeightChange 比 avoidAreaChange 语义直接且 API 版本最低。
- **Alternatives considered**: ① 保留系统 bar 仅切 barBottomMargin（无动画，否决）；② 改 KeyboardAvoidMode.NONE 手工全量避让（全工程输入点都要改，代价过大）。

### D7: 支持入口三个目的地

- **Decision**: 使用说明→新 HelpPage（'help'，PageHeader+分节静态中文指南卡片：快速开始/聊天/专家/工作台/我的）；反馈与建议→MeTab 内 bindSheet 面板（说明文案 + "复制反馈信息"按钮：粘贴板写入含动态版本号的反馈模板，仿 copyServerUrl 模式）；关于→新 AboutPage（'about'，居中 logo+应用名+slogan+版本卡：bundleManager.getBundleInfoForSelf(GET_BUNDLE_INFO_DEFAULT) 动态读 versionName，失败回退静态文本）。MeTab 底部硬编码 "v0.2.0"（702-705）改为同一动态版本源。
- **Rationale**: 无任何服务端 help/feedback 端点（服务层+api-contract 双重穷举确认），本地页面与复制模板是唯一可行路径；动态版本号消除 UI(0.2.0) 与 app.json5(1.0.0) 的既有脱节；getBundleInfoForSelf 为官方标准做法（docs faqs-package-structure-52）。
- **Alternatives considered**: ① 反馈走 mailto/openLink（工程零先例需真机首验，且无既定反馈邮箱，否决为主路径）；② 版本号继续硬编码（已有脱节先例，否决）。

### D8: 外观胶囊与沉浸光感开关行

- **Decision**: MeTab 外观节：① 整节包进与连接/账号节同款玻璃卡片（radius16+card_glass+COMPONENT_THIN+card_stroke+软影）；② 三模式按钮行替换为 CapsuleSegmentBar（3 段等分：浅色/深色/跟随系统，零组件改造），selectedIndex 由 appearanceMode 映射（light=0/dark=1/auto=2），onSelect 反向映射调既有 setAppearance（去重逻辑保留）；③ 沉浸光感行改为图标盒+标题+副标题（说明控制范围）+右侧状态徽标（已开启/已关闭小胶囊，brand/brand_light 与 bg_input/text_tertiary 双态）+Toggle（isOn: $$this.immersiveOn 双向绑定、selectedColor brand、systemMaterial UiMaterialKit.button() 试点）。
- **Rationale**: CapsuleSegmentBar 已实测 3/4 段可用（ExpertListPage 实况）；外观节当前裸露无卡片是"单调"主因之一；Toggle systemMaterial 为 API 26 能力（工程目标版本满足），材质不可用时自动降级不影响功能；$$ 双向绑定为官方支持（faqs-arkui-1016）。
- **Alternatives considered**: ① 给 CapsuleSegmentBar 加样式透传参数（本期无必要，零改造可用）；② 沉浸光感用 contentModifier 自绘开关（工程零先例，风险高收益低）。

### D9: 渠道二维码收不到的根因与修复方案

- **Decision**: 根因已三方实证（服务端源码 Octop main@890111b + dashboard web 参考实现 + 模拟器运行时抓包）：服务端四平台 generate 返回的 `qrcode_url`（企微为 `auth_url`）语义是"待本地编码成二维码的授权链接字符串"，而客户端把它当远程图片 URL 交给 Image 组件下载——Image 实际下载到的是平台登录页 HTML（hilog: ImageSource failed to create decoder），必然进入失败态；企微则因 QrSessionModel.parse 不读 `auth_url` 而永久卡在 waitcode。修复：① ChannelPage qrSheetBuilder（原 737-775 区域）弃用 Image 下载链路，改用 ArkUI 内置 `QRCode(value: string)` 组件本地编码渲染（与 dashboard web 的 QRCodeSVG 行为对齐），加载态简化为"有内容即渲染"；② WorkspaceModels.ets QrSessionModel.parse 的二维码内容取值链补 `auth_url` 兜底；③ 扫码场景移除 qrFullUrl 的 baseUrl+access_token 拼接（二维码内容是外部平台 URL，与 Octop token 无关；MeTab 头像场景的 avatarFullUrl 保留不动）；④ 四态轮询状态机（waiting/expired/failed/success 的 poll 映射）经逐字段比对已正确，原样保留。
- **Rationale**: 参照实现（web 端 ChannelDrawer.tsx 用 QRCodeSVG 对各平台链接本地编码）定死字段语义；四个平台 generate/poll 请求与响应字段和服务端逐字段比对全部吻合，WorkspaceService 零改动；本地编码同时消除"网络下载失败"与"内容非图片解码失败"两类故障，并自然修复企微永久等待。
- **Alternatives considered**: ① 给 Image 请求加 UA/重试（治标：HTML 本来就不是图片）；② 服务端改为返回图片（违背服务器零改动约束且与 web 端契约冲突）；③ 企微单独分支渲染（统一在 parse 层兜底更简洁）。

## Data Model

### 新增模型

- **MenuSheetOption**（components/MenuSheet.ets，纯数据类）: `icon: Resource | null`（null 时渲染默认符号）、`label: string`、`subtitle: string`（''=不渲染说明）、`danger: boolean`（true=红色警示态：图标容器 danger_soft 底+danger 色图标与文字）。
- **ProviderPresetModel**（model/WorkspaceModels.ets，预设模板）: `id/name/kind/baseUrl/description` 等字段，由 presetsRaw 原始 JSON 防御性解析（先断言原始类型再拷贝入严格模型，禁止裸断言）。

### 复用模型（零改动）

- **ProviderModel**（WorkspaceModels 1148-1186）: providerId/name/kind/enabled/model_count/has_api_key 等，provider 列表卡片直接消费。
- **ActiveModel**（ProviderService）: provider_name/model，全局默认模型卡消费。
- **ChatMessageModel.usageIn/usageOut**（MessageModels 171-172）: 气泡右侧标识数据源（setUsage/fromHistoryRecord 两条路径均已闭环）。
- **ResolvedModelEntry / SegmentBarOption / ContextUsageModel**: 均复用。
- **QrSessionModel**（修改）: 二维码内容字段解析链补 `auth_url` 兜底（企微 generate 响应无 qrcode_url，返回 auth_url）；轮询 token 三态容错（registration_id/scode/qrcode_token）保持不变。

### 页面状态（非持久化）

- 各菜单页: `menuOpen: boolean`、`menuTitle/menuMessage: string`、`menuOptions: Array<MenuSheetOption>`、`menuActions: Array<() => void>`。
- MainPage: `keyboardOn: boolean`（键盘高度事件驱动，animateTo 包裹切换）。
- MeTab: `appVersion: string`（getBundleInfoForSelf 异步填充）、`feedbackOpen: boolean`。
- ProvidersPage: `providers: Array<ProviderModel>`、`activeModel: ActiveModel | null`、`loading/error` 常规三态、表单编辑态。

## Contracts & Interfaces

### 组件契约

- **MenuSheetContent**: `@Prop title: string`、`@Prop message: string`（''=不渲染副题）、`@Prop options: Array<MenuSheetOption>`、`onSelect: (index: number) => void`、`onDismiss: () => void`。样式基准 = MemoryPage 迁移弹窗（D1 详列参数）。宿主页模式：`.bindSheet($$this.menuOpen, this.menuSheetBuilder, { detents:[SheetSize.FIT_CONTENT], showClose:true, systemMaterial: UiMaterialKit.sheet() })`。
- **CapsuleSegmentBar**（复用，零改造）: `options: Array<SegmentBarOption>`、`selectedIndex: number`、`onSelect: (index) => void`。
- **QRCode**（ArkUI 内置组件，QR 修复用）: `QRCode(value: string)` 本地编码渲染，color 白色/backgroundColor 深色固定搭配保证可扫描性。

### 路由契约（Index.ets pageMap 新增 3 项）

- `'providers'` → ProvidersPage（入口：MeTab 账号节"模型配置"行）
- `'help'` → HelpPage（入口：MeTab 支持节"使用说明"行）
- `'about'` → AboutPage（入口：MeTab 支持节"关于"行）
- 反馈与建议不建路由（MeTab 内 bindSheet）。

### 服务契约（全部既有，零新增端点）

- ProviderService: `activeModelGet/activeModelPut(providerName, model)/list()/adminList()/adminPatch(id, body)/adminRemove(id)/adminTestDraft(body)/adminFetchModels(body)/adminTest(id, body)/adminCreate(body)/presetsRaw()`；resolvedModels 供 ModelPickerSheet 复用。
- window: `on('keyboardHeightChange', Callback<number>)`（px，收起=0）+ 配对 off；密度换算 vp。
- bundleManager: `getBundleInfoForSelf(BundleFlag.GET_BUNDLE_INFO_DEFAULT)` → BundleInfo.versionName/versionCode。
- pasteboard: 复用 MeTab copyServerUrl 模式（getSystemPasteboard().setData）。

### 保护性红线（实施与验证均须遵守）

- MessageBubble 仅动分隔线/操作行尺寸样式与用量标识位置；`toggleSpeak()/BubbleTtsCallbacks/speaking/speakingBusy` 三态链路逐行保留。
- LocalTtsService/TtsModels/AppPrefs tts_* 键/VoiceSettingsPage/LocalTtsConfigDialog 零改动。
- 服务器端零改动；KeyboardAvoidMode.RESIZE（Index.ets:42）不动。
- MainTab 既有行为保留：四 tab 切换、聊天红点清零（onChange 写回）、内容左右滑切换、expandSafeArea。

验证范围由 tasks.md 承载（`<!-- verification_scope: build+ui -->`）：build 成功 + 模拟器部署 + 8 个用户故事逐条 UI 验收（24 处菜单逐页抽验动作等价、模型配置页全流程、气泡样式与 token 标识、键盘动画、我的页三个入口、外观胶囊、沉浸光感状态）。
