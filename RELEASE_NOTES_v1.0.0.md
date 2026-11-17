## OctopLink v1.0.0

首个正式版本，HarmonyOS ArkTS 客户端，连接 TencentCloud / Octop 智能体平台。

### 核心功能
- **多智能体对话**：流式 SSE + WebSocket 双通道，支持 HITL 交互确认
- **智能体管理**：创建/编辑/共享/发布为专家，团队协作
- **工作区**：文件树、知识库、技能/技能包、子代理、定时任务、连接器
- **语音交互**：STT/TTS（含本地 TTS 配置）
- **记忆系统**：候选审核、强记忆、每日记忆、抽取配置
- **Bridge 远程能力**：对端专家连接管理
- **SSO/OAuth**：邀请码注册、OIDC 授权
- **管理员运维**：备份、存储后端、安全、环境变量、Langfuse、用量统计
- **UI 特性**：沉浸式全屏、深色/浅色/跟随系统、宠物吉祥物（5种心情）、命令面板

### 构建信息
- **包名**: com.octop.link
- **版本**: 1.0.0 (versionCode: 1000000)
- **目标 SDK**: HarmonyOS 26 (API 26)
- **签名**: Release 证书已签名
- **架构**: arm64 (HarmonyOS 标准设备)

### 安装方式
```bash
# 通过 hdc 安装到设备/模拟器
hdc install OctopLink-signed.hap
```

### API 对接
完整 API 契约见 [docs/api-contract.md](https://github.com/dwc13775953197-spec/OctopLink/blob/master/docs/api-contract.md)