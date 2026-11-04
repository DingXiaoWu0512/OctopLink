# OctopLink 聊天页头部宠物（Chat Header Pet）设计文档

> 参考：nanoMuse 的聊天头部 Avatar（AgentAvatar + rememberAgentMood）与 OctopPet 的吉祥物素材。
> 最终形态：**宠物只住在聊天页头部**（标题栏区域），心情从会话状态派生，带显隐开关（默认开）。
> 已裁剪：应用内悬浮/跨页显示、拖拽与位置记忆、用户自定义视频、换脸/生图链路、系统级悬浮窗。

## 1. 形态与位置

- 宠物是一个 **48×48vp 的吉祥物组件**，住在聊天页（ChatHomeTab）标题栏上部：
  - 技术落点：`HdsNavigation` titleBar 的 **`stackBuilder` 槽位**——它的渲染层覆盖整个标题栏
    区域（聊天页现在用它放断线提示条），可把吉祥物绝对定位在标题左侧（mainTitle 前）或
    右上角（menu 图标旁），与现有结构零冲突；
  - 心情不对时自然让位：stackBuilder 与 HDS 标题元素同一坐标系，不需要新增布局通道。
- **显隐开关**：`我的 → 外观` 卡新增"宠物"Toggle（沿用沉浸光感开关的模式：
  `@StorageLink('pet.visible')`，默认 **true**，AppPrefs 持久化，EntryAbility 恢复）。
  关闭时 stackBuilder 只渲染原断线提示条。
- 键盘弹出/页面滚动时宠物随标题栏一起被系统处理，无需额外避让逻辑。

## 2. 心情状态机（五心情，全部派生，零新增状态源）

```
enum PetMood { Idle, Working, Waiting, Happy, Error }
```

| Mood | 派生条件（ChatHomeTab 现有状态） | 视觉 | 气泡 |
|---|---|---|---|
| Working | `streaming === true`；帧 `tool_call_chunk` 时记 toolName | 敲键盘循环动画 | "正在调用：web_fetch" / "生成中 · 12s" |
| Waiting | `hitlPending !== null`（HITL 待确认） | 抱水晶球循环动画 | "等你确认" |
| Happy | 一轮流式回复正常结束 → **afterglow 3s** | 抛星星循环动画，随后回 Idle | "搞定！" |
| Error | 回复出错 → **afterglow 4s**；或 `wsError !== ''` | 慌张擦汗动画 | "出错了，点我重试"（点击触发重连） |
| Idle | 以上皆无 | 摇头轻摆 idle 循环 + 呼吸/张望 | 无 |

仲裁：Waiting > Error > Happy/Working（Happy/Error 为 3~4s afterglow，回落 Idle）。
派生原则（学自 nanoMuse `rememberAgentMood`）：**宠物不维护业务状态**——working 派生自
streaming、waiting 派生自 hitlPending、happy/error 是唯一本地记忆的 afterglow（两个时间戳）。

## 3. 动画（三层叠加）

**A. 骨骼层（属性动画，零素材成本）**：呼吸 scaleY、待机 ±2vp 浮动、切态 spring 缩放、
afterglow 小弹跳。

**B. 表情动作层**：

- M1：`Image`/`ImageAnimator` 循环播 webp——OctopPet 的 `type.webp`（working）+ `peek.webp`
  （idle/waiting 借用），MIT 许可；
- M2：`@ohos/lottie`，每个心情一个 Lottie JSON（idle/working/waiting/happy/error 五件套），
  切态即换动画；
- **不做**：图生视频、用户自定义视频（均已裁剪，无运行时媒体链路）。

**C. 气泡层**：48vp 宠物旁的小气泡（圆角 + 尾巴），文案随心情（上表），scale+opacity 出入，
最长 4s 自动收（Working 的计时气泡持续刷新）。

## 4. 交互

- **单击**：Happy/Error 时触发对应动作（Error → 重连/重试；Happy → 无操作彩蛋跳一下）；
  其余心情播放一个随机小动画（彩蛋）。
- 不做拖拽/双击/长按/下拉——头部空间小，保持克制。

## 5. 工程结构

```
entry/src/main/ets/pet/
  PetMood.ets          // 枚举 + afterglow 时长常量 + 派生函数 deriveMood(...)
  PetAvatar.ets        // 头部吉祥物组件：@Component，输入 streaming/error/hitlPending/toolName
resources/rawfile/pet/
  type.webp peek.webp  // M1 素材（OctopPet，MIT）
  lottie/              // M2：idle/working/waiting/happy/error 五件套 JSON
```

- `ChatHomeTab`：stackBuilder 内条件渲染 `PetAvatar`（`pet.visible` 为 true 时）；
- 素材之外无新依赖（M2 前不引入 @ohos/lottie）；
- AppPrefs 新增：`pet.visible`（默认 true）。

## 6. 状态来源（全部现有，不新增网络层）

| 事件 | 现有代码位置 |
|---|---|
| streaming/toolName/done/error | ChatStreamController 帧分发（ChatHomeTab 已有 streaming/wsError 状态） |
| HITL 待确认 | ChatHomeTab hitlPending |
| afterglow | PetAvatar 组件内部时间戳 |

## 7. 分期

- **M1（可演示）**：deriveMood + PetAvatar 组件（webp 两态 + 骨骼动画 + 气泡）+ stackBuilder
  挂载 + 显隐开关（默认开）。
- **M2（动画丰富）**：@ohos/lottie 五心情动画 + Error 点击重连。
- **M3（可选）**：五心情专属素材（设计期美术产出）；多皮肤。

## 8. 风险与注意

1. 功耗：Idle 循环帧率压到 24fps；页面不可见（Tab 切走/后台）暂停动画；
2. 布局：MINI 标题栏内空间有限，宠物 48vp 需与 mainTitle/menu 共存（绝对定位 + 让位规则）；
3. 状态抖动：afterglow 之外的自动态带最短展示时长（Working 3s）；
4. Lottie 依赖与 API 26 兼容性确认（M1 不引入）；
5. 素材授权：OctopPet webp 为 MIT（保留版权注释）；nanoMuse 为 GPL-3.0，只参考交互设计、
   不取用素材文件；五心情完整素材为设计期一次性产出。

## 9. 来自 nanoMuse 的借鉴清单（已核实源码）

| nanoMuse 实现 | 采纳情况 |
|---|---|
| `AgentMood` 五心情 + afterglow（happy 3s / error 4s） | **采纳**：心情全部派生自会话状态，宠物零独立状态源 |
| 聊天头部 Avatar 组件（AgentAvatar，Crossfade 切态） | **采纳**：本次最终形态，不做悬浮窗 |
| 每心情 4s 循环视频（图生视频） | **裁剪**：无生成链路；视频/自定义视频均已移除 |
| `ToolOverlayController`（系统悬浮胶囊） | **裁剪**：HarmonyOS 无对应权限；气泡层承担状态展示 |
| 换脸流（聊天正则意图 → 4 候选 → 姿势生成） | **裁剪**：无生图链路 |
| 用户自定义视频（own-clip） | **裁剪** |
| 素材组织（每心情一文件 + 来源/许可清单） | **采纳规范**，素材自产 |
