# Implementation Plan: App 端本机 TTS 引擎接入与后端选择（Message TTS Local Engine）

**Input**: Feature specification from `spec/message-tts/spec.md`

## Summary

在现有「语音设置」页 TTS 区新增「本机引擎」卡片（CoreSpeechKit `textToSpeech`），与服务器 TTS 预设并列可选；消息朗读按钮按所选后端分流——本机引擎走端侧合成播放（零流量），服务器走现有 `VoiceService.tts` → `AudioIOService.playTts` 链路（行为不变）。本机引擎提供全套参数配置（语速 0.5-2.0、音调 0.5-2.0、音量 0-2、音色、合成模式），后端选择与参数为 App 级本地持久化（preferences），全局生效。核心新增：`LocalTtsService`（引擎封装 + 设置缓存）、`TtsModels`（设置/音色模型）、`LocalTtsConfigDialog`（参数面板）；改造：`MessageBubble.toggleSpeak` 分流、`VoiceSettingsPage` 本机引擎卡片、`AppPrefs` TTS 键、聊天页生命周期兜底。

## Technical Context

**Language/Version**: ArkTS（API 12+，HMS CoreSpeechKit `@kit.CoreSpeechKit` 的 `textToSpeech` 自 4.1.0(11) 起可用）
**Primary Dependencies**: `@kit.CoreSpeechKit`（textToSpeech 端侧合成）、`@kit.ArkData`（preferences 持久化，现有 AppPrefs）
**State Management**: 沿用项目现有 V1 状态管理（@Component/@State/@ObjectLink），增量改造不引入 V2
**Storage**: preferences 本地键值（`octop_link_prefs`，经现有 `AppPrefs` 单例）；服务器端零改动
**Testing**: arkts_check + devecocli build + 模拟器/真机手工验证（朗读出声、参数保存、降级提示）
**Target Platform**: HarmonyOS 真机（HMS CoreSpeech 可用）；模拟器可能无引擎（降级提示路径）
**Project Type**: 既有 HarmonyOS 应用（OctopLink，bundle com.octop.link）增量功能
**Performance Goals**: 本机引擎点击朗读到出声 ≤3s（真机）；参数保存即时生效（下次朗读即用新值）
**Constraints**: 文本 ≤10000 字符（SDK 限制）；每设备最多 3 个 TTS 引擎实例（App 持有 1 个复用）；引擎 `online` 参数仅 1=离线受支持（0=在线暂不支持）；无需 user_grant 权限
**Scale/Scope**: 新增 3 个 ArkTS 文件 + 修改 4 个既有文件；单用户端侧功能

## Project Structure

### Documentation (this feature)

```text
spec/message-tts/
├── spec.md              # 需求规格（Phase 1 产物）
├── plan.md              # 本文件
└── tasks.md             # Phase 3 产物
```

### Source Code (repository root)

```text
entry/src/main/ets/
├── model/
│   └── TtsModels.ets                  # [新增] TtsSettingsModel、VoiceOptionModel
├── service/
│   └── LocalTtsService.ets            # [新增] CoreSpeechKit 封装：引擎懒创建/复用、speak/stop、
│                                       #   设置缓存与持久化、音色查询、可用性检测
├── components/
│   ├── LocalTtsConfigDialog.ets       # [新增] 本机引擎参数面板 @CustomDialog（3 滑杆+音色+模式）
│   └── MessageBubble.ets              # [修改] toggleSpeak 按后端分流；生命周期回调复位
├── store/
│   └── AppPrefs.ets                   # [修改] 新增 TTS 后端与引擎参数键的读写
├── pages/
│   ├── me/
│   │   └── VoiceSettingsPage.ets      # [修改] TTS 区新增「本机引擎」卡片；设为当前分流；打开配置面板
│   └── chat/
│       └── ChatHomeTab.ets            # [修改] 离开页/切会话停止朗读（两条后端链路）
```

**Structure Decision**: 遵循项目既有架构（pages/components/service/store/model 分层，无 viewmodel 目录），不引入 MVVM 迁移。新增 3 个文件均落入既有职责目录：模型入 `model/`、引擎封装与设置缓存入 `service/`、配置弹窗入 `components/`（与 MessageBubble 等 UI 组件同层）。参数面板拆为独立 `LocalTtsConfigDialog.ets` 而非内嵌 VoiceSettingsPage，原因是该页已约 700 行、面板含 3 滑杆+音色选择+模式切换+试听逻辑，内嵌将超 1000 行不利维护。文件总数 3 新增 + 4 修改，为该功能的最小充分拆分。

## Complexity Tracking

（无 Constitution Check 违规，无需说明）

## Research & Decisions

### R1: TTS 引擎选型 — CoreSpeechKit textToSpeech

- **Decision**: 采用 HMS `@kit.CoreSpeechKit` 的 `textToSpeech`（`@hms.ai.textToSpeech`），单例封装为 `LocalTtsService`。
- **Rationale**: 系统级端侧 TTS，无需权限、无需 API Key、离线可用；SDK 声明已核实（API 11 起可用）：`createEngine(CreateEngineParams)` → `setListener(SpeakListener)` → `speak(text, SpeakParams)` → `stop()/shutdown()`；引擎自带播放（`extraParams.playType=1`），无需 AVPlayer。
- **Alternatives considered**: 服务器 TTS（现状，无法离线/零流量）；第三方端侧 TTS SDK（引入体积与合规成本）。

### R2: 参数传递方式 — SpeakParams.extraParams

- **Decision**: 语速/音量/音调通过 `SpeakParams.extraParams` 传入（键：`speed`/`volume`/`pitch`/`queueMode=0`/`languageContext='zh-CN'`/`audioType='pcm'`/`playType=1`）；引擎初始化参数（`language='zh-CN'`、`person`、`online`）走 `CreateEngineParams`。
- **Rationale**: SDK `SpeakParams` 仅有 `requestId` + `extraParams` 两字段，运行时参数全部在 extraParams；官方参考代码同构。
- **Alternatives considered**: 无（SDK 契约唯一）。

### R3: 合成模式（在线/离线）配置语义

- **Decision**: 配置面板提供「离线（推荐）/在线」选择，默认**离线（online=1）**；选择「在线（online=0）」时面板提示"当前引擎版本暂不支持在线模式，合成可能失败"。
- **Rationale**: SDK 声明明确 `online=0`（在线）暂不被支持、`online=1`（离线）受支持；spec FR-002 要求模式可配，故保留开关但标注限制，不做静默吞掉。
- **Alternatives considered**: 仅暴露离线（违背 FR-002 可配要求，弃）；强制双模式无提示（在线模式实际会失败，误导用户，弃）。

### R4: 后端选择与参数的持久化 — 扩展 AppPrefs

- **Decision**: 在既有 `AppPrefs`（preferences 单例，`octop_link_prefs`）中新增键：`tts_backend`（'local'|'server'）、`tts_speed`、`tts_pitch`、`tts_volume`、`tts_person`、`tts_online`。数值以字符串存取（与该类既有 getString/putString 模式一致），读取时类型归一。默认值：backend='server'（不改变现有行为）、speed=1.0、pitch=1.0、volume=2、person=13、online=1。
- **Rationale**: 项目已有 AppPrefs 单例模式（init 于启动时），复用避免第二个 Preferences 实例；默认 'server' 保证存量用户行为零变化，本机引擎为显式 opt-in。
- **Alternatives considered**: 独立 `TtsPrefs` 类/独立 preferences 文件（多余拆分，弃）；存服务器（违背"端侧能力端侧存"，且要求网络，弃）。

### R5: 设置的同步访问 — LocalTtsService 内存缓存

- **Decision**: `LocalTtsService` 持有 `TtsSettingsModel` 内存缓存，首次访问异步加载（`ensureLoaded()`，幂等），之后同步读；写路径"先改内存+落盘"。`MessageBubble.toggleSpeak` 为 async，点击时 `await ensureLoaded()` 后取缓存值分流。
- **Rationale**: AppPrefs 读为异步，而朗读按钮点击、弹窗滑杆渲染需要即时值；集中缓存避免各 UI 处散落 await 与不一致。
- **Alternatives considered**: 每次 await AppPrefs（点击延迟+竞态，弃）；AppStorage 全局状态（V1 观察对象与本功能无绑定 UI 需求，且服务缓存更内聚，弃）。

### R6: 朗读状态协调 — 单活动请求 + 回调登记

- **Decision**: `LocalTtsService` 内部维护"当前活动朗读请求"（requestId + 各回调引用）：新 `speak()` 前先对当前请求 `stop()`（引擎 `onStop`/`onError` 触发旧回调复位）；`stop()`/页面离开统一走服务入口。`SpeakListener` 仅注册一次（引擎创建时），内部按 requestId 分发到当前回调。
- **Rationale**: 与既有服务器链路的打断语义对齐（`AudioIOService.playTts` 新播放打断旧播放并回调 onEnd）；单活动请求天然满足"同一时刻仅读一条、点 B 停 A"。
- **Alternatives considered**: 引擎 queueMode 排队（违背"点 B 立即换 B"，弃）；多个 SpeakListener 轮换（SDK 单 listener，弃）。

### R7: 引擎可用性检测与降级

- **Decision**: 三层检测：(1) `canIUse('SystemCapability.AI.TextToSpeech')` 静态判断；(2) `createEngine` 失败（如 1002300005）置不可用标记并向上抛错误信息；(3) 朗读时任何失败路径统一 toast「本机语音引擎不可用/朗读失败」并复位按钮。配置面板在无引擎设备仍可设置保存（FR 约定朗读时才提示）。
- **Rationale**: 模拟器与部分设备无 HMS TTS 引擎，需优雅降级；spec Edge Cases 明确此行为。
- **Alternatives considered**: 启动即预创建引擎探测（增加启动开销，弃；保留懒创建首次朗读时探测）。

### R8: 生命周期兜底挂点

- **Decision**: 聊天页销毁（`aboutToDisappear`）与会话切换（消息列表重置处）调用统一停止入口：同时停 `LocalTtsService.stop()` 与 `AudioIOService.stopPlayback()`；引擎实例保留复用（不反复 shutdown/create，规避 3 实例上限与创建延迟）。
- **Rationale**: spec FR-008 要求无残留声音；实例复用兼顾 ≤3 实例约束与 ≤3s 出声目标。
- **Alternatives considered**: 每次朗读后 shutdown（下次朗读需重建引擎，延迟叠加，弃）；仅页面级停止不覆盖切会话（场景 2 漏，弃）。

### R9: 音色选择数据源 — listVoices 动态 + 静态兜底

- **Decision**: 配置面板打开时调用引擎 `listVoices`（离线 zh-CN）取可用音色（含 status：INSTALLED 可用/GA 可下载）；查询失败或引擎不可用时回退静态清单：13=玲小姗（女声·推荐）、21=玲飞哲（男声·需下载）、0=默认女声。音色下载（`downloadVoice`）不在本期范围。
- **Rationale**: 动态查询覆盖设备差异（部分音色需下载）；静态兜底保证无引擎设备配置页不空白。
- **Alternatives considered**: 仅静态清单（无法反映设备实际安装状态，弃）；集成 downloadVoice（扩大范围，spec 未要求，弃）。

## Data Model

### TtsSettingsModel（model/TtsModels.ets，App 级全局、本地持久化）

| 字段 | 类型 | 约束/默认 | 说明 |
|------|------|-----------|------|
| backend | string | 'local' \| 'server'，默认 'server' | 当前朗读后端；'server' 时走既有链路 |
| speed | number | 0.5-2.0，默认 1.0，步进 0.05 | 语速（SpeakParams.extraParams.speed） |
| pitch | number | 0.5-2.0，默认 1.0，步进 0.05 | 音调（extraParams.pitch） |
| volume | number | 0-2，默认 2，步进 0.1 | 音量（extraParams.volume） |
| person | number | 0/13/21（zh-CN），默认 13 | 音色（CreateEngineParams.person） |
| online | number | 0=在线（暂不支持）/1=离线，默认 1 | 合成模式（CreateEngineParams.online） |

校验规则：数值写入前 clamp 到合法区间（越界取边界）；backend 仅接受两枚举值，非法回退 'server'。切换 person/online 后的下一次朗读须重建引擎（参数在 createEngine 时生效）。

### VoiceOptionModel（model/TtsModels.ets，配置面板音色列表项）

| 字段 | 类型 | 说明 |
|------|------|------|
| person | number | 音色 ID |
| displayName | string | 展示名（如「玲小姗·女声·推荐」） |
| status | string | 'INSTALLED'=已安装可选 / 'GA'=可下载 / 'EOM'=不可用 |

来源：`listVoices` 的 `VoiceInfo`（language/person/gender/description/status）映射；静态兜底清单同构。

### 状态转移（朗读会话，requestId 维度）

```
idle --speak()--> starting(onStart 前的合成中) --onStart--> speaking
speaking --onComplete(type=1)--> idle（按钮复位）
speaking --stop()/新请求打断/切后端/离页 --> onStop --> idle
任意 --onError--> idle + toast（引擎不可用/合成失败文案）
```

`MessageBubble.speakingBusy` 对应 starting、`speaking` 对应 speaking，与既有服务器链路语义一致。

## Contracts & Interfaces

### LocalTtsService（service/LocalTtsService.ets，静态门面 + 单例内部状态）

```
ensureLoaded(): Promise<void>                      // 幂等：首访加载设置到内存缓存；App 启动后任意调用方先 await
getSettings(): TtsSettingsModel                    // 同步读缓存（须在 ensureLoaded 后）
setSettings(s: TtsSettingsModel): Promise<void>    // 校验+clamp → 更新缓存 → 落盘（AppPrefs）；person/online 变化置引擎重建标记
isLocalBackend(): Promise<boolean>                 // 便捷：ensureLoaded 后判 backend==='local'
speak(text: string, cb: SpeakCallbacks): Promise<void>
   // cb: onStart()/onComplete()/onStop()/onError(msg: string)
   // 前置：文本非空且 ≤10000 字符（超长截断）；打断当前活动请求；引擎懒创建（不可用→reject 'engine unavailable'）
stop(): void                                       // 停当前活动朗读（无活动则空操作）；触发旧请求 onStop
release(): void                                    // stop + engine.shutdown()，置空实例（仅极端兜底用）
listVoices(): Promise<Array<VoiceOptionModel>>     // 引擎离线 zh-CN 查询；失败回退静态清单
isEngineAvailable(): boolean                       // canIUse + 最近一次 createEngine 结果
```

副作用约定：speak 成功后活动请求登记；onComplete/onStop/onError 任一触发即注销并复位；新 speak/stop 对旧请求的打断必须先于新请求发出。

### AppPrefs 扩展（store/AppPrefs.ets）

```
getTtsBackend(): Promise<string>                   // 'local' | 'server'，默认 'server'
setTtsBackend(v: string): Promise<void>
getTtsSpeed()/getTtsPitch(): Promise<number>       // 默认 1.0；字符串读取→number 归一，NaN 回退默认
setTtsSpeed(v)/setTtsPitch(v): Promise<void>
getTtsVolume(): Promise<number>                    // 默认 2
setTtsVolume(v): Promise<void>
getTtsPerson(): Promise<number>                    // 默认 13
setTtsPerson(v): Promise<void>
getTtsOnline(): Promise<number>                    // 默认 1
setTtsOnline(v): Promise<void>
```

### MessageBubble.toggleSpeak 分流契约（components/MessageBubble.ets 修改）

```
await LocalTtsService.ensureLoaded()
if (LocalTtsService.isLocalBackend())  → LocalTtsService.speak(ttsPlainText(), 回调驱动 speaking/speakingBusy/toast)
else                                   → 既有服务器链路（VoiceService.tts + AudioIOService.playTts），行为不变
```

约束：Markdown 剥离（ttsPlainText）两链路共用；本机链路复用按钮三态（busy=speakingBusy、播放中=speaking、玫瑰底停止态）。

### VoiceSettingsPage 集成契约（pages/me/VoiceSettingsPage.ets 修改）

- TTS 区新增「本机引擎」卡片：标题「本机引擎（设备端合成）」、副标题「离线朗读·无需服务器·零流量」、状态行显示当前参数摘要（语速/音色）、操作：「设为当前」（backend='local'，持久化）与「配置」（打开 LocalTtsConfigDialog）；backend='local' 时卡片呈激活态（与服务器预设激活样式一致）。
- 点任一服务器预设「设为当前」：backend='server'（既有 putActive 流程不变）；两处激活动作均先停两条链路朗读（LocalTtsService.stop() + AudioIOService.stopPlayback()）。

### LocalTtsConfigDialog（components/LocalTtsConfigDialog.ets，@CustomDialog）

```
入参：当前 TtsSettingsModel 快照
出参：保存回调回传完整 TtsSettingsModel（已 clamp）
内容：语速滑杆(0.5-2.0/0.05)、音调滑杆(0.5-2.0/0.05)、音量滑杆(0-2/0.1)、
      音色单选（listVoices 结果或静态兜底，标注安装状态）、
      模式切换（离线=默认推荐 / 在线附"暂不支持"提示）、取消/保存
```

### ChatHomeTab 生命周期契约（pages/chat/ChatHomeTab.ets 修改）

- `aboutToDisappear` 与会话切换（消息列表重置处）：调用统一停止（LocalTtsService.stop() + AudioIOService.stopPlayback()）。
- 不持有引擎引用、不感知后端细节。

### 外部系统契约（只读依赖，零改动）

- CoreSpeechKit `textToSpeech`：`createEngine(CreateEngineParams{language:'zh-CN', person, online, extraParams{style:'interaction-broadcast', locate:'CN', name:'octop'}})`；`speak(text, SpeakParams{requestId, extraParams{queueMode:0, speed, volume, pitch, languageContext:'zh-CN', audioType:'pcm', playType:1}})`；`SpeakListener{onStart/onComplete/onStop/onError(/onData 不实现，playType=1 引擎自播)}`。
- 服务器 `/api/voice/*`：现有契约不变；本机引擎不出现在服务器 provider 体系。
