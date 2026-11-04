# OctopLink API 覆盖度审计（对照服务端 OpenAPI docs）

> **状态更新（同日）**：本报告列出的 P0/P1 缺失已全部实现并通过编译、推送真机验证。
> 新增/修改：`InviteService`（validate/redeem）、`SsoService`（oauth/oidc start+exchange+oidc status）、
> `MemoryService`（+31 op：候选审核/strong/user/daily/终端五卡/journal/entities/episodes/raw_events/extract-config/growth/storage）、
> `MemoryModels`（+11 模型）、`AgentService`（heartbeat-config/markRead/tool-settings PUT/publish-expert/published 管理/hub 原始列表）、
> `AgentModels`（+HeartbeatConfigModel）、`BridgeService`（+9 op 对端隧道）、`WorkspaceService`（cron settings/KB 头像/connector OAuth）、
> `SkillPackageService`（+6 op）、`ThreadService`（导出/重绑/迁移）、`AuthService.UserService`（permissions/getUser）、
> `AdminService`（+45 op：备份/存储后端/安全/环境变量/Langfuse/更新/TLS/用量）、新增 `FilesystemService`。
> UI：LoginPage（邀请码注册+SSO Web 授权流）、MemoryPage（五分区）、ThreadSettingsPage（心跳卡+历史导出）、
> AgentEditPage（发布为专家）、BridgePage（对端专家）、KnowledgePage（头像）、AdminPage→新增 AdminOpsPage（运维管理）。
> `/api/mobile/status` 在部署服务器上实际存在（401 可达，spec 未收录），App 已改用 spec 内的
> `GET /api/settings/capabilities`（mobile 节点）作为能力判断来源。

- 依据：`http://192.168.3.2:8088/api/openapi.json`（Octop API 0.1.0，424 paths / 536 operations）
- 对象：`entry/src/main/ets` 全部代码（行级扫描，排除注释行；REST + SSE + WS + multipart 全形态）
- 结论速览：**app 覆盖 224 个路径 / 309 个操作（58%）**；请求体字段抽查 **0 处 drift**；1 个死接口；真正值得补的缺失集中在 **记忆系统、SSO/邀请注册、专家发布、Bridge 远端能力**。

## 一、已验证正确的部分（REST）

| 领域 | 覆盖 | 说明 |
|---|---|---|
| 认证 | login/captcha/change-password/me/me-avatar/logout | 字段与 LoginBody 完全一致（username/password/captcha_token） |
| 会话 chat | 13 op：threads CRUD、fork、read、context-usage、history、trajectory(+export/metrics/events)、upload、hitl/resume(SSE) | 发送走 WS `/api/agents/{id}/chat/ws`、通知走 `/api/notifications/ws`（WS 不在 REST spec，正常） |
| 智能体 agents | CRUD、start/stop/reload/status、avatar GET/POST、tool-settings(+单工具) | create/patch 字段全部在 AgentBody schema 内 |
| 渠道 channels | **19/19 全覆盖** | 含钉钉/企微/微信/QQ/飞书/元宝全部扫码绑定 generate+poll、probe、test |
| 连接器 connectors | 22 op | 含 CLI 设备码授权（agently start/status/refresh/logout）、feishu-user-auth、custom-mcp、oauth pending |
| 知识库 knowledge | 20 op | 文档上传(multipart upload 字段)/text 建档/重命名/重索引/预览/原文下载/OCR/ONNX 本地嵌入 |
| 技能 skills | 16 op | CRUD、enable/disable、copy、import、export、push-to-package、hub search/rankings/install |
| 技能包 skill-packages | 8 op | CRUD、avatar、export、from-skillhub、hub/install |
| 子代理 subagents | 5 op | catalog list/divisions/detail + agent 安装列表/install |
| 团队 teams | 3 op | create 含 member_ids |
| MBTI | 7 op 全覆盖 | |
| 语音 voice | 5 op | stt multipart 字段 `audio`+language；tts text/voice_id/speed（客户端还做了 1~8000 字、0.5~2.0 的 422 预裁剪） |
| 用户/组/角色/邀请 | 15 op | 含头像、重置密码、解锁、batch、revoke |
| 定时任务 cron | 4 op | create 字段 trigger/prompt/enabled/fresh_thread/task_type 与 CronBody 一致 |
| 用量 usage | summary + export.xlsx | |
| 工作区文件 workspace | 12 op | tree/file(读+写+删)/doc/mkdir/move/glob/grep/upload/download/archive/mention-index/media-preview |
| 插件 plugins | 9 op | 全局+agent 级+市场+上传安装 |
| Bridge | 连接管理 6 op | probe/connect/disconnect/CRUD |
| 专家 experts | 7 op | 内置列表/详情、hub 详情/安装、published 列表/安装、from-expert |
| SSO 管理 | oauth/oidc/ldap 的 config+test+status | 仅管理端配置 |
| 设置 | capabilities/captcha/hitl/timezone/upload | |
| 管理 admin | overview/users/audit-log/providers(含 codex-oauth)/voice-providers | |

抽查过请求体契约的接口：login、agents create/patch、threads patch（title/pinned/model_ref/reasoning_*/conversation_mode/hitl_policy）、chat upload（字段 `file`）、voice stt/tts、skills create（name/content/overwrite/files）、cron create、teams create（member_ids）、memory atoms replace（assertion）——**均与 schema 一致，未发现字段级 drift**。

## 二、发现的问题

### 2.1 死接口：`GET /api/mobile/status`
`pages/` 下 ToolSettingsPage.ets:66 调用，但 spec 中不存在 `/api/mobile/*`。
后果：远程手机工具不可用时，原因提示永远走兜底文案（“服务器未启用远程手机能力…”）。
建议：确认服务端是否有改名/未发版；否则改从 `GET /api/settings/capabilities` 的 mobile 节点取 reason（app 已解析该结构 MobileCapability）。

### 2.2 P0 缺失（直接影响移动端可用性）

| 缺失 | 端点 | 影响 |
|---|---|---|
| 邀请码注册 | `POST /api/auth/invite/validate`、`POST /api/auth/invite/redeem` | 管理员能发邀请，但新用户在手机上**无法自助注册**，只能去 Web 端 |
| SSO 登录 | `POST /api/auth/oauth/start` + `/exchange`、`oidc/start` + `/exchange`（callback 由系统浏览器承接） | LoginPage 无任何 SSO 入口；服务器关闭密码登录时 App 将无法登录 |
| 记忆候选审核 | `POST /memory/candidates/list` + `:promote` + `:reject` | 记忆写入→确认的闭环断了，MemoryPage 只能看/建/废 atoms |
| 日积月累记忆 | `GET /memory/daily`(列表/单篇/删除 3 op) | 移动端看不到每日记忆 |
| 强记忆/用户画像 | `GET+PUT /memory/strong`、`GET+PUT /memory/user`（+manual-review 2 op） | 用户无法查看/纠正专家对自己的核心记忆 |
| 记忆终端视图 | `GET /memory/terminal/{about_me,current_focus,things_you_told_me,recent_stories,entities}` 5 op | 服务器精心准备的“记忆可视终端”移动端完全没有 |
| 心跳配置 | `GET+PUT /agents/{id}/heartbeat-config` | 主动唤醒(心跳)无法配置 |

### 2.3 P1 缺失（能力在，App 未接）

- **专家发布闭环**：`POST /api/agents/{id}/publish-expert`、`DELETE /api/experts/published/{id}`、`POST .../refresh`、`GET /api/experts/published/{id}`（详情）+ published/hub 头像 2 op —— 能装别人的专家，不能发布自己的
- **Bridge 远端**：`GET /api/bridge/connections/{id}/agents`（列出对端可对话 agents——Bridge 核心价值）、对端 KB/模型/providers 浏览隧道 5 op、头像 3 op
- **连接器 OAuth**：`GET /api/connectors/auth/{kind}/authorize-url` + `POST .../exchange-code` —— 设备码授权已做，网页 OAuth 授权在手机走不通
- **KB 头像与嵌入选项**：avatar GET/POST/DELETE、`GET /api/knowledge-bases/embedding-options`
- **技能包补全**：包级 hub search/rankings、包内技能 file/tree/download、URL 导入（6 op）
- **Agent 编辑深度字段**：spec 支持但编辑页未露出——`config`（temperature/max_iters/max_tokens/top_p 等）、`knowledge_base_ids`、`skill_package_ids`、`mcp_servers`、`visibility/group_ids`；另有 `POST /agents/{id}/read`（标记已读）与 tool-settings 批量 PUT
- **服务器目录选择器**：`GET /api/filesystem/dirs`、`POST /probe`、`/mkdir`、`GET /defaults` 等 9 op —— 创建专家时服务器路径只能手输
- **杂项**：`GET /api/cron/settings`、`GET /api/users/permissions`（权限目录）、`GET /memory/extract-config`+PUT、`GET /memory/journal/recent`、`GET /memory/stats/{growth,atom_kinds}`、`POST /memory/raw_events/list`、`POST /memory/entities/list`、`POST /memory/episodes/list`、`GET /memory/{atoms,candidates,entities,episodes,raw_events}/{id}` 详情 5 op、`GET /memory/portable/sources`、`POST /memory/portable/doctor`、`POST /memory/storage/{maintenance,restore}` + backups 3 op、chat 侧 `GET history/export`、`POST chat/polish`、`PATCH session`、history-migration 2 op
- **Admin 页可扩展**：backup 全套 11 op、storage-backends 11、security/tool-guard 7、envs 3、observability 3、`GET /api/admin/usage/summary`+export、update 状态 6、tls 3

### 2.4 P2：服务器/桌面专属（移动端不建议做）

- `setup` 首次安装向导（10）—— Web 控制台职责
- `browser` 本地 Chrome 控制/录屏(12)、`desktop`(5)、`agent-mcp`/`internal-mcp`(6)、ACP runners(12)
- `ollama`(7)、`onnx` 管理面(8 中 KB 侧已接 4 个)、`plugins` UI 资源(2)
- `terminal context`、`search test`、`media-generation` admin(4)、`settings decision/Laya + downloads`(10)、`storage-backends` 用户面(1)、`plugins upload`(已接)、admin voice 单测(1)

## 三、建议补齐顺序

1. 邀请码注册 + SSO 登录入口（登录可用性，工作量小）
2. 记忆闭环：candidates 审核 + strong/user + daily（MemoryPage 扩两个 Tab 即可承接大部分 op）
3. heartbeat-config（ThreadSettingsPage 加一节）
4. 专家发布/下架（AgentEditPage 加“发布为专家”入口）
5. Bridge 对端 agents 列表
6. Agent 编辑页深度字段（config/KB/技能包/MCP）
