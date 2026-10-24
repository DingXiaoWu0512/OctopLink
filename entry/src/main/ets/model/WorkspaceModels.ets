import { JsonHelper } from '../utils/JsonHelper';

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

  constructor(id: string, name: string, trigger: string, prompt: string, enabled: boolean,
    freshThread: boolean, lastRunAtMs: number, lastStatus: string, lastError: string, model: string) {
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
      JsonHelper.getString(rec, 'model', '')
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

/** 渠道（GET /api/agents/{id}/channels 列表项） */
export class ChannelModel {
  readonly id: string;
  readonly kind: string;
  readonly name: string;
  readonly enabled: boolean;

  constructor(id: string, kind: string, name: string, enabled: boolean) {
    this.id = id;
    this.kind = kind;
    this.name = name;
    this.enabled = enabled;
  }

  static fromRecord(rec: Record<string, Object>): ChannelModel {
    return new ChannelModel(
      JsonHelper.getString(rec, 'id', ''),
      JsonHelper.getString(rec, 'kind', ''),
      JsonHelper.getString(rec, 'name', ''),
      JsonHelper.getBool(rec, 'enabled', true)
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

/** MBTI 类型（GET /api/mbti/types 列表项） */
export class MbtiTypeModel {
  readonly code: string;
  readonly nameZh: string;
  readonly nameEn: string;
  readonly summaryZh: string;
  readonly color: string;

  constructor(code: string, nameZh: string, nameEn: string, summaryZh: string, color: string) {
    this.code = code;
    this.nameZh = nameZh;
    this.nameEn = nameEn;
    this.summaryZh = summaryZh;
    this.color = color;
  }

  static fromRecord(rec: Record<string, Object>): MbtiTypeModel {
    return new MbtiTypeModel(
      JsonHelper.getString(rec, 'code', ''),
      JsonHelper.getString(rec, 'name_zh', ''),
      JsonHelper.getString(rec, 'name_en', ''),
      JsonHelper.getString(rec, 'summary_zh', ''),
      JsonHelper.getString(rec, 'color', '')
    );
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
