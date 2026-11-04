# Feature Specification: OctopPet 吉祥物动效素材集成（mascot-integration）

**Created**: 2026-11-01  
**Status**: Approved（用户已确认"把能加上的都加上"）  
**Input**: User decision: 将 OctopPet（MIT, github.com/jubaoliang/OctopPet）仓库的两个动画 WebP 吉祥物素材全场景集成到 OctopLink。

## Overview

将调研确认的两个 MIT 许可动画 WebP 章鱼吉祥物素材集成到 OctopLink 的等待、空态与品牌场景中：**打字章鱼（type.webp，88×44px，24 帧）**用于 AI 思考等待指示，**探头章鱼（peek.webp，96×64px，30 帧）**用于各类空状态引导，并在关于页新增 MIT 开源致谢。目标是强化章鱼品牌形象、提升等待与空态场景的趣味性和情感温度。

### 素材清单（已提取至本地，随包分发）

| 素材 | 源路径（仓库内） | 规格 | 内容描述 | 目标资源名 |
|---|---|---|---|---|
| type（打字） | `public/mascots/type.webp` | 88×44px，~24 帧，无限循环，透明通道，369KB | 红色章鱼单眼眨眼、使用笔记本电脑打字，电脑盖有章鱼骷髅标志 | `octop_mascot_type.webp` |
| peek（探头） | `public/mascots/peek.webp` | 96×64px，~30 帧，无限循环，透明通道，243KB | 粉红色章鱼大眼睛从白色横幅后探出头，周围黄色闪光星星 | `octop_mascot_peek.webp` |

**本地源文件**（Phase 4 复制到 `resources/base/media/`）：
- `C:\Users\13775\AppData\Local\Temp\deveco\octoppet_src\jubaoliang-OctopPet-4ed0711\public\mascots\peek.webp`
- `C:\Users\13775\AppData\Local\Temp\deveco\octoppet_src\jubaoliang-OctopPet-4ed0711\public\mascots\type.webp`

## User Scenarios & Testing *(mandatory)*

### User Story 1 - 思考胶囊打字章鱼（Priority: P1）

用户发送消息后，AI 处于等待/流式生成阶段时，聊天页输入区上方浮出的品质思考胶囊（玻璃胶囊 + 状态文本）中，当前居中的静态 logo 图标升级为"打字章鱼"动画——红色章鱼在笔记本上敲键盘，向用户传达"AI 正在忙"的具象化状态；原有的玫瑰/品牌蓝双弧线环绕动画保留。

**Why this priority**: 思考胶囊是聊天主流程中最高频可见的等待场景，打字章鱼与"AI 正在思考/生成"语义完全契合，是素材价值最大化的落点。

**Independent Test**: 进入聊天页发送一条消息，观察输入区上方思考胶囊出现打字章鱼动画并可正常随流式结束消失。

**Acceptance Scenarios**:

1. **Given** 空闲聊天页，**When** 用户发送消息进入 streaming 且 streamPhase 非空，**Then** 思考胶囊出现，胶囊内显示打字章鱼动画（循环播放）+ 状态文本 + 保留的双弧线环绕动画
2. **Given** streaming 结束，**When** streamPhase 清空，**Then** 思考胶囊（含打字章鱼）整体消失，无残留
3. **Given** 思考胶囊显示中，**When** 用户浏览消息列表，**Then** 胶囊不遮挡列表滚动交互（现有 hitTestBehavior 行为不回归）

---

### User Story 2 - 空会话欢迎卡探头章鱼（Priority: P1）

用户进入一个没有消息的空会话（或默认聊天 Tab 空态）时，欢迎卡片上方出现"探头章鱼"动画——粉红章鱼从横幅后探出头偷看用户——作为空态引导的情感化装饰，欢迎文案与最近会话卡逻辑保持不变。

**Why this priority**: 空会话是每个新用户的第一个画面，探头章鱼"偷看"姿态与"开启一段新对话吧"文案语义天然契合，强化第一印象。

**Independent Test**: 进入聊天页选择/新建空会话，观察欢迎卡上方出现探头章鱼动画。

**Acceptance Scenarios**:

1. **Given** 无消息的空会话，**When** 聊天内容区渲染，**Then** WelcomeCard 上方居中显示探头章鱼动画（循环播放），下方欢迎文案与最近会话卡不回归
2. **Given** 会话出现消息，**When** 空态切换为消息列表，**Then** 探头章鱼随 WelcomeCard 一并消失，消息列表布局不受影响

---

### User Story 3 - 通用空态组件探头章鱼（Priority: P2）

全 App 使用的通用空态组件 `EmptyView`（当前为 SymbolGlyph 图标 + 圆形底，30+ 处复用）默认图标升级为探头章鱼动画，使专家列表、会话列表、工作台等所有列表/数据空态获得统一的品牌化情感表达；组件保留可选参数以回退原 SymbolGlyph 图标形态。

**Why this priority**: EmptyView 是全 App 空态的唯一汇聚点，单点改动覆盖面最广，但属装饰性增强，优先级次于聊天主流程两个场景。

**Independent Test**: 打开任一空数据页面（如专家列表无数据时），观察空态图标位置显示探头章鱼动画。

**Acceptance Scenarios**:

1. **Given** 任一使用 EmptyView 的页面数据为空，**When** 空态渲染，**Then** 图标区域显示探头章鱼动画替代原 SymbolGlyph，标题/副标题文案与布局不回归
2. **Given** EmptyView 使用方显式指定回退模式，**When** 空态渲染，**Then** 显示原 SymbolGlyph 形态（向后兼容）
3. **Given** EmptyView 在同一页面被多次复用（如 SkillsPage 两处），**When** 空态渲染，**Then** 每处独立正常显示章鱼动画，无闪烁或错位

---

### User Story 4 - 关于页开源致谢（MIT 合规）（Priority: P1）

关于页新增"开源致谢"卡片，注明吉祥物动效素材源自开源项目 OctopPet（MIT License）及其作者，履行 MIT 许可证的版权与许可声明保留义务。

**Why this priority**: MIT 许可证合规是使用素材的法律前提，必须与本批素材落地同步交付。

**Independent Test**: 进入"我的"→"关于"页，滚动可见开源致谢卡片及 OctopPet MIT 声明文案。

**Acceptance Scenarios**:

1. **Given** 关于页，**When** 页面渲染完成，**Then** 版本卡下方出现"开源致谢"卡片，含"吉祥物动效素材源自开源项目 OctopPet（作者 jubaoliang），基于 MIT License 使用"语义的文案
2. **Given** 版本号加载失败回退静态文本，**When** 关于页渲染，**Then** 致谢卡仍正常显示（与版本逻辑解耦）

---

### Edge Cases

- 动画 WebP 解码失败或设备不支持动图播放时：Image 静态显示首帧，UI 不空白、不崩溃（Image 组件原生降级行为，需验证不报错）
- 像素风素材放大显示时必须保持锐利（禁用默认插值模糊），避免发糊破坏像素风观感
- 章鱼动画均为无限循环小尺寸（96×64 / 88×44）区域动效，需注意持续动画的功耗影响，仅在对应状态可见时渲染（随 if 条件挂载/卸载，沿用现有思考胶囊策略）
- peek 素材含白色横幅设计元素，在深色背景上形成视觉焦点属预期效果，不做二次抠图处理

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: 系统 MUST 将 `peek.webp`、`type.webp` 以资源名 `octop_mascot_peek`、`octop_mascot_type` 加入应用媒体资源目录，随包分发
- **FR-002**: 思考胶囊（OctopThinkingIndicator）在 streaming 且 streamPhase 非空时 MUST 于双弧线环绕中心显示打字章鱼循环动画，替代原静态 logo；弧线环绕动画与胶囊结构不回归
- **FR-003**: 思考胶囊随流式结束 MUST 整体消失，打字章鱼动画同步停止渲染（组件卸载）
- **FR-004**: 空会话状态（emptyStateBuilder）MUST 在 WelcomeCard 上方显示探头章鱼循环动画；欢迎文案、最近会话卡、有消息后的切换行为不回归
- **FR-005**: EmptyView 默认 MUST 显示探头章鱼循环动画替代原 SymbolGlyph 圆形图标形态；MUST 提供显式参数回退原形态，且现有调用方不传参数即获得章鱼形态（默认升级）
- **FR-006**: EmptyView 的标题、副标题、整体布局与对齐 MUST 与升级前保持一致（仅图标区变化）
- **FR-007**: 关于页 MUST 包含开源致谢卡，注明吉祥物素材源自 jubaoliang/OctopPet 且基于 MIT License 使用
- **FR-008**: 所有章鱼 Image MUST 使用无损缩放插值配置保持像素风锐利，且不得拉伸变形（保持素材原始宽高比 88:44 与 96:64）
- **FR-009**: 章鱼动画 MUST 仅在其承载状态可见时渲染（随条件挂载/卸载），空闲态不得存在持续渲染的隐藏动画

### Key Entities

- **MascotAsset（资源常量）**: 两个应用媒体资源 `octop_mascot_peek`（探头章鱼）、`octop_mascot_type`（打字章鱼），动画 WebP 格式，透明通道，无限循环

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: 聊天发送消息后思考胶囊内可见循环播放的打字章鱼，流式结束后胶囊消失，全程无白屏/闪烁/崩溃
- **SC-002**: 空会话欢迎卡上方可见探头章鱼动画，会话产生消息后正确消失
- **SC-003**: 任一 EmptyView 空态页（抽查 ≥2 处：专家列表空态 + 会话/工作台类空态）显示探头章鱼动画，文案布局零回归
- **SC-004**: 关于页可见含 OctopPet MIT 语义的开源致谢文案
- **SC-005**: 本批改动后全 App 构建零错误，模拟器实测 FATAL=0，非本批场景页面（登录页、工作台正常态、我的页等）视觉零变化

## Assumptions

- 素材许可证为 MIT（已核实仓库 LICENSE），致谢文案放关于页即满足"保留版权与许可声明"义务，无需在素材旁重复标注
- HarmonyOS ArkUI Image 组件原生支持动画 WebP 自动循环播放；若模拟器实测个别场景不自动播放，以静态首帧呈现为可接受降级（不阻塞验收，但需在验证报告中注明）
- 像素风放大产生的颗粒感为素材固有风格，不视为缺陷
- EmptyView 默认升级为章鱼形态是用户"把能加上的都加上"的直接要求；回退参数仅为工程灵活性保留，本批不修改任何现有调用方
- 服务器零改动；素材完全本地化，离线可用
- 用户长期指令"不需要再次询问，直接执行"继续适用，SDD 各阶段确认门全部跳过

## Open Questions

（无——素材规格、许可证、集成场景均已调研确认，用户已明确"把能加上的都加上"）
