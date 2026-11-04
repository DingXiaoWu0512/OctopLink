import { HttpClient } from '../net/HttpClient';
import {
  AgentPluginModel,
  CaptchaSettingsModel,
  ChannelModel,
  ChannelPluginKindModel,
  ConnectorCatalogEntry,
  ConnectorInstanceModel,
  CronJobModel,
  CustomMcpServerModel,
  GlobalPluginModel,
  HitlSettings,
  KnowledgeBaseModel,
  KnowledgeCapability,
  KnowledgeDocModel,
  MarketPluginModel,
  MbtiQuestionModel,
  MbtiTestResultModel,
  MbtiTypeModel,
  MobileCapability,
  PluginToolModel,
  QrPollResult,
  QrSessionModel,
  TeamModel
} from '../model/WorkspaceModels';
import { JsonHelper } from '../utils/JsonHelper';

/** 定时任务（/api/agents/{id}/cron，owner-only） */
export class CronService {
  static async list(agentId: string): Promise<Array<CronJobModel>> {
    const text: string = await HttpClient.getInstance().get(`/api/agents/${agentId}/cron`);
    return CronJobModel.parseList(text);
  }

  /** 创建：trigger 为 cron:/interval:/date:/agently: 形式 */
  static async create(agentId: string, name: string, trigger: string, prompt: string,
    freshThread: boolean = false, model: string = '', taskType: string = 'text'): Promise<void> {
    const body: Record<string, Object> = {
      'trigger': trigger,
      'prompt': prompt,
      'enabled': true,
      'fresh_thread': freshThread,
      'task_type': taskType
    };
    if (name !== '') {
      body['name'] = name;
    }
    if (model !== '') {
      body['model'] = model;
    }
    await HttpClient.getInstance().post(`/api/agents/${agentId}/cron`, JSON.stringify(body));
  }

  /** 部分更新（name/trigger/prompt/fresh_thread/enabled/model/task_type 均可选） */
  static async patch(agentId: string, cronId: string, bodyStr: string): Promise<void> {
    await HttpClient.getInstance().patch(`/api/agents/${agentId}/cron/${cronId}`, bodyStr);
  }

  static async get(agentId: string, cronId: string): Promise<CronJobModel> {
    const text: string = await HttpClient.getInstance().get(`/api/agents/${agentId}/cron/${cronId}`);
    const rec = JsonHelper.parse(text);
    return CronJobModel.fromRecord(rec === null ? {} : rec);
  }

  /** 任务页示例提示词（task_examples.workspace，缺失时取首个可用分组） */
  static async examples(agentId: string): Promise<Array<string>> {
    const text: string = await HttpClient.getInstance().get(`/api/agents/${agentId}/cron/examples`);
    const rec = JsonHelper.parse(text);
    if (rec === null) {
      return [];
    }
    const groups = JsonHelper.toRecord(rec['task_examples']);
    if (groups === null) {
      return [];
    }
    const workspace: Array<string> = CronService.extractStrings(groups['workspace']);
    if (workspace.length > 0) {
      return workspace;
    }
    const keys: Array<string> = Object.keys(groups);
    for (const key of keys) {
      const found: Array<string> = CronService.extractStrings(groups[key]);
      if (found.length > 0) {
        return found;
      }
    }
    return [];
  }

  private static extractStrings(value: Object | undefined): Array<string> {
    const result: Array<string> = [];
    if (value === undefined || value === null || !Array.isArray(value)) {
      return result;
    }
    const arr: Object[] = value as Object[];
    for (const item of arr) {
      if (typeof item === 'string') {
        result.push(item);
      }
    }
    return result;
  }

  static async setEnabled(agentId: string, cronId: string, enabled: boolean): Promise<void> {
    const body: Record<string, Object> = { 'enabled': enabled };
    await HttpClient.getInstance().patch(`/api/agents/${agentId}/cron/${cronId}`, JSON.stringify(body));
  }

  static async remove(agentId: string, cronId: string): Promise<void> {
    await HttpClient.getInstance().delete(`/api/agents/${agentId}/cron/${cronId}`);
  }

  static async runNow(agentId: string, cronId: string): Promise<void> {
    await HttpClient.getInstance().post(`/api/agents/${agentId}/cron/${cronId}/run-now`, '{}');
  }

  /** 定时服务全局设置（GET /api/cron/settings → {key: string}） */
  static async settings(): Promise<Record<string, string>> {
    const text: string = await HttpClient.getInstance().get('/api/cron/settings');
    const result: Record<string, string> = {};
    const rec = JsonHelper.parse(text);
    if (rec === null) {
      return result;
    }
    for (const key of Object.keys(rec)) {
      const v: Object = rec[key];
      if (typeof v === 'string') {
        result[key] = v as string;
      } else if (typeof v === 'number') {
        result[key] = `${v}`;
      }
    }
    return result;
  }
}

/** 知识库（/api/knowledge-bases） */
export class KnowledgeService {
  static async listBases(): Promise<Array<KnowledgeBaseModel>> {
    const text: string = await HttpClient.getInstance().get('/api/knowledge-bases');
    return KnowledgeBaseModel.parseList(text);
  }

  static async createBase(name: string, description: string, shared: boolean = false,
    defaultOpen: boolean = false, maxDocs: number = 0): Promise<void> {
    const body: Record<string, Object> = {
      'name': name,
      'description': description,
      'shared': shared,
      'default_open': defaultOpen
    };
    if (maxDocs > 0) {
      body['max_documents'] = maxDocs;
    }
    await HttpClient.getInstance().post('/api/knowledge-bases', JSON.stringify(body));
  }

  /** 库编辑（PATCH：name/description/shared/default_open/icon_name/max_documents） */
  static async patchBase(kbId: string, bodyStr: string): Promise<void> {
    await HttpClient.getInstance().patch(`/api/knowledge-bases/${kbId}`, bodyStr);
  }

  static async removeBase(kbId: string): Promise<void> {
    await HttpClient.getInstance().delete(`/api/knowledge-bases/${kbId}`);
  }

  /** 服务能力与限制（任意登录用户；含 embedding 后端/OCR/chunk 参数） */
  static async capability(): Promise<KnowledgeCapability> {
    const text: string = await HttpClient.getInstance().get('/api/knowledge-bases/capability');
    return KnowledgeCapability.parse(text);
  }

  /** 总开关与后端选择（需 knowledge_settings 权限；backend: onnx|remote） */
  static async putFeature(enabled: boolean, backend: string = '', model: string = '',
    providerId: string = ''): Promise<KnowledgeCapability> {
    const body: Record<string, Object> = { 'enabled': enabled };
    if (backend !== '') {
      body['backend'] = backend;
    }
    if (model !== '') {
      body['model'] = model;
    }
    if (providerId !== '') {
      body['provider_id'] = providerId;
    }
    const text: string = await HttpClient.getInstance().put(
      '/api/knowledge-bases/feature', JSON.stringify(body));
    return KnowledgeCapability.parse(text);
  }

  /** 当前用户默认展开的知识库 id 列表 */
  static async defaultOpenIds(): Promise<Array<string>> {
    const text: string = await HttpClient.getInstance().get('/api/knowledge-bases/default-open');
    const rec = JsonHelper.parse(text);
    if (rec === null) {
      return [];
    }
    const ids: Array<string> = JsonHelper.getStringArray(rec, 'knowledge_base_ids');
    if (ids.length > 0) {
      return ids;
    }
    return JsonHelper.getStringArray(rec, 'ids');
  }

  /** OCR 后端选项（需 knowledge_settings 权限） */
  static async ocrOptions(): Promise<string> {
    return await HttpClient.getInstance().get('/api/knowledge-bases/ocr-options');
  }

  /** 启动 ONNX 嵌入模型下载（需 knowledge_settings 权限） */
  static async onnxDownload(model: string): Promise<string> {
    const body: Record<string, Object> = { 'model': model };
    return await HttpClient.getInstance().post(
      '/api/knowledge-bases/onnx-download', JSON.stringify(body));
  }

  /** 轮询 ONNX 模型下载进度 */
  static async onnxDownloadStatus(): Promise<string> {
    return await HttpClient.getInstance().get('/api/knowledge-bases/onnx-download-status');
  }

  /** 激活已下载的 ONNX 模型为本地嵌入服务 */
  static async onnxActivate(model: string): Promise<string> {
    const body: Record<string, Object> = { 'model': model };
    return await HttpClient.getInstance().post(
      '/api/knowledge-bases/onnx-activate', JSON.stringify(body));
  }

  /** 探测本地 ONNX 模型可用性 */
  static async onnxTest(model: string): Promise<string> {
    const body: Record<string, Object> = { 'model': model };
    return await HttpClient.getInstance().post(
      '/api/knowledge-bases/onnx-test', JSON.stringify(body));
  }

  static async listDocs(kbId: string): Promise<Array<KnowledgeDocModel>> {
    const text: string = await HttpClient.getInstance().get(`/api/knowledge-bases/${kbId}/documents`);
    return KnowledgeDocModel.parseList(text);
  }

  /** multipart 上传文档（字段 upload；path 为可选相对路径含文件名） */
  static async uploadDocument(kbId: string, fileName: string, contentType: string,
    data: ArrayBuffer, path: string = ''): Promise<void> {
    const formFields: Record<string, string> = {};
    if (path !== '') {
      formFields['path'] = path;
    }
    await HttpClient.getInstance().postMultipartFile(
      `/api/knowledge-bases/${kbId}/documents`, 'upload', fileName, contentType, data,
      Object.keys(formFields).length > 0 ? formFields : undefined);
  }

  /** 创建 md/txt 在线文档 */
  static async createTextDoc(kbId: string, name: string, format: string, content: string): Promise<void> {
    const body: Record<string, Object> = {
      'name': name,
      'format': format,
      'content': content
    };
    await HttpClient.getInstance().post(
      `/api/knowledge-bases/${kbId}/documents/text`, JSON.stringify(body));
  }

  /** 创建文件夹 */
  static async createFolder(kbId: string, path: string): Promise<void> {
    const body: Record<string, Object> = { 'path': path };
    await HttpClient.getInstance().post(
      `/api/knowledge-bases/${kbId}/folders`, JSON.stringify(body));
  }

  /** 重命名文档/文件夹（文件夹会重写子孙路径） */
  static async renameDoc(kbId: string, docId: string, newName: string): Promise<void> {
    const body: Record<string, Object> = { 'new_name': newName };
    await HttpClient.getInstance().post(
      `/api/knowledge-bases/${kbId}/documents/${docId}/rename`, JSON.stringify(body));
  }

  /** 重建单文档索引 */
  static async reindexDoc(kbId: string, docId: string): Promise<void> {
    await HttpClient.getInstance().post(
      `/api/knowledge-bases/${kbId}/documents/${docId}/reindex`, '{}');
  }

  /** 重建全库索引 */
  static async reindexKb(kbId: string): Promise<void> {
    await HttpClient.getInstance().post(`/api/knowledge-bases/${kbId}/reindex`, '{}');
  }

  /** 读 md/txt 原文 */
  static async getDocContent(kbId: string, docId: string): Promise<string> {
    const text: string = await HttpClient.getInstance().get(
      `/api/knowledge-bases/${kbId}/documents/${docId}/content`);
    const rec = JsonHelper.parse(text);
    return rec === null ? '' : JsonHelper.getString(rec, 'text', '');
  }

  /** 覆写 md/txt 并重建索引 */
  static async putDocContent(kbId: string, docId: string, content: string): Promise<void> {
    const body: Record<string, Object> = { 'content': content };
    await HttpClient.getInstance().put(
      `/api/knowledge-bases/${kbId}/documents/${docId}/content`, JSON.stringify(body));
  }

  /** 下载原件字节（disposition=attachment|inline） */
  static async downloadDoc(kbId: string, docId: string, disposition: string): Promise<ArrayBuffer> {
    return await HttpClient.getInstance().downloadGet(
      `/api/knowledge-bases/${kbId}/documents/${docId}/file?disposition=${disposition}`);
  }

  static async removeDoc(kbId: string, docId: string): Promise<void> {
    await HttpClient.getInstance().delete(`/api/knowledge-bases/${kbId}/documents/${docId}`);
  }

  /** 文本预览：返回 {filename, text}；text 客户端截断展示 */
  static async previewDoc(kbId: string, docId: string): Promise<DocPreview> {
    const text: string = await HttpClient.getInstance().get(
      `/api/knowledge-bases/${kbId}/documents/${docId}/preview`);
    const rec = JsonHelper.parse(text);
    const filename: string = rec === null ? '' : JsonHelper.getString(rec, 'filename', '');
    let content: string = rec === null ? '' : JsonHelper.getString(rec, 'text', '');
    if (content.length > 5000) {
      content = `${content.substring(0, 5000)}\n\n...（内容过长，已截断）`;
    }
    return new DocPreview(filename, content);
  }

  /** KB 头像地址（Image 直连，access_token 查询参数鉴权） */
  static avatarUrl(kbId: string): string {
    const base: string = HttpClient.getInstance().getBaseUrl();
    const token: string = HttpClient.getInstance().getToken();
    return `${base}/api/knowledge-bases/${kbId}/avatar?access_token=${encodeURIComponent(token)}`;
  }

  /** 带版本号：上传/删除后自增 rev 穿透 Image 缓存 */
  static avatarUrlWithRev(kbId: string, rev: number): string {
    if (rev <= 0) {
      return KnowledgeService.avatarUrl(kbId);
    }
    return `${KnowledgeService.avatarUrl(kbId)}&v=${rev}`;
  }

  /** 上传 KB 头像（multipart 字段 file，201） */
  static async uploadAvatar(kbId: string, fileName: string, contentType: string,
    data: ArrayBuffer): Promise<void> {
    await HttpClient.getInstance().postMultipartFile(
      `/api/knowledge-bases/${kbId}/avatar`, 'file', fileName, contentType, data);
  }

  /** 删除 KB 头像 */
  static async deleteAvatar(kbId: string): Promise<void> {
    await HttpClient.getInstance().delete(`/api/knowledge-bases/${kbId}/avatar`);
  }

  /** 嵌入后端选项（GET /api/knowledge-bases/embedding-options；all_onnx 返回完整本地目录） */
  static async embeddingOptions(allOnnx: boolean): Promise<string> {
    const suffix: string = allOnnx ? '?all_onnx=true' : '';
    return await HttpClient.getInstance().get(`/api/knowledge-bases/embedding-options${suffix}`);
  }
}

/** 文档预览结果 */
export class DocPreview {
  readonly filename: string;
  readonly text: string;

  constructor(filename: string, text: string) {
    this.filename = filename;
    this.text = text;
  }
}

/** 渠道（/api/agents/{id}/channels + /api/channels/plugin-kinds + 扫码辅助） */
export class ChannelService {
  static async list(agentId: string): Promise<Array<ChannelModel>> {
    const text: string = await HttpClient.getInstance().get(`/api/agents/${agentId}/channels`);
    return ChannelModel.parseList(text);
  }

  /** 插件贡献的渠道类型 */
  static async pluginKinds(): Promise<Array<ChannelPluginKindModel>> {
    const text: string = await HttpClient.getInstance().get('/api/channels/plugin-kinds');
    return ChannelPluginKindModel.parseList(text);
  }

  /** 创建渠道：{kind, name, config} */
  static async create(agentId: string, kind: string, name: string,
    configStr: string): Promise<void> {
    const config: Record<string, Object> | null = JsonHelper.parse(configStr);
    const emptyConfig: Record<string, Object> = {};
    const body: Record<string, Object> = {
      'kind': kind,
      'name': name,
      'config': config === null ? emptyConfig : config
    };
    await HttpClient.getInstance().post(
      `/api/agents/${agentId}/channels`, JSON.stringify(body));
  }

  /** 详情原始响应（含 config），用于展示 */
  static async getChannel(agentId: string, channelId: string): Promise<string> {
    return await HttpClient.getInstance().get(`/api/agents/${agentId}/channels/${channelId}`);
  }

  static async patchChannel(agentId: string, channelId: string, bodyStr: string): Promise<void> {
    await HttpClient.getInstance().patch(`/api/agents/${agentId}/channels/${channelId}`, bodyStr);
  }

  static async setEnabled(agentId: string, channelId: string, enabled: boolean): Promise<void> {
    const body: Record<string, Object> = { 'enabled': enabled };
    await ChannelService.patchChannel(agentId, channelId, JSON.stringify(body));
  }

  /** 用已存配置探测连通性，返回原始响应文本 */
  static async testChannel(agentId: string, channelId: string): Promise<string> {
    return await HttpClient.getInstance().post(
      `/api/agents/${agentId}/channels/${channelId}/test`, '{}');
  }

  /** 用草稿配置探测（不落库），返回原始响应文本 */
  static async probe(agentId: string, kind: string, configStr: string): Promise<string> {
    const config: Record<string, Object> | null = JsonHelper.parse(configStr);
    const emptyConfig: Record<string, Object> = {};
    const body: Record<string, Object> = {
      'kind': kind,
      'config': config === null ? emptyConfig : config
    };
    return await HttpClient.getInstance().post(
      `/api/agents/${agentId}/channels/probe`, JSON.stringify(body));
  }

  static async remove(agentId: string, channelId: string): Promise<void> {
    await HttpClient.getInstance().delete(`/api/agents/${agentId}/channels/${channelId}`);
  }

  // ---- 扫码/机器人创建辅助（agent owner，channels 权限）----

  /** 钉钉扫码：generate → {registration_id, qrcode_url, user_code...} */
  static async dingtalkQrcodeGenerate(agentId: string): Promise<QrSessionModel> {
    const text: string = await HttpClient.getInstance().post(
      `/api/agents/${agentId}/channels/dingtalk/qrcode/generate`, '{}');
    return QrSessionModel.parse(text);
  }

  static async dingtalkQrcodePoll(agentId: string, registrationId: string): Promise<QrPollResult> {
    const body: Record<string, Object> = { 'registration_id': registrationId };
    const text: string = await HttpClient.getInstance().postLongPoll(
      `/api/agents/${agentId}/channels/dingtalk/qrcode/poll`, JSON.stringify(body), 50000);
    return QrPollResult.parse(text);
  }

  /** 企微扫码：generate → {scode, qrcode_url...}；poll Body {"scode"} */
  static async wecomQrcodeGenerate(agentId: string): Promise<QrSessionModel> {
    const text: string = await HttpClient.getInstance().post(
      `/api/agents/${agentId}/channels/wecom/qrcode/generate`, '{}');
    return QrSessionModel.parse(text);
  }

  static async wecomQrcodePoll(agentId: string, scode: string): Promise<QrPollResult> {
    const body: Record<string, Object> = { 'scode': scode };
    const text: string = await HttpClient.getInstance().postLongPoll(
      `/api/agents/${agentId}/channels/wecom/qrcode/poll`, JSON.stringify(body), 50000);
    return QrPollResult.parse(text);
  }

  /** QQ Bot：generate → {qrcode_token, qrcode_url}；poll Body {"qrcode_token"} */
  static async qqQrcodeGenerate(agentId: string): Promise<QrSessionModel> {
    const text: string = await HttpClient.getInstance().post(
      `/api/agents/${agentId}/channels/qq/qrcode/generate`, '{}');
    return QrSessionModel.parse(text);
  }

  static async qqQrcodePoll(agentId: string, qrcodeToken: string): Promise<QrPollResult> {
    const body: Record<string, Object> = { 'qrcode_token': qrcodeToken };
    const text: string = await HttpClient.getInstance().postLongPoll(
      `/api/agents/${agentId}/channels/qq/qrcode/poll`, JSON.stringify(body), 50000);
    return QrPollResult.parse(text);
  }

  /** 微信：generate → {qrcode_token, qrcode_url}；poll 长轮询 ~40s */
  static async weixinQrcodeGenerate(agentId: string): Promise<QrSessionModel> {
    const text: string = await HttpClient.getInstance().post(
      `/api/agents/${agentId}/channels/weixin/qrcode/generate`, '{}');
    return QrSessionModel.parse(text);
  }

  static async weixinQrcodePoll(agentId: string, qrcodeToken: string): Promise<QrPollResult> {
    const body: Record<string, Object> = { 'qrcode_token': qrcodeToken };
    const text: string = await HttpClient.getInstance().postLongPoll(
      `/api/agents/${agentId}/channels/weixin/qrcode/poll`, JSON.stringify(body), 50000);
    return QrPollResult.parse(text);
  }

  /** 飞书机器人创建：start|poll|stop */
  static async feishuBotStart(agentId: string): Promise<QrSessionModel> {
    const text: string = await HttpClient.getInstance().post(
      `/api/agents/${agentId}/channels/feishu/bot-creator/start`, '{}');
    return QrSessionModel.parse(text);
  }

  static async feishuBotPoll(agentId: string): Promise<QrPollResult> {
    const text: string = await HttpClient.getInstance().postLongPoll(
      `/api/agents/${agentId}/channels/feishu/bot-creator/poll`, '{}', 50000);
    return QrPollResult.parse(text);
  }

  static async feishuBotStop(agentId: string): Promise<void> {
    await HttpClient.getInstance().post(
      `/api/agents/${agentId}/channels/feishu/bot-creator/stop`, '{}');
  }

  /** 元宝机器人创建：start|poll|stop */
  static async yuanbaoBotStart(agentId: string): Promise<QrSessionModel> {
    const text: string = await HttpClient.getInstance().post(
      `/api/agents/${agentId}/channels/yuanbao/bot-creator/start`, '{}');
    return QrSessionModel.parse(text);
  }

  static async yuanbaoBotPoll(agentId: string): Promise<QrPollResult> {
    const text: string = await HttpClient.getInstance().postLongPoll(
      `/api/agents/${agentId}/channels/yuanbao/bot-creator/poll`, '{}', 50000);
    return QrPollResult.parse(text);
  }

  static async yuanbaoBotStop(agentId: string): Promise<void> {
    await HttpClient.getInstance().post(
      `/api/agents/${agentId}/channels/yuanbao/bot-creator/stop`, '{}');
  }
}

/** 连接器实例（/api/connector-instances + /api/connectors） */
export class ConnectorService {
  static async list(): Promise<Array<ConnectorInstanceModel>> {
    const text: string = await HttpClient.getInstance().get('/api/connector-instances');
    return ConnectorInstanceModel.parseList(text);
  }

  /** 连接器目录（kind/可用性/OAuth 配置） */
  static async catalog(): Promise<Array<ConnectorCatalogEntry>> {
    const text: string = await HttpClient.getInstance().get('/api/connectors/catalog');
    return ConnectorCatalogEntry.parseList(text);
  }

  /** 创建实例（bodyStr 为 CreateInstanceBody JSON 文本） */
  static async createInstance(bodyStr: string): Promise<void> {
    await HttpClient.getInstance().post('/api/connector-instances', bodyStr);
  }

  /** 详情原始响应（含 config 与 credentials 脱敏预览） */
  static async getInstance(instanceId: string): Promise<string> {
    return await HttpClient.getInstance().get(`/api/connector-instances/${instanceId}`);
  }

  static async patchInstance(instanceId: string, bodyStr: string): Promise<void> {
    await HttpClient.getInstance().patch(`/api/connector-instances/${instanceId}`, bodyStr);
  }

  static async test(instanceId: string): Promise<void> {
    await HttpClient.getInstance().post(`/api/connector-instances/${instanceId}/test`, '{}');
  }

  /** 刷新 OAuth token，返回原始响应（{"ok":true,"expires_at":...}） */
  static async refreshToken(instanceId: string): Promise<string> {
    return await HttpClient.getInstance().post(
      `/api/connector-instances/${instanceId}/refresh`, '{}');
  }

  /** 创建前试凭证（不落库） */
  static async testCredentials(kind: string, credentialsStr: string): Promise<void> {
    const credentials: Record<string, Object> | null = JsonHelper.parse(credentialsStr);
    const emptyCredentials: Record<string, Object> = {};
    const body: Record<string, Object> = {
      'kind': kind,
      'credentials': credentials === null ? emptyCredentials : credentials
    };
    await HttpClient.getInstance().post(
      '/api/connectors/test-credentials', JSON.stringify(body));
  }

  /** 自定义 MCP 服务器列表 */
  static async customMcpGet(): Promise<Array<CustomMcpServerModel>> {
    const text: string = await HttpClient.getInstance().get('/api/connectors/custom-mcp');
    return CustomMcpServerModel.parseList(text);
  }

  /** 单个自定义 MCP 服务器开关 */
  static async customMcpPatchServer(serverName: string, bodyStr: string): Promise<void> {
    await HttpClient.getInstance().patch(
      `/api/connectors/custom-mcp/servers/${serverName}`, bodyStr);
  }

  /** OAuth 发起：target 为 {"type":"catalog","kind":...} JSON 文本 → {authorize_url, state_id} */
  static async oauthStart(targetStr: string): Promise<OAuthStartResult> {
    const target: Record<string, Object> | null = JsonHelper.parse(targetStr);
    const emptyTarget: Record<string, Object> = {};
    const body: Record<string, Object> = {
      'target': target === null ? emptyTarget : target
    };
    const text: string = await HttpClient.getInstance().post(
      '/api/connectors/oauth/start', JSON.stringify(body));
    return OAuthStartResult.parse(text);
  }

  /** OAuth 轮询（一次性读取）→ {kind, tokens, applied?}，返回原始文本 */
  static async oauthPending(stateId: string): Promise<string> {
    return await HttpClient.getInstance().get(`/api/connectors/oauth/pending/${stateId}`);
  }

  static async remove(instanceId: string): Promise<void> {
    await HttpClient.getInstance().delete(`/api/connector-instances/${instanceId}`);
  }

  // ---- CLI 授权（Agently/钉钉 CLI 设备码登录）----

  /** 发起/刷新/登出 CLI 授权：action = start|refresh|logout */
  static async agentlyAuth(instanceId: string, action: string): Promise<AgentlyAuthState> {
    const text: string = await HttpClient.getInstance().post(
      `/api/connector-instances/${instanceId}/agently-auth/${action}`, '{}');
    return AgentlyAuthState.parse(text);
  }

  /** 轮询 CLI 授权状态（authorized 时服务端会恢复邮件监听） */
  static async agentlyAuthStatus(instanceId: string): Promise<AgentlyAuthState> {
    const text: string = await HttpClient.getInstance().get(
      `/api/connector-instances/${instanceId}/agently-auth/status`);
    return AgentlyAuthState.parse(text);
  }

  // ---- 飞书 CLI 用户设备码登录 ----

  /** 全局发起（需 app_id/app_secret）→ {device_code, verification_url, expires_in, user_code, hint} */
  static async feishuUserAuthStart(appId: string, appSecret: string): Promise<string> {
    const body: Record<string, Object> = {
      'app_id': appId,
      'app_secret': appSecret
    };
    return await HttpClient.getInstance().post(
      '/api/connectors/feishu-cli/user-auth/start', JSON.stringify(body));
  }

  /** 全局完成（device_code 换取用户身份） */
  static async feishuUserAuthComplete(appId: string, appSecret: string,
    deviceCode: string): Promise<string> {
    const body: Record<string, Object> = {
      'app_id': appId,
      'app_secret': appSecret,
      'device_code': deviceCode
    };
    return await HttpClient.getInstance().post(
      '/api/connectors/feishu-cli/user-auth/complete', JSON.stringify(body));
  }

  /** 实例级发起（App Secret 读自已存实例） */
  static async feishuUserAuthStartForInstance(instanceId: string): Promise<string> {
    return await HttpClient.getInstance().post(
      `/api/connector-instances/${instanceId}/feishu-user-auth/start`, '{}');
  }

  /** 实例级完成（device_code 换取用户身份并热重载连接器） */
  static async feishuUserAuthCompleteForInstance(instanceId: string,
    deviceCode: string): Promise<string> {
    const body: Record<string, Object> = { 'device_code': deviceCode };
    return await HttpClient.getInstance().post(
      `/api/connector-instances/${instanceId}/feishu-user-auth/complete`, JSON.stringify(body));
  }

  // ---- CLI 安装状态（宿主机）----

  /** CLI 安装状态：{kind, binary, npm_package, install_command, doc_url, guide_url, installed, binary_path, version} */
  static async cliStatus(kind: string): Promise<CliInstallStatus> {
    const text: string =
      await HttpClient.getInstance().get(`/api/connectors/${kind}/cli-status`);
    return CliInstallStatus.parse(text);
  }

  /** 安装 CLI（需 connectors 权限，npm install -g） */
  static async installCli(kind: string): Promise<CliInstallStatus> {
    const text: string =
      await HttpClient.getInstance().post(`/api/connectors/${kind}/install-cli`, '{}');
    return CliInstallStatus.parse(text);
  }

  // ---- OAuth 辅助 ----

  /** 连接器鉴权信息：{authorize_url, login_url, guide_url, manual_url, auth_hint} */
  static async authInfo(kind: string): Promise<string> {
    return await HttpClient.getInstance().get(`/api/connectors/auth/${kind}/info`);
  }

  /** 全量保存自定义 MCP 服务器配置 */
  static async customMcpPut(bodyStr: string): Promise<void> {
    await HttpClient.getInstance().put('/api/connectors/custom-mcp', bodyStr);
  }

  /** 探测自定义 MCP 服务器连通性 */
  static async customMcpTest(bodyStr: string): Promise<string> {
    return await HttpClient.getInstance().post('/api/connectors/custom-mcp/test', bodyStr);
  }

  // ---- 网页 OAuth 授权（authorize-url → 系统浏览器/内嵌 Web → exchange-code）----

  /** 获取 OAuth 授权跳转地址（GET /api/connectors/auth/{kind}/authorize-url） */
  static async oauthAuthorizeUrl(kind: string): Promise<string> {
    const text: string =
      await HttpClient.getInstance().get(`/api/connectors/auth/${kind}/authorize-url`);
    const rec = JsonHelper.parse(text);
    if (rec === null) {
      return '';
    }
    let url: string = JsonHelper.getString(rec, 'authorize_url', '');
    if (url === '') {
      url = JsonHelper.getString(rec, 'url', '');
    }
    if (url === '') {
      url = JsonHelper.getString(rec, 'login_url', '');
    }
    return url;
  }

  /** 用回跳 code 完成授权（POST /api/connectors/auth/{kind}/exchange-code） */
  static async oauthExchangeCode(kind: string, code: string, bkn: string,
    knowledgeBaseId: string): Promise<string> {
    const body: Record<string, Object> = { 'code': code };
    if (bkn !== '') {
      body['bkn'] = bkn;
    }
    if (knowledgeBaseId !== '') {
      body['knowledge_base_id'] = knowledgeBaseId;
    }
    return await HttpClient.getInstance().post(
      `/api/connectors/auth/${kind}/exchange-code`, JSON.stringify(body));
  }
}

/** CLI 授权状态（AgentlyAuthResponse） */
export class AgentlyAuthState {
  readonly status: string; // idle|pending|authorized|expired|error
  readonly verificationUrl: string;
  readonly userCode: string;
  readonly expiresAtSec: number;
  readonly error: string;

  constructor(status: string, verificationUrl: string, userCode: string, expiresAtSec: number,
    error: string) {
    this.status = status;
    this.verificationUrl = verificationUrl;
    this.userCode = userCode;
    this.expiresAtSec = expiresAtSec;
    this.error = error;
  }

  static parse(text: string): AgentlyAuthState {
    const rec = JsonHelper.parse(text);
    if (rec === null) {
      return new AgentlyAuthState('idle', '', '', 0, '');
    }
    return new AgentlyAuthState(
      JsonHelper.getString(rec, 'status', 'idle'),
      JsonHelper.getString(rec, 'verification_url', ''),
      JsonHelper.getString(rec, 'user_code', ''),
      JsonHelper.getNumber(rec, 'expires_at', 0),
      JsonHelper.getString(rec, 'error', '')
    );
  }
}

/** 宿主 CLI 安装状态 */
export class CliInstallStatus {
  readonly kind: string;
  readonly binary: string;
  readonly npmPackage: string;
  readonly installCommand: string;
  readonly docUrl: string;
  readonly guideUrl: string;
  readonly installed: boolean;
  readonly binaryPath: string;
  readonly version: string;
  readonly error: string;

  constructor(kind: string, binary: string, npmPackage: string, installCommand: string,
    docUrl: string, guideUrl: string, installed: boolean, binaryPath: string, version: string,
    error: string) {
    this.kind = kind;
    this.binary = binary;
    this.npmPackage = npmPackage;
    this.installCommand = installCommand;
    this.docUrl = docUrl;
    this.guideUrl = guideUrl;
    this.installed = installed;
    this.binaryPath = binaryPath;
    this.version = version;
    this.error = error;
  }

  static parse(text: string): CliInstallStatus {
    const rec = JsonHelper.parse(text);
    if (rec === null) {
      return new CliInstallStatus('', '', '', '', '', '', false, '', '', '');
    }
    return new CliInstallStatus(
      JsonHelper.getString(rec, 'kind', ''),
      JsonHelper.getString(rec, 'binary', ''),
      JsonHelper.getString(rec, 'npm_package', ''),
      JsonHelper.getString(rec, 'install_command', ''),
      JsonHelper.getString(rec, 'doc_url', ''),
      JsonHelper.getString(rec, 'guide_url', ''),
      JsonHelper.getBool(rec, 'installed', false),
      JsonHelper.getString(rec, 'binary_path', ''),
      JsonHelper.getString(rec, 'version', ''),
      JsonHelper.getString(rec, 'error', '')
    );
  }
}

/** OAuth 发起结果 */
export class OAuthStartResult {
  readonly authorizeUrl: string;
  readonly stateId: string;

  constructor(authorizeUrl: string, stateId: string) {
    this.authorizeUrl = authorizeUrl;
    this.stateId = stateId;
  }

  static parse(text: string): OAuthStartResult {
    const rec = JsonHelper.parse(text);
    if (rec === null) {
      return new OAuthStartResult('', '');
    }
    return new OAuthStartResult(
      JsonHelper.getString(rec, 'authorize_url', ''),
      JsonHelper.getString(rec, 'state_id', '')
    );
  }
}

/** 专家团队（/api/teams，owner-only） */
export class TeamService {
  static async list(): Promise<Array<TeamModel>> {
    const text: string = await HttpClient.getInstance().get('/api/teams');
    return TeamModel.parseList(text);
  }

  /** 创建：{name, description?, default_model?, color?, icon_name?, icon_url?, welcome_message?, member_ids, config?} */
  static async create(bodyStr: string): Promise<void> {
    await HttpClient.getInstance().post('/api/teams', bodyStr);
  }

  static async get(teamId: string): Promise<TeamModel> {
    const text: string = await HttpClient.getInstance().get(`/api/teams/${teamId}`);
    return TeamModel.parseOne(text);
  }

  static async patch(teamId: string, bodyStr: string): Promise<void> {
    await HttpClient.getInstance().patch(`/api/teams/${teamId}`, bodyStr);
  }

  static async remove(teamId: string): Promise<void> {
    await HttpClient.getInstance().delete(`/api/teams/${teamId}`);
  }

  /** 默认团队模板文件预览：[{name, content}] */
  static async template(): Promise<string> {
    return await HttpClient.getInstance().get('/api/teams/template');
  }
}

/** per-agent 插件（/api/plugins/agents/{agent_id}） */
export class PluginService {
  static async listForAgent(agentId: string): Promise<Array<AgentPluginModel>> {
    const text: string = await HttpClient.getInstance().get(`/api/plugins/agents/${agentId}`);
    return AgentPluginModel.parseList(text);
  }

  static async setAgentEnabled(agentId: string, pluginId: string, enabled: boolean): Promise<void> {
    const inner: Record<string, Object> = { 'enabled': enabled };
    const plugins: Record<string, Object> = {};
    plugins[pluginId] = inner;
    const body: Record<string, Object> = { 'plugins': plugins };
    await HttpClient.getInstance().patch(
      `/api/plugins/agents/${agentId}`, JSON.stringify(body));
  }

  /** agent 工具配置列表（每工具一个开关，未显式覆盖时默认启用） */
  static async getAgentTools(agentId: string): Promise<Array<PluginToolModel>> {
    const text: string = await HttpClient.getInstance().get(`/api/plugins/agents/${agentId}/tools`);
    return PluginToolModel.parseList(text);
  }

  /** 覆盖某插件工具的启用状态 */
  static async patchAgentTools(agentId: string, pluginId: string, enabled: boolean): Promise<void> {
    const inner: Record<string, Object> = { 'enabled': enabled };
    const plugins: Record<string, Object> = {};
    plugins[pluginId] = inner;
    const body: Record<string, Object> = { 'plugins': plugins };
    await HttpClient.getInstance().patch(
      `/api/plugins/agents/${agentId}/tools`, JSON.stringify(body));
  }
}

/** 全局插件管理（/api/plugins，需 plugins 权限） */
export class GlobalPluginService {
  /** 已安装插件列表 */
  static async list(): Promise<Array<GlobalPluginModel>> {
    const text: string = await HttpClient.getInstance().get('/api/plugins');
    return GlobalPluginModel.parseList(text);
  }

  /** 全局启停 */
  static async setEnabled(pluginId: string, enabled: boolean): Promise<void> {
    const body: Record<string, Object> = { 'enabled': enabled };
    await HttpClient.getInstance().patch(`/api/plugins/${pluginId}`, JSON.stringify(body));
  }

  /** 从 URL 安装 ZIP */
  static async installUrl(url: string): Promise<void> {
    const body: Record<string, Object> = { 'url': url };
    await HttpClient.getInstance().post('/api/plugins/install', JSON.stringify(body));
  }

  /** 上传本地 ZIP 安装插件（multipart file + force；需 plugins 权限） */
  static async uploadZip(fileName: string, data: ArrayBuffer,
    force: boolean = false): Promise<void> {
    const formFields: Record<string, string> = { 'force': force ? 'true' : 'false' };
    await HttpClient.getInstance().postMultipartFile(
      '/api/plugins/upload', 'file', fileName, 'application/zip', data, formFields);
  }

  /** 市场目录 */
  static async market(): Promise<Array<MarketPluginModel>> {
    const text: string = await HttpClient.getInstance().get('/api/plugins/market');
    return MarketPluginModel.parseList(text);
  }

  /** 从市场安装（force=true 覆盖已装） */
  static async marketInstall(pluginId: string, force: boolean = false): Promise<void> {
    await HttpClient.getInstance().post(
      `/api/plugins/market/${pluginId}/install?force=${force}`, '{}');
  }

  /** 卸载 */
  static async uninstall(pluginId: string): Promise<void> {
    await HttpClient.getInstance().delete(`/api/plugins/${pluginId}`);
  }

  /** 从磁盘重载（CLI 安装后使用） */
  static async reload(): Promise<void> {
    await HttpClient.getInstance().post('/api/plugins/reload', '{}');
  }
}

/** MBTI 人格（/api/mbti/*，agent 上下文经 X-Octop-Agent-Id 头传递） */
export class MbtiService {
  private static agentHeader(agentId: string): Record<string, string> {
    const header: Record<string, string> = {};
    header['X-Octop-Agent-Id'] = agentId;
    return header;
  }

  /** 当前 agent 人格：{code, configured} */
  static async current(agentId: string): Promise<string> {
    const text: string = await HttpClient.getInstance().get('/api/mbti/current',
      MbtiService.agentHeader(agentId));
    const rec = JsonHelper.parse(text);
    return rec === null ? '' : JsonHelper.getString(rec, 'code', '');
  }

  static async listTypes(): Promise<Array<MbtiTypeModel>> {
    const text: string = await HttpClient.getInstance().get('/api/mbti/types');
    return MbtiTypeModel.parseList(text);
  }

  /** 单类型详情（含 dimensions/behavior 全量字段） */
  static async typeDetail(code: string): Promise<MbtiTypeModel> {
    const text: string = await HttpClient.getInstance().get(`/api/mbti/types/${code}`);
    const rec = JsonHelper.parse(text);
    return MbtiTypeModel.fromRecord(rec === null ? {} : rec);
  }

  /** 人格模板渲染预览 markdown */
  static async preview(code: string): Promise<string> {
    const text: string = await HttpClient.getInstance().get(`/api/mbti/preview/${code}`);
    const rec = JsonHelper.parse(text);
    return rec === null ? '' : JsonHelper.getString(rec, 'preview', '');
  }

  /** 28 道测试题 */
  static async questions(): Promise<Array<MbtiQuestionModel>> {
    const text: string = await HttpClient.getInstance().get('/api/mbti/test/questions');
    return MbtiQuestionModel.parseList(text);
  }

  /** 提交答卷：answers 键为题号字符串、值 'A'/'B'；autoApply 时需 agentId */
  static async submit(answers: Record<string, Object>, autoApply: boolean,
    agentId: string = ''): Promise<MbtiTestResultModel> {
    const body: Record<string, Object> = {
      'answers': answers,
      'auto_apply': autoApply,
      'language': 'zh'
    };
    const headers: Record<string, string> | undefined =
      autoApply && agentId !== '' ? MbtiService.agentHeader(agentId) : undefined;
    const text: string = await HttpClient.getInstance().post(
      '/api/mbti/test/submit', JSON.stringify(body), headers);
    return MbtiTestResultModel.parse(text);
  }

  /** 应用人格到 agent */
  static async apply(agentId: string, code: string): Promise<void> {
    const body: Record<string, Object> = {
      'code': code,
      'language': 'zh'
    };
    await HttpClient.getInstance().post('/api/mbti/apply', JSON.stringify(body),
      MbtiService.agentHeader(agentId));
  }
}

/** 服务器设置（/api/settings/*，只读展示） */
export class SettingsService {
  /** 进程时区：{"timezone": "Asia/Shanghai"} */
  static async getTimezone(): Promise<string> {
    const text: string = await HttpClient.getInstance().get('/api/settings/timezone');
    const rec = JsonHelper.parse(text);
    return rec === null ? '' : JsonHelper.getString(rec, 'timezone', '');
  }

  /** 上传上限 MB：{"max_upload_mb": 100} */
  static async getMaxUploadMb(): Promise<number> {
    const text: string = await HttpClient.getInstance().get('/api/settings/upload');
    const rec = JsonHelper.parse(text);
    return rec === null ? 0 : JsonHelper.getNumber(rec, 'max_upload_mb', 0);
  }

  /** HITL 审批设置 */
  static async getHitl(): Promise<HitlSettings> {
    const text: string = await HttpClient.getInstance().get('/api/settings/hitl');
    const rec = JsonHelper.parse(text);
    return HitlSettings.fromRecord(rec === null ? {} : rec);
  }

  /** 移动端能力（capabilities.mobile） */
  static async getMobileCapability(): Promise<MobileCapability> {
    const text: string = await HttpClient.getInstance().get('/api/settings/capabilities');
    const rec = JsonHelper.parse(text);
    const mobile = JsonHelper.getRecord(rec, 'mobile');
    return MobileCapability.fromRecord(mobile === null ? {} : mobile);
  }

  /** 验证码设置（需 captcha 权限） */
  static async getCaptcha(): Promise<CaptchaSettingsModel> {
    const text: string = await HttpClient.getInstance().get('/api/settings/captcha');
    const rec = JsonHelper.parse(text);
    return CaptchaSettingsModel.fromRecord(rec === null ? {} : rec);
  }

  /** 更新验证码设置：{active?, providers?{kind:{site_key?, secret?, cam_secret_id?, cam_secret?}}} */
  static async putCaptcha(body: string): Promise<void> {
    await HttpClient.getInstance().put('/api/settings/captcha', body);
  }
}
