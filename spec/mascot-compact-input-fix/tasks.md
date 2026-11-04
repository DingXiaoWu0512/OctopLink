# Tasks: 思考章鱼精简 + 输入区三项修复（mascot-compact-input-fix）

**Input**: Design documents from `spec/mascot-compact-input-fix/`
**Prerequisites**: plan.md (required), spec.md (required for user stories)
**Tests**: 未要求独立测试任务（以 Verification 阶段构建 + 模拟器 UI 实测验收）

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (US1-US4)
- Include exact file paths in descriptions

## Path Conventions

- **单项目根**: `C:\Users\13775\OctopLink`（PROJECT_ROOT）
- 本批仅涉及 2 个源码文件：`entry/src/main/ets/pages/chat/ChatHomeTab.ets`、`entry/src/main/ets/pages/MainPage.ets`
- 素材复用既有资源 `entry/src/main/resources/base/media/octop_mascot_type.webp`（零新增资源）

---

## Phase 1: User Story 1 - 思考指示器精简为"坐框打字章鱼"（Priority: P1）🎯 MVP

**Goal**: 移除玻璃胶囊/光晕/状态文字/双弧线，替换为放大的打字章鱼坐在输入卡上沿
**Independent Test**: 发送消息触发 streaming，输入框上方仅见章鱼动画，回复结束消失

- [x] T001 [US1] 修改 `C:\Users\13775\OctopLink\entry\src\main\ets\pages\chat\ChatHomeTab.ets` 思考胶囊块（约 L2652-2690，`if (this.streaming && this.streamPhase !== '')` 整块）：条件改为 `if (this.streaming)`；块内玻璃胶囊 Row、呼吸光晕 Row、`Text(this.streamPhase)`、`OctopThinkingIndicator({ indSize: 44 })` 全部移除，替换为单 `Image($r('app.media.octop_mascot_type'))`——宽 96vp 高 48vp、`.objectFit(ImageFit.Contain)`、`.interpolation(ImageInterpolation.None)`、`.hitTestBehavior(HitTestMode.None)`、水平居中、`.margin({ bottom: -6 })`（抵消输入卡 margin top 6，使章鱼底边与输入卡上沿视觉相接）；外层容器宽度 '100%'、无上下 padding、`hitTestBehavior(HitTestMode.Transparent)` 保持
- [x] T002 [US1] 修改 `C:\Users\13775\OctopLink\entry\src\main\ets\pages\chat\ChatHomeTab.ets` 清理死代码：先 grep 确认 `thinkGlowBreath`、`startThinkingGlowBreath` 仅被 T001 移除块引用后，删除该 @State 与方法；import 行 `import { OctopThinkingIndicator, InputFlowBorder }` 改为仅 `InputFlowBorder`（L2784 仍在用，勿动）；`streamPhase` @State 及全部赋值逻辑保留（状态机仍驱动流程，仅不再展示文字）

**Checkpoint**: US1 独立可测（发送消息观察）

---

## Phase 2: User Story 2 - 修复键盘收起后最新消息被遮挡（Priority: P1）

**Goal**: kbHeight 变化时贴底状态延迟重锚，最新消息永不被输入卡遮挡
**Independent Test**: 键盘弹出输入→发送→键盘收起，最新消息完整可见于输入框上方

- [x] T003 [US2] 修改 `C:\Users\13775\OctopLink\entry\src\main\ets\pages\chat\ChatHomeTab.ets`：L57 `@Prop kbHeight: number = 0;` 增加 `@Watch('onKbHeightChange')`；新增私有方法 `onKbHeightChange()`：若 `this.stickBottom && this.messages.length > 0`，两段延迟（约 120ms 与 320ms 各一次）在回调内重查 `this.stickBottom` 仍为 true 后执行 `this.scroller.scrollEdge(Edge.Bottom)`（不调 scrollToBottom、不强制置位 stickBottom，尊重用户滚动位置）；幂等可重入

**Checkpoint**: US2 独立可测（发送流程观察遮挡）

---

## Phase 3: User Story 4 - 修复输入框 6 行截断，改为封顶滚动（Priority: P1）

**Goal**: 取消 maxLines 截断，6 行封顶 + 内部滚动 + 右侧滑动条，不限字数
**Independent Test**: 输入 8 行文本，高度封顶 6 行、滑动条出现、滚动见全文、发送完整

- [x] T004 [US4] 修改 `C:\Users\13775\OctopLink\entry\src\main\ets\pages\chat\ChatHomeTab.ets` 输入 TextArea（约 L2787-2806）：移除 `.maxLines(5)`；`.constraintSize({ minHeight: 46, maxHeight: 128 })` 改为 `.constraintSize({ minHeight: 46, maxHeight: 146 })`（初始值，验证轮按 fontSize 15 实际行高校准至恰好 6 行完整可见）；新增 `.scrollBar(BarState.Auto)`（右侧滑动条，溢出出现/不溢出隐藏）；其余属性（fontSize 15、padding、placeholder、controller、onChange/onFocus/onBlur）零改动

**Checkpoint**: US4 独立可测（长文本输入）

---

## Phase 4: User Story 3 - 悬浮 TabBar 宽度与输入框对齐（Priority: P2）

**Goal**: barWidth 数值化（屏宽 vp - 32），TabBar 左右边缘与输入卡对齐
**Independent Test**: 聊天页观察 TabBar 与输入卡左右边缘对齐、四 Tab 均分可点

- [x] T005 [P] [US3] 修改 `C:\Users\13775\OctopLink\entry\src\main\ets\pages\MainPage.ets`：新增 `@State winWidthVp: number = 0;`；aboutToAppear 的 getLastWindow 回调内（avoidArea 读取附近）赋值 `this.winWidthVp = ui.px2vp(win.getWindowProperties().windowProperties.rect.width);`；L176 `.barWidth(this.kbHeight > 0 ? 0 : '100%')` 改为 `.barWidth(this.kbHeight > 0 ? 0 : (this.winWidthVp > 0 ? this.winWidthVp - 32 : '100%'))`；floatingBarStyle()/barHeight/barFloatingStyle/keyboardHeightChange 监听零改动

**Checkpoint**: US3 独立可测（聊天页底部观察）

---

## Phase 5: Polish（静态回归）

- [x] T006 对 2 个修改文件运行 arkts_check（`ChatHomeTab.ets`、`MainPage.ets`），修复全部诊断至零告警

---

## Phase 6: Verification

<!-- verification_scope: build+ui -->

**Purpose**: 构建、部署到模拟器，逐故事 UI 验收（含参数校准）

- [ ] T007 构建项目并修复全部编译错误（`devecocli build`，workdir `C:\Users\13775\OctopLink`；迭代直至成功）
- [ ] T008 部署应用到模拟器 127.0.0.1:5555（`devecocli run --skip-build`；锁屏密码 Abc541755）
- [ ] T009 对部署后的应用执行 UI 验收（手动路径：uinput + dumpLayout + snapshot_display .jpeg + 像素亮度分析 + recognize_ui_components，图片置于 `C:\Users\13775\OctopLink\.recon\`），逐项验收并按需校准参数：
  - US1：发送消息触发 streaming——输入框上方仅见约 96×48vp 打字章鱼（无 Text 状态字节点/无 Circle 弧线节点/无光晕），章鱼底边坐在输入卡上沿，透传可点输入框；流式结束章鱼消失；章鱼与"回到最新"胶囊同屏不错位（章鱼尺寸允许 ±20% 校准）
  - US2：键盘弹出输入文字点发送（键盘收起）——最新消息完整可见、底部与输入卡上沿间隙 ≈22vp、无遮挡；滚离底部阅读历史时收起键盘不被拉回；键盘弹出态贴底同样完整
  - US4：输入 8 行文本——输入框高度封顶（校准 maxHeight 至恰好 6 行完整可见，142-146vp 邻域微调）、右侧滑动条出现、滚动可见全部文字、删除文字降至 6 行内高度恢复收缩、滑动条随溢出消失；发送完整不丢字、发送后恢复单行
  - US3：悬浮 TabBar 左右边缘与输入卡对齐（dumpLayout 实测两边距差 ≤4px，超出则校准 -32 常量），四 Tab 均分可点；键盘期隐藏/收起恢复零回归
  - 回归红线：第十二批键盘间距行为（无横杠/40px 间距/收起态零变化）、流式滚动自由、任务进度面板、空态章鱼、关于页致谢、专家/工作台/我的 Tab、登录页、InputFlowBorder 流光；hilog FATAL=0

---

## Parallel Example: 跨文件并行

```bash
# T005 独占 MainPage.ets，与 T001-T004（独占 ChatHomeTab.ets）可并行：
Task: T005 "TabBar 宽度数值化" → pages/MainPage.ets
Task: T001-T004 "章鱼/重锚/输入滚动" → pages/chat/ChatHomeTab.ets（同文件内串行）
```

## Dependencies & Execution Order

### Phase Dependencies

- **US1 (Phase 1)**: 无依赖，立即开始（MVP 核心）
- **US2 (Phase 2)**: 依赖 T001-T002 完成（同文件，避免编辑冲突）
- **US4 (Phase 3)**: 依赖 T003 完成（同文件串行）
- **US3 (Phase 4)**: 与 T001-T004 并行（不同文件）；T005 无外部依赖
- **Polish (Phase 5)**: 依赖全部实现任务完成
- **Verification (Phase 6)**: 依赖 Polish；内部串行 T007 → T008 → T009

### Within Each User Story

- T001 → T002（先替换块再清死代码，grep 确认引用后再删）
- T003/T004 与 T005 无交叉依赖

## Implementation Strategy

### MVP First（User Story 1 Only）

1. 完成 T001-T002（章鱼精简）
2. **STOP and VALIDATE**: 发送消息独立验证章鱼显示/消失
3. 部署演示（MVP 即用户最强烈的观感诉求）

### Incremental Delivery

1. +US1 章鱼精简 → 独立验证（MVP）
2. +US2 键盘重锚 → 发送流程验证遮挡修复
3. +US4 输入滚动 → 长文本验证
4. +US3 TabBar 宽度 → 对齐验证
5. Polish → Verification 全量验收（含四项参数校准）

## Notes

- 总任务数 9（T001-T009）：US1×2、US2×1、US4×1、US3×1、Polish×1、Verification×3
- 并行机会：T005（MainPage）与 T001-T004（ChatHomeTab）跨文件并行；ChatHomeTab 内部任务串行
- 独立验收：每个 US 可单独触发观察（发送消息 / 键盘收起流程 / 长文本输入 / 底部 TabBar 观察）
- MVP scope：T001+T002（+构建部署）
- 参数校准权限：验证轮（T009）允许对章鱼尺寸（±20%）、maxHeight（142-146vp 邻域）、barWidth 常量（-32 邻域）、重锚延迟（120/320ms 邻域）一次性校准，属参数微调不构成方案变更
- [P] tasks = different files, no dependencies；[Story] 标签映射 spec.md 用户故事
