# OctopLink

HarmonyOS ArkTS 客户端，连接 TencentCloud / Octop 智能体平台。

## 项目简介

OctopLink 是一个基于 HarmonyOS (ArkTS) 的智能体对话客户端，为 TencentCloud Octop 平台提供完整的智能体交互体验。支持多智能体管理、流式对话、工作区文件操作、记忆系统、定时任务、语音交互、Bridge 远程对端等能力。

## 技术栈

- **HarmonyOS** (API 26, stageMode)
- **ArkTS** (TypeScript 风格)
- **Hvigor** 构建工具
- **JWT Bearer** 认证
- **WebSocket / SSE** 实时通信

## 功能特性

### 核心对话
- 多智能体切换与管理
- 流式对话（SSE + WebSocket 双通道）
- 消息历史查看与导出
- HITL（Human-in-the-Loop）交互确认
- Markdown 消息渲染

### 智能体管理
- 创建/编辑/删除智能体
- 智能体共享与权限控制
- 发布为专家（Expert）
- 团队协作（Teams）

### 工作区
- 文件树浏览与读写
- 知识库文档管理（上传/索引/OCR）
- 技能（Skills）安装与管理
- 技能包（Skill Packages）
- 子代理（Subagents）管理
- 定时任务（Cron）调度
- 连接器（Connectors）配置

### 语音与多媒体
- STT 语音转文字
- TTS 文字转语音（含本地 TTS）
- 语音设置与管理

### 记忆系统
- 候选记忆审核
- 强记忆管理
- 每日记忆
- 记忆抽取与存储配置

### Bridge 远程能力
- 对端专家连接管理
- 隧道探测与连接/断开

### 系统与运维
- SSO（OAuth/OIDC）授权
- 邀请码注册与兑换
- 管理员运维面板（备份/存储/安全/环境变量/Langfuse）
- 用户与权限管理
- 使用量统计与导出

### UI 特性
- 沉浸式全屏布局
- 浅色/深色/跟随系统外观模式
- 宠物吉祥物（聊天头部，五种心情状态）
- 命令面板（Command Palette）
- 丰富的自定义组件库

## 项目结构

```
OctopLink/
├── entry/                        # 应用主模块
│   ├── src/main/ets/
│   │   ├── components/           # 可复用 UI 组件
│   │   ├── entryability/         # 应用入口 Ability
│   │   ├── model/                # 数据模型
│   │   ├── net/                  # 网络层（HTTP/SSE/WS）
│   │   ├── pages/                # 页面
│   │   │   ├── chat/             # 对话相关页面
│   │   │   ├── expert/           # 专家管理页面
│   │   │   ├── me/               # 个人中心页面
│   │   │   └── workspace/        # 工作区页面
│   │   ├── pet/                  # 宠物吉祥物
│   │   ├── service/              # 业务服务层
│   │   ├── store/                # 状态管理
│   │   └── utils/                # 工具类
│   └── src/main/resources/       # 资源文件
├── docs/                         # 文档
│   ├── api-contract.md           # API 契约文档
│   ├── api-gap-audit.md          # API 覆盖度审计
│   └── pet-design.md             # 宠物设计文档
├── spec/                         # 规格与设计
└── AppScope/                     # 应用配置
```

## 开发环境

- HarmonyOS SDK 26.0.0
- Node.js 18+
- Hvigor 构建工具

## 构建与运行

```bash
# 安装依赖
npm install

# 构建调试版本
hvigorw assembleDebug

# 构建发布版本
hvigorw assembleRelease
```

## 认证

客户端通过 JWT Bearer Token 与 Octop 服务端交互：
- 登录接口：`POST /api/auth/login`
- 滑动续期：响应头 `X-Octop-Access-Token` 自动替换过期 token
- WebSocket 连接：`/api/agents/{id}/chat/ws?token=<token>`

## API 对接

完整的 API 契约见 [docs/api-contract.md](docs/api-contract.md)，覆盖认证、智能体、会话线程、工作区、知识库、技能、记忆、Bridge 等全部领域。

## License

Apache License 2.0