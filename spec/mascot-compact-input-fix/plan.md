# Implementation Plan: 思考章鱼精简 + 输入区三项修复（mascot-compact-input-fix）

**Input**: Feature specification from `spec/mascot-compact-input-fix/spec.md`

## Summary

四项改动（2 个 Bug 修复 + 2 项视觉精简）：① 思考指示器由玻璃胶囊（光晕+双弧线+状态文字）整体替换为放大的打字章鱼动画（约 96×48vp，坐在输入卡上沿居中，透传触摸）；② 修复键盘收起后最新消息被输入卡遮挡——kbHeight 变化时贴底状态延迟重锚滚动；③ 悬浮 TabBar 宽度收敛至与输入卡同宽（barWidth = 屏宽 vp - 32）；④ 输入框取消 5 行截断，6 行封顶 + 内部滚动 + 右侧滑动条（BarState.Auto）。全部为 UI 层改动，仅涉及 ChatHomeTab.ets 与 MainPage.ets 两个文件。

## Technical Context

**Language/Version**: ArkTS（HarmonyOS ArkUI，API 12+）
**Primary Dependencies**: ArkUI List（stackFromEnd/contentEndOffset/scrollEdge）、TextArea（constraintSize + 内部滚动 + scrollBar）、Tabs（barWidth/barFloatingStyle）、动画 WebP Image（octop_mascot_type 既有资源）
**State Management**: 沿用项目现有 State Management V1（@Component/@State/@Prop + @Watch）
**Storage**: N/A
**Testing**: devecocli build + 模拟器（127.0.0.1:5555）实测（uinput + dumpLayout + snapshot_display + 像素亮度分析 + recognize_ui_components）
**Target Platform**: HarmonyOS 模拟器 / 真机
**Project Type**: mobile-app（既有项目增量改动）
**Performance Goals**: 章鱼动画仅 streaming 期间渲染；重锚滚动幂等零抖动
**Constraints**: 服务器零改动；非本批页面/行为零回归；素材宽高比与像素锐利保持
**Scale/Scope**: 修改 2 个 ArkTS 文件，零新增文件

## Project Structure

### Documentation (this feature)

```text
spec/mascot-compact-input-fix/
├── spec.md
├── plan.md              # 本文件
└── tasks.md
```

### Source Code (repository root)

```text
entry/src/main/ets/
├── pages/
│   ├── chat/ChatHomeTab.ets    # 修改：US1 章鱼替换胶囊 / US2 kbHeight @Watch 重锚 / US4 TextArea 滚动
│   └── MainPage.ets            # 修改：US3 barWidth 数值化（屏宽 vp - 32）
└── components/
    └── OctopThinkingIndicator.ets  # 不改动：OctopThinkingIndicator 用法移除后保留组件文件（无引用方，留作复用）
```

**Structure Decision**: 遵循既有项目架构，不引入新目录/文件；2 文件最小改动集覆盖全部需求。

## Complexity Tracking

（无 Constitution Check 违规）

## Research & Decisions

**Decision 1 - US1 章鱼替换胶囊（ChatHomeTab L2652-2690 整块重写）**：移除玻璃胶囊 Row（UiMaterialKit.glassBg 背景卡）、呼吸光晕 Row（渐变 blur + thinkGlowBreath）、`Text(this.streamPhase)` 状态文字、`OctopThinkingIndicator({ indSize: 44 })` 弧线环绕。替换为：条件 `if (this.streaming)` 下的单 `Image($r('app.media.octop_mascot_type'))`，宽 96vp × 高 48vp（2:1 防拉伸），`.objectFit(ImageFit.Contain)` + `.interpolation(ImageInterpolation.None)`，`.hitTestBehavior(HitTestMode.None)` 透传，水平居中，`.margin({ bottom: -6 })` 抵消输入卡自身 margin top 6 使章鱼底边与输入卡上沿视觉相接（"坐在框上"）。
**Rationale**: 用户明确要求去背景/去字/去弧线/去光晕、放大章鱼、坐在输入框上；条件从 `streaming && streamPhase !== ''` 简化为 `streaming`（无文字后全程稳定显示更连贯）；触摸透传保证不拦截输入区点击。
**Alternatives considered**: 保留弧线环绕仅去文字（用户明确"去掉外面环绕的环"，弃用）；章鱼右对齐发送按钮（"坐在输入框上"以居中为最稳观感，弃用）。

**Decision 2 - US1 清理死代码**：胶囊块移除后同步清理仅被该块引用的 `thinkGlowBreath` @State、`startThinkingGlowBreath()` 方法，以及 import 中不再使用的 `OctopThinkingIndicator`（`InputFlowBorder` 保留，L2784 仍用）；`streamPhase` @State 及其全部赋值逻辑保留（深度推理/工具阶段状态机仍驱动流程，仅不再展示文字）。清理前 grep 确认各符号引用方。
**Rationale**: 最小 diff 原则下移除确定性死代码；streamPhase 参与多处流程判断（L150/726/741/774/867 等），保留。
**Alternatives considered**: 全删 streamPhase（改动面大、风险高，弃用）；死代码全留（命名空间污染，弃用）。

**Decision 3 - US2 键盘重锚（kbHeight @Watch 双段延迟贴底）**：`@Prop kbHeight` 增加 `@Watch('onKbHeightChange')`；回调内若 `stickBottom && messages.length > 0`，两段延迟（约 120ms 与 320ms 各一次，覆盖键盘动画前后两帧布局）直接 `this.scroller.scrollEdge(Edge.Bottom)` 重锚；不调用 scrollToBottom(force)（避免强制置位 stickBottom 覆盖用户阅读位置），触发时二次读取最新 stickBottom（闭包捕获问题用触发时重查规避——延迟回调内重查 this.stickBottom）。
**Rationale**: 根因：键盘收起瞬间 List 视口扩展 + contentEndOffset 尚未随 kbHeight 更新完成，stackFromEnd 把内容末端锚到新视口底，contentEndOffset 仍为键盘态小值 → 最新消息沉入输入卡后方；布局稳定后补一次 scrollEdge 使新 contentEndOffset（含 bottomPad+10 收起值）生效，消息回到输入卡上方 22vp 间隙位。双段延迟覆盖窗口 RESIZE 动画时序不确定性，幂等无副作用；stickBottom 门禁尊重用户滚动自由（FR-004）。
**Alternatives considered**: 单次延迟（键盘动画时长不定，单点易踩空，弃用）；监听 List onAreaChange 全量重锚（触发源过多，滚动敏感场景引入抖动风险，弃用）；keyboardAvoidMode 调整（影响全局布局，过重，弃用）。

**Decision 4 - US3 TabBar 宽度数值化（MainPage）**：aboutToAppear 获取窗口后记录 `@State winWidthVp`（`ui.px2vp(win.getWindowProperties().windowProperties.rect.width)`）；Tabs `.barWidth()` 由 `'100%'` 改为 `this.kbHeight > 0 ? 0 : (this.winWidthVp > 0 ? this.winWidthVp - 32 : '100%')`（32 = 输入卡左右 margin 16×2，winWidthVp 未就绪首帧回退 '100%'）。验证轮用 dumpLayout 实测悬浮胶囊左右边缘 vs 输入卡左右边缘对齐度校准常量（若框架对悬浮胶囊有内边距则相应增减）。
**Rationale**: 输入卡 margin left/right 16（L2985），barWidth 数值化后 BarMode.Fixed 四 Tab 均分收窄宽度，左右边缘与输入卡对齐；保留键盘期 barWidth 0 隐藏逻辑（三元优先级不变）。
**Alternatives considered**: FloatingTabBarStyle 内部字段控宽（无公开宽度字段，弃用）；CSS calc 表达式（barWidth Length 不支持 calc，弃用）。

**Decision 5 - US4 TextArea 6 行滚动（ChatHomeTab L2793-2795）**：移除 `.maxLines(5)`；`.constraintSize` 改为 `{ minHeight: 46, maxHeight: 146 }`（初始值，验证轮按 fontSize 15 实际行高校准至"恰好 6 行完整可见"，约 142-146vp）；新增 `.scrollBar(BarState.Auto)`（溢出出现/不溢出隐藏、可拖动）。TextArea 在高度受 constraintSize 封顶且无 maxLines 时内容内部滚动（scrollable 组件原生行为）。
**Rationale**: maxLines 是渲染截断（不滚动）根因；去 maxLines + 高度封顶触发内部滚动；BarState.Auto 满足"带右侧滑动条"且自动显隐；flowH 经 onAreaChange 动态跟随（封顶后停止增长），contentEndOffset 停止位自动保持正确。
**Alternatives considered**: maxLines(6) + maxHeight（maxLines 截断不可滚动，正是现 Bug 机理，弃用）；显式 lineHeight 锁定行高（改变短文本现渲染，回归风险，弃用）；enableScrollBarLength 自定义（无必要，弃用）。

**Decision 6 - US4 校准策略**：maxHeight 初始 146vp、章鱼 96×48vp、重锚延迟 120/320ms、barWidth -32 均为初始参数，验证轮以实测为准校准一次（章鱼尺寸允许 ±20%、maxHeight 以 6 行恰好完整可见为准、TabBar 以两边距差 ≤4px 为准、延迟以遮挡不残留为准）；校准属参数微调不构成方案变更。
**Rationale**: 像素级行高/胶囊内边距/动画时序无法离线精确推定，用一次性实测校准收敛，避免反复猜参数。

## Data Model

（无数据模型变更。涉及状态成员：`kbHeight`（@Prop 增加 @Watch，类型不变）、`winWidthVp`（MainPage 新增 @State number，窗口宽 vp）、`thinkGlowBreath`（移除）、既有 `stickBottom`/`messages`/`streamPhase`/`flowH`/`scroller` 沿用。）

## Contracts & Interfaces

**组件行为契约变更**：

1. **ChatHomeTab（pages/chat/ChatHomeTab.ets）**
   - 思考指示区：`streaming` 时渲染 96×48vp 打字章鱼（居中、透传、坐输入卡上沿）；玻璃胶囊/文字/弧线/光晕全部移除；`startThinkingGlowBreath`/`thinkGlowBreath` 删除；`OctopThinkingIndicator` import 移除（`InputFlowBorder` 保留）
   - 滚动重锚：`kbHeight` 带 `@Watch('onKbHeightChange')`；变化时 stickBottom 贴底双段延迟重锚；非贴底零干预
   - 输入框：TextArea 去 `maxLines`，constraintSize `{ minHeight: 46, maxHeight: 146 }`（校准），`scrollBar(BarState.Auto)`；其余属性（fontSize 15/padding/placeholder/onChange/onFocus/onBlur）零改动
2. **MainPage（pages/MainPage.ets）**
   - 新增 `@State winWidthVp: number = 0`，aboutToAppear 窗口就绪后赋值
   - `.barWidth()` 三元改为：键盘期 0 → 收起期 `winWidthVp - 32`（未就绪回退 '100%'）
   - floatingBarStyle()/barHeight/barFloatingStyle/keyboardHeightChange 监听零改动

**回归红线**：第十二批键盘间距（横杠清除/40px 间距/FR-014 收起态零变化）；流式滚动自由（stickBottom/onScroll/onReachEnd/stackFromEnd 行为）；任务进度面板；"回到最新"胶囊；空态章鱼/关于页致谢（上一批）；InputFlowBorder 流光；斜杠面板/附件/录音/润色等输入卡全部功能；专家/工作台/我的 Tab；登录页。

**资源契约**：复用既有 `octop_mascot_type`（打字章鱼 88×44 动画 WebP），无新增资源。
