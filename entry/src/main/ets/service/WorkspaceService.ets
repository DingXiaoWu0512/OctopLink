import { HttpClient } from '../net/HttpClient';
import {
  AgentPluginModel,
  ChannelModel,
  ChannelPluginKindModel,
  ConnectorCatalogEntry,
  ConnectorInstanceModel,
  CronJobModel,
  CustomMcpServerModel,
  HitlSettings,
  KnowledgeBaseModel,
  KnowledgeCapability,
  KnowledgeDocModel,
  MbtiTypeModel,
  MobileCapability,
  QrPollResult,
  QrSessionModel
} from '../model/WorkspaceModels';
import { JsonHelper } from '../utils/JsonHelper';

/** 定时任务（/api/agents/{id}/cron，owner-only） */
export class CronService {
  static async list(agentId: string): Promise<Array<CronJobModel>> {
    const text: string = await HttpClient.getInstance().get(`/api/agents/${agentId}/cron`);
    return CronJobModel.parseList(text);
  }

  /** 创建：trigger 为 cron:/interval:/date:/agently: 形式 */
  static async create(agentId: string, name: string, trigger: string, prompt: string): Promise<void> {
    const body: Record<string, Object> = {
      'trigger': trigger,
      'prompt': prompt,
      'enabled': true
    };
    if (name !== '') {
      body['name'] = name;
    }
    await HttpClient.getInstance().post(`/api/agents/${agentId}/cron`, JSON.stringify(body));
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

  /** 服务能力与限制（任意登录用户） */
  static async capability(): Promise<KnowledgeCapability> {
    const text: string = await HttpClient.getInstance().get('/api/knowledge-bases/capability');
    return KnowledgeCapability.parse(text);
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
}
