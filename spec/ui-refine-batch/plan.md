# Implementation Plan: 移动端 UI 精修批次（UI Refine Batch）

**Input**: Feature specification from `spec/ui-refine-batch/spec.md`

## Summary

8 项 UI 精修/缺陷修复，全部落在既有页面：① ChatHomeTab 输入气泡设置层紧凑化+上下文 pill 右置；② ExpertListPage 筛选改滑动胶囊（新增可复用 CapsuleSegmentBar 组件）+ 底部占位修复遮挡；③ ChannelPage 扫码二维码 URL 拼接与失败态修复；④ SkillsPage 三弹窗 + PluginPage 安装 sheet/主体版式统一；⑤ MemoryPage 记忆迁移 ActionSheet 升级为双选项弹窗 + ChannelPage 接入渠道双卡优化；⑥ 渠道头像渐变美化；⑦ 模型设置能力为调研结论（无代码）。遵循既有分层与视觉语言（UiMaterialKit 玻璃材质、V1 状态管理），服务器端零改动，新增 1 个组件文件、修改 6 个页面文件。

## Technical Context

**Language/Version**: ArkTS（API 12+，barFloatingStyle/expandSafeArea 等已使用）
**Primary Dependencies**: 既有 UiMaterialKit（玻璃材质）、SymbolGlyph 系统图标、@kit.ArkData（不新增依赖）
**State Management**: 沿用项目 V1（@Component/@State/@Prop/@Link/@Watch），不引入 V2
**Storage**: 无新增持久化（纯 UI 层改动；扫码 URL 为运行时派生值）
**Testing**: arkts_check + devecocli build + 模拟器 UI 逐条验收（build+ui，用户要求逐项验收）
**Target Platform**: HarmonyOS 真机/模拟器（悬浮胶囊 TabBar 布局，MainPage contentBottomPad 体系）
**Project Type**: 既有应用增量 UI 精修
**Performance Goals**: 滑动胶囊切换动画流畅（animateTo，≤250ms）；列表滚动无卡顿（底部占位用空 ListItem，不加惰性负担）
**Constraints**: 服务器端零改动；message-tts 批次文件（MessageBubble 朗读链路/VoiceSettingsPage/LocalTtsService/AppPrefs/LocalTtsConfigDialog）不触碰；既有功能全量回归无损
**Scale/Scope**: 1 新增组件 + 6 页面修改，单用户端侧

## Project Structure

### Documentation (this feature)

```text
spec/ui-refine-batch/
├── spec.md
├── plan.md
└── tasks.md
```

### Source Code (repository root)

```text
entry/src/main/ets/
├── components/
│   └── CapsuleSegmentBar.ets          # [新增] 滑动胶囊分段控件（胶囊容器+滑块高亮+animateTo 滑动）
├── pages/
│   ├── chat/
│   │   └── ChatHomeTab.ets            # [修改][US1] 工具行/深度思考 pill 紧凑化；上下文 pill 锚定发送按钮左侧
│   ├── expert/
│   │   └── ExpertListPage.ets         # [修改][US2] 筛选 chips → CapsuleSegmentBar；列表底部占位 ListItem(bottomPad)
│   └── workspace/
│       ├── SkillsPage.ets             # [修改][US4] 新建/编辑/导入三弹窗版式统一
│       ├── PluginPage.ets             # [修改][US4] 市场/URL/工具三 sheet + 主体分区版式优化
│       ├── MemoryPage.ets             # [修改][US5] 记忆迁移 ActionSheet → bindSheet 双选项弹窗
│       └── ChannelPage.ets            # [修改][US3/US5/US6] 二维码 URL 拼接+失败态；接入渠道双卡优化；头像渐变
```

**Structure Decision**: 遵循项目既有架构（pages/components/service/model 分层），不引入 MVVM。滑动胶囊抽为独立 `components/CapsuleSegmentBar.ets`：它是可复用通用控件（专家页筛选、后续其他筛选场景均可用），且 ExpertListPage 已 552 行，内嵌会进一步膨胀；这是本批次唯一新文件。其余 6 处均为既有文件原位修改，符合最小拆分原则。

## Complexity Tracking

（无 Constitution Check 违规，无需说明）

## Research & Decisions

### R1: "设置层"范围界定与紧凑化策略（US1）

- **Decision**: "气泡的设置那层" = 输入气泡附属设置控件带：卡上方深度思考 pill（ChatHomeTab.ets 2500-2528）+ 卡底部工具行左侧设置控件（附件/润色/麦克风/模型 pill，2546-2633）。紧凑化手段：圆形按钮 38→34、行间距 8→6、模型 pill 高 34→30（padding 与 maxWidth 90→72 收紧）、深度思考 pill 高 30→28；上下文 pill（2637-2655）保持 Blank() 之后、发送按钮之前，间距收至 ≤6vp，并加 constraintSize({minWidth}) 防挤压。
- **Rationale**: 真机窗口 ~440vp 时 inputMaxWidth 取 320，工具行 38×3+模型 pill+上下文 pill+发送+间距 ≈ 339vp 溢出，上下文 pill 被挤压偏离右缘——即用户所见"太宽/数字不在右边"。收窄控件是最小改动解。
- **Alternatives considered**: 修 aboutToAppear 窗口宽刷新时序（曾实测 px2vp 时序问题，风险大、非本需求核心，弃）；把设置 pill 移出卡片成独立带（改动大，弃）。

### R2: 滑动胶囊实现选型（US2）

- **Decision**: 新增 `CapsuleSegmentBar` V1 组件：外层胶囊容器（radius 全圆、glassBg、border card_stroke、padding 3），内层 Row 等分选项段；选中段衬 brand 色（或 brand_light+brand 文字）圆角滑块，切换用 `animateTo({duration: 220, curve: Curve.easeOut})` 平移滑块位置（Stack 布局，滑块按段宽 translate）。接口：选项数组（label/value）、选中索引、onSelect 回调。
- **Rationale**: 系统 Tabs/SubTabBarStyle 样式不可控，无法匹配玻璃胶囊视觉语言；自绘滑块可控且复用性强。数据过滤逻辑（ExpertListPage.load/visibleAgents）不动。
- **Alternatives considered**: 保留 chips 仅加过渡动画（不满足"滑动胶囊"观感，弃）；Hds 组件库若已有等价分段胶囊则优先复用（实现时先查 hds 组件声明，有则用、无则自绘——以观感一致为准）。

### R3: 专家页底部遮挡修复方式（US2）

- **Decision**: 复用页内既有"占位 ListItem"模式（顶部 150 占位项 422-425 同构）：列表尾部加空 `ListItem().height(this.bottomPad).hitTestBehavior(HitTestMode.None)`。`@Prop bottomPad`（MainPage 传 contentBottomPad()）当前声明未用，直接接上；List 自身 padding bottom 保持 0。
- **Rationale**: contentStartOffset/contentEndOffset 在该页滚动回顶后失效（页内注释已注明真机实测），占位项随数据重建保留位置，是本项目已验证模式；bottomPad = floatingBarBottomMargin+68 恰好覆盖悬浮 TabBar+安全区。
- **Alternatives considered**: List padding bottom: bottomPad（expandSafeArea 下缘延伸时 padding 计算含安全区，行为不稳，弃）；Refresh 外层 margin（影响下拉刷新位置，弃）。

### R4: 二维码修复——URL 拼接与鉴权（US3）

- **Decision**: 参照 `MeTab.avatarFullUrl()`（MeTab.ets 61-72）既有模式新增派生方法：qrcode_url 为相对路径时拼服务器 baseUrl、按头像同款方式携带鉴权（access_token）；Image 增加 `.onError()` 置失败态；新增展示状态机 loading → loaded | failed，failed 态显示"二维码加载失败"文案+重试按钮（重试重设 Image src 或重新 generate）；generate 抛错时 sheet 显示错误文案+重新生成入口，不再纯 Loading；仅 token 无 qrcode_url 时显示验证码/等待态文案。
- **Rationale**: 全工程唯一 QR UI 在 ChannelPage，服务器返回 qrcode_url 本地加载；对照 MeTab.avatarFullUrl 与 AgentService 均有"相对路径+access_token"处理而 QR 缺失——即"码拿不到"的根因（相对 URL 直接交给 Image 静默失败、无 onError、无失败态）。
- **Alternatives considered**: 本地生成二维码（服务器契约是返回图址，本地化改动大且飞书/元宝流程不同，弃）；全局 HTTP 拦截改写（影响面大，弃）。

### R5: 弹窗版式统一标准（US4/US5）

- **Decision**: 以项目最佳实践弹窗为基准制定版式标准并在 6 处弹窗/sheet 落实：标题 16-17fp Medium 左对齐；内容区 Scroll+constraintSize({maxHeight})（防超高溢出与键盘遮挡）；TextInput 高 40-44/radius 12、TextArea minHeight 96；开关行高 44-48（标签左 Toggle 右）；按钮行主按钮高 40 渐变/brand 底胶囊、次按钮同高透明底、右对齐；区块间距 14-16、控件间距 10-12、内边距 20-24；sheet 保持 detents FIT_CONTENT + UiMaterialKit.sheet()。各弹窗仅调版式，不改提交逻辑与 API 调用。
- **Rationale**: "优化布局"无逐像素要求，以统一标准收敛为可验收口径；项目内已有成熟样式语言，最小学习成本。
- **Alternatives considered**: 逐弹窗自由发挥（不可验收，弃）；抽统一 DialogScaffold 组件（6 处弹窗结构差异大——CustomDialog vs bindSheet 混用，抽象成本高于收益，弃）。

### R6: 记忆迁移入口形态（US5）

- **Decision**: 将 showPortMenu 的 ActionSheet 升级为 bindSheet 半模态（sheetMode='port' 分发）：标题"记忆迁移"+副题"导出或导入 .hmpkg 记忆包"+两个选项行（图标 square_and_arrow_up / square_and_arrow_down、标题+说明、整行可点），选中分别调既有 exportPackage()/importPackage()。
- **Rationale**: ActionSheet 只有两行文字，无法承载图标与说明；bindSheet 与页内其他 sheet 视觉统一；导出/导入逻辑零改动。
- **Alternatives considered**: CustomDialog（页内 MemoryAtomEditDialog 模式也可，但 bindSheet 与工作台页其余半模态一致，取 sheet）；保留 ActionSheet 仅改文案（不满足"优化布局"，弃）。

### R7: 渠道头像美化（US6）

- **Decision**: platformBadge 映射扩展为 {label, 渐变色对[纯色→亮色], 文字色}：头像容器 44×44 radius 14 改为线性渐变背景（GradientDirection.RightBottom，品牌色→提亮色）+ 细描边（#33FFFFFF 内高光）+ 字母 18fp Bold 白字；未知 kind 回退灰渐变；禁用态 opacity 0.5 不变。服务器不提供头像（ChannelModel 仅 id/kind/name/enabled/runtime，已核实），此为最终形态而非过渡方案。
- **Rationale**: 无平台 logo 资源（resources/base/media 仅应用图标，sys.media 无平台品牌图），渐变+字母是无需新增资源的高质量占位；品牌色对沿用现有六平台色值。
- **Alternatives considered**: 下载平台 logo PNG 入 resources（版权与包体问题，弃）；保留纯色仅换色（不满足"不好看"诉求，弃）。

## Data Model

### ExpertFilterOption（既有，不改结构）

label/value 两字段；渲染容器由 chips Row 换为 CapsuleSegmentBar，`filterOptions()` 构造逻辑不变（全部0/运行中1/未运行2/全部用户3[admin]）。

### QrSessionModel 展示态（ChannelPage 页内新增 @State，不改模型类）

| 状态 | 含义 | UI |
|------|------|-----|
| loading | generate 已发/图未加载 | LoadingProgress+状态文字 |
| loaded | qrFullUrl 非空且 Image 加载成功 | 210×210 白底二维码 |
| failed | generate 抛错 或 Image onError | 失败文案+重试按钮（重新 generate） |

派生值 `qrFullUrl: string` = qrcode_url 相对路径时 baseUrl 拼接+鉴权参数（MeTab.avatarFullUrl 同款规则）。

### platformBadge 扩展（ChannelPage 页内映射，不改类）

kind → { label: string, mainColor: string, lightColor: string }：dingtalk #1677FF→#69B4FF、wecom #00B96B→#67E0A8、qq #12B7F5→#7ADCFF、weixin #07C160→#6BDD9B、feishu #3370FF→#8AA8FF、yuanbao #FF7D00→#FFB366；未知 kind 回退 #7F7F7F→#B2B2B2。

### CapsuleSegmentBar 组件接口（新组件）

选项数组（label/value 泛化为 string 标签+number/string 值）、选中索引、onSelect(索引) 回调；滑块位移动画 220ms easeOut；组件无业务状态、不持久化。

## Contracts & Interfaces

### CapsuleSegmentBar（components/CapsuleSegmentBar.ets，新增 @Component V1）

```
入参: options: Array<SegmentOption>（label+value）、selectedIndex: number、onSelect: (index: number) => void
渲染: 胶囊容器(glassBg+border) → 等分段 Row → Stack 滑块(brand 底圆角) translate 动画到选中段
约束: 高度 36-40；选项 2-5 个；宽度随内容或 100% 由调用方指定；不依赖外部状态管理
```

### ChatHomeTab 工具行契约（pages/chat/ChatHomeTab.ets 修改，US1）

- 圆形按钮 38→34、Row space 8→6、模型 pill 高 34→30、深度思考 pill 高 30→28（间距/内边距同步收紧）
- 上下文 pill：保持 Blank() 后、发送按钮前，与发送按钮间距 ≤6vp，加 minWidth 防挤压；三态（<70% 绿/<90% 黄/≥90% 红）与点击开 contextSheet 不变
- 发送/停止按钮（40）与全部 onClick 逻辑不变；流光 overlay、onAreaChange 量尺寸链路不变

### ExpertListPage 契约（pages/expert/ExpertListPage.ets 修改，US2）

- searchFilterBuilder 非搜索态：chips Row → `CapsuleSegmentBar({options: filterOptions(), selectedIndex: filterIndex, onSelect})`，选中回调内复用现有 `filterIndex` 切换+`load()` 调用
- List 尾部新增占位 `ListItem().height(this.bottomPad).hitTestBehavior(HitTestMode.None)`（bottomPad prop 已由 MainPage 传入）
- 搜索态 TextInput、下拉刷新、agentCard、长按菜单全部不变

### ChannelPage 契约（pages/workspace/ChannelPage.ets 修改，US3/US5/US6）

- 新增私有派生方法 qrFullUrl()：相对路径拼接 baseUrl+鉴权（实现前先读 MeTab.avatarFullUrl 61-72 与 HttpClient 的 baseUrl/token 获取方式，完全同款规则）
- qrSheetBuilder：状态机 loading/loaded/failed；Image(qrFullUrl).onError(→failed)；failed 态"二维码加载失败"+重试（重新 startQr/generate）；generate 仅回 token 无 url 时显示验证码等待态；轮询逻辑不变
- accessModeBuilder 双卡：图标尺寸/标题/副题/间距/整卡可点优化，openCreateSheet 与 sheetMode='qr' 分发不变
- platformBadge 渐变映射+列表项头像渐变渲染；enabled=false opacity 0.5 不变；长按菜单/启停/删除/测试全部不变

### SkillsPage 契约（pages/workspace/SkillsPage.ets 修改，US4）

- SkillCreateDialog/SkillEditDialog/SkillImportDialog：按 R5 版式标准重排（标题/输入/开关行/按钮行/间距/内容可滚动），提交与 API 调用（SkillService.create/update/importSkill）不变
- FAB/ActionSheet 添加菜单/hub 搜索安装不变

### PluginPage 契约（pages/workspace/PluginPage.ets 修改，US4）

- marketBuilder/urlBuilder/toolsBuilder 三 sheet 按 R5 标准重排；主体"全局插件/此专家插件"分区标题、列表行、Toggle、长按卸载布局优化；GlobalPluginService/PluginService 调用与 confirmForceInstall/confirmUninstall 流程不变

### MemoryPage 契约（pages/workspace/MemoryPage.ets 修改，US5）

- showPortMenu ActionSheet → bindSheet('port')：标题+副题+导出/导入两选项行（图标+标题+说明），点击分别调既有 exportPackage()/importPackage()；MemoryService.pack/adopt、DocumentViewPicker 流程不变；MemoryAtomEditDialog/MemoryPrefsDialog 不动

### 外部系统契约（只读依赖，零改动）

- 服务器 /api/channels/*、/api/skills/*、/api/plugins/*、/api/agents/*、/api/providers/resolved：全部既有端点原样调用
- qrcode_url 的 URL 形态以运行时服务器返回为准，相对/绝对均兼容处理
