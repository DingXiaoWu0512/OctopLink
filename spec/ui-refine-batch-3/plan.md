# Implementation Plan: 第四批精修+排障（ui-refine-batch-3）

**Input**: Feature specification from `spec/ui-refine-batch-3/spec.md`

## Summary

8 项客户端精修与修复：①语音识别 422——根因为 `HttpClient.postMultipartFile` 的 header 未设置 `Content-Type: multipart/form-data`，官方文档确证 `multiFormDataList` 仅在该头存在时生效，导致 multipart 体未发出、FastAPI 返回 422；在 header 中补一行即修复全部 13 处 multipart 调用（语音/头像/附件/工作区/技能包）。②导航栏光感——自绘导航栏无法承载沉浸光感（官方确证仅 Navigation 标题栏与横向 Tabs 底部 TabBar 支持），还原系统 Tabs 底部 TabBar 并用 `FloatingTabBarStyle`（barFloatingStyle，API 26+）挂载 `UiMaterialKit.navBarMaterial()`，删除自绘栏与键盘下沉动画。③ProvidersPage 卡片补单击弹菜单。④渠道列表按 kind 渲染品牌 Logo（dashboard 同源资源复制进 app resources/base/media）。⑤气泡 token 用量移入框内右下角。⑥操作按钮放大 20%/底距缩小 20%。⑦输入卡边距 12→16 对齐系统 TabBar。⑧新会话按钮对齐发送按钮并抬高。全部改动仅客户端，服务器零改动。

## Technical Context

**Language/Version**: ArkTS（HarmonyOS API 26+，SDK 6.0.5）  
**Primary Dependencies**: ArkUI 系统组件（Tabs/TabContent/FloatingTabBarStyle、Image、http@kit.NetworkKit、AVRecorder）、本地 SVG/PNG 媒体资源  
**State Management**: 保留项目现有 State Management V1（@Component/@State/@StorageLink/@Provide/@Consume），本批不迁移 V2  
**Storage**: 无新增持久化；现有 AppStorage/LocalStorage/AppPrefs 不变  
**Testing**: devecocli build + 模拟器（127.0.0.1:5555）人工/坐标验证 + hilog 日志验证 + uitest dumpLayout 布局断言 + VLM 截图分析  
**Target Platform**: HarmonyOS 模拟器（验证环境）；真机（用户复验光感材质）  
**Project Type**: mobile-app（既有工程增量改动）  
**Performance Goals**: 导航栏切换/页面路由无回归；导航栏渲染 60fps；无新增启动耗时  
**Constraints**: 服务器端零改动；不破坏第三批已交付的 TTS/QR/MenuSheet/自绘导航栏键盘动画被移除后页面布局完整；all-in ArkTS 严格模式编译通过  
**Scale/Scope**: 8 个用户故事，涉及 6 个既有文件 + 1 个资源目录，预计改动量小（一处网络修复 + 一处导航栏还原 + 四处布局微调 + 一处交互入口 + 资源复制）

## Project Structure

### Documentation (this feature)

```text
spec/ui-refine-batch-3/
├── spec.md              # Feature specification
├── plan.md              # This file
└── tasks.md             # Task breakdown
```

### Source Code (repository root)

```text
entry/src/main/
├── ets/
│   ├── net/
│   │   └── HttpClient.ets            # US1: postMultipartFile header 补 Content-Type
│   ├── pages/
│   │   ├── MainPage.ets              # US2: 还原系统 Tabs 底部 TabBar + FloatingTabBarStyle 沉浸材质；删自绘导航栏/键盘下沉
│   │   ├── me/
│   │   │   └── ProvidersPage.ets     # US3: 卡片单击弹菜单；编辑 bindSheet 挂常驻节点
│   │   ├── workspace/
│   │   │   └── ChannelPage.ets       # US4: 渠道卡片按 kind 渲染品牌 Logo，未知回退 platformBadge
│   │   └── chat/
│   │       └── ChatHomeTab.ets       # US7: 输入卡 margin 12→16；US8: 新会话按钮 offset 对齐发送+抬高
│   ├── components/
│   │   └── MessageBubble.ets         # US5: 用量移框内右下角；US6: 按钮 20→24/图标 12→14/底距 14→11
│   └── components/
│       └── UiMaterialKit.ets         # US2: navBarMaterial() 供 barFloatingStyle.systemMaterial（不改动，仅引用）
└── resources/
    └── base/media/                   # US4: 品牌 Logo 资源（feishu/dingtalk/wecom/weixin/qq/yuanbao 等，从 dashboard 同源资源复制）
```

**Structure Decision**: 遵循既有工程架构（分层 pages/components/service/model/net），本批全部为既有文件增量修改 + 资源复制，不新增文件、不引入 MVVM、不做结构迁移。品牌 Logo 资源按 ArkUI 规范放 `entry/src/main/resources/base/media/`（不放 ets 目录）。

## Complexity Tracking

> 无 Constitution Check 违规，无需填写。

## Research & Decisions

- **Decision 1（US1 422 根因与修法）**: 在 `HttpClient.postMultipartFile` 的请求 header 中补充 `'Content-Type': 'multipart/form-data'`，boundary 由 netstack 自动生成补全（官方 FAQ 示例即此写法）。  
  **Rationale**: 官方文档确证 `multiFormDataList` "仅当 Header 中 'content-Type' 为 'multipart/form-data' 时生效"；现 header 只有 Accept/Authorization，multipart 体从未发出，服务端 `audio: UploadFile = File(...)` 收不到字段 → FastAPI RequestValidationError 422（复现证据：hilog `POST(multipart) /api/voice/stt -> 422` + toast "请求失败 (422)"，buildApiError 对 FastAPI detail 数组解析为空所致）。一处修复覆盖全部 13 处 multipart 调用。  
  **Alternatives considered**: 改用 `http.request` 手工拼 multipart 体（工作量大、易错）；服务端放宽校验（违背零改动）。

- **Decision 2（US2 光感还原方案）**: 移除第三批自绘导航栏（floatingNavBar/keyboardOn/keyboardHeightChange/contentBottomPad），恢复系统 `Tabs` 底部 TabBar（`barPosition(BarPosition.End)`），并调用 `barFloatingStyle(FloatingTabBarStyle)`（API 26+）设置 `systemMaterial: UiMaterialKit.navBarMaterial()` 挂载沉浸光感；`barFloatingStyle` 生效三条件 `barOverlap(true)+vertical(false)+barPosition(BarPosition.End)` 必须同时满足；低版本/不支持时降级普通 TabBar。键盘弹出不再对导航栏做动画，交系统键盘避让。  
  **Rationale**: 官方文档确证沉浸光感仅作用于 Navigation/NavDestination 标题栏、横向 Tabs 底部 TabBar、弹窗类等系统组件，自绘 Row+systemMaterial 无效（compare_images 实证无渲染差异）；`FloatingTabBarStyle.systemMaterial` 字段类型 `ImmersiveMaterial | null` 与现有 `navBarMaterial(): ImmersiveMaterial | null` 完全匹配。用户已明示"实在解决不了就别让导航栏下沉了"，放弃键盘下沉动画。  
  **Alternatives considered**: 继续自绘栏硬套 systemMaterial（已实证无效）；Navigation 模式侧边/标题栏光感（不符合底部四标签交互）。

- **Decision 3（US3 编辑入口）**: provider 卡片在现有 LongPressGesture 之外增加 onClick 触发同一 `showProviderMenu`；编辑用 bindSheet 从条件 FAB 移到页面常驻根节点，规避"菜单关闭→sheet 挂载点未建/已拆"时序冲突。  
  **Rationale**: 编辑功能存在但入口仅长按、不可发现；bindSheet 挂在 `if (this.canManage)` 条件节点上存在时序冲突风险。  
  **Alternatives considered**: 仅保留长按+加提示文案（未解决可发现性）；卡片整卡点击直接进编辑（少了菜单中删除/启用等入口的可达性）。

- **Decision 4（US4 品牌 Logo）**: 将 dashboard 同源品牌资源（`feishu.svg/dingtalk.svg/wecom.svg/weixin.svg/qq.svg/yuanbao.svg/telegram.svg/discord.svg` 等，本地缓存 `Temp\deveco\octop_src\TencentCloud-Octop-890111b\dashboard\src\assets\channels\`）复制进 `entry/src/main/resources/base/media/`；ChannelPage 卡片 44×44 圆角徽章内按渠道 kind 匹配渲染 `Image($r('app.media.xxx'))`（SVG 媒体资源 ArkUI 支持），未知 kind 回退现有 platformBadge 文字+渐变徽章；停用渠道保持降透明度。  
  **Rationale**: 用户澄清需求为渠道品牌 Logo（飞书显示飞书 Logo），非聊天图片；dashboard 前端即用此同源本地资源渲染渠道图标，客户端本地携带与服务端能力解耦、离线可用。  
  **Alternatives considered**: 服务端下发 Logo URL（服务端零改动原则+现状不下发）；仅文字徽章优化（未满足品牌识别需求）。

- **Decision 5（US5/US6 气泡布局）**: 用量（↑/↓）从气泡外右侧竖排胶囊（外层 Row VerticalAlign.Bottom 包裹，L497-511）移除，改为气泡内容列底部右对齐行（`alignItems(HorizontalAlign.End)` 的用量行放气泡框内）；无用量不渲染不占位。操作行按钮容器 20→24、图标 12→14（放大 20%），操作行 margin top 14→11（底距缩小 20%）。  
  **Rationale**: 用户点名"放框内右下角"与两处 20% 精修；数据字段与来源不变，纯展示层调整。  
  **Alternatives considered**: 用量并入操作行同一 Row（操作行是交互区，用量是元信息，语义混合且拥挤）。

- **Decision 6（US7/US8 输入区对齐）**: 输入卡左右 margin 12→16（系统 TabBar 默认内容边距 16vp，视觉同宽）；新会话按钮 offset 由 {x:-2, y:-52} 调整为 x≈-25（实测发送按钮中心 x=1092px≈312vp，新会话按钮现中心 x≈1172px≈334.8vp，差约 23vp，取整 -25）并适当抬高 y（-52→-64 量级，实现时以截图微调为准），保持不遮挡最后一条消息正文。  
  **Rationale**: 实测坐标差推导；y 抬高量按"再抬高点"保守调整并目视验收。  
  **Alternatives considered**: 用相对布局约束对齐（ChatHomeTab 为 Stack+offset 悬浮方案，改布局约束牵动大）。

- **Decision 7（回归边界）**: 不改动第三批已交付的 TTS 链路（LocalTtsService/TtsModels/AppPrefs tts_*）、QR 本地编码、MenuSheet 体系、MeTab 支持节；US2 移除的是第三批的自绘导航栏与键盘动画，其"沉浸光感"开关经 `@StorageLink('immersive.light.on')` 继续驱动 `navBarMaterial()` 输出，语义保持。  
  **Rationale**: 逐批增量、不回退已验收功能。  
  **Alternatives considered**: 无。

## Data Model

本批无新增/变更数据模型，全部为展示层与交互层调整：

- **渠道品牌映射（US4，纯前端常量）**: `CHANNEL_KIND_LOGO: Record<string, Resource>` —— kind → `Image($r)` 资源映射：feishu→app.media.feishu、dingtalk→app.media.dingtalk、wecom→app.media.wecom、weixin→app.media.weixin、qq→app.media.qq、yuanbao→app.media.yuanbao（以渠道页 qrPlatforms/kinds 实际取值为准，资源文件名与 media 目录一一对应）。未知 kind 不在映射内 → 渲染回退徽章。
- **MsgAttachmentModel / 消息用量（US5）**: 字段不变（输入/输出 token 数），仅展示位置变化（气泡外右侧 → 气泡框内右下角）。
- **VoiceProviderModel（US3）**: 字段不变，卡片交互增加单击入口。
- **Tabs 悬浮样式参数（US2）**: `FloatingTabBarStyle` 构造（悬浮宽度/底边距/遮罩/`systemMaterial: ImmersiveMaterial | null`），材质来源 `UiMaterialKit.navBarMaterial()` 现有实现。

## Contracts & Interfaces

- **HttpClient.postMultipartFile（US1，内部契约修正）**: 请求头新增 `'Content-Type': 'multipart/form-data'`（值不含 boundary，netstack 自动补）；方法签名、multiFormDataList 字段名/fileName/contentType、超时（连接 10s/读 120s）、返回处理与错误包络解析全部不变。修复后服务端契约：`POST /api/voice/stt` 收到 `audio`(file)+`language`(form, 默认 zh-CN)+`provider`(可选) → 200 返回识别文本；OctopError 包络 {error:{code,message}} 正常解析展示语义化文案。
- **MainPage Tabs 契约（US2）**: 四标签（专家/聊天/工作台/我的）index 与页面路由映射不变；`barFloatingStyle(FloatingTabBarStyle)` 需 `barOverlap(true)+vertical(false)+barPosition(BarPosition.End)` 三条件同时成立；`systemMaterial` 随 `immersive.light.on` 开关输出材质或 null（null=普通 TabBar 底色）；对外无新接口。
- **ProvidersPage 交互契约（US3）**: 卡片单击与长按触发同一 `showProviderMenu(provider)`；菜单"编辑"→ `openEdit(provider)` → 编辑 bindSheet（挂常驻根节点）打开并预填；保存后列表回显。只读用户行为不变。
- **ChannelPage 渲染契约（US4）**: 渠道卡片徽章渲染规则：kind 在映射内 → 44×44 圆角 Image 品牌资源；否则 → 现有 platformBadge 文字渐变徽章；停用态统一降透明度。无网络请求新增。
- **UI 尺寸契约（US5-US8）**: 气泡用量行：气泡内容列底部、HorizontalAlign.End、无数据不渲染；操作行：按钮容器 24vp/图标 14vp/操作行与气泡底边距离 11vp；输入卡左右边距 16vp（与系统 TabBar 内容边距一致）；新会话按钮中心 x 与发送按钮中心 x 对齐（offset x≈-25）并抬高（y≈-64，以截图验收为准）。
