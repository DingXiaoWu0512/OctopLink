# Octop Link API 契约（服务端源码实证版）

> 依据 TencentCloud/Octop 服务端源码（main 分支，2026-10 抓取）整理，供 HarmonyOS 客户端（Octop Link）对接使用。
> 所有字段名、帧类型、错误码均直接来自源码，未做任何推测。Sources 见文末。

## 0. 基础约定

- Base URL：`https://<octop-server>`（下文省略），所有 REST 接口前缀 `/api`。
- 请求/响应体均为 UTF-8 JSON（除 SSE 与文件上传）。
- 认证：JWT Bearer Token。
  - 请求头 `Authorization: Bearer <access_token>`，或查询参数 `?access_token=<token>`（WS 用 `?token=`，见 §5.1）。
  - 滑动续期：token 接近过期时，任意 `/api/*` 响应携带 `X-Octop-Access-Token` 头，内含新 token，客户端应静默替换。
  - 除豁免路径（登录、验证码、setup 等）外，所有 `/api/*` 均要求 JWT；未认证返回 401 + 标准错误包络（§7）。
- 鉴权模型：
  - admin 全放行；普通用户仅能访问 `user_id == 自己` 的 agent/thread；
  - `is_shared=1` 的 agent 对所有登录用户开放（只读对话）；
  - `as_user` 查询参数仅 admin 可用（以其他用户身份操作）。

## 1. 认证

### 1.1 登录 `POST /api/auth/login`

请求：
```json
{
  "username": "user 或 email",
  "password": "明文密码",
  "captcha_token": "可选，验证码开启时必填（max 4096）"
}
```

响应 200：
```json
{
  "access_token": "<JWT>",
  "token_type": "Bearer",
  "expires_in": 3600,
  "user": {
    "id": 1,
    "username": "admin",
    "role": "admin",
    "display_name": "Admin",
    "locale": "zh",
    "permissions": ["..."]
  }
}
```

错误：
| code | HTTP | 说明 |
|---|---|---|
| `SETUP_REQUIRED` | 409 | 系统尚无任何用户（未初始化管理员） |
| `AUTH_FAILED` | 401 | 用户名或密码错误（本地失败且 LDAP 不接管时） |
| `LOGIN_LOCKED` | 429 | 登录尝试次数过多 |
| `CAPTCHA_REQUIRED` | 400 | 需要验证码 |

### 1.2 验证码配置 `GET /api/auth/captcha`

响应：`{"provider": "none|turnstile|geetest...", "site_key": "可选"}`（无 secret）。用户数为 0 时返回 `SETUP_REQUIRED`。

### 1.3 其他

- `GET /api/auth/me`：当前用户 profile（含 `sso_linked`、`has_password`、`avatar_url` 等）。
- `POST /api/auth/logout`：204，仅审计，JWT 不做服务端吊销。
- `POST /api/auth/change-password`：`{old_password, new_password}` → 204。

## 2. Agents（智能体）

### 2.1 列表 `GET /api/agents?scope=mine|all`

- `scope=mine`（默认）：自己拥有的 + 其他人显式共享（`is_shared=1`）的 agents。
- `scope=all`：全部（需 `users` 权限，否则 `FORBIDDEN`）。

响应为对象数组，每项字段（`_row_dict`）：
```
id, agent_id, user_id, name, description, persona_mbti, default_model,
system_prompt, state, last_error, config, icon, template_name,
icon_name, icon_url, color, skill_package_ids, knowledge_base_ids,
mcp_servers, published_expert_id, welcome_message, is_shared,
is_owner, owner_username, kind("expert"|"team"), unread_count,
bootstrap_pending, member_ids(仅 team)
```

### 2.2 其他 agent 端点

- `GET /api/agents/{agent_id}`：单个详情（owner 或 shared 可见）。
- `POST /api/agents`：创建（`AgentCreateBody`：name 必填，另含 description / persona_mbti / default_model / system_prompt / config / icon / is_shared / color / icon_name / icon_url / welcome_message / skill_package_ids / knowledge_base_ids / mcp_servers）。
- `PATCH /api/agents/{agent_id}`、`DELETE /api/agents/{agent_id}`：owner/admin。
- `POST /api/agents/{agent_id}/avatar`（multipart 上传）、`GET .../avatar`、`DELETE .../avatar`。
- `POST .../start|stop|reload`：204；`GET .../status`。

## 3. 会话线程（Threads）

所有路径前缀 `/api/agents/{agent_id}`。`as_user` 为 admin 专用查询参数。

| 方法/路径 | 说明 |
|---|---|
| `GET /threads?limit=50&as_user=` | 线程列表（见下） |
| `POST /threads` | 新建会话，返回 `{"thread_id": "...", "session_key": "..."}`（同时重置该用户 dashboard 绑定） |
| `GET /threads/{thread_id}/history?limit=25&offset=0&cursor=` | 历史消息（§6） |
| `PATCH /threads/{thread_id}` | 重命名/置顶/组合器设置：`{title?, pinned?, model_ref?, reasoning_mode?, reasoning_effort?, conversation_mode?, hitl_policy?}` |
| `DELETE /threads/{thread_id}?compact=` | 删除线程（先删 checkpoint，失败报 `CHECKPOINT_DELETE_FAILED` 409） |
| `POST /threads/{thread_id}/read` | 清除未读（204） |
| `POST /threads/{thread_id}/fork` | 从某条 assistant 消息分叉：`{message_id?, content?, assistant_turns_from_end?}`（201） |
| `PATCH /session` | 重绑会话：`{"thread_id": "..."}` → `{"session_key", "thread_id"}` |
| `GET /threads/{thread_id}/context-usage` | 上下文窗口用量 |

线程列表项字段：
```
thread_id, title, channel_type, session_key, last_active, created_at,
is_active, has_messages, pinned, model_ref, reasoning_mode,
reasoning_effort, conversation_mode("ask"|"plan"|"craft"，默认 craft),
pending_plan_path, hitl_policy, turn_active(该线程正在流式输出),
awaiting_user(线程暂停在 HITL 审批), artifacts...
```

历史分页：默认 `limit=25`，最大 `200`；`has_more` 为 true 时用 `offset` 或（版本化历史开启时）`next_cursor` 翻页。

## 4. 聊天欢迎语与提示

- `GET /api/agents/{agent_id}/chat/welcome`：空会话欢迎卡片（welcome_message zh/en、quick_prompts、task_examples）。
- `POST /api/agents/{agent_id}/chat/polish`：`{text, default_model?}` → `{"text": "润色后的提示词"}`。

## 5. WebSocket 流式聊天协议

### 5.1 端点与握手

```
GET wss://<host>/api/agents/{agent_id}/chat/ws?token=<JWT>
```

- `token` 必填；服务端 `accept()` 前的失败以**关闭码**表达：
  - `4001`：缺少 token（reason `missing token`）或 token 无效/过期（reason `auth: <ErrorCode>`，如 `auth: TOKEN_EXPIRED`）
  - `4003`：agent 存在但无权访问（`FORBIDDEN`）
  - `4404`：agent 不存在（`AGENT_NOT_FOUND`）
  - `1011`：gateway 未就绪
- accept 之后的错误一律走 `error` 帧（§5.3）。
- 鉴权模型同 REST：owner / admin / shared（`is_shared=1`）可对话。
- **断线不取消进行中的 turn**：客户端可重连 + `subscribe` 续流（弱流恢复）。

### 5.2 客户端 → 服务端帧

| type | 载荷 | 说明 |
|---|---|---|
| `ping` | `{}` | 心跳，服务端回 `pong` |
| `subscribe` | `{thread_id}` | 订阅线程：回放成员追赶帧 + `turn_status` + steer 快照；线程不存在回 `error` |
| `user_turn` | 见 §5.2.1 | 发起一轮对话 |
| `cancel` | `{thread_id}` | 取消进行中的 turn（同时丢弃未 drain 的 steer） |
| `steer_remove` | `{thread_id, turn_id, client_pending_id, pending_id}` | 撤回已排队的 steer |
| 其他/未知 type | — | 服务端回 `{"type":"error","message":"unknown message type: ..."}` |

注意：发送**非 JSON 文本**时，服务端按 `{"type":"user_turn","text":"<原文>"}` 处理。

#### 5.2.1 `user_turn` 字段（`UserTurnWsFrame` / `ChatTurnBody`）

```jsonc
{
  "type": "user_turn",
  "text": "用户消息纯文本（与 messages 二选一或并用）",
  "messages": [ { "role": "user", "content": "文本 或 内容块数组" } ],
  "thread_id": "已有线程 id；省略则复用/新建该用户+agent 的 dashboard 会话线程",
  "session_key": "可选，默认 dashboard key",
  "model": "模型 ref，如 openai/gpt-4o",
  "mcp_servers": ["连接器名"],          // 显式传 [] 表示本轮关闭默认 MCP
  "knowledge_base_ids": ["kb id"],      // 显式传 [] 表示本轮关闭默认知识库
  "skills": ["技能名"],
  "target_agent_ids": ["@提及的 agent"],
  "reasoning_mode": "auto|enabled|disabled",
  "reasoning_effort": "low|medium|high",
  "conversation_mode": "ask|plan|craft", // ask 只读；plan 写 plans/*.md；craft 默认
  "hitl_policy": { "mode": "ask|allow_all|allow_tools", "tools": [] },
  // —— steer（turn 进行中追加消息）——
  "delivery": "auto|steer|follow_up",
  "client_pending_id": "客户端生成 UUID，steer 关联必填",
  "expected_turn_id": "turn.started/turn.resumed 返回的 turn_id"
}
```

### 5.3 服务端 → 客户端帧（完整清单）

#### A. 内容帧（harness stream chunks，经网关原样转发，`wire protocol mirrors harness stream chunks`）

| type | 关键字段 | 说明 |
|---|---|---|
| `token` | `content`（**增量文本**）、`node`、`agent_id`（团队成员发言者）、`team_snapshot`、`team_live`、`team_wrapup` | 助手文本增量，**delta 字段名为 `content`** |
| `reasoning` | `content` | 思考链增量 |
| `tool_call_chunk` | `id`、`name`（分片累积）、`args`（分片）、`index`、`agent_id`、`display_name` | 工具调用流式分片 |
| `tool_result` | `node`、`messages`、`agent_id` | 工具执行结果 |
| `usage` | token 用量统计 | 回合用量 |
| `done` | `conversation_mode`、`pending_plan_path`、`hitl_paused`、`team_member_continuing`、`team_wrapup` | harness 流结束 |
| `error` | `message`、`error_code`（可选） | 流内错误（附 error 气泡） |
| `hitl_required` | `request`（含 `action_requests`、服务端注入的 `pending_id`） | 图中断，等待人工审批；**视为流终止**，恢复走 SSE（§5.6） |
| `slash_action` | `action`、`agent_id`、`mode` | 斜杠命令动作 |
| `attachment` | `kind`、`mime_type`、`data`(base64) 或 `url`/`preview_url`、`filename`、`alt_text` | 附件/媒体 |
| `state_update` / `state_snapshot` | 上下文用量 | |
| `custom` | `data` | 决策（decision）通知等 |

#### B. 网关/WS 层帧

| type | 关键字段 | 触发时机 |
|---|---|---|
| `pong` | — | 心跳应答 |
| `turn_status` | `thread_id`、`active`(bool) | `subscribe` 的状态应答；`active=true` 表示服务端仍在流式输出（弱流恢复判定） |
| `turn.started` | `turn_id`、`seq`、`phase:"streaming_text"`、`thread_id` | 新 turn 开始（记下 `turn_id` 供 steer） |
| `turn.resumed` | `turn_id`、`seq`、`phase:"between_model_steps"`、`thread_id` | steer drain 后继续同一逻辑 turn |
| `turn.ended` | `turn_id`、`thread_id`、`failed`(bool\|null)、`hitl_paused`(可选 true) | **turn 终止** |
| `steer.queued` | `seq`、`client_pending_id`、`pending_id`、`turn_id`、`queue_length`、`preview`、`thread_id` | 排队成功（广播到线程） |
| `steer.ack` | `status`("queued"/"rejected"/"removed")、`turn_id`、`pending_id`、`client_pending_id`、`message_id`、`reason`、`thread_id` | 仅发送方收到的应答 |
| `steer.drained` | `seq`、`client_pending_ids`、`pending_ids`、`turn_id`、`message_id`、`thread_id` | 排队消息被合并执行 |
| `steer.discarded` | `seq`、`client_pending_ids`、`pending_ids`、`turn_id`、`reason`、`thread_id` | 排队消息被丢弃（取消/过期等） |
| `steer.removed` | `seq`、`client_pending_id`、`pending_id`、`turn_id`、`already_drained`、`already_gone`、`thread_id` | 撤回成功 |
| `steer.rejected` | `seq`、`client_pending_id`、`reason`、`active_turn_id`、`thread_id`、`gateway_class` | 排队被拒绝（如缺 `client_pending_id` / `expected_turn_id` 过期）。**注意：拒绝不会发 `error` 帧** |
| `steer.queue_snapshot` | `turn_id`、`items[]` | 重连后服务端权威队列快照 |
| `user` | `content`、`message_id`、`meta:{steer:true}`、`thread_id`、`attachments`(可选) | drain 后服务端合成的正式用户气泡 |
| `error` | `message`（WS 层错误：帧校验失败、subscribe 线程不存在、empty message、内部错误等） | 校验类错误后紧跟 `done` |
| `done` | — | 与 WS 层 `error` 成对出现，表示本轮终止 |

### 5.4 流结束判定（与官方 Dashboard 一致）

- 终止帧：`turn.ended`、`error`、`hitl_required`。
- harness `done`：仅当客户端未持有 `activeTurnId`（无逻辑 steer turn）时才结束 1:1 会话；团队房间（team）与 bridge 房间须在 `turn.ended` 后保持 socket。
- 客户端过滤规则：帧带 `thread_id` 且与本地不符则丢弃；不带 `thread_id` 的帧（pong、部分 error）直接通过。

### 5.5 典型对话时序

新会话：
```
客户端                                   服务端
│ POST /api/agents/{id}/threads          │ → {thread_id, session_key}
│ WS connect /chat/ws?token=JWT          │ (101)
│ {"type":"subscribe","thread_id":T}     │
│                                        │ ← {"type":"turn_status","thread_id":T,"active":false}
│ {"type":"user_turn","text":"hi",       │
│  "thread_id":T}                        │
│                                        │ ← {"type":"turn.started","turn_id":X,"seq":N,...}
│                                        │ ← {"type":"token","content":"你"}
│                                        │ ← {"type":"token","content":"好"}
│                                        │ ← {"type":"usage",...}
│                                        │ ← {"type":"done"}
│                                        │ ← {"type":"turn.ended","turn_id":X,...}
│ GET .../threads/T/history?limit=25     │ （按需刷新历史）
```

工具调用回合：`turn.started` → `token*` → `reasoning*` → `tool_call_chunk*`（name/args 分片累积）→ `tool_result` → `token*` → `done` → `turn.ended`。

HITL 审批：`...` → `hitl_required {request:{...,pending_id}}`（流终止）→ `POST /api/agents/{id}/chat/hitl/resume`（SSE）→ `token*` → `done`。

Steer（turn 进行中追加）：
```
│ {"type":"user_turn","text":"补充...",
│  "thread_id":T,"delivery":"auto",
│  "client_pending_id":"uuid","expected_turn_id":X}
│                                        │ ← {"type":"steer.ack","status":"queued",...}
│                                        │ ← {"type":"steer.queued","preview":"补充...",...}
│            （当前流结束，drain 排队消息）
│                                        │ ← {"type":"user","content":"补充...","message_id":M,"meta":{"steer":true}}
│                                        │ ← {"type":"steer.drained",...,"message_id":M}
│                                        │ ← {"type":"turn.resumed","turn_id":X,...}
│                                        │ ← token* → done → turn.ended
```

### 5.6 HITL 恢复 `POST /api/agents/{agent_id}/chat/hitl/resume`（SSE）

请求（`HitlResumeBody`）：
```json
{
  "thread_id": "T",
  "decisions": [ {"type": "approve"} | {"type": "reject", "message": "..."} |
                 {"type": "respond", "message": "<人工答复>"} | {"type": "edit", "edited_action": {...}} ],
  "hitl_policy": { "mode": "ask", "tools": [] },
  "pending_id": "多张审批卡时必填"
}
```
响应为 `text/event-stream`，`event: chunk` 的 data 为与 WS 相同的 harness 帧序列（`token`/`tool_result`/`done`/`error` 等）。决议格式非法返回 400。

## 6. 历史消息 JSON（`_serialize_history_message` 输出）

`GET /api/agents/{agent_id}/threads/{thread_id}/history` 响应：
```jsonc
{
  "thread_id": "T",
  "messages": [ /* 见下 */ ],
  "has_more": true,
  "limit": 25,
  "offset": 0,
  "next_cursor": null,          // 版本化历史开启时非空
  "history_loading": false,
  "history_status": "ready",
  "history_retry_after_ms": 1500, // history_loading=true 时建议 1.5s 后重试
  "turn_active": false,
  "hitl_pending": null,          // 待审批时为审批卡对象
  "conversation_mode": "craft",
  "pending_plan_path": null,
  "hitl_policy": {"mode": "ask", "tools": []}
}
```

messages 数组元素（role ∈ user | assistant | tool；system 消息被过滤）：

```jsonc
// 用户消息
{
  "role": "user",
  "id": "langgraph message id",
  "content": [ {"type": "text", "text": "这图是啥"} ],
  "timestamp": 1730000000000,          // ms
  "composer_context": { "model_ref": "...", ... },   // 可选
  "inbound_attachments": [             // 可选，用户上传附件
    {"filename": "a.png", "media_type": "image/png", "kind": "image", "workspace_path": "inbound/a.png"}
  ]
}

// 助手消息
{
  "role": "assistant",
  "id": "...",
  "content": [
    {"type": "thinking", "thinking": "推理文本"},
    {"type": "text", "text": "最终回答"},
    {"type": "tool_use", "name": "web_search", "id": "call_x", "input": {"q": "..."}}
  ],
  "usage": {"input_tokens": 100, "output_tokens": 50},   // 可选
  "agent_id": "成员 agent_id",       // 团队发言者，可选
  "timestamp": 1730000000000,
  "status": "error", "error_code": "...",   // 该回合流式失败时
  "team_wrapup": true,                      // 团队总结消息
  "decision": {...}, "edited_files": ["path"]  // 可选
}

// 工具结果消息
{
  "role": "tool",
  "id": "...",
  "agent_id": "...",                  // 可选（团队成员）
  "content": [
    {"type": "tool_result", "id": "call_x", "name": "web_search",
     "output": "文本结果", "artifact": {...}, "error_code": "tool_error"}
  ],
  "timestamp": 1730000000000
}
```

内容块类型全集：`text{text}`、`thinking{thinking}`、`tool_use{name,id,input}`、`tool_result{id,name,output,artifact?,error_code?}`。

## 7. 错误包络与错误码

所有 `OctopError`（含 jwt 中间件 401/403）返回统一包络：
```json
{
  "error": {
    "code": "AGENT_NOT_FOUND",
    "message": "人类可读信息（可本地化）",
    "details": {}
  }
}
```
HTTP 状态由错误码决定。客户端需要处理的核心错误码：

| code | HTTP | 场景 |
|---|---|---|
| `AUTH_FAILED` | 401 | 凭证错误 / JWT 无效 |
| `TOKEN_EXPIRED` | 401 | JWT 过期（应引导重新登录） |
| `SETUP_REQUIRED` | 409 | 服务端未初始化管理员（登录时） |
| `FORBIDDEN` | 403 | 无权访问（非 owner 访问他人 agent/thread） |
| `NOT_FOUND` | 404 | 资源不存在（通用） |
| `AGENT_NOT_FOUND` | 404 | agent / thread 不存在 |
| `AGENT_BUSY` | 409 | agent 忙 |
| `AGENT_NOT_RUNNING` | 409 | agent 未运行 |
| `CHECKPOINT_DELETE_FAILED` | 409 | 线程 checkpoint 删除失败（thread 行保留，可重试） |
| `LOGIN_LOCKED` | 429 | 登录锁定 |
| `CAPTCHA_REQUIRED` | 400 | 需要验证码 |
| `TOKEN_QUOTA_EXCEEDED` | 403 | token 配额超限 |
| `AGENT_QUOTA_EXCEEDED` | 403 | agent 数量配额超限 |
| `SLASH_BAD_ARGS` | 400 | 参数错误（如非法 model ref） |
| `EXPERT_MARKET_FAILED` | 502 | 专家市场请求失败 |
| `INTERNAL_ERROR` | 500 | 服务端内部错误 |

完整错误码枚举见 `src/octop/infra/errors.py`（StrEnum，值=枚举名）。

## 8. 专家（Experts）接口

Octop 的"专家"有两层含义，客户端按需取用：

1. **用户自己的 agents**（§2.1 `GET /api/agents?scope=mine`）——已安装的智能体，含 `welcome_message`、`persona_mbti`、`unread_count` 等，适合做"我的智能体"列表。
2. **内置/市场专家模板**——用于"新建智能体"页：

| 端点 | 说明 |
|---|---|
| `GET /api/experts` | 内置专家摘要列表：`{id, label:{zh,en}, description:{zh,en}, welcome_message:{zh,en}, icon_name, icon_url, color, quick_prompts[], task_examples}` |
| `GET /api/experts/{id}` | 模板详情 + `files`/`prompt_files`/`file_contents` |
| `GET /api/experts/hub?q=&scene=` | SkillHub 市场卡片：`{items:[{id, slug, label, description, scene, sub_scene, icon_url, icon_name, color, skill_slugs, skill_count, source:"skillhub", quick_prompts, task_examples}], scenes:[]}` |
| `GET /api/experts/hub/{slug}` | 市场详情（含 content 与默认 quick_prompts） |
| `POST /api/agents/from-expert/{id}` | 从内置专家创建 agent（`FromExpertBody`，201） |
| `POST /api/experts/hub/{slug}/install` | 从市场专家创建 agent（201） |
| `GET /api/experts/published` / `GET /api/experts/published/{id}` / `POST /api/experts/published/{id}/install` | 用户发布的私有专家模板 |

## 9. Sources（本研究引用的服务端源码）

- https://github.com/TencentCloud/Octop —— `src/octop/api/routers/auth.py`（登录/me）、`agents.py`（agent CRUD）、`experts.py`（专家/市场）、`chat/ws.py`（WS 服务端与关闭码）、`chat/models.py`（UserTurnWsFrame/ChatTurnBody/HitlResumeBody）、`chat/turn.py`（线程解析与 inbound 组装）、`chat/history.py`（线程 CRUD/历史分页）、`chat/serialize.py`（历史消息序列化）、`chat/routes.py`（HITL resume SSE/polish/welcome）、`infra/errors.py`（ErrorCode 与错误包络）、`api/middleware/jwt_auth.py`（JWT 与滑动续期）
- 同仓库 `src/octop/infra/gateway/ws/ws_channel.py`（turn.started/ended、steer 协议帧生成）、`infra/gateway/process/stream_project.py`（帧投影，仅 IM 通道）
- 官方前端参照：`dashboard/src/pages/Chat/hooks/chatStore.ts`（帧消费逻辑、流终止判定、steer 客户端协议）、`dashboard/src/pages/Chat/hooks/frameThread.ts`（帧过滤）、`dashboard/src/utils/parseHarnessChunk.ts`（harness 帧类型定义）

> 注：`{"type":"thread","thread_id":...}` 帧仅出现在 bridge（跨实例桥接）链路中；单实例直连场景下客户端通过 `POST /api/agents/{id}/threads` 或线程列表获得 thread_id，无需依赖该帧。
