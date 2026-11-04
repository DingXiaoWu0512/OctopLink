# Feature Specification: 第五批精修+排障（技能市场直出榜单/市场头像/手机工具不可用提示/使用说明详细化/全局默认模型点击修复/token用量与按钮平齐）

**Created**: 2026-10-29
**Status**: Approved
**Input**: User description: "技能市场页面现在要点一下搜索才会出来，改成直接就有，技能市场的头像都是空的。检查一下工具开关里带手机的都不能用。使用说明写的太简单，写的详细一些。模型配置里的全局默认模型点击没用。token使用量和前面的按钮平齐。"

## Overview

本批为 6 项精修与修复，全部客户端改动、服务器端零改动：①技能市场页进入即直接展示技能列表（默认拉取推荐榜单，不再需要先点搜索），搜索仍可用于关键词过滤；②技能市场列表项显示各技能的真实头像图标（SkillHub 注册表返回 iconUrl/icon_url CDN 图片，当前客户端模型丢弃了该字段导致全部显示通用占位图标）；③工具开关页中"手机"系列工具（手机截图/点击/滑动/启动应用/界面结构/交给用户操作）当前全部"不可用"——已确证为服务器 `capabilities.mobile` 能力开关未启用所致（服务端 `builtin_tool_available` 仅在 mobile_enabled 时放行），属服务器配置而非客户端缺陷；客户端补"不可用原因"提示（调用 `GET /api/mobile/status` 展示服务端返回的语义化 reason，如"此主机不支持远程手机。"），让用户明白为何不可用及如何解决；④使用说明页从 5 节简略文案扩写为详细的分步操作指南（覆盖登录/聊天/专家/工作台/我的/常见问题）；⑤修复模型配置页"全局默认模型"卡片点击无反应——第四批将编辑表单 bindSheet 链到了与模型选择 bindSheet 相同的根节点上，同节点后链的 bindSheet 使先链的失效（编辑表单正常、模型选择死掉即为实证），改用本代码库已验证的"单 bindSheet 分发"模式；⑥助手气泡 token 用量从操作行下方独立行移入操作行内、与复制/朗读/重试按钮同一行并垂直居中平齐（按钮居左、用量靠右）。

## User Scenarios & Testing *(mandatory)*

### User Story 1 - 全局默认模型点击恢复 (Priority: P1)

用户在模型配置页点击"全局默认模型"卡片，模型选择半模态正常弹出，选择模型后保存成功并回显；同时"编辑 Provider 表单"半模态仍正常工作（第四批功能不回归）。

**Why this priority**: 功能性故障——第四批引入的回归，全局默认模型入口完全失效。

**Independent Test**: 进入 我的→模型配置，点击"全局默认模型"卡→模型选择面板弹出；选一个模型→toast"全局默认模型已保存"、卡片右侧回显 provider/model；再验证长按 provider→编辑→表单仍正常打开。

**Acceptance Scenarios**:

1. **Given** 模型配置页（有 providers 权限），**When** 点击"全局默认模型"卡片，**Then** 模型选择半模态弹出（可滚动选择 provider/model）。
2. **Given** 弹出的模型选择面板，**When** 选择某模型，**Then** 面板关闭、toast"全局默认模型已保存"、卡片右侧显示 provider/model。
3. **Given** provider 卡片长按菜单，**When** 点"编辑"，**Then** 编辑表单仍正常打开并预填（第四批功能无回归）。
4. **Given** 无 providers 权限用户，**When** 点击卡片，**Then** 提示"需要 providers 权限"（只读行为不变）。

---

### User Story 2 - 技能市场进入即展示列表 (Priority: P1)

用户进入技能页切到"技能市场"标签（或进入页面直接是市场标签）时，无需任何操作即可看到技能列表（默认为推荐榜单数据），带加载态与失败重试；搜索框仍在，输入关键词搜索后切换为搜索结果；清空/重新进入仍先展示默认榜单。

**Why this priority**: 用户点名的可用性问题——市场页初始为空态，必须手动搜索才有内容，像坏了一样。

**Independent Test**: 进入 技能页→点"技能市场"标签→列表自动加载出现（无需点搜索）；下拉刷新可用；搜索"pdf"显示搜索结果。

**Acceptance Scenarios**:

1. **Given** 技能页市场标签（未搜索过），**When** 切入该标签，**Then** 自动发起默认榜单请求（`GET /api/agents/{id}/skills/hub/rankings?type=recommended`），加载中显示 Loading，成功后展示技能列表（含名称/描述/头像/安装按钮）。
2. **Given** 榜单加载失败（网络错误/502），**When** 查看市场标签，**Then** 显示错误重试视图（ErrorRetry），点重试重新加载，不再退回"搜索技能市场"空态。
3. **Given** 已展示默认榜单，**When** 输入关键词点搜索，**Then** 列表切换为搜索结果（现有 hubSearch 行为保留）。
4. **Given** 搜索结果为空或清空关键词后重新进入市场标签，**When** 再次进入，**Then** 仍优先展示默认榜单（未被空搜索态覆盖）。
5. **Given** 未选择专家（无 agentId），**When** 进入技能页，**Then** 现有"未选择专家"错误提示保持。

---

### User Story 3 - 技能市场头像显示 (Priority: P2)

技能市场列表每个技能项左侧 42×42 圆角徽章显示该技能的真实头像图标（SkillHub CDN 图片，来源字段 iconUrl/icon_url）；无图标或图片加载失败时回退现有通用魔法棒图标，不空白不报错；"我的技能"列表图标行为不变（emoji 优先）。

**Why this priority**: 用户点名"头像都是空的"——模型丢弃了服务端透传的图标字段。

**Independent Test**: 市场列表加载后，各技能项显示各自 CDN 头像（多数字段非空）；断网图片加载失败时显示通用图标。

**Acceptance Scenarios**:

1. **Given** 默认榜单/搜索结果中带 iconUrl 的技能，**When** 查看市场列表，**Then** 该项左侧显示对应网络图片头像（42×42 圆角裁剪）。
2. **Given** 无 iconUrl 的技能项或图片加载失败，**When** 查看，**Then** 回退通用魔法棒图标占位（现有样式），不空白。
3. **Given** "我的技能"列表，**When** 查看，**Then** 图标行为保持不变（emoji 优先、无 emoji 通用图标）。
4. **Given** 市场列表滚动，**When** 快速上下滚动，**Then** 图片加载平稳、无错位闪烁严重问题（列表复用正常）。

---

### User Story 4 - 手机工具"不可用"原因提示 (Priority: P2)

用户在工具开关页看到"手机截图/手机点击/手机滑动/启动手机应用/手机界面结构/交给用户操作（手机）"等工具显示"不可用"时，页面给出明确原因说明（服务端 `GET /api/mobile/status` 返回的语义化 reason，如"此主机不支持远程手机。"或"没有已连接的 adb 设备…"），让用户知道这是服务器侧能力/设备未就绪，而非 App 故障；工具开关其余行为（可用工具的开关、插件工具）不变。

**Why this priority**: 用户要求"检查一下"——已确证服务端 `builtin_tool_available` 对 mobile_* 系列工具仅在 `capabilities.mobile.enabled` 时返回可用（tool_catalog.py），当前用户服务器该能力未启用，属服务器配置；客户端补全"为什么不可用"的信息披露。

**Independent Test**: 进入 工作台→工具开关，手机系列工具卡片显示"不可用"标记及下方灰色小字原因说明（来自 /api/mobile/status 的 reason）；可用工具照常可开关。

**Acceptance Scenarios**:

1. **Given** 工具开关页存在 mobile_* 工具且 available=false，**When** 列表加载完成，**Then** 页面调用 `GET /api/mobile/status`，在手机工具分组附近或每个不可用手机工具卡片上展示服务端 reason（本地化文案）。
2. **Given** /api/mobile/status 请求失败或无权限（403），**When** 查看，**Then** 回退显示通用提示"服务器未启用远程手机能力，请在服务器配置中开启"（不崩溃、不阻断页面）。
3. **Given** 服务器后来启用了 mobile 能力，**When** 重新进入工具开关页，**Then** 手机工具变为可用可开关（available=true 走现有渲染路径，提示不显示）。
4. **Given** 非手机类不可用工具（如有），**When** 查看，**Then** 保持现有"不可用"徽章渲染，不误显示手机类原因。

---

### User Story 5 - 使用说明详细化 (Priority: P2)

使用说明页从当前 5 节一句话式文案扩写为详细分步指南：每个功能模块展开为具体操作步骤、入口路径、注意事项与常见问题（如：登录与服务器配置步骤、聊天发送/附件/语音/朗读/会话管理、专家创建与配置、渠道接入方式、知识库上传、技能/插件/定时任务、外观与沉浸光感、模型配置、语音设置、用量统计、遇到 422/网络错误怎么排查等），页面结构保持卡片式分节、可滚动，纯本地静态内容。

**Why this priority**: 用户点名"写的太简单，写的详细一些"。

**Independent Test**: 打开 我的→使用说明，可见明显更详细的分节内容（节数≥6、每节含编号步骤/要点，覆盖核心功能），滚动流畅无截断。

**Acceptance Scenarios**:

1. **Given** 使用说明页，**When** 打开，**Then** 至少包含：快速开始（含服务器配置与登录详细步骤）、聊天详解（消息/附件/语音/朗读/会话切换/用量含义）、专家与团队、工作台各功能（渠道/知识库/技能与市场/插件/连接器/定时任务/用量）、我的与设置（外观/沉浸光感/模型配置/语音设置）、常见问题排查 六大块。
2. **Given** 每节内容，**When** 阅读，**Then** 含具体入口路径（如"我的 → 服务器设置"）与操作步骤（编号列表），不再是单行概述。
3. **Given** 帮助页，**When** 上下滚动，**Then** 卡片布局正常、长文案完整显示不截断、滚动流畅。
4. **Given** 离线状态，**When** 打开使用说明，**Then** 全部内容可读（纯本地静态，无网络依赖）。

---

### User Story 6 - token 用量与操作按钮平齐 (Priority: P3)

助手气泡内 token 用量（↑输入 ↓输出）从操作行下方的独立行移入操作行：与复制/朗读/重试按钮同一行，按钮居左、用量靠右、垂直居中平齐；无用量数据时操作行右侧不显示不占位；按钮尺寸与交互不变。

**Why this priority**: 用户点名"token使用量和前面的按钮平齐"——当前用量在按钮下方独立一行，视觉上多占一行且不齐。

**Independent Test**: 打开带用量的对话，气泡底部一行内：左三个操作按钮、右 ↑/↓ 用量，垂直居中对齐；无用量消息操作行右端为空。

**Acceptance Scenarios**:

1. **Given** 带用量的助手消息，**When** 查看气泡底部，**Then** 操作行内左侧为复制/朗读/重试三按钮、右侧为 ↑/↓ 用量文本，二者同一行且垂直居中平齐。
2. **Given** 气泡内容区，**When** 查看操作行下方，**Then** 不再有独立的用量行。
3. **Given** 无用量数据的历史消息，**When** 查看，**Then** 操作行右侧无用量、不占位。
4. **Given** 复制/朗读（三态）/重试按钮，**When** 依次点击，**Then** 功能正常无回归。

---

### Edge Cases

- 市场榜单与搜索共用列表渲染：切换时加载态/空态/错误态互不串扰（搜索失败不影响已展示榜单）。
- 网络头像 URL 为 http/https CDN 域名，加载失败静默回退（不留破图占位）。
- mobile/status 无权限（用户无"远程手机"权限）时提示回退，不影响工具列表本身加载。
- 模型选择与编辑表单两个半模态互斥（同一时刻只开一个），单 bindSheet 分发天然保证。
- 帮助页文案量增大后长文本换行与行高正常，深色模式下颜色资源复用现有 token。

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: 模型配置页 MUST 通过单一 bindSheet 分发承载"模型选择"与"Provider 编辑表单"两个半模态（互斥状态机），修复全局默认模型点击无反应的回归。
- **FR-002**: 技能市场标签 MUST 在进入时自动加载默认榜单（rankings type=recommended），无需用户点击搜索；加载失败展示错误重试。
- **FR-003**: 技能市场列表项 MUST 显示技能真实头像（解析 iconUrl/icon_url 网络图片），缺失/失败回退通用图标。
- **FR-004**: 工具开关页 MUST 对不可用的 mobile_* 工具展示服务端原因（/api/mobile/status 的 reason），请求失败回退通用文案。
- **FR-005**: 使用说明页 MUST 扩写为详细分步指南（≥6 节，含入口路径与操作步骤），保持纯本地静态内容。
- **FR-006**: 助手气泡 token 用量 MUST 移入操作行内与按钮同行右对齐、垂直居中平齐，无数据不占位。
- **FR-007**: 上述改动 MUST NOT 破坏既有功能：Provider 编辑/测试/启停/删除、技能安装/新建/编辑/导出、工具开关可用项的启停、聊天 TTS 朗读三态、复制、重试。

### Key Entities

- **HubSkillModel（技能市场项）**：新增 iconUrl 字段（解析 'iconUrl' 或 'icon_url' 两键，榜单与搜索响应键名不同）；slug/name/description/version 不变。
- **HubRankingSectionModel（榜单分区）**：已存在（section/skills/total 解析），本批补 service 调用与 UI 使用。
- **SkillService**：新增 hubRankings(agentId, type) 方法（GET /api/agents/{id}/skills/hub/rankings?type=recommended）。
- **ToolSettingsPage + mobile status**：新增对 GET /api/mobile/status 的只读调用（ok/mobile_supported/reason/devices），仅用于不可用提示展示。
- **ProvidersPage sheet 状态机**：由 modelSheetOpen/formOpen 两个布尔合并为单一分发（open 时按 mode 选 builder），修复同节点双 bindSheet 覆盖问题。
- **HelpSection（帮助分节）**：结构不变（title/body），内容扩写。

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: 全局默认模型点击 100% 弹出选择面板，保存后回显正确；Provider 编辑表单同时 100% 正常（两入口各连续 10 次无失败）。
- **SC-002**: 进入市场标签 ≤3 秒内出现默认列表（网络正常时）；失败时出现重试视图。
- **SC-003**: 市场列表头像显示率：有 iconUrl 的项 100% 显示网络头像（加载失败回退除外）。
- **SC-004**: 手机工具不可用时 100% 展示原因提示（服务端 reason 或回退文案）。
- **SC-005**: 帮助页节数 ≥6 且每节含步骤化内容。
- **SC-006**: 气泡操作行与用量同行平齐，无独立用量行；三按钮功能无回归。
- **SC-007**: 本批 6 项逐条验收通过（6/6）。

## Assumptions

- 服务器端零改动；服务端源码（本地缓存）仅作契约参考。
- 手机工具不可用的根因是服务器 `capabilities.mobile.enabled` 未开启（tool_catalog.py L197-198 已确证判定逻辑）；是否开启由用户在服务器配置决定，本批仅做客户端信息披露，验收"手机工具可用"本身不在本批范围（需用户自行开启服务器能力+接入 adb 设备）。
- SkillHub 榜单/搜索响应中 iconUrl/icon_url 为 CDN 图片 URL（已实测样例）；应用已有网络权限与 Image 网络图能力。
- `/api/mobile/status` 需要"远程手机"权限（require_permission("mobile")）；普通用户 403 时客户端回退通用文案。
- 单 bindSheet 分发模式已在 PluginPage（market/url/tools 分发）验证可行。
- 本批不改动第四批已交付的导航栏/渠道 Logo/气泡按钮尺寸（20%/间距调整保持）。

## Open Questions

- （无——6 项根因均已定位：模型选择 bindSheet 被同节点后链覆盖、市场无默认数据加载、HubSkillModel 丢 iconUrl 字段、mobile 工具受服务器能力开关控制、帮助文案过简、用量独立成行）
