---
description: "Task list for input-glow-hitfix"
---

# Tasks: input-glow-hitfix（输入卡流光触摸拦截根治）

**Input**: Design documents from `spec/input-glow-hitfix/`
**Prerequisites**: plan.md (required), spec.md (required for user stories)

**Organization**: 任务按阶段分组（Setup → Implementation → Verification），单文件定点改造，全程串行。

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (US1, US2)
- Include exact file paths in descriptions

## Path Conventions

- 项目根：`C:\Users\13775\OctopLink`
- 主改造（唯一）：`entry\src\main\ets\pages\chat\ChatHomeTab.ets`（输入卡区域约 L2621-2845；`inputGlowOverlay` @Builder 约 L2314-2320）
- 禁改（只读参考）：`entry\src\main\ets\components\OctopThinkingIndicator.ets`（InputFlowBorder/OctopThinkingIndicator 零改动）
- 构建产物：`entry\build\default\outputs\default\entry-default-signed.hap`
- 服务端：`C:\Users\13775\AppData\Local\Temp\deveco\octop_src\TencentCloud-Octop-890111b\`（零改动）

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: 现状锚点确认

- [X] T001 通读 `ChatHomeTab.ets` 输入卡区域，确认锚点——`inputGlowOverlay` @Builder（约 L2314-2320）；外层 `Stack({ alignContent: Alignment.TopEnd })`（约 L2621，子节点=输入卡 Column + FAB）；输入卡内容 Column（约 L2622-2809：TextArea + 操作行 Row）；输入卡属性链（约 L2810-2825：width/borderRadius(24)/backgroundColor(glass)/backgroundBlurStyle(COMPONENT_REGULAR)/systemMaterial/border/shadow/constraintSize/margin/onAreaChange(flowW/flowH 测量)/`.overlay(this.inputGlowOverlay, { align: Alignment.Center })`）；FAB（约 L2827-2843）；`flowW`/`flowH` @State（约 L104-105）。行号漂移以实际内容为准，结构语义必须一致；语义不符则停止并上报

---

## Phase 2: Implementation

**Purpose**: 输入卡 z 序重构——流光垫底，触摸拦截确定性根治

### Implementation for User Story 1 (触摸恢复) & User Story 2 (视觉零回归)

- [X] T002 [US1][US2] 输入卡 z 序重构：①删除 `inputGlowOverlay` @Builder；②删除输入卡 Column 属性链上的 `.overlay(this.inputGlowOverlay, ...)`；③原内容 Column 外包一层包裹 Stack——子1（底层）`if (this.streaming) { InputFlowBorder({ w: this.flowW, h: this.flowH }) }`，子2（顶层）原内容 Column（TextArea + 操作行原样保留）；④原 Column 全部视觉属性逐属性迁移到包裹 Stack（width/borderRadius/backgroundColor/backgroundBlurStyle/systemMaterial/border/shadow/constraintSize/margin/onAreaChange，flowW/flowH 测量语义不变）；⑤内容 Column 仅保留 `width('100%')` 与原 padding；⑥FAB 层级不变（外层 Stack 子2，TopEnd 对齐）；⑦InputFlowBorder 调用参数不变（仅 w/h），`components/OctopThinkingIndicator.ets` 零改动；⑧第九批行为（TextPacer/turnGen/endTurnReconciled/sendSteer 守卫等）零改动
- [X] T003 `arkts_check` 对 `ChatHomeTab.ets` 通过（无新增违例；已知坑：arkts-no-untyped-obj-literals、枚举大小写、禁 any）；grep 确认无残留 `inputGlowOverlay`/`.overlay(` 引用

**Checkpoint**: 结构改造完成，静态检查清零

---

## Phase 3: Verification

<!-- verification_scope: build+ui -->

**Purpose**: Build, deploy, and UI-verify the implemented feature

- [X] T004 构建：`devecocli build`（workdir=项目根）修复循环直至成功（上限 10 次）
- [X] T005 部署模拟器：`devecocli run --skip-build --device 127.0.0.1:5555`（锁屏先解锁，密码 Abc541755）
- [X] T006 UI 逐条验收：按 spec US1/US2 与 SC-001~SC-005 逐条执行——US1 流式期间依次点击 TextArea（预期获焦弹键盘）/停止按钮（预期回合终止流光熄灭）/plus/wand/mic/model 各胶囊（预期各自响应）/输入文字点发送（预期 steer 追问排队成功）；US2 流光形态与修复前一致（双层玫瑰/品牌蓝沿卡边流动，无错位/裁剪/发暗）、FAB 新对话正常、idle 态无流光、输入卡布局无错位；截屏（.jpeg）+dumpLayout（UTF8）+hilog（FATAL=0）取证

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: 无依赖，立即开始
- **Implementation (Phase 2)**: T002 依赖 T001 锚点确认；T003 依赖 T002
- **Verification (Phase 3)**: 依赖 Phase 2 完成

### Within Each Phase

- 全程串行，无并行任务（单文件定点改造）
- T002 是全部实现改动所在；T003 仅静态检查与残留 grep

### Parallel Opportunities

- 无（本特性单文件串行）

---

## Parallel Example: （本特性无并行任务）

```bash
# 全部串行：
Task: "T001 锚点勘察"
Task: "T002 输入卡 z 序重构"
Task: "T003 arkts_check + grep 残留"
```

---

## Implementation Strategy

### Single-Pass Fix

1. Complete Phase 1: Setup（锚点确认）
2. Complete Phase 2: Implementation（z 序重构 + 静态检查）
3. Complete Phase 3: Verification（构建/部署/UI 逐条验收）

### Incremental Delivery

1. T001 → 确认结构与 spec 一致
2. T002 → 一次改到位（删 overlay/@Builder + 包裹 Stack + 属性迁移）
3. T003 → 静态检查清零
4. T004-T006 → 验证与逐条验收

---

## Notes

- [P] tasks = different files, no dependencies（本特性无）
- [Story] label maps task to specific user story for traceability
- 服务端零改动；客户端仅 1 文件改造
- ArkTS 硬规则：无 any/unknown、显式类型、build() 顶层无局部声明、禁止裸对象字面量、V1 状态管理
- 构建前必过 `arkts_check`
- 验证环境：模拟器 127.0.0.1:5555，服务器 s3.z100.vip:35796；锁屏密码 Abc541755
- 触控：`hdc -t 127.0.0.1:5555 shell "uinput -T -c <x> <y>"`；返回键 `uinput -K -d 2 -u 2`
- 坐标（模拟器 1280×2832）：发送 (1092,2325)；操作行 y≈2325：plus(177)/wand(317)/mic(457)/model(634)；以 dumpLayout 实测为准
- 杀 App：`hdc -t 127.0.0.1:5555 shell aa force-stop com.octop.link`
- 仅模拟器部署；真机（192.168.3.190:44541）仅用户明确要求时推送
