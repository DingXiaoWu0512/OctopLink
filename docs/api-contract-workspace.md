# Octop Link API 契约 · 工作台/设置篇（服务端源码实证版）

> 本文覆盖 `api-contract.md` 未涉及的**工作台/设置类路由**，依据 TencentCloud/Octop 服务端源码（main 分支，2026-10 抓取）整理。
> 基础约定（Base URL、JWT、错误包络、滑动续期）见 `api-contract.md` §0/§7，本文不重复；所有字段名、限制值、错误码均直接来自源码。Sources 见文末。

## 0. 本文补充的通用约定

- **权限依赖**：多数管理端点使用 `require_permission("<key>")`（`src/octop/api/deps.py`）。admin 自动放行；普通用户需在 `permissions` 列表中持有该 key，否则返回 403：
  ```json
  {"error": {"code": "FORBIDDEN", "message": "permission required", "details": {"permission": "users"}}}
  ```
  本文出现的权限 key：`users`、`providers`、`plugins`、`channels`、`connectors`、`knowledge_bases`、`knowledge_settings`、`mbti`、`agent_plugins`、`tools`、`captcha`。
- **`current_user`**：任意已登录用户（无额外权限要求）。
- **上传大小上限**：全局 `max_upload_mb`（config，默认 **100 MiB**，可在 1–1024 间配置，env `OCTOP_MAX_UPLOAD_MB` 覆盖）。客户端应先 `GET /api/settings/upload` 获取实际值。超限错误码均为 `KNOWLEDGE_DOC_TOO_LARGE`(413) / `ATTACHMENT_TOO_LARGE`(413)。
- **JWT 豁免路径**（与本文相关）：`/api/connectors/oauth/callback`（OAuth 回调）、`/api/downloads/link/{token}`（短时下载链接，token 即凭证）。
- 所有时间戳为 Unix 秒（int），除非注明。

## 1. 定时任务（Cron）

挂载：`cron.router → /api`。鉴权：cron 属于 agent 的一部分，**仅 agent owner 可管理**（`user_owns_agent`；非 owner 调列表返回 `[]`，调操作端点返回 `FORBIDDEN` 403；job 不属于该 agent 时 `NOT_FOUND` 404）。

| 方法/路径 | 说明 |
|---|---|
| `GET /api/cron/settings` | 进程级时区：`{"timezone": "Asia/Shanghai"}`（兼容接口，推荐 `GET /api/settings/timezone`） |
| `GET /api/agents/{agent_id}/cron/examples` | 任务页示例提示词：`{"task_examples": {"workspace": ["..."]}}`，与 `.../chat/welcome` 同源 |
| `GET /api/agents/{agent_id}/cron` | 列表（含 disabled） |
| `POST /api/agents/{agent_id}/cron` | 创建（201） |
| `GET /api/agents/{agent_id}/cron/{cron_id}` | 单个详情 |
| `PATCH /api/agents/{agent_id}/cron/{cron_id}` | 更新（部分字段） |
| `DELETE /api/agents/{agent_id}/cron/{cron_id}` | 删除（204） |
| `POST /api/agents/{agent_id}/cron/{cron_id}/run-now` | 立即触发一次（204） |

创建请求体（`CronCreateBody`）：
```jsonc
{
  "name": "可选，缺省由 prompt/cron_id 生成",
  "trigger": "必填。四种形式：cron:0 9 * * * | interval:3600 | date:2030-01-01T08:00:00 | agently:INSTANCE_ID（新邮件事件）",
  "prompt": "必填，触达时执行的提示词",
  "session_key": "可选，缺省用该 user+agent 的 dashboard 会话",
  "fresh_thread": false,          // true=每次运行开新线程
  "enabled": true,
  "model": "可选，模型 ref",
  "task_type": "text",            // 默认 "text"
  "mcp_servers": []               // 会经 validate_chat_mcp_servers 校验
}
```
PATCH（`CronPatchBody`）字段同上、全部可选。

响应（`CronJobRow.to_public_dict(include_agent=True)`）：
```jsonc
{
  "id": "cron_id（ULID）",
  "name": "...", "trigger": "cron:0 9 * * *", "prompt": "...",
  "session_key": "...", "model": null, "fresh_thread": false,
  "enabled": true, "task_type": "text", "mcp_servers": [],
  "last_run_at": 1730000000, "last_status": "ok",
  "agent_id": "agent_xxx", "last_error": null
}
```

关键错误：`CRON_TRIGGER_INVALID` 400（trigger 非法，或 `agently:` 触发源对应的 Agent Mail 连接器不可用/未授权）；`FORBIDDEN` 403；`NOT_FOUND` 404。`date:` 一次性任务运行后自动 `enabled=false`。

## 2. 知识库（Knowledge Bases）

挂载：`knowledge_bases.router → /api`（router 自带 prefix `/knowledge-bases`）。可见性：owner 或 `shared=true` 的库；admin 全部。写操作权限 `knowledge_bases`；服务级配置权限 `knowledge_settings`。

### 2.1 服务能力与配置（knowledge_settings）

| 方法/路径 | 说明 |
|---|---|
| `GET /api/knowledge-bases/capability` | **任意登录用户**。功能开关/模型/OCR 能力 + 限制：`limits: {max_bases_per_owner: 20, max_docs_per_kb: 100, max_document_bytes}` |
| `GET /api/knowledge-bases/embedding-options?all_onnx=` | 嵌入后端选项（onnx 目录 + remote provider 模型） |
| `GET /api/knowledge-bases/ocr-options` | OCR 后端：`{local: {id:"rapidocr", name:"RapidOCR (ONNX)"}, remote: [...]}` |
| `PUT /api/knowledge-bases/feature` | 开关知识库功能：`{enabled, model?, backend?("onnx"\|"remote"), provider_id?, ocr_enabled?, ocr_backend?, ocr_model?, ocr_provider_id?}` |
| `POST .../onnx-download` / `GET .../onnx-download-status` / `POST .../onnx-activate` / `POST .../onnx-test` | 本地 ONNX 嵌入模型下载/激活/测试 |

### 2.2 知识库 CRUD

| 方法/路径 | 说明 |
|---|---|
| `GET /api/knowledge-bases` | 可见库列表（owner + shared；admin 全部） |
| `POST /api/knowledge-bases` | 创建（201） |
| `GET /api/knowledge-bases/{kb_id}` | 详情 |
| `PATCH /api/knowledge-bases/{kb_id}` | 更新 |
| `DELETE /api/knowledge-bases/{kb_id}` | 删除（204） |
| `GET /api/knowledge-bases/default-open` | 当前用户 default-open 的库 id：`{"knowledge_base_ids": []}` |

创建请求体（`CreateBaseBody`）：
```jsonc
{
  "name": "必填，1-200 字符",
  "description": "≤2000，默认 \"\"",
  "default_open": false,
  "shared": false,
  "icon_name": "≤64，默认 \"\"",
  "max_documents": 100   // 可选 0-10000；0=不限，默认 100
}
```
PATCH（`UpdateBaseBody`）字段同上、全可选。

库对象（`KnowledgeBaseRow` asdict + `knowledge_base_id` + owner 信息）：
```jsonc
{
  "id": "kb_xxx", "knowledge_base_id": "kb_xxx", "pk": 1,
  "owner_user_id": 1, "name": "...", "description": "...",
  "default_open": false, "shared": false, "icon_name": "",
  "embedding_model": "...", "embedding_dim": 768, "doc_count": 3,
  "max_documents": 100, "created_at": 1730000000, "updated_at": 1730000000,
  "owner_username": "admin", "owner_display_name": "Admin"
}
```

配额：每用户最多 **20** 个库（`KNOWLEDGE_BASE_LIMIT` 409）。

### 2.3 文档与上传

| 方法/路径 | 说明 |
|---|---|
| `GET /api/knowledge-bases/{kb_id}/documents?prefix=` | 文档列表；`prefix` 设置时仅返回该文件夹的直接子项 |
| `POST .../documents` | **multipart 上传文档**（201），见下 |
| `POST .../documents/text` | 创建 md/txt 文档（201）：`{name(1-200), format("md"\|"txt"), content, path?}` |
| `POST .../folders` | 创建文件夹（201）：`{path(1-500)}` |
| `GET .../documents/{doc_id}/preview` | 抽取文本预览：`{id, filename, text}`（text 截断至 20 万字符） |
| `GET .../documents/{doc_id}/file?disposition=attachment\|inline` | 下载/内联打开原件（FileResponse） |
| `GET .../documents/{doc_id}/content` | 读 md/txt 原文：`{id, filename, content_type, text}` |
| `PUT .../documents/{doc_id}/content` | 覆写 md/txt 并重建索引：`{content}` |
| `POST .../documents/{doc_id}/rename` | 重命名：`{new_name(1-255)}`（文件夹重命名会重写子孙路径） |
| `DELETE .../documents/{doc_id}` | 删除文档/文件夹（204） |
| `POST .../documents/{doc_id}/reindex` | 重建单文档索引 |
| `POST .../{kb_id}/reindex` | 重建全库索引：`{"enqueued": N}` |

**上传端点（multipart/form-data）**：`POST /api/knowledge-bases/{kb_id}/documents`
- 文件字段名：**`upload`**（`File(...)`）；附加 Form 字段 `path`（可选，含文件名的相对路径，用于嵌套文件夹）。
- 大小上限：服务端配置的 `max_upload_bytes`（默认 100 MiB；上限截断为 `KNOWLEDGE_DOC_TOO_LARGE` 413，details 含 `max_mb`）。
- 支持类型（按扩展名映射）：`txt md markdown rst html htm json jsonl yaml yml csv tsv pdf doc wps docx pptx xls xlsx xlsm png jpg jpeg webp`；图片需 OCR 开启，否则报错。不支持的类型 → `KNOWLEDGE_UNSUPPORTED_TYPE` 400。

文档对象（`KnowledgeDocumentRow` asdict + `document_id` + `has_original`）：
```jsonc
{
  "id": "doc_xxx", "document_id": "doc_xxx", "pk": 1, "kb_id": "kb_xxx",
  "path": "a/b.pdf", "filename": "b.pdf", "is_dir": false,
  "content_type": "application/pdf", "byte_size": 10240, "content_hash": "",
  "status": "pending",            // pending → processing → ready / error
  "error_message": "", "chunk_count": 0,
  "created_at": 1730000000, "updated_at": 1730000000,
  "has_original": true
}
```

知识库错误码（全部走标准错误包络）：

| code | HTTP | 场景 |
|---|---|---|
| `KNOWLEDGE_FEATURE_DISABLED` | 403 | 功能未开启 |
| `KNOWLEDGE_PREREQUISITES_FAILED` | 409 | 嵌入/OCR 依赖未就绪 |
| `KNOWLEDGE_PREREQUISITES_RESTART_REQUIRED` | 409 | 安装依赖后需重启服务 |
| `KNOWLEDGE_NOT_FOUND` | 404 | 库/文档不存在 |
| `KNOWLEDGE_FORBIDDEN` | 403 | 无读写权限 |
| `KNOWLEDGE_DOC_LIMIT` | 409 | 文档数超过 per-base 上限 |
| `KNOWLEDGE_DOC_TOO_LARGE` | 413 | 文档超限（details.max_mb） |
| `KNOWLEDGE_BASE_LIMIT` | 409 | 库数量超限（20/用户） |
| `KNOWLEDGE_UNSUPPORTED_TYPE` | 400 | 类型不支持 |
| `KNOWLEDGE_NAME_TAKEN` | 409 | 同路径重名 |
| `KNOWLEDGE_NAME_INVALID` | 400 | 文件名非法 |

## 3. 聊天附件上传（uploads）

挂载：`uploads.router → /api`。

### `POST /api/agents/{agent_id}/upload`（multipart）

- 字段名：**`file`**；admin 可用 `?as_user=`。
- 要求 agent 处于运行中的 workspace（owner/admin）。
- 大小上限：`config.max_upload_bytes`（默认 100 MiB）。
- 媒体类型按 扩展名 → Content-Type → 文件头嗅探 依次判定。

响应 200：
```jsonc
{
  "path": "inbound/a.png",          // workspace 相对路径
  "workspace_path": "inbound/a.png",
  "url": "/api/agents/{agent_id}/files/...（预览 URL）",
  "access_url": "同上",
  "filename": "a.png",
  "media_type": "image/png"
}
```
`path`/`workspace_path` 即 WS `user_turn` 历史里 `inbound_attachments[].workspace_path` 的取值来源。

## 4. 渠道（Channels）

挂载：`channels.router → /api`。权限：`channels`；且要求当前用户是 agent owner（`as_user` 仅 admin）。渠道 kind 支持内置 `ChannelKind` + 已安装渠道插件注册的 kind（大小写归一）。

| 方法/路径 | 说明 |
|---|---|
| `GET /api/channels/plugin-kinds` | 插件贡献的渠道类型（kind/label/icon/intro_url/fields/plugin_id） |
| `GET /api/agents/{agent_id}/channels` | 列表 |
| `POST /api/agents/{agent_id}/channels` | 创建（201）：`{kind, name, config:{}}` |
| `GET /api/agents/{agent_id}/channels/{channel_id}` | 详情（含 `config`） |
| `PATCH .../channels/{channel_id}` | 更新：`{kind?, name?, config?, enabled?}` |
| `DELETE .../channels/{channel_id}` | 删除（204） |
| `POST .../channels/{channel_id}/test` | 用已存配置探测连通性 |
| `POST .../channels/probe` | 用草稿配置探测（不落库）：`{kind, config:{}}` |

列表项：`{id(channel_id), agent_id, kind, name, enabled, runtime?（网关运行状态，可能缺省）}`；详情额外含 `config`（对象）。

扫码/机器人创建辅助端点（均权限 `channels`，agent owner）：
- 钉钉：`POST .../channels/dingtalk/qrcode/generate` → `{registration_id, qrcode_url, user_code, expires_in, interval}`；`POST .../qrcode/poll` `{registration_id}` → `{status: waiting|expired|failed|success, channel_id?, message?}`（success 时自动创建渠道）。
- 企微：`.../wecom/qrcode/generate` / `.../poll`（Body `{"scode": "..."}`）。
- QQ Bot：`.../qq/qrcode/generate` / `.../poll`（Body `{"qrcode_token": "..."}`）。
- 微信：`.../weixin/qrcode/generate` → `{qrcode_token, qrcode_url}`；`.../poll`（长轮询 ~40s，Body `{"qrcode_token"}`）→ `{status: success|wait|error, account_id?, token?, base_url?, message?}`。
- 飞书机器人创建：`.../channels/feishu/bot-creator/start|poll|stop`（start 可带 `{platform:"feishu"|"lark", avatar_url, greeting}`）。
- 元宝：`.../channels/yuanbao/bot-creator/start|poll|stop`。

## 5. 连接器（Connectors / MCP）

挂载：`connectors.router → /api`。连接器实例归 user 所有（admin 可管任何人的）。custom MCP 为"每用户一份 servers 文档"，其余 kind 走实例表。

### 5.1 目录与实例

| 方法/路径 | 权限 | 说明 |
|---|---|---|
| `GET /api/connectors/catalog` | 登录 | 连接器目录（kind、是否可用、OAuth 是否配置） |
| `GET /api/connectors/weknora/detect-local` | 登录 | 探测本机 WeKnora |
| `GET /api/connector-instances` | 登录 | **当前用户**的实例列表（custom MCP 按服务器展开） |
| `POST /api/connector-instances` | 登录 | 创建实例（201），见下 |
| `GET /api/connector-instances/{instance_id}` | owner/admin | 详情（含 `config`、`credentials_preview` 脱敏预览） |
| `PATCH /api/connector-instances/{instance_id}` | owner/admin | 更新 |
| `DELETE /api/connector-instances/{instance_id}` | owner/admin | 删除（204，含撤销授权） |
| `POST /api/connector-instances/{instance_id}/test` | owner/admin | 用存储凭证探测 |
| `POST /api/connector-instances/{instance_id}/refresh` | owner | 刷新 OAuth token：`{"ok": true, "expires_at": ...}` |
| `POST /api/connectors/test-credentials` | 登录 | 创建前试凭证（不落库）：`{kind, credentials:{}}` |

创建请求体（`CreateInstanceBody`）：
```jsonc
{
  "kind": "目录中的 kind（custom_mcp 需走 PUT custom-mcp）",
  "display_name": "必填，实例名（唯一）",
  "description": "可选 ≤500",
  "credentials": {},          // 按 kind 的 auth_kind：api_key / token / code 等
  "shared": false,
  "default_open": false       // true=IM 与无显式选择的 Cron 默认注入此连接器
}
```
PATCH（`PatchInstanceBody`）：`{status?("active"|"disabled"), display_name?, description?, credentials?, shared?, default_open?}`（不能全空）。

实例对象（`_instance_to_dict`）：
```jsonc
{
  "instance_id": "ULID", "kind": "...", "display_name": "...",
  "description": "...", "status": "active", "mcp_server_name": "...",
  "has_credentials": true, "default_open": false, "shared": false,
  "owner_user_id": 1, "created_at": 1730000000, "updated_at": 1730000000
}
```
列表项额外含 `owner_username`、`owner_display_name`、`can_manage`。

### 5.2 自定义 MCP 服务器

| 方法/路径 | 说明 |
|---|---|
| `GET /api/connectors/custom-mcp` | `{servers: {...}}`（langchain-mcp-adapters 形态，API 返回已脱敏） |
| `PUT /api/connectors/custom-mcp` | 整体替换：`{servers: {...}}` |
| `PATCH /api/connectors/custom-mcp/servers/{server_name}` | 单服务器开关：`{enabled?, default_open?, shared?}`（至少一项） |
| `POST /api/connectors/custom-mcp/test` | 探测：`{name?}`（已存）或 `{server: {...}}`（内联 spec） |

### 5.3 OAuth 流程

1. `POST /api/connectors/oauth/start`：`{redirect_after?, target: {"type":"catalog","kind":"notion"} | {"type":"custom_mcp","server_name":"my-server"}}` → `{"authorize_url", "state_id"}`（custom MCP 仅 streamable_http 支持 OAuth；公网回调必须 HTTPS，否则 `CONNECTOR_OAUTH_HTTPS_REQUIRED` 400）。
   - 旧版别名：`POST /api/connectors/oauth/{kind}/start`。
2. 浏览器完成授权 → `GET /api/connectors/oauth/callback`（**无 JWT**，HTML 应答并 postMessage）。
3. `GET /api/connectors/oauth/pending/{state_id}`（一次性读取）→ `{kind, tokens, server_name?, applied?}`，随后用 tokens 调 `POST /api/connector-instances` 落库。

CLI 设备授权（Agent Mail / 飞书等，owner）：
`POST|GET|POST /api/connector-instances/{instance_id}/agently-auth/start|status|logout|refresh`，响应（`AgentlyAuthResponse`）：`{status: "idle"|"pending"|"authorized"|"expired"|"error", verification_url?, user_code?, expires_at?, error?}`。
另有 `POST /api/connectors/feishu-cli/user-auth/start|complete`、`POST /api/connector-instances/{instance_id}/feishu-user-auth/start|complete`、`GET /api/connectors/{kind}/cli-status`、`POST /api/connectors/{kind}/install-cli`（install 需 `connectors` 权限）、`GET /api/connectors/auth/{kind}/info|authorize-url`、`POST /api/connectors/auth/{kind}/exchange-code`。

连接器错误码：`CONNECTOR_NOT_FOUND` 404、`CONNECTOR_NAME_TAKEN` 409、`CONNECTOR_INVALID_CREDENTIALS` 400、`CONNECTOR_KIND_UNSUPPORTED` 400、`CONNECTOR_OAUTH_HTTPS_REQUIRED` 400、`CONNECTOR_MCP_LOAD_FAILED` 502。

## 6. 插件（Plugins）

挂载：`plugins.router → /api`（router prefix `/plugins`）。全局插件管理需 `plugins` 权限；per-agent 开关需 `agent_plugins`；工具配置需 `tools`。

| 方法/路径 | 权限 | 说明 |
|---|---|---|
| `GET /api/plugins` | 登录 | 已安装插件列表 |
| `POST /api/plugins/reload` | plugins | 从磁盘重载（CLI 安装后使用） |
| `POST /api/plugins/install` | plugins | 从 URL 安装 ZIP：`{url}` |
| `POST /api/plugins/upload` | plugins | **multipart**：字段 `file`（ZIP）+ Form `force`（覆盖已装） |
| `GET /api/plugins/market` | 登录 | 市场目录 |
| `POST /api/plugins/market/{plugin_id}/install?force=` | plugins | 从市场安装 |
| `GET /api/plugins/market/{plugin_id}/ui/{file_path}` | 登录 | 市场插件静态资源（icon 等） |
| `PATCH /api/plugins/{plugin_id}` | plugins | 全局启停：`{enabled: bool}` |
| `DELETE /api/plugins/{plugin_id}` | plugins | 卸载 → `{"status":"ok","id":...}` |
| `GET /api/plugins/{plugin_id}/ui/{file_path}` | 登录 | 已装插件静态资源 |

安装/上传响应：`{id, version, name, kind}`。错误：`PLUGIN_INVALID_ARCHIVE` 400（空归档）、`PLUGIN_INSTALL_FAILED` 502、`PLUGIN_ALREADY_EXISTS` 409。

### per-agent 插件开关（agent owner）

- `GET /api/plugins/agents/{agent_id}` →
  ```jsonc
  {"plugins": [{
    "id": "...", "version": "...", "name": "...", "kind": "...",
    "description": "...", "icon": "...", "group": "...",
    "loaded": true, "global_enabled": true, "agent_enabled": true,
    "enabled": true,   // = global_enabled && agent_enabled
    "tools": [{"name": "...", "description": "...", "config_fields": []}]
  }]}
  ```
- `PATCH /api/plugins/agents/{agent_id}`（权限 `agent_plugins`）：`{"plugins": {"<plugin_id>": {"enabled": true}}}`（未知 plugin → `NOT_FOUND`）。
- `GET /api/plugins/agents/{agent_id}/tools` → `{"tools": [{plugin_id, name, description, config_fields, enabled, config}]}`（无显式覆盖时默认 enabled=true）。
- `PATCH /api/plugins/agents/{agent_id}/tools`（权限 `tools`）：`{"plugins": {"<plugin_id>": {"enabled": false, "config": {...}}}}` → `{"status":"ok"}`。

## 7. 模型 Provider

分两组挂载：用户侧 `providers.router → /api/providers`；管理侧 `admin_router → /api/admin/providers`（需 `providers` 权限）。

### 7.1 用户侧（任意登录用户可读）

| 方法/路径 | 说明 |
|---|---|
| `GET /api/providers/presets` | 内置 provider 预设 |
| `GET /api/providers/resolved` | 所有启用 provider 的全部可用模型（agent 模型选择器数据源） |
| `GET /api/providers` | provider 列表（同 admin 列表，只读） |
| `GET /api/providers/active-model` | 全局默认模型：`{"provider_name": "...", "model": "..."}` |
| `PUT /api/providers/active-model` | 设置全局默认模型（**需 providers 权限**）：`{"provider_name": "...", "model": "..."}` |

Provider 对象：
```jsonc
{
  "id": 1, "name": "openai", "kind": "openai",
  "base_url": "https://...", "api_key": "sk-...",
  "models": [{"id": "gpt-4o", "reasoning": true, "reasoning_config": {...}}],
  "note": null, "enabled": true, "stream_usage": false
}
```

### 7.2 管理侧（providers 权限）

| 方法/路径 | 说明 |
|---|---|
| `GET /api/admin/providers` | 列表 |
| `POST /api/admin/providers` | 创建（201）：`{name, kind, base_url?, api_key?, extra_json?, stream_usage?, models?, note?}` |
| `PATCH /api/admin/providers/{provider_id}` | 部分更新（同上字段 + `enabled`）；`api_key: null` 或空串=清除 |
| `DELETE /api/admin/providers/{provider_id}` | 删除（204）。本地运行时 provider → `PROVIDER_LOCAL_PROTECTED` 409；仍被 agent 引用 → `PROVIDER_REFERENCED` 409（details.agents） |
| `POST /api/admin/providers/test-draft` | 试探未保存草稿：`{name, kind, api_key, base_url?, model_id, extra_json?, embedding?}` |
| `POST /api/admin/providers/fetch-models` | OpenAI 兼容 `GET /models`（仅 kind=openai）：`{kind, api_key, base_url?, extra_json?, name?}` |
| `POST /api/admin/providers/{provider_id}/test` | 试探已存 provider：`{model_id?, embedding?}` |
| `POST /api/admin/providers/codex-oauth/start` | ChatGPT 设备码登录 → `{state_id, user_code, verification_url}` |
| `GET /api/admin/providers/codex-oauth/pending/{state_id}` | 轮询结果（pending/ok/error） |
| `DELETE /api/admin/providers/codex-oauth` | 清除 ChatGPT 登录（204） |

## 8. MBTI 人格

挂载：`mbti.router → /api`（prefix `/mbti`），**整个 router 要求 `mbti` 权限**。agent 上下文经请求头 **`X-Octop-Agent-Id`** 传递（必须是 owner 的 agent）。

| 方法/路径 | 说明 |
|---|---|
| `GET /api/mbti/current` | 当前 agent 人格（头必填）→ `{"code": "INTJ", "configured": true}` |
| `GET /api/mbti/types` | 16 种类型全量 |
| `GET /api/mbti/types/{code}` | 单类型详情；未知 code → 404 |
| `GET /api/mbti/preview/{code}` | 人格模板渲染预览：`{"code": "...", "preview": "markdown"}` |
| `GET /api/mbti/test/questions` | 28 道测试题 |
| `POST /api/mbti/test/submit` | 提交答卷并评分 |
| `POST /api/mbti/apply` | 直接应用某类型到 agent（头必填） |

类型对象（`MBTITypeResponse`）：
```jsonc
{
  "code": "INTJ", "name_zh": "建筑师", "name_en": "Architect",
  "nickname_zh": "...", "summary_zh": "...", "summary_en": "...",
  "descriptors_zh": "...", "descriptors_en": "...",
  "dimensions": {"ei": ["I", 72], "sn": ["N", 65], "tf": ["T", 70], "jp": ["J", 60]},
  "behavior": {"answer_style": "...", "casual_chat": "...", "conflict": "...",
               "creativity": "...", "emotion": "...", "planning": "...",
               "answer_style_zh": "...", "..._zh": "..."},
  "color": "#...", "symbol": "..."
}
```

测试题（`TestQuestion`）：`{id(1-28), dimension("EI"|"SN"|"TF"|"JP"), a_pole, b_pole, question_zh, option_a_zh, option_b_zh, question_en, option_a_en, option_b_en}`。

`POST /test/submit` 请求：`{"answers": {"1": "A", "2": "B", ...}, "auto_apply": false, "language": "zh"}`；有效作答 < 20 → 400。响应：`{code, profile(MBTITypeResponse), dimensions, applied}`（`auto_apply=true` 时需带 `X-Octop-Agent-Id`）。

`POST /apply` 请求：`{"code": "INTJ", "language": "zh"}` → `{success: true, code, message}`；应用后 agent 重载并重生成 `SOUL.md`。

## 9. 专家团队（AgentTeams）

挂载：`teams.router → /api`。仅 team owner 可读写（`assert_agent_owner`）。成员必须是当前用户可用的**专家** agent（owner/admin/shared），且不能是 team；有效成员 **< 2** → `TEAM_MEMBERS_TOO_FEW` 400。

| 方法/路径 | 说明 |
|---|---|
| `GET /api/teams` | 我的团队列表（`team_payload` 数组） |
| `POST /api/teams` | 创建：`{name, description?, default_model?, color?, icon_name?, icon_url?, welcome_message?, member_ids: [], config?}` |
| `GET /api/teams/template` | 默认团队模板文件预览：`[{name, content}]` |
| `GET /api/teams/{team_id}` | 详情 |
| `PATCH /api/teams/{team_id}` | 更新：`{name?, description?, default_model?, color?, icon_name?, welcome_message?, member_ids?}`（member_ids 为**完整下一版名单**，非增量） |
| `DELETE /api/teams/{team_id}` | 删除（204） |

团队对象（`team_payload`）：
```jsonc
{
  "team_id": "agent_xxx", "agent_id": "agent_xxx",
  "name": "...", "description": "...", "default_model": "...",
  "color": "...", "icon_name": "users", "icon_url": "/experts/avatars/team-host.svg",
  "welcome_message": "...", "state": "running", "kind": "team",
  "member_ids": ["agent_a", "agent_b"],
  "members": [{"agent_id": "agent_a", "name": "...", "color": "...",
               "icon_name": "...", "icon_url": "...", "state": "running",
               "is_shared": false, "user_id": 1}]
}
```

错误：`TEAM_NOT_FOUND` 404、`TEAM_MEMBER_INVALID` 400（details.member_agent_ids）、`TEAM_MEMBERS_TOO_FEW` 400（最少 2）、`TEAM_MEMBER_BUSY` 409（成员有进行中团队任务，不能移除/删除）。

## 10. 用户与角色（Users / User Roles）

挂载：`users.router → /api/users`；角色模板 `user_roles.router → /api/users/roles`。除注明外均需 `users` 权限。

### 10.1 用户 CRUD

| 方法/路径 | 说明 |
|---|---|
| `GET /api/users/permissions` | **任意登录用户**。可分配权限目录（按 Accept-Language 本地化）：`[{key, category, label, page, page_label}]` |
| `GET /api/users` | 全量用户列表（含 disabled） |
| `POST /api/users` | 创建（201） |
| `GET /api/users/{user_id}` | 详情 |
| `PATCH /api/users/{user_id}` | 更新 |
| `DELETE /api/users/{user_id}` | 删除（204；不能删自己） |
| `POST /api/users/batch` | 批量操作（见下） |
| `POST /api/users/{user_id}/unlock-login` | 清除登录锁定（204） |
| `POST /api/users/{user_id}/reset-password` | 重置密码（204）：`{new_password(1-200)}` |
| `POST /api/users/{user_id}/avatar` | **multipart** 字段 `file`（201）→ `{avatar_url}` |
| `GET /api/users/{user_id}/avatar` | 头像（本人或持 `users` 权限） |
| `DELETE /api/users/{user_id}/avatar` | 删除头像（204） |

创建（`UserCreateBody`）：`{username(1-64), password(1-200), role("admin"|"user"|自定义角色 id，必填), display_name?, email?(≤254), permissions?[], role_name?(≤64), workspace_root_dir?, token_quota?(≥0), max_agents?(≥0)}`。
更新（`UserPatchBody`）：同上（无 username/password）+ `{disabled?: bool, avatar_icon?(≤32)}`；不能给自己降级/禁用关键权限。

批量（`UserBatchBody`）：
```jsonc
{
  "user_ids": [1, 2],        // 1-500 个
  "action": "enable | disable | delete | set_token_quota | set_max_agents",
  "token_quota": null,       // set_token_quota 用；null=清除限制（不限）
  "max_agents": null         // set_max_agents 用；null=清除限制
}
```
响应：`{action, results: [{user_id, ok, error?, code?}], succeeded, failed}`（单项失败不中断）。

用户对象：
```jsonc
{
  "id": 1, "username": "admin", "role": "admin", "display_name": "Admin",
  "email": null, "has_password": true, "sso_linked": false, "disabled": false,
  "login_failed_count": 0, "login_locked": false, "login_locked_until": 0,
  "login_retry_after_seconds": 0, "created_at": 1730000000,
  "permissions": ["users", "providers", ...], "role_name": "管理员",
  "avatar_icon": null, "avatar_url": "/api/users/1/avatar",
  "workspace_root_dir": null, "token_quota": null, "max_agents": null
}
```

### 10.2 角色模板（`/api/users/roles`，需 `users` 权限）

| 方法/路径 | 说明 |
|---|---|
| `GET /api/users/roles` | 角色列表 |
| `POST /api/users/roles` | 创建（201）：`{user_role_name(1-64), user_role_id?(1-64 字母/下划线，可省略由服务端分配), description?(≤500), permissions?[], policies?[{name, value}]}` |
| `PATCH /api/users/roles/{user_role_id}` | 更新（admin 内置角色仅能改名/描述/头像） |
| `DELETE /api/users/roles/{user_role_id}` | 删除（204；内置不可删；仍有用户使用 → `USER_ROLE_IN_USE` 409） |
| `POST /api/users/roles/{user_role_id}/avatar` / `GET` / `DELETE` | 角色头像（POST 为 multipart `file`） |

角色对象（`public_role`）：`{user_role_id, user_role_name, description, system_role("admin"|"user"), permissions[], policies[{name, value}], deletable, immutable, workspace_root_dir, token_quota, max_agents, created_at, updated_at, avatar_icon, avatar_url}`。
policies 已知名：`workspace_root_dir`、`token_quota`、`max_agents`。
错误：`USER_ROLE_ID_INVALID` 400、`USER_ROLE_ID_TAKEN` 409、`USER_ROLE_IN_USE` 409。

## 11. 系统设置（Settings / Downloads）

挂载：`settings.router → /api`。

### 11.1 客户端有用的只读设置（任意登录用户）

| 方法/路径 | 响应 |
|---|---|
| `GET /api/settings/timezone` | `{"timezone": "Asia/Shanghai"}`（IANA 时区） |
| `GET /api/settings/upload` | `{"max_upload_mb": 100, "max_upload_bytes": 104857600}` |
| `GET /api/settings/hitl` | `{"enabled": bool, "tool_guard_require_approval": bool, "show_approval_ui": bool}`（审批 UI 显隐判定） |
| `GET /api/settings/capabilities` | `{"mobile": {"enabled": false, "backend": "none\|physical\|redroid\|emulator"}}` |

### 11.2 下载辅助

| 方法/路径 | 说明 |
|---|---|
| `POST /api/downloads/local` | multipart 字段 `file`；把已取回的 blob 写入服务器主机 ~/Downloads（仅本机 dashboard 请求，否则 `LOCAL_DOWNLOAD_UNAVAILABLE` 403）→ `{path, filename}` |
| `POST /api/downloads/link` | multipart 字段 `file`；生成短时免凭证链接 → `{url: "/api/downloads/link/{token}", filename, expires_in}` |
| `GET /api/downloads/link/{token}` | **免 JWT** 下载（token 即凭证，几分钟有效） |

### 11.3 验证码设置（`captcha` 权限）

- `GET /api/settings/captcha` → `{active, available[], providers{kind: {site_key, has_secret, cam_secret_id, cam_secret}}, source("settings"|"env"), v3_min_score}`（不含 secret）。
- `PUT /api/settings/captcha`：`{active?, providers?{kind: {site_key?, secret?, cam_secret_id?, cam_secret?}}}`（空 secret 保留已存值）。

## 12. 本文新增错误码汇总（均走 §7 标准包络）

| code | HTTP | 域 |
|---|---|---|
| `CRON_TRIGGER_INVALID` | 400 | cron |
| `KNOWLEDGE_FEATURE_DISABLED` / `KNOWLEDGE_FORBIDDEN` | 403 | 知识库 |
| `KNOWLEDGE_NOT_FOUND` | 404 | 知识库 |
| `KNOWLEDGE_PREREQUISITES_FAILED` / `_RESTART_REQUIRED` / `DOC_LIMIT` / `BASE_LIMIT` / `NAME_TAKEN` | 409 | 知识库 |
| `KNOWLEDGE_DOC_TOO_LARGE` | 413 | 知识库（details.max_mb） |
| `KNOWLEDGE_UNSUPPORTED_TYPE` / `KNOWLEDGE_NAME_INVALID` | 400 | 知识库 |
| `ATTACHMENT_TOO_LARGE` | 413 | 聊天附件 |
| `ATTACHMENT_UNSUPPORTED_TYPE` | 400 | 聊天附件 |
| `CONNECTOR_NOT_FOUND` | 404 | 连接器 |
| `CONNECTOR_NAME_TAKEN` | 409 | 连接器 |
| `CONNECTOR_INVALID_CREDENTIALS` / `_KIND_UNSUPPORTED` / `_OAUTH_HTTPS_REQUIRED` | 400 | 连接器 |
| `CONNECTOR_MCP_LOAD_FAILED` | 502 | 连接器 |
| `PLUGIN_INVALID_ARCHIVE` | 400 | 插件 |
| `PLUGIN_INSTALL_FAILED` | 502 | 插件 |
| `PLUGIN_ALREADY_EXISTS` | 409 | 插件 |
| `PROVIDER_LOCAL_PROTECTED` / `PROVIDER_REFERENCED` | 409 | Provider |
| `PROVIDER_NAME_TAKEN` | 409 | Provider |
| `CODEX_OAUTH_START_FAILED` | 502 | Provider |
| `TEAM_NOT_FOUND` | 404 | 团队 |
| `TEAM_MEMBERS_TOO_FEW` / `TEAM_MEMBER_INVALID` / `TEAM_NOT_SHAREABLE` | 400 | 团队 |
| `TEAM_MEMBER_BUSY` | 409 | 团队 |
| `USER_ROLE_ID_INVALID` | 400 | 角色 |
| `USER_ROLE_ID_TAKEN` / `USER_ROLE_IN_USE` | 409 | 角色 |
| `LOCAL_DOWNLOAD_UNAVAILABLE` | 403 | 设置 |

## 13. Sources（本文引用的服务端源码）

路由实现（均为 main 分支 raw）：
- https://raw.githubusercontent.com/TencentCloud/Octop/main/src/octop/api/routers/cron.py
- https://raw.githubusercontent.com/TencentCloud/Octop/main/src/octop/api/routers/knowledge_bases.py
- https://raw.githubusercontent.com/TencentCloud/Octop/main/src/octop/api/routers/uploads.py
- https://raw.githubusercontent.com/TencentCloud/Octop/main/src/octop/api/routers/channels.py
- https://raw.githubusercontent.com/TencentCloud/Octop/main/src/octop/api/routers/connectors.py
- https://raw.githubusercontent.com/TencentCloud/Octop/main/src/octop/api/routers/plugins.py
- https://raw.githubusercontent.com/TencentCloud/Octop/main/src/octop/api/routers/providers.py
- https://raw.githubusercontent.com/TencentCloud/Octop/main/src/octop/api/routers/mbti.py
- https://raw.githubusercontent.com/TencentCloud/Octop/main/src/octop/api/routers/teams.py
- https://raw.githubusercontent.com/TencentCloud/Octop/main/src/octop/api/routers/users.py
- https://raw.githubusercontent.com/TencentCloud/Octop/main/src/octop/api/routers/user_roles.py
- https://raw.githubusercontent.com/TencentCloud/Octop/main/src/octop/api/routers/settings.py

装配与依赖：
- https://raw.githubusercontent.com/TencentCloud/Octop/main/src/octop/api/app.py（路由挂载前缀）
- https://raw.githubusercontent.com/TencentCloud/Octop/main/src/octop/api/deps.py（current_user / require_permission / JWT 豁免路径）
- https://raw.githubusercontent.com/TencentCloud/Octop/main/src/octop/infra/errors.py（错误码 → HTTP 映射）

支撑模型与限制：
- https://raw.githubusercontent.com/TencentCloud/Octop/main/src/octop/infra/db/repos/cron.py（CronJobRow.to_public_dict）
- https://raw.githubusercontent.com/TencentCloud/Octop/main/src/octop/infra/cron/manager.py（trigger 语义 / agently 邮件触发）
- https://raw.githubusercontent.com/TencentCloud/Octop/main/src/octop/infra/knowledge/service.py（MAX_DOCS_PER_KB=100 / MAX_BASES_PER_OWNER=20 / 支持类型）
- https://raw.githubusercontent.com/TencentCloud/Octop/main/src/octop/infra/db/repos/knowledge.py（KnowledgeBaseRow / KnowledgeDocumentRow 字段）
- https://raw.githubusercontent.com/TencentCloud/Octop/main/src/octop/infra/agents/teams/service.py（team_payload / TEAM_MIN_MEMBERS=2）
- https://raw.githubusercontent.com/TencentCloud/Octop/main/src/octop/config.py（max_upload_mb 默认 100、上限 1024）

> 说明：routers 目录中另有 `mobile/` 子目录（Remote Android 能力，`/api/settings/capabilities.mobile.enabled` 开启时挂载）与 `browser/`、`desktop/`、`terminal/` 等桌面端路由，与 HarmonyOS 客户端无关，本文未展开。
