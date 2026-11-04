# Implementation Plan: 第五批精修+排障（ui-refine-batch-4）

**Input**: Feature specification from `spec/ui-refine-batch-4/spec.md`

## Summary

6 项客户端修复与精修：①全局默认模型点击无反应——第四批把 Provider 编辑表单的 bindSheet 链到了与模型选择 bindSheet 相同的根节点，同节点多次链 bindSheet 后者生效前者失效（实证：编辑表单正常、模型选择死掉）；改用 PluginPage 已验证的"单 bindSheet 分发"模式（一个 open 布尔 + mode 分发 builder）。②技能市场进入即展示——市场标签初始空态需手动搜索；进入时自动调 `GET /api/agents/{id}/skills/hub/rankings?type=recommended`（返回 {section, skills, total}，skills 含 iconUrl 富字段）展示推荐榜单，搜索行为保留。③市场头像——HubSkillModel 丢弃了服务端透传的图标字段；新增 iconUrl 解析（榜单键 'iconUrl'、搜索键 'icon_url' 两键兼容），列表项渲染网络 Image，失败回退通用图标。④手机工具不可用提示——服务端 `builtin_tool_available` 仅在 `capabilities.mobile.enabled` 时放行 mobile_* 工具（tool_catalog.py L197-198），用户服务器该能力未开启属服务器配置；客户端调用 `GET /api/mobile/status`（require_permission("mobile")，返回 ok/mobile_supported/reason/devices）展示语义化原因，失败回退通用文案。⑤使用说明扩写——HelpPage 五节一句话文案扩为 ≥6 节详细分步指南。⑥token 用量与操作按钮平齐——用量从操作行下方独立行移入操作行（按钮居左 + Blank + 用量靠右，垂直居中）。全部仅客户端，服务器零改动。

## Technical Context

**Language/Version**: ArkTS（HarmonyOS API 26+，SDK 6.0.5）
**Primary Dependencies**: ArkUI（bindSheet 半模态、Image 网络图、Scroll/List、SymbolGlyph）、http@kit.NetworkKit（复用 HttpClient）
**State Management**: 保留项目现有 State Management V1（@Component/@State），不迁移 V2
**Storage**: 无新增持久化；技能市场榜单不做本地缓存（每次进入拉取，服务端有上游缓存）
**Testing**: devecocli build + 模拟器（127.0.0.1:5555）坐标验证 + uitest dumpLayout 布局断言 + VLM 截图分析 + hilog 日志
**Target Platform**: HarmonyOS 模拟器（验证环境）；真机复验由用户进行
**Project Type**: mobile-app（既有工程增量改动）
**Performance Goals**: 市场标签进入 ≤3s 出列表（网络正常）；帮助页滚动流畅；市场列表滚动图片加载平稳
**Constraints**: 服务器端零改动；不回归前四批已交付功能（导航栏系统 TabBar、渠道 Logo、TTS 三态、QR、MenuSheet、气泡按钮 20% 放大、语音 422 修复等）；ArkTS 严格模式编译通过
**Scale/Scope**: 6 个用户故事，涉及 5 个既有文件修改 + 1 个模型文件扩展 + 1 个 service 方法新增，无新文件

## Project Structure

### Documentation (this feature)

```text
spec/ui-refine-batch-4/
├── spec.md              # Feature specification
├── plan.md              # This file
└── tasks.md             # Task breakdown
```

### Source Code (repository root)

```text
entry/src/main/ets/
├── model/
│   └── SkillModels.ets              # US3: HubSkillModel 增加 iconUrl 字段（兼容 iconUrl/icon_url 两键）
├── service/
│   └── SkillService.ets             # US2: 新增 hubRankings(agentId, type)（GET /api/agents/{id}/skills/hub/rankings）
├── pages/
│   ├── me/
│   │   ├── ProvidersPage.ets        # US1: modelSheetOpen/formOpen 双 bindSheet 合并为单 bindSheet 分发
│   │   └── HelpPage.ets             # US5: 使用说明扩写（≥6 节详细分步）
│   └── workspace/
│       ├── SkillsPage.ets           # US2/US3: 市场标签进入自动加载推荐榜单；列表项渲染 iconUrl 网络头像
│       └── ToolSettingsPage.ets     # US4: 不可用 mobile_* 工具展示 /api/mobile/status 的 reason 提示
└── components/
    └── MessageBubble.ets            # US6: 用量移入操作行内与按钮平齐（右对齐、垂直居中）
```

**Structure Decision**: 遵循既有工程架构（pages/components/service/model 分层），本批全部为既有文件增量修改，不新增文件、不引入 MVVM、不迁移状态管理。

## Complexity Tracking

> 无 Constitution Check 违规，无需填写。

## Research & Decisions

- **Decision 1（US1 双 bindSheet 覆盖根因与修法）**: ProvidersPage 根节点当前链了两个 bindSheet（L891 modelSheetOpen + L897 formOpen，第四批引入），同节点重复链 bindSheet 后者生效前者失效（官方 FAQ faqs-arkui-1375 佐证同组件多转场绑定会"不生效或逻辑混乱"；实证：后链的编辑表单正常、先链的模型选择点击无反应）。修法采用本代码库 PluginPage 已验证的"单 bindSheet 分发"模式：保留一个 open 布尔 + sheetMode 分发（'model' | 'form'），builder 按 mode 渲染 ModelPickerSheet 或表单，两个半模态天然互斥；菜单 bindSheet（menuOpen，挂在内容节点）不受影响。
  **Rationale**: 修复回归的最小且已验证方案；避免同节点多 bindSheet 的未定义行为。
  **Alternatives considered**: 把两个 bindSheet 拆到两个不同常驻节点（两处挂载点、状态同步复杂）；恢复 formOpen 挂回条件 FAB（第四批刚因时序冲突移走，回退不可取）。

- **Decision 2（US2 市场默认榜单）**: 市场标签进入时（segIndex 切到 1 或页面就绪即市场态）自动调用新增的 `SkillService.hubRankings(agentId, 'recommended')`（`GET /api/agents/{id}/skills/hub/rankings?type=recommended`，服务端 `_hub_rankings` 返回单分区 {section, skills, total}），展示推荐榜单；搜索仍走现有 hubSearch 覆盖列表；榜单/搜索共用列表渲染，各自加载态/错误态独立。
  **Rationale**: 服务端已提供 rankings 端点（skills.py L1478-1496，agent 路径与全局路径均可）；推荐榜单内容质量高于空关键词搜索（服务端空 q 回退搜"a"，结果不可控）；dashboard 的 SkillHubTab 默认视图同样是 rankings（recommended 激活），保持两端体验一致。
  **Alternatives considered**: 进入时自动 hubSearch('')（服务端把空 q 当"a"搜索，榜单内容差）；本地缓存榜单（首版从简，服务端有上游缓存）。

- **Decision 3（US3 市场头像）**: HubSkillModel 新增 `iconUrl` 字段，fromRecord 兼容解析 'iconUrl'（rankings/showcase 响应键，实测样例）与 'icon_url'（search 响应键，实测样例）两键；市场列表项 42×42 徽章优先渲染 `Image(iconUrl)` 网络图（borderRadius 裁剪、alt 失败回退通用魔法棒图标）；"我的技能"列表不动（emoji 优先逻辑保持）。
  **Rationale**: 实测 SkillHub 两个端点均返回 CDN 图标 URL（cloudcache.tencent-cloud.com 等），服务端 `item = dict(raw)` 原样透传，客户端此前解析时丢弃；补字段即可恢复头像。
  **Alternatives considered**: 本地 slug→emoji 映射兜底（dashboard 有 builtinSkillIcon 本地映射，但网络真图更准确，本地映射只做回退不需要）。

- **Decision 4（US4 手机工具不可用提示）**: ToolSettingsPage 加载列表后，若存在 `available=false` 且 name 以 `mobile_` 开头的工具，则调用 `GET /api/mobile/status`（require_permission("mobile")，返回 {ok, mobile_supported, reason, devices, ...}，reason 为服务端本地化文案如"此主机不支持远程手机。"），在这些工具卡片下方（或分组处）展示灰色小字原因；请求失败/无权限时回退通用文案"服务器未启用远程手机能力，请在服务器配置中开启后重试"。
  **Rationale**: 服务端 `builtin_tool_available`（tool_catalog.py L197-198）对 _MOBILE_TOOLS 仅在 `server.config.capabilities.mobile.enabled` 为真时返回可用——用户服务器该能力未开启，工具显示"不可用"是服务端如实的状态而非客户端 bug；/api/mobile/status 是服务端已有的状态自省端点（status.py L37-67），reason 字段就是给用户看的解释。客户端无法"修好"服务器能力，但可以告知用户原因与解法（服务器开启 capabilities.mobile + 接 adb 设备）。
  **Alternatives considered**: 客户端硬编码"需服务器开启远程手机"文案（丢失 status 端点更精确的原因，如 adb 未连接 vs 主机不支持）；不做处理仅口头解释（用户下次仍困惑）。

- **Decision 5（US5 帮助页扩写）**: HelpPage 保持 HelpSection（title/body）结构与卡片式 UI，sections 内容整体重写扩为 6+ 节：快速开始（服务器配置/登录分步）、聊天详解（消息收发/附件/语音输入/朗读/会话切换/长按菜单/用量含义）、专家与团队、工作台（渠道/知识库/技能与市场/插件/连接器/定时任务/用量统计逐项）、我的与设置（外观/沉浸光感/模型配置/语音设置/用户管理）、常见问题（422 与网络错误/权限不足/手机工具不可用/语音仅浏览器等排查）。每节含编号步骤与入口路径。
  **Rationale**: 用户点名"太简单"；纯本地静态扩写零风险；文案中的入口路径与现有 App 导航一致。
  **Alternatives considered**: 引入富文本/图文混排（超出需求且需资源）；接入在线文档（引入网络依赖，违背纯本地设计）。

- **Decision 6（US6 用量平齐）**: MessageBubble 助手气泡：把操作行下方独立的用量 Row（L485-497，alignSelf(ItemAlign.End)）移除，用量两个 Text 并入操作 Row（L429-484）——三按钮后加 `Blank()`（或 layoutWeight 占位）再放用量 Text，Row 垂直居中（默认 alignItems VerticalAlign.Center），实现"按钮居左、用量靠右、同行平齐"；无用量时右侧为空。按钮尺寸/交互（24/14、复制/朗读三态/重试）全部不动。
  **Rationale**: 用户点名"token使用量和前面的按钮平齐"——同 Row 垂直居中即视觉平齐；移除独立行还减少一行占位。
  **Alternatives considered**: 保持独立行但调 margin 对齐（仍不同行，不满足"平齐"字面要求）。

## Data Model

- **HubSkillModel（US3，扩展）**: 新增 `readonly iconUrl: string`；fromRecord 解析顺序 `JsonHelper.getString(rec, 'iconUrl', '')` 为空再取 `'icon_url'`（两键兼容：rankings 用 camelCase、search 用 snake_case——均实测确认）；其余字段（slug/name/description/version）与 parseList/trySection 解析路径不变。
- **HubRankingSectionModel（US2，复用既有）**: section/skills/total 结构已实现（parseSections 支持 type=具体榜单时顶层即分区对象），本批仅补 UI 消费路径（type=recommended 返回单分区）。
- **SheetMode 状态机（US1，纯 UI 状态）**: ProvidersPage 以 `sheetMode: string`（'' | 'model' | 'form'）+ 单一 open 布尔驱动根节点唯一 bindSheet，builder 按 mode 分发 modelSheetBuilder/formSheetBuilder；menuOpen 菜单 bindSheet 独立不变。
- **MobileStatus（US4，只读展示）**: 不建完整模型类，JsonHelper 直接解析响应中的 `reason`（string）与 `ok`/`mobile_supported`（bool）字段用于提示文案。
- **HelpSection（US5，内容扩展）**: title/body 结构不变，sections 数组内容重写扩充。
- **MessageBubble 操作行（US6，布局调整）**: 无数据结构变化；usageIn/usageOut 字段不变，仅渲染位置并入操作 Row。

## Contracts & Interfaces

- **SkillService.hubRankings（US2，新增）**: `static async hubRankings(agentId: string, type: string): Promise<Array<HubRankingSectionModel>>` —— `GET /api/agents/${agentId}/skills/hub/rankings?type=${type}`（type=recommended）；响应为单分区对象 {section, skills, total}，复用 `HubRankingSectionModel.parseSections` 解析；skills 内含 iconUrl 富字段；鉴权走 HttpClient 既有 Bearer 头。
- **HttpClient（既有，不变）**: get 路径带 query 的调用方式与现有 hubSearch 一致；不改动任何网络层代码（第四批 Content-Type 修复保持）。
- **GET /api/mobile/status（US4，只读消费）**: 响应字段 ok/mobile_supported/setup_state/reason/adb_available/devices（reason 为服务端本地化字符串）；require_permission("mobile")——403/失败时客户端回退通用文案，不抛错阻断页面。
- **ProvidersPage bindSheet 分发（US1）**: 根节点单 bindSheet（open + builder 按 mode 'model'|'form' 分发），SheetOptions 沿用各自现有配置（model: detents [MEDIUM, LARGE]；form: detents [LARGE]；均 systemMaterial: UiMaterialKit.sheet()、showClose）；openActiveModelPicker 置 mode='model' 后 open=true；openEditForm/openCreateForm 置 mode='form' 后 open=true；保存/关闭统一置 open=false。
- **市场标签生命周期（US2）**: segIndex 切到 1 且未搜索且未加载过榜单时自动触发 hubRankings('recommended')；hubSearched=true 后以搜索结果为准；下拉刷新重新加载当前视图（榜单或搜索）。
- **UI 布局契约（US6）**: 助手气泡操作 Row：三按钮（24×24）+ Blank + 用量 Text（fontSize 10、text_tertiary），Row 垂直居中；无用量时 Blank 收尾不占额外高度。
