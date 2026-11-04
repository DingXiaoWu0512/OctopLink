import { JsonHelper } from '../utils/JsonHelper';
import { OctopApiError } from '../net/HttpClient';

/**
 * 工作台数据模型（契约见 docs/api-contract-workspace.md）：
 * - CronJobModel：定时任务
 * - KnowledgeBaseModel / KnowledgeDocModel：知识库与文档
 * - ChannelModel：渠道
 * - ConnectorInstanceModel：连接器实例
 * - AgentPluginModel：per-agent 插件
 * - MbtiTypeModel：MBTI 人格类型
 */

/** 定时任务（GET /api/agents/{id}/cron 列表项） */
export class CronJobModel {
  readonly id: string;
  readonly name: string;
  readonly trigger: string;
  readonly prompt: string;
  readonly enabled: boolean;
  readonly freshThread: boolean;
  readonly lastRunAtMs: number;
  readonly lastStatus: string;
  readonly lastError: string;
  readonly model: string;
  readonly taskType: string;

  constructor(id: string, name: string, trigger: string, prompt: string, enabled: boolean,
    freshThread: boolean, lastRunAtMs: number, lastStatus: string, lastError: string, model: string,
    taskType: string) {
    this.id = id;
    this.name = name;
    this.trigger = trigger;
    this.prompt = prompt;
    this.enabled = enabled;
    this.freshThread = freshThread;
    this.lastRunAtMs = lastRunAtMs;
    this.lastStatus = lastStatus;
    this.lastError = lastError;
    this.model = model;
    this.taskType = taskType;
  }

  static fromRecord(rec: Record<string, Object>): CronJobModel {
    return new CronJobModel(
      JsonHelper.getString(rec, 'id', ''),
      JsonHelper.getString(rec, 'name', ''),
      JsonHelper.getString(rec, 'trigger', ''),
      JsonHelper.getString(rec, 'prompt', ''),
      JsonHelper.getBool(rec, 'enabled', true),
      JsonHelper.getBool(rec, 'fresh_thread', false),
      JsonHelper.toMs(rec['last_run_at']),
      JsonHelper.getString(rec, 'last_status', ''),
      JsonHelper.getString(rec, 'last_error', ''),
      JsonHelper.getString(rec, 'model', ''),
      JsonHelper.getString(rec, 'task_type', 'text')
    );
  }

  /** 触发器人类可读描述：cron:/interval:/date:/agently: 四种形式 */
  triggerDisplay(): string {
    if (this.trigger.startsWith('cron:')) {
      return `Cron ${this.trigger.substring(5)}`;
    }
    if (this.trigger.startsWith('interval:')) {
      return `每 ${this.trigger.substring(9)} 秒`;
    }
    if (this.trigger.startsWith('date:')) {
      return `定时 ${this.trigger.substring(5)}`;
    }
    if (this.trigger.startsWith('agently:')) {
      return '收到新邮件时';
    }
    return this.trigger;
  }

  static parseList(text: string): Array<CronJobModel> {
    const result: Array<CronJobModel> = [];
    const arr = JsonHelper.parseArray(text);
    if (arr !== null) {
      for (const rec of arr) {
        result.push(CronJobModel.fromRecord(rec));
      }
      return result;
    }
    const obj = JsonHelper.parse(text);
    const items = JsonHelper.getRecordArray(obj, 'jobs');
    for (const rec of items) {
      result.push(CronJobModel.fromRecord(rec));
    }
    return result;
  }
}

/** 知识库（GET /api/knowledge-bases 列表项） */
export class KnowledgeBaseModel {
  readonly id: string;
  readonly name: string;
  readonly description: string;
  readonly docCount: number;
  readonly shared: boolean;
  readonly defaultOpen: boolean;
  readonly maxDocuments: number;
  readonly createdAtMs: number;
  readonly ownerUsername: string;

  constructor(id: string, name: string, description: string, docCount: number, shared: boolean,
    defaultOpen: boolean, maxDocuments: number, createdAtMs: number, ownerUsername: string) {
    this.id = id;
    this.name = name;
    this.description = description;
    this.docCount = docCount;
    this.shared = shared;
    this.defaultOpen = defaultOpen;
    this.maxDocuments = maxDocuments;
    this.createdAtMs = createdAtMs;
    this.ownerUsername = ownerUsername;
  }

  static fromRecord(rec: Record<string, Object>): KnowledgeBaseModel {
    return new KnowledgeBaseModel(
      JsonHelper.getString(rec, 'id', '') !== '' ? JsonHelper.getString(rec, 'id', '') :
        JsonHelper.getString(rec, 'knowledge_base_id', ''),
      JsonHelper.getString(rec, 'name', ''),
      JsonHelper.getString(rec, 'description', ''),
      JsonHelper.getNumber(rec, 'doc_count', 0),
      JsonHelper.getBool(rec, 'shared', false),
      JsonHelper.getBool(rec, 'default_open', false),
      JsonHelper.getNumber(rec, 'max_documents', 100),
      JsonHelper.toMs(rec['created_at']),
      JsonHelper.getString(rec, 'owner_username', '')
    );
  }

  static parseList(text: string): Array<KnowledgeBaseModel> {
    const result: Array<KnowledgeBaseModel> = [];
    const arr = JsonHelper.parseArray(text);
    if (arr !== null) {
      for (const rec of arr) {
        result.push(KnowledgeBaseModel.fromRecord(rec));
      }
      return result;
    }
    const obj = JsonHelper.parse(text);
    const items = JsonHelper.getRecordArray(obj, 'bases');
    for (const rec of items) {
      result.push(KnowledgeBaseModel.fromRecord(rec));
    }
    return result;
  }
}

/** 知识库文档（GET .../documents 列表项） */
export class KnowledgeDocModel {
  readonly id: string;
  readonly path: string;
  readonly filename: string;
  readonly isDir: boolean;
  readonly byteSize: number;
  readonly status: string;
  readonly errorMessage: string;
  readonly chunkCount: number;

  constructor(id: string, path: string, filename: string, isDir: boolean, byteSize: number,
    status: string, errorMessage: string, chunkCount: number) {
    this.id = id;
    this.path = path;
    this.filename = filename;
    this.isDir = isDir;
    this.byteSize = byteSize;
    this.status = status;
    this.errorMessage = errorMessage;
    this.chunkCount = chunkCount;
  }

  static fromRecord(rec: Record<string, Object>): KnowledgeDocModel {
    const id: string = JsonHelper.getString(rec, 'id', '') !== '' ? JsonHelper.getString(rec, 'id', '') :
      JsonHelper.getString(rec, 'document_id', '');
    return new KnowledgeDocModel(
      id,
      JsonHelper.getString(rec, 'path', ''),
      JsonHelper.getString(rec, 'filename', ''),
      JsonHelper.getBool(rec, 'is_dir', false),
      JsonHelper.getNumber(rec, 'byte_size', 0),
      JsonHelper.getString(rec, 'status', ''),
      JsonHelper.getString(rec, 'error_message', ''),
      JsonHelper.getNumber(rec, 'chunk_count', 0)
    );
  }

  /** 文件大小可读化 */
  sizeDisplay(): string {
    if (this.isDir) {
      return '文件夹';
    }
    if (this.byteSize < 1024) {
      return `${this.byteSize} B`;
    }
    if (this.byteSize < 1024 * 1024) {
      return `${(this.byteSize / 1024).toFixed(1)} KB`;
    }
    return `${(this.byteSize / 1024 / 1024).toFixed(1)} MB`;
  }

  static parseList(text: string): Array<KnowledgeDocModel> {
    const result: Array<KnowledgeDocModel> = [];
    const arr = JsonHelper.parseArray(text);
    if (arr !== null) {
      for (const rec of arr) {
        result.push(KnowledgeDocModel.fromRecord(rec));
      }
      return result;
    }
    const obj = JsonHelper.parse(text);
    const items = JsonHelper.getRecordArray(obj, 'documents');
    for (const rec of items) {
      result.push(KnowledgeDocModel.fromRecord(rec));
    }
    return result;
  }
}

/** 知识库服务能力（GET /api/knowledge-bases/capability）：功能开关、嵌入后端、OCR 与限制 */
export class KnowledgeCapability {
  readonly enabled: boolean;
  readonly selectedModel: string;
  readonly backend: string; // onnx | remote
  readonly providerId: string;
  readonly prerequisitesOk: boolean;
  readonly usable: boolean;
  readonly chunkSize: number;
  readonly chunkOverlap: number;
  readonly retrievalK: number;
  readonly contextCharBudget: number;
  readonly ocrEnabled: boolean;
  readonly ocrBackend: string;
  readonly ocrModel: string;
  readonly maxBasesPerOwner: number;
  readonly maxDocsPerKb: number;
  readonly maxDocumentBytes: number;

  constructor(enabled: boolean, selectedModel: string, backend: string, providerId: string,
    prerequisitesOk: boolean, usable: boolean, chunkSize: number, chunkOverlap: number,
    retrievalK: number, contextCharBudget: number, ocrEnabled: boolean, ocrBackend: string,
    ocrModel: string, maxBasesPerOwner: number, maxDocsPerKb: number, maxDocumentBytes: number) {
    this.enabled = enabled;
    this.selectedModel = selectedModel;
    this.backend = backend;
    this.providerId = providerId;
    this.prerequisitesOk = prerequisitesOk;
    this.usable = usable;
    this.chunkSize = chunkSize;
    this.chunkOverlap = chunkOverlap;
    this.retrievalK = retrievalK;
    this.contextCharBudget = contextCharBudget;
    this.ocrEnabled = ocrEnabled;
    this.ocrBackend = ocrBackend;
    this.ocrModel = ocrModel;
    this.maxBasesPerOwner = maxBasesPerOwner;
    this.maxDocsPerKb = maxDocsPerKb;
    this.maxDocumentBytes = maxDocumentBytes;
  }

  static parse(text: string): KnowledgeCapability {
    const rec = JsonHelper.parse(text);
    if (rec === null) {
      return new KnowledgeCapability(false, '', '', '', false, false, 800, 120, 8, 6000,
        false, '', '', 0, 0, 0);
    }
    const ocr: Record<string, Object> | null = JsonHelper.getRecord(rec, 'ocr');
    const limits: Record<string, Object> | null = JsonHelper.getRecord(rec, 'limits');
    return new KnowledgeCapability(
      JsonHelper.getBool(rec, 'feature_enabled', true),
      JsonHelper.getString(rec, 'selected_model', ''),
      JsonHelper.getString(rec, 'backend', ''),
      JsonHelper.getString(rec, 'provider_id', ''),
      JsonHelper.getBool(rec, 'prerequisites_ok', false),
      JsonHelper.getBool(rec, 'usable', false),
      JsonHelper.getNumber(rec, 'chunk_size', 800),
      JsonHelper.getNumber(rec, 'chunk_overlap', 120),
      JsonHelper.getNumber(rec, 'retrieval_k', 8),
      JsonHelper.getNumber(rec, 'context_char_budget', 6000),
      ocr === null ? false : JsonHelper.getBool(ocr, 'enabled', false),
      ocr === null ? '' : JsonHelper.getString(ocr, 'backend', ''),
      ocr === null ? '' : JsonHelper.getString(ocr, 'model', ''),
      limits === null ? 0 : JsonHelper.getNumber(limits, 'max_bases_per_owner', 0),
      limits === null ? 0 : JsonHelper.getNumber(limits, 'max_docs_per_kb', 0),
      limits === null ? 0 : JsonHelper.getNumber(limits, 'max_document_bytes', 0)
    );
  }
}

/** 渠道（GET /api/agents/{id}/channels 列表项） */
export class ChannelModel {
  readonly id: string;
  readonly kind: string;
  readonly name: string;
  readonly enabled: boolean;
  readonly runtime: string;

  constructor(id: string, kind: string, name: string, enabled: boolean, runtime: string) {
    this.id = id;
    this.kind = kind;
    this.name = name;
    this.enabled = enabled;
    this.runtime = runtime;
  }

  static fromRecord(rec: Record<string, Object>): ChannelModel {
    return new ChannelModel(
      JsonHelper.getString(rec, 'id', '') !== '' ? JsonHelper.getString(rec, 'id', '') :
        JsonHelper.getString(rec, 'channel_id', ''),
      JsonHelper.getString(rec, 'kind', ''),
      JsonHelper.getString(rec, 'name', ''),
      JsonHelper.getBool(rec, 'enabled', true),
      JsonHelper.getString(rec, 'runtime', '')
    );
  }

  static parseList(text: string): Array<ChannelModel> {
    const result: Array<ChannelModel> = [];
    const arr = JsonHelper.parseArray(text);
    if (arr !== null) {
      for (const rec of arr) {
        result.push(ChannelModel.fromRecord(rec));
      }
      return result;
    }
    const obj = JsonHelper.parse(text);
    const items = JsonHelper.getRecordArray(obj, 'channels');
    for (const rec of items) {
      result.push(ChannelModel.fromRecord(rec));
    }
    return result;
  }
}

/** 插件贡献的渠道类型（GET /api/channels/plugin-kinds） */
export class ChannelPluginKindModel {
  readonly kind: string;
  readonly label: string;
  readonly pluginId: string;

  constructor(kind: string, label: string, pluginId: string) {
    this.kind = kind;
    this.label = label;
    this.pluginId = pluginId;
  }

  static parseList(text: string): Array<ChannelPluginKindModel> {
    const result: Array<ChannelPluginKindModel> = [];
    const arr = JsonHelper.parseArray(text);
    if (arr !== null) {
      for (const rec of arr) {
        result.push(new ChannelPluginKindModel(
          JsonHelper.getString(rec, 'kind', ''),
          JsonHelper.getString(rec, 'label', ''),
          JsonHelper.getString(rec, 'plugin_id', '')
        ));
      }
    }
    return result;
  }
}

/** 扫码会话（generate 响应的容错解析：registration_id/scode/qrcode_token 三态） */
export class QrSessionModel {
  readonly token: string;
  readonly qrcodeUrl: string;
  readonly userCode: string;

  constructor(token: string, qrcodeUrl: string, userCode: string) {
    this.token = token;
    this.qrcodeUrl = qrcodeUrl;
    this.userCode = userCode;
  }

  static parse(text: string): QrSessionModel {
    const rec = JsonHelper.parse(text);
    if (rec === null) {
      return new QrSessionModel('', '', '');
    }
    let token: string = JsonHelper.getString(rec, 'registration_id', '');
    if (token === '') {
      token = JsonHelper.getString(rec, 'scode', '');
    }
    if (token === '') {
      token = JsonHelper.getString(rec, 'qrcode_token', '');
    }
    // 二维码内容取值链：qrcode_url 优先，企微 generate 无 qrcode_url 时兜底 auth_url
    let qrUrl: string = JsonHelper.getString(rec, 'qrcode_url', '');
    if (qrUrl === '') {
      qrUrl = JsonHelper.getString(rec, 'auth_url', '');
    }
    return new QrSessionModel(
      token,
      qrUrl,
      JsonHelper.getString(rec, 'user_code', '')
    );
  }
}

/** 扫码轮询结果（waiting|expired|failed|success / wait|error） */
export class QrPollResult {
  readonly status: string;
  readonly channelId: string;
  readonly message: string;

  constructor(status: string, channelId: string, message: string) {
    this.status = status;
    this.channelId = channelId;
    this.message = message;
  }

  static parse(text: string): QrPollResult {
    const rec = JsonHelper.parse(text);
    if (rec === null) {
      return new QrPollResult('error', '', '响应格式错误');
    }
    let status: string = JsonHelper.getString(rec, 'status', '');
    if (status === 'wait') {
      status = 'waiting';
    }
    if (status === 'error') {
      status = 'failed';
    }
    return new QrPollResult(
      status,
      JsonHelper.getString(rec, 'channel_id', ''),
      JsonHelper.getString(rec, 'message', '')
    );
  }
}

/** 连接器目录项（GET /api/connectors/catalog，字段容错） */
export class ConnectorCatalogEntry {
  readonly kind: string;
  readonly label: string;
  readonly description: string;
  readonly available: boolean;
  readonly oauthConfigured: boolean;
  readonly authKind: string;

  constructor(kind: string, label: string, description: string, available: boolean,
    oauthConfigured: boolean, authKind: string) {
    this.kind = kind;
    this.label = label;
    this.description = description;
    this.available = available;
    this.oauthConfigured = oauthConfigured;
    this.authKind = authKind;
  }

  static fromRecord(rec: Record<string, Object>): ConnectorCatalogEntry {
    const label: string = JsonHelper.getString(rec, 'label', '') !== '' ?
      JsonHelper.getString(rec, 'label', '') : JsonHelper.getString(rec, 'name', '');
    return new ConnectorCatalogEntry(
      JsonHelper.getString(rec, 'kind', ''),
      label,
      JsonHelper.getString(rec, 'description', ''),
      JsonHelper.getBool(rec, 'available', true),
      JsonHelper.getBool(rec, 'oauth_configured', false),
      JsonHelper.getString(rec, 'auth_kind', '')
    );
  }

  static parseList(text: string): Array<ConnectorCatalogEntry> {
    const result: Array<ConnectorCatalogEntry> = [];
    const arr = JsonHelper.parseArray(text);
    if (arr !== null) {
      for (const rec of arr) {
        result.push(ConnectorCatalogEntry.fromRecord(rec));
      }
      return result;
    }
    const obj = JsonHelper.parse(text);
    const items: Array<Record<string, Object>> = JsonHelper.getRecordArray(obj, 'catalog');
    for (const rec of items) {
      result.push(ConnectorCatalogEntry.fromRecord(rec));
    }
    const items2: Array<Record<string, Object>> = JsonHelper.getRecordArray(obj, 'connectors');
    for (const rec of items2) {
      result.push(ConnectorCatalogEntry.fromRecord(rec));
    }
    return result;
  }
}

/** 自定义 MCP 服务器（GET /api/connectors/custom-mcp 的 servers 展开项） */
export class CustomMcpServerModel {
  readonly name: string;
  readonly enabled: boolean;
  readonly defaultOpen: boolean;
  readonly shared: boolean;

  constructor(name: string, enabled: boolean, defaultOpen: boolean, shared: boolean) {
    this.name = name;
    this.enabled = enabled;
    this.defaultOpen = defaultOpen;
    this.shared = shared;
  }

  static parseList(text: string): Array<CustomMcpServerModel> {
    const result: Array<CustomMcpServerModel> = [];
    const rec = JsonHelper.parse(text);
    if (rec === null) {
      return result;
    }
    const servers: Record<string, Object> | null = JsonHelper.getRecord(rec, 'servers');
    if (servers === null) {
      return result;
    }
    const names: Array<string> = Object.keys(servers);
    for (const name of names) {
      const spec: Object | undefined = servers[name];
      if (spec === undefined || spec === null || typeof spec !== 'object') {
        continue;
      }
      const specRec: Record<string, Object> = spec as Record<string, Object>;
      result.push(new CustomMcpServerModel(
        name,
        JsonHelper.getBool(specRec, 'enabled', true),
        JsonHelper.getBool(specRec, 'default_open', false),
        JsonHelper.getBool(specRec, 'shared', false)
      ));
    }
    return result;
  }
}

/** 连接器实例（GET /api/connector-instances 列表项） */
export class ConnectorInstanceModel {
  readonly instanceId: string;
  readonly kind: string;
  readonly displayName: string;
  readonly description: string;
  readonly status: string;
  readonly hasCredentials: boolean;
  readonly defaultOpen: boolean;
  readonly shared: boolean;
  readonly ownerUsername: string;
  readonly canManage: boolean;

  constructor(instanceId: string, kind: string, displayName: string, description: string,
    status: string, hasCredentials: boolean, defaultOpen: boolean, shared: boolean,
    ownerUsername: string, canManage: boolean) {
    this.instanceId = instanceId;
    this.kind = kind;
    this.displayName = displayName;
    this.description = description;
    this.status = status;
    this.hasCredentials = hasCredentials;
    this.defaultOpen = defaultOpen;
    this.shared = shared;
    this.ownerUsername = ownerUsername;
    this.canManage = canManage;
  }

  static fromRecord(rec: Record<string, Object>): ConnectorInstanceModel {
    return new ConnectorInstanceModel(
      JsonHelper.getString(rec, 'instance_id', ''),
      JsonHelper.getString(rec, 'kind', ''),
      JsonHelper.getString(rec, 'display_name', ''),
      JsonHelper.getString(rec, 'description', ''),
      JsonHelper.getString(rec, 'status', 'active'),
      JsonHelper.getBool(rec, 'has_credentials', false),
      JsonHelper.getBool(rec, 'default_open', false),
      JsonHelper.getBool(rec, 'shared', false),
      JsonHelper.getString(rec, 'owner_username', ''),
      JsonHelper.getBool(rec, 'can_manage', true)
    );
  }

  static parseList(text: string): Array<ConnectorInstanceModel> {
    const result: Array<ConnectorInstanceModel> = [];
    const arr = JsonHelper.parseArray(text);
    if (arr !== null) {
      for (const rec of arr) {
        result.push(ConnectorInstanceModel.fromRecord(rec));
      }
      return result;
    }
    const obj = JsonHelper.parse(text);
    const items = JsonHelper.getRecordArray(obj, 'instances');
    for (const rec of items) {
      result.push(ConnectorInstanceModel.fromRecord(rec));
    }
    return result;
  }
}

/** per-agent 插件（GET /api/plugins/agents/{agent_id} 列表项） */
export class AgentPluginModel {
  readonly id: string;
  readonly name: string;
  readonly kind: string;
  readonly description: string;
  readonly globalEnabled: boolean;
  readonly agentEnabled: boolean;
  readonly loaded: boolean;

  constructor(id: string, name: string, kind: string, description: string,
    globalEnabled: boolean, agentEnabled: boolean, loaded: boolean) {
    this.id = id;
    this.name = name;
    this.kind = kind;
    this.description = description;
    this.globalEnabled = globalEnabled;
    this.agentEnabled = agentEnabled;
    this.loaded = loaded;
  }

  static fromRecord(rec: Record<string, Object>): AgentPluginModel {
    return new AgentPluginModel(
      JsonHelper.getString(rec, 'id', ''),
      JsonHelper.getString(rec, 'name', ''),
      JsonHelper.getString(rec, 'kind', ''),
      JsonHelper.getString(rec, 'description', ''),
      JsonHelper.getBool(rec, 'global_enabled', false),
      JsonHelper.getBool(rec, 'agent_enabled', false),
      JsonHelper.getBool(rec, 'loaded', false)
    );
  }

  static parseList(text: string): Array<AgentPluginModel> {
    const result: Array<AgentPluginModel> = [];
    const rec = JsonHelper.parse(text);
    if (rec === null) {
      return result;
    }
    const items = JsonHelper.getRecordArray(rec, 'plugins');
    for (const item of items) {
      result.push(AgentPluginModel.fromRecord(item));
    }
    return result;
  }
}

/** 全局插件（GET /api/plugins 列表项） */
export class GlobalPluginModel {
  readonly id: string;
  readonly name: string;
  readonly kind: string;
  readonly version: string;
  readonly description: string;
  readonly loaded: boolean;
  readonly enabled: boolean;

  constructor(id: string, name: string, kind: string, version: string, description: string,
    loaded: boolean, enabled: boolean) {
    this.id = id;
    this.name = name;
    this.kind = kind;
    this.version = version;
    this.description = description;
    this.loaded = loaded;
    this.enabled = enabled;
  }

  static fromRecord(rec: Record<string, Object>): GlobalPluginModel {
    return new GlobalPluginModel(
      JsonHelper.getString(rec, 'id', ''),
      JsonHelper.getString(rec, 'name', ''),
      JsonHelper.getString(rec, 'kind', ''),
      JsonHelper.getString(rec, 'version', ''),
      JsonHelper.getString(rec, 'description', ''),
      JsonHelper.getBool(rec, 'loaded', false),
      JsonHelper.getBool(rec, 'enabled', JsonHelper.getBool(rec, 'global_enabled', false))
    );
  }

  static parseList(text: string): Array<GlobalPluginModel> {
    const result: Array<GlobalPluginModel> = [];
    const arr = JsonHelper.parseArray(text);
    if (arr !== null) {
      for (const rec of arr) {
        result.push(GlobalPluginModel.fromRecord(rec));
      }
      return result;
    }
    const obj = JsonHelper.parse(text);
    const items = JsonHelper.getRecordArray(obj, 'plugins');
    for (const rec of items) {
      result.push(GlobalPluginModel.fromRecord(rec));
    }
    return result;
  }
}

/** 市场插件（GET /api/plugins/market 目录项） */
export class MarketPluginModel {
  readonly id: string;
  readonly name: string;
  readonly description: string;
  readonly version: string;
  readonly kind: string;

  constructor(id: string, name: string, description: string, version: string, kind: string) {
    this.id = id;
    this.name = name;
    this.description = description;
    this.version = version;
    this.kind = kind;
  }

  static fromRecord(rec: Record<string, Object>): MarketPluginModel {
    return new MarketPluginModel(
      JsonHelper.getString(rec, 'id', ''),
      JsonHelper.getString(rec, 'name', ''),
      JsonHelper.getString(rec, 'description', ''),
      JsonHelper.getString(rec, 'version', ''),
      JsonHelper.getString(rec, 'kind', '')
    );
  }

  static parseList(text: string): Array<MarketPluginModel> {
    const result: Array<MarketPluginModel> = [];
    const arr = JsonHelper.parseArray(text);
    if (arr !== null) {
      for (const rec of arr) {
        result.push(MarketPluginModel.fromRecord(rec));
      }
      return result;
    }
    const obj = JsonHelper.parse(text);
    let items = JsonHelper.getRecordArray(obj, 'plugins');
    if (items.length === 0) {
      items = JsonHelper.getRecordArray(obj, 'market');
    }
    for (const rec of items) {
      result.push(MarketPluginModel.fromRecord(rec));
    }
    return result;
  }
}

/** agent 工具配置项（GET /api/plugins/agents/{id}/tools） */
export class PluginToolModel {
  readonly pluginId: string;
  readonly name: string;
  readonly description: string;
  readonly enabled: boolean;

  constructor(pluginId: string, name: string, description: string, enabled: boolean) {
    this.pluginId = pluginId;
    this.name = name;
    this.description = description;
    this.enabled = enabled;
  }

  static fromRecord(rec: Record<string, Object>): PluginToolModel {
    return new PluginToolModel(
      JsonHelper.getString(rec, 'plugin_id', ''),
      JsonHelper.getString(rec, 'name', ''),
      JsonHelper.getString(rec, 'description', ''),
      JsonHelper.getBool(rec, 'enabled', true)
    );
  }

  static parseList(text: string): Array<PluginToolModel> {
    const result: Array<PluginToolModel> = [];
    const arr = JsonHelper.parseArray(text);
    if (arr !== null) {
      for (const rec of arr) {
        result.push(PluginToolModel.fromRecord(rec));
      }
      return result;
    }
    const obj = JsonHelper.parse(text);
    const items = JsonHelper.getRecordArray(obj, 'tools');
    for (const rec of items) {
      result.push(PluginToolModel.fromRecord(rec));
    }
    return result;
  }
}

/** MBTI 维度（dimensions: {"ei": ["I", 72], ...}） */
export class MbtiDimensionModel {
  readonly key: string;
  readonly pole: string;
  readonly percent: number;

  constructor(key: string, pole: string, percent: number) {
    this.key = key;
    this.pole = pole;
    this.percent = percent;
  }

  /** 维度中文名 */
  labelZh(): string {
    if (this.key === 'ei') {
      return '精力方向';
    }
    if (this.key === 'sn') {
      return '认知方式';
    }
    if (this.key === 'tf') {
      return '决策方式';
    }
    return '生活态度';
  }
}

/** MBTI 类型（GET /api/mbti/types 列表项） */
export class MbtiTypeModel {
  readonly code: string;
  readonly nameZh: string;
  readonly nameEn: string;
  readonly summaryZh: string;
  readonly color: string;
  readonly nicknameZh: string;
  readonly descriptorsZh: string;
  readonly dimensions: Array<MbtiDimensionModel>;

  constructor(code: string, nameZh: string, nameEn: string, summaryZh: string, color: string,
    nicknameZh: string, descriptorsZh: string, dimensions: Array<MbtiDimensionModel>) {
    this.code = code;
    this.nameZh = nameZh;
    this.nameEn = nameEn;
    this.summaryZh = summaryZh;
    this.color = color;
    this.nicknameZh = nicknameZh;
    this.descriptorsZh = descriptorsZh;
    this.dimensions = dimensions;
  }

  static fromRecord(rec: Record<string, Object>): MbtiTypeModel {
    return new MbtiTypeModel(
      JsonHelper.getString(rec, 'code', ''),
      JsonHelper.getString(rec, 'name_zh', ''),
      JsonHelper.getString(rec, 'name_en', ''),
      JsonHelper.getString(rec, 'summary_zh', ''),
      JsonHelper.getString(rec, 'color', ''),
      JsonHelper.getString(rec, 'nickname_zh', ''),
      JsonHelper.getString(rec, 'descriptors_zh', ''),
      MbtiTypeModel.parseDimensions(rec)
    );
  }

  /** dimensions 固定四键 ei/sn/tf/jp，值形如 ["I", 72] */
  private static parseDimensions(rec: Record<string, Object>): Array<MbtiDimensionModel> {
    const result: Array<MbtiDimensionModel> = [];
    const dimRec: Record<string, Object> | null = JsonHelper.toRecord(rec['dimensions']);
    if (dimRec === null) {
      return result;
    }
    const keys: Array<string> = ['ei', 'sn', 'tf', 'jp'];
    for (const key of keys) {
      const value: Object | undefined = dimRec[key];
      if (value === undefined || value === null || !Array.isArray(value)) {
        continue;
      }
      const arr: Object[] = value as Object[];
      if (arr.length < 2) {
        continue;
      }
      const pole: Object = arr[0];
      if (typeof pole !== 'string') {
        continue;
      }
      const percent: Object = arr[1];
      result.push(new MbtiDimensionModel(key, pole, typeof percent === 'number' ? percent : 0));
    }
    return result;
  }

  static parseList(text: string): Array<MbtiTypeModel> {
    const result: Array<MbtiTypeModel> = [];
    const arr = JsonHelper.parseArray(text);
    if (arr !== null) {
      for (const rec of arr) {
        result.push(MbtiTypeModel.fromRecord(rec));
      }
      return result;
    }
    const obj = JsonHelper.parse(text);
    const items = JsonHelper.getRecordArray(obj, 'types');
    for (const rec of items) {
      result.push(MbtiTypeModel.fromRecord(rec));
    }
    return result;
  }
}

/** MBTI 测试题（GET /api/mbti/test/questions） */
export class MbtiQuestionModel {
  readonly id: number;
  readonly dimension: string;
  readonly aPole: string;
  readonly bPole: string;
  readonly questionZh: string;
  readonly optionAZh: string;
  readonly optionBZh: string;

  constructor(id: number, dimension: string, aPole: string, bPole: string, questionZh: string,
    optionAZh: string, optionBZh: string) {
    this.id = id;
    this.dimension = dimension;
    this.aPole = aPole;
    this.bPole = bPole;
    this.questionZh = questionZh;
    this.optionAZh = optionAZh;
    this.optionBZh = optionBZh;
  }

  static fromRecord(rec: Record<string, Object>): MbtiQuestionModel {
    return new MbtiQuestionModel(
      JsonHelper.getNumber(rec, 'id', 0),
      JsonHelper.getString(rec, 'dimension', ''),
      JsonHelper.getString(rec, 'a_pole', ''),
      JsonHelper.getString(rec, 'b_pole', ''),
      JsonHelper.getString(rec, 'question_zh', ''),
      JsonHelper.getString(rec, 'option_a_zh', ''),
      JsonHelper.getString(rec, 'option_b_zh', '')
    );
  }

  static parseList(text: string): Array<MbtiQuestionModel> {
    const result: Array<MbtiQuestionModel> = [];
    const arr = JsonHelper.parseArray(text);
    if (arr !== null) {
      for (const rec of arr) {
        result.push(MbtiQuestionModel.fromRecord(rec));
      }
      return result;
    }
    const obj = JsonHelper.parse(text);
    const items = JsonHelper.getRecordArray(obj, 'questions');
    for (const rec of items) {
      result.push(MbtiQuestionModel.fromRecord(rec));
    }
    return result;
  }
}

/** MBTI 测试结果（POST /api/mbti/test/submit 响应） */
export class MbtiTestResultModel {
  readonly code: string;
  readonly applied: boolean;
  readonly profile: MbtiTypeModel | null;

  constructor(code: string, applied: boolean, profile: MbtiTypeModel | null) {
    this.code = code;
    this.applied = applied;
    this.profile = profile;
  }

  static parse(text: string): MbtiTestResultModel {
    const rec = JsonHelper.parse(text);
    if (rec === null) {
      return new MbtiTestResultModel('', false, null);
    }
    const profileRec = JsonHelper.toRecord(rec['profile']);
    return new MbtiTestResultModel(
      JsonHelper.getString(rec, 'code', ''),
      JsonHelper.getBool(rec, 'applied', false),
      profileRec === null ? null : MbtiTypeModel.fromRecord(profileRec)
    );
  }
}

/** HITL 人工审批设置（GET /api/settings/hitl） */
export class HitlSettings {
  readonly enabled: boolean;
  readonly toolGuardRequireApproval: boolean;
  readonly showApprovalUi: boolean;

  constructor(enabled: boolean, toolGuardRequireApproval: boolean, showApprovalUi: boolean) {
    this.enabled = enabled;
    this.toolGuardRequireApproval = toolGuardRequireApproval;
    this.showApprovalUi = showApprovalUi;
  }

  static fromRecord(rec: Record<string, Object>): HitlSettings {
    return new HitlSettings(
      JsonHelper.getBool(rec, 'enabled', false),
      JsonHelper.getBool(rec, 'tool_guard_require_approval', false),
      JsonHelper.getBool(rec, 'show_approval_ui', false)
    );
  }
}

/** 移动端能力（GET /api/settings/capabilities → mobile） */
export class MobileCapability {
  readonly enabled: boolean;
  readonly backend: string;

  constructor(enabled: boolean, backend: string) {
    this.enabled = enabled;
    this.backend = backend;
  }

  static fromRecord(rec: Record<string, Object>): MobileCapability {
    return new MobileCapability(
      JsonHelper.getBool(rec, 'enabled', false),
      JsonHelper.getString(rec, 'backend', 'none')
    );
  }
}

/** 验证码 Provider 配置（GET /api/settings/captcha → providers{kind}，不含 secret 明文） */
export class CaptchaProviderModel {
  readonly siteKey: string;
  readonly hasSecret: boolean;
  readonly camSecretId: string;
  readonly camSecret: string;

  constructor(siteKey: string, hasSecret: boolean, camSecretId: string, camSecret: string) {
    this.siteKey = siteKey;
    this.hasSecret = hasSecret;
    this.camSecretId = camSecretId;
    this.camSecret = camSecret;
  }

  static fromRecord(rec: Record<string, Object>): CaptchaProviderModel {
    return new CaptchaProviderModel(
      JsonHelper.getString(rec, 'site_key', ''),
      JsonHelper.getBool(rec, 'has_secret', false),
      JsonHelper.getString(rec, 'cam_secret_id', ''),
      JsonHelper.getString(rec, 'cam_secret', '')
    );
  }
}

/** 验证码 Provider 条目（kind + 配置） */
export class CaptchaProviderEntry {
  readonly kind: string;
  readonly provider: CaptchaProviderModel;

  constructor(kind: string, provider: CaptchaProviderModel) {
    this.kind = kind;
    this.provider = provider;
  }
}

/** 验证码设置（GET /api/settings/captcha，需 captcha 权限） */
export class CaptchaSettingsModel {
  readonly active: string;
  readonly available: Array<string>;
  readonly providers: Array<CaptchaProviderEntry>;
  readonly source: string;
  readonly v3MinScore: number;

  constructor(active: string, available: Array<string>, providers: Array<CaptchaProviderEntry>,
    source: string, v3MinScore: number) {
    this.active = active;
    this.available = available;
    this.providers = providers;
    this.source = source;
    this.v3MinScore = v3MinScore;
  }

  static fromRecord(rec: Record<string, Object>): CaptchaSettingsModel {
    const available: Array<string> = JsonHelper.getStringArray(rec, 'available');
    const providersRec = JsonHelper.getRecord(rec, 'providers');
    const providers: Array<CaptchaProviderEntry> = [];
    for (const kind of available) {
      const providerRec = JsonHelper.getRecord(providersRec, kind);
      providers.push(new CaptchaProviderEntry(kind,
        CaptchaProviderModel.fromRecord(providerRec === null ? {} : providerRec)));
    }
    return new CaptchaSettingsModel(
      JsonHelper.getString(rec, 'active', ''),
      available,
      providers,
      JsonHelper.getString(rec, 'source', ''),
      JsonHelper.getOptionalNumber(rec, 'v3_min_score', 0)
    );
  }
}

/** 已解析可用模型（GET /api/providers/resolved 列表项，模型选择器数据源） */
export class ResolvedModelEntry {
  readonly providerId: number;
  readonly providerName: string;
  readonly providerKind: string;
  readonly model: string;
  readonly name: string;
  readonly reasoning: boolean;
  /** 思考强度档位（reasoning_config.efforts，enum 或 token_budget 档位值） */
  readonly reasoningEfforts: Array<string>;
  /** 默认档位 */
  readonly reasoningDefaultEffort: string;

  constructor(providerId: number, providerName: string, providerKind: string,
    model: string, name: string, reasoning: boolean,
    reasoningEfforts: Array<string>, reasoningDefaultEffort: string) {
    this.providerId = providerId;
    this.providerName = providerName;
    this.providerKind = providerKind;
    this.model = model;
    this.name = name;
    this.reasoning = reasoning;
    this.reasoningEfforts = reasoningEfforts;
    this.reasoningDefaultEffort = reasoningDefaultEffort;
  }

  static fromRecord(rec: Record<string, Object>): ResolvedModelEntry {
    const config: Record<string, Object> | null = JsonHelper.getRecord(rec, 'reasoning_config');
    const efforts: Array<string> = [];
    let defaultEffort: string = '';
    if (config !== null) {
      const rawEfforts = JsonHelper.getStringArray(config, 'efforts');
      for (const item of rawEfforts) {
        const v: string = item.trim();
        if (v !== '') {
          efforts.push(v);
        }
      }
      defaultEffort = JsonHelper.getString(config, 'default_effort', '');
    }
    return new ResolvedModelEntry(
      JsonHelper.getNumber(rec, 'provider_id', 0),
      JsonHelper.getString(rec, 'provider_name', ''),
      JsonHelper.getString(rec, 'provider_kind', ''),
      JsonHelper.getString(rec, 'model', ''),
      JsonHelper.getString(rec, 'name', ''),
      JsonHelper.getBool(rec, 'reasoning', false),
      efforts,
      defaultEffort
    );
  }

  /** 模型引用（threads model_ref / agent default_model）："provider/model" */
  ref(): string {
    return `${this.providerName}/${this.model}`;
  }

  /** 显示名：name 缺失时回退 model id */
  displayName(): string {
    return this.name !== '' ? this.name : this.model;
  }

  static parseList(text: string): Array<ResolvedModelEntry> {
    const result: Array<ResolvedModelEntry> = [];
    const arr = JsonHelper.parseArray(text);
    if (arr !== null) {
      for (const rec of arr) {
        result.push(ResolvedModelEntry.fromRecord(rec));
      }
      return result;
    }
    const obj = JsonHelper.parse(text);
    const items = JsonHelper.getRecordArray(obj, 'models');
    for (const rec of items) {
      result.push(ResolvedModelEntry.fromRecord(rec));
    }
    return result;
  }
}

/** Provider（GET /api/providers 或 /api/admin/providers 列表项） */
export class ProviderModel {
  readonly id: number;
  readonly name: string;
  readonly kind: string;
  readonly baseUrl: string;
  readonly enabled: boolean;
  readonly note: string;
  readonly streamUsage: boolean;
  readonly models: Array<string>;
  readonly hasApiKey: boolean;

  constructor(id: number, name: string, kind: string, baseUrl: string, enabled: boolean,
    note: string, streamUsage: boolean, models: Array<string>, hasApiKey: boolean) {
    this.id = id;
    this.name = name;
    this.kind = kind;
    this.baseUrl = baseUrl;
    this.enabled = enabled;
    this.note = note;
    this.streamUsage = streamUsage;
    this.models = models;
    this.hasApiKey = hasApiKey;
  }

  get modelCount(): number {
    return this.models.length;
  }

  static fromRecord(rec: Record<string, Object>): ProviderModel {
    const apiKey: Object | undefined = rec['api_key'];
    // models 容错：字符串数组或 {id: ...} 对象数组两种形态都接受
    const models: Array<string> = [];
    const recModels = JsonHelper.getRecordArray(rec, 'models');
    for (const item of recModels) {
      const id: string = JsonHelper.getString(item, 'id', '');
      if (id !== '') {
        models.push(id);
      }
    }
    if (models.length === 0) {
      const rawModels = JsonHelper.getStringArray(rec, 'models');
      for (const item of rawModels) {
        const id: string = item.trim();
        if (id !== '') {
          models.push(id);
        }
      }
    }
    return new ProviderModel(
      JsonHelper.getNumber(rec, 'id', 0),
      JsonHelper.getString(rec, 'name', ''),
      JsonHelper.getString(rec, 'kind', ''),
      JsonHelper.getString(rec, 'base_url', ''),
      JsonHelper.getBool(rec, 'enabled', false),
      JsonHelper.getString(rec, 'note', ''),
      JsonHelper.getBool(rec, 'stream_usage', false),
      models,
      typeof apiKey === 'string' && apiKey !== ''
    );
  }

  static parseList(text: string): Array<ProviderModel> {
    const result: Array<ProviderModel> = [];
    const arr = JsonHelper.parseArray(text);
    if (arr !== null) {
      for (const rec of arr) {
        result.push(ProviderModel.fromRecord(rec));
      }
      return result;
    }
    const obj = JsonHelper.parse(text);
    const items = JsonHelper.getRecordArray(obj, 'providers');
    for (const rec of items) {
      result.push(ProviderModel.fromRecord(rec));
    }
    return result;
  }
}

/** Provider 内置预设（GET /api/providers/presets，新建 provider 表单预填模板） */
export class ProviderPresetModel {
  readonly id: string;
  readonly name: string;
  readonly kind: string;
  readonly baseUrl: string;
  readonly description: string;
  readonly models: Array<string>;

  constructor(id: string, name: string, kind: string, baseUrl: string,
    description: string, models: Array<string>) {
    this.id = id;
    this.name = name;
    this.kind = kind;
    this.baseUrl = baseUrl;
    this.description = description;
    this.models = models;
  }

  static fromRecord(rec: Record<string, Object>): ProviderPresetModel {
    // models 容错：字符串数组或 {id: ...} 对象数组两种形态都接受
    const models: Array<string> = [];
    const recModels = JsonHelper.getRecordArray(rec, 'models');
    for (const item of recModels) {
      const modelId: string = JsonHelper.getString(item, 'id', '');
      if (modelId !== '') {
        models.push(modelId);
      }
    }
    if (models.length === 0) {
      const rawModels = JsonHelper.getStringArray(rec, 'models');
      for (const item of rawModels) {
        const modelId: string = item.trim();
        if (modelId !== '') {
          models.push(modelId);
        }
      }
    }
    return new ProviderPresetModel(
      JsonHelper.getString(rec, 'id', ''),
      JsonHelper.getString(rec, 'name', ''),
      JsonHelper.getString(rec, 'kind', ''),
      JsonHelper.getString(rec, 'base_url', ''),
      JsonHelper.getString(rec, 'description', ''),
      models
    );
  }

  static parseList(text: string): Array<ProviderPresetModel> {
    const result: Array<ProviderPresetModel> = [];
    const arr = JsonHelper.parseArray(text);
    if (arr !== null) {
      for (const rec of arr) {
        result.push(ProviderPresetModel.fromRecord(rec));
      }
      return result;
    }
    const obj = JsonHelper.parse(text);
    const items = JsonHelper.getRecordArray(obj, 'presets');
    for (const rec of items) {
      result.push(ProviderPresetModel.fromRecord(rec));
    }
    return result;
  }
}

/** 团队成员（team_payload.members 元素） */
export class TeamMemberModel {
  readonly agentId: string;
  readonly name: string;
  readonly color: string;
  readonly iconName: string;
  readonly iconUrl: string;
  readonly state: string;
  readonly isShared: boolean;

  constructor(agentId: string, name: string, color: string, iconName: string,
    iconUrl: string, state: string, isShared: boolean) {
    this.agentId = agentId;
    this.name = name === '' ? '成员' : name;
    this.color = color;
    this.iconName = iconName;
    this.iconUrl = iconUrl;
    this.state = state;
    this.isShared = isShared;
  }

  static fromRecord(rec: Record<string, Object>): TeamMemberModel {
    return new TeamMemberModel(
      JsonHelper.getString(rec, 'agent_id', ''),
      JsonHelper.getString(rec, 'name', ''),
      JsonHelper.getString(rec, 'color', ''),
      JsonHelper.getString(rec, 'icon_name', ''),
      JsonHelper.getString(rec, 'icon_url', ''),
      JsonHelper.getString(rec, 'state', ''),
      JsonHelper.getBool(rec, 'is_shared', false)
    );
  }
}

/** 专家团队（GET /api/teams team_payload） */
export class TeamModel {
  readonly teamId: string;
  readonly name: string;
  readonly description: string;
  readonly defaultModel: string;
  readonly color: string;
  readonly welcomeMessage: string;
  readonly state: string;
  readonly memberIds: Array<string>;
  readonly members: Array<TeamMemberModel>;

  constructor(teamId: string, name: string, description: string, defaultModel: string,
    color: string, welcomeMessage: string, state: string, memberIds: Array<string>,
    members: Array<TeamMemberModel>) {
    this.teamId = teamId;
    this.name = name === '' ? '团队' : name;
    this.description = description;
    this.defaultModel = defaultModel;
    this.color = color;
    this.welcomeMessage = welcomeMessage;
    this.state = state;
    this.memberIds = memberIds;
    this.members = members;
  }

  static fromRecord(rec: Record<string, Object>): TeamModel {
    const members: Array<TeamMemberModel> = [];
    const memberRecs: Array<Record<string, Object>> = JsonHelper.getRecordArray(rec, 'members');
    for (const memberRec of memberRecs) {
      members.push(TeamMemberModel.fromRecord(memberRec));
    }
    return new TeamModel(
      JsonHelper.getString(rec, 'team_id', ''),
      JsonHelper.getString(rec, 'name', ''),
      JsonHelper.getString(rec, 'description', ''),
      JsonHelper.getString(rec, 'default_model', ''),
      JsonHelper.getString(rec, 'color', ''),
      JsonHelper.getString(rec, 'welcome_message', ''),
      JsonHelper.getString(rec, 'state', ''),
      JsonHelper.getStringArray(rec, 'member_ids'),
      members
    );
  }

  /** 成员名串（最多 4 个） */
  memberNames(): string {
    const names: Array<string> = [];
    const limit: number = this.members.length > 4 ? 4 : this.members.length;
    for (let i = 0; i < limit; i++) {
      names.push(this.members[i].name);
    }
    let joined: string = names.join('、');
    if (this.members.length > 4) {
      joined += ` 等 ${this.members.length} 位`;
    }
    return joined;
  }

  static parseOne(text: string): TeamModel {
    const rec = JsonHelper.parse(text);
    if (rec === null) {
      throw new OctopApiError('团队信息响应格式错误', 0, 'BAD_RESPONSE');
    }
    return TeamModel.fromRecord(rec);
  }

  static parseList(text: string): Array<TeamModel> {
    const result: Array<TeamModel> = [];
    const arr = JsonHelper.parseArray(text);
    if (arr !== null) {
      for (const rec of arr) {
        result.push(TeamModel.fromRecord(rec));
      }
      return result;
    }
    const obj = JsonHelper.parse(text);
    const items = JsonHelper.getRecordArray(obj, 'teams');
    for (const rec of items) {
      result.push(TeamModel.fromRecord(rec));
    }
    return result;
  }
}
