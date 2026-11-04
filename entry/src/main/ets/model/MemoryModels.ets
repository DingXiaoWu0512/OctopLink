import { JsonHelper } from '../utils/JsonHelper';

/**
 * 记忆域数据模型（源：octop/api/routers/memory.py、memory_portable.py、preferences.py）：
 * - MemoryAtomModel：长期记忆条目（atoms/list 响应 items 元素）
 * - MemoryStatsCountsModel：记忆规模统计（stats/counts）
 * - MemoryKindFilterItem：类型筛选项
 * - MemoryAdoptSummaryModel：.hmpkg 导入结果摘要（portable/adopt）
 * - UserPreferencesModel：用户偏好（/api/preferences）
 */

/** 记忆条目（memory.py atoms/list items 元素；废弃以 deprecated_at 表示，null 为有效） */
export class MemoryAtomModel {
  readonly id: string;
  readonly entityId: string;
  readonly assertion: string;
  readonly verbatimQuote: string;
  readonly kind: string; // Fact / Decision / Task / Preference
  readonly importance: string; // low / medium / high
  readonly confidence: string; // low / medium / high
  readonly occurredAtMs: number;
  readonly createdAtMs: number;
  readonly deprecatedAtMs: number;
  readonly supersededBy: string;

  constructor(id: string, entityId: string, assertion: string, verbatimQuote: string,
    kind: string, importance: string, confidence: string, occurredAtMs: number,
    createdAtMs: number, deprecatedAtMs: number, supersededBy: string) {
    this.id = id;
    this.entityId = entityId;
    this.assertion = assertion;
    this.verbatimQuote = verbatimQuote;
    this.kind = kind;
    this.importance = importance;
    this.confidence = confidence;
    this.occurredAtMs = occurredAtMs;
    this.createdAtMs = createdAtMs;
    this.deprecatedAtMs = deprecatedAtMs;
    this.supersededBy = supersededBy;
  }

  isDeprecated(): boolean {
    return this.deprecatedAtMs > 0;
  }

  kindLabel(): string {
    if (this.kind === 'Fact') {
      return '事实';
    }
    if (this.kind === 'Decision') {
      return '决策';
    }
    if (this.kind === 'Task') {
      return '任务';
    }
    if (this.kind === 'Preference') {
      return '偏好';
    }
    return '未分类';
  }

  importanceLabel(): string {
    if (this.importance === 'high') {
      return '高';
    }
    if (this.importance === 'low') {
      return '低';
    }
    return '中';
  }

  static fromRecord(rec: Record<string, Object>): MemoryAtomModel {
    return new MemoryAtomModel(
      JsonHelper.getString(rec, 'id', ''),
      JsonHelper.getString(rec, 'entity_id', ''),
      JsonHelper.getString(rec, 'assertion', ''),
      JsonHelper.getString(rec, 'verbatim_quote', ''),
      JsonHelper.getString(rec, 'kind', ''),
      JsonHelper.getString(rec, 'importance', 'medium'),
      JsonHelper.getString(rec, 'confidence', 'medium'),
      JsonHelper.toMs(rec['occurred_at']),
      JsonHelper.toMs(rec['created_at']),
      JsonHelper.toMs(rec['deprecated_at']),
      JsonHelper.getString(rec, 'superseded_by', '')
    );
  }
}

/** 记忆规模统计（memory.py stats/counts） */
export class MemoryStatsCountsModel {
  readonly rawEvents: number;
  readonly atoms: number;
  readonly entities: number;
  readonly episodes: number;
  readonly candidatesPending: number;

  constructor(rawEvents: number, atoms: number, entities: number, episodes: number,
    candidatesPending: number) {
    this.rawEvents = rawEvents;
    this.atoms = atoms;
    this.entities = entities;
    this.episodes = episodes;
    this.candidatesPending = candidatesPending;
  }

  static fromRecord(rec: Record<string, Object>): MemoryStatsCountsModel {
    return new MemoryStatsCountsModel(
      JsonHelper.getNumber(rec, 'raw_events', 0),
      JsonHelper.getNumber(rec, 'atoms', 0),
      JsonHelper.getNumber(rec, 'entities', 0),
      JsonHelper.getNumber(rec, 'episodes', 0),
      JsonHelper.getNumber(rec, 'candidates_pending', 0)
    );
  }
}

/** 类型筛选项（kind 为空串表示全部） */
export class MemoryKindFilterItem {
  readonly kind: string;
  readonly label: string;

  constructor(kind: string, label: string) {
    this.kind = kind;
    this.label = label;
  }

  static all(): Array<MemoryKindFilterItem> {
    return [
      new MemoryKindFilterItem('', '全部'),
      new MemoryKindFilterItem('Fact', '事实'),
      new MemoryKindFilterItem('Decision', '决策'),
      new MemoryKindFilterItem('Task', '任务'),
      new MemoryKindFilterItem('Preference', '偏好')
    ];
  }
}

/** .hmpkg 导入结果摘要（memory_portable.py adopt 响应） */
export class MemoryAdoptSummaryModel {
  readonly targetNamespace: string;
  readonly applied: number;
  readonly skipped: number;
  readonly errors: number;
  readonly dryRun: boolean;

  constructor(targetNamespace: string, applied: number, skipped: number,
    errors: number, dryRun: boolean) {
    this.targetNamespace = targetNamespace;
    this.applied = applied;
    this.skipped = skipped;
    this.errors = errors;
    this.dryRun = dryRun;
  }

  static fromRecord(rec: Record<string, Object>): MemoryAdoptSummaryModel {
    return new MemoryAdoptSummaryModel(
      JsonHelper.getString(rec, 'target_namespace', ''),
      JsonHelper.getNumber(rec, 'applied', 0),
      JsonHelper.getNumber(rec, 'skipped', 0),
      JsonHelper.getNumber(rec, 'errors', 0),
      JsonHelper.getBool(rec, 'dry_run', false)
    );
  }
}

/** 用户偏好（preferences.py GET/PATCH /api/preferences；timezone/preferred_model 可空） */
export class UserPreferencesModel {
  readonly locale: string; // zh / en
  readonly timezone: string;
  readonly preferredModel: string;

  constructor(locale: string, timezone: string, preferredModel: string) {
    this.locale = locale;
    this.timezone = timezone;
    this.preferredModel = preferredModel;
  }

  static parse(text: string): UserPreferencesModel {
    const rec = JsonHelper.parse(text);
    if (rec === null) {
      return new UserPreferencesModel('zh', '', '');
    }
    return UserPreferencesModel.fromRecord(rec);
  }

  static fromRecord(rec: Record<string, Object>): UserPreferencesModel {
    return new UserPreferencesModel(
      JsonHelper.getString(rec, 'locale', 'zh'),
      JsonHelper.getString(rec, 'timezone', ''),
      JsonHelper.getString(rec, 'preferred_model', '')
    );
  }
}

// ---------------------------------------------------------------------------
// 记忆终端 / 审核域（源：octop_memory dashboard_data.py + agent_files.py）
// ---------------------------------------------------------------------------

/** L1 候选记忆（candidates/list items 元素，octop_memory.types.Candidate） */
export class MemoryCandidateModel {
  readonly id: string;
  readonly kind: string; // Fact / Decision / Task / Preference / ConflictCandidate
  readonly status: string; // pending / needs_review / conflict / promoted / rejected
  readonly title: string;
  readonly assertion: string;
  readonly verbatimQuote: string;
  readonly subjectName: string;
  readonly importance: string;
  readonly confidence: string;
  readonly recommendedAction: string;
  readonly promotionReason: string;
  readonly targetEntityId: string;
  readonly createdAtMs: number;
  readonly decidedAtMs: number;

  constructor(id: string, kind: string, status: string, title: string, assertion: string,
    verbatimQuote: string, subjectName: string, importance: string, confidence: string,
    recommendedAction: string, promotionReason: string, targetEntityId: string,
    createdAtMs: number, decidedAtMs: number) {
    this.id = id;
    this.kind = kind;
    this.status = status;
    this.title = title;
    this.assertion = assertion;
    this.verbatimQuote = verbatimQuote;
    this.subjectName = subjectName;
    this.importance = importance;
    this.confidence = confidence;
    this.recommendedAction = recommendedAction;
    this.promotionReason = promotionReason;
    this.targetEntityId = targetEntityId;
    this.createdAtMs = createdAtMs;
    this.decidedAtMs = decidedAtMs;
  }

  statusLabel(): string {
    if (this.status === 'pending') {
      return '待定';
    }
    if (this.status === 'needs_review') {
      return '需审核';
    }
    if (this.status === 'conflict') {
      return '冲突';
    }
    if (this.status === 'promoted') {
      return '已采纳';
    }
    if (this.status === 'rejected') {
      return '已拒绝';
    }
    return this.status;
  }

  static fromRecord(rec: Record<string, Object>): MemoryCandidateModel {
    return new MemoryCandidateModel(
      JsonHelper.getString(rec, 'id', ''),
      JsonHelper.getString(rec, 'candidate_type', ''),
      JsonHelper.getString(rec, 'status', ''),
      JsonHelper.getString(rec, 'title', ''),
      JsonHelper.getString(rec, 'assertion', ''),
      JsonHelper.getString(rec, 'verbatim_quote', ''),
      JsonHelper.getString(rec, 'subject_name', ''),
      JsonHelper.getString(rec, 'importance', 'medium'),
      JsonHelper.getString(rec, 'confidence', 'medium'),
      JsonHelper.getString(rec, 'recommended_action', ''),
      JsonHelper.getString(rec, 'promotion_reason', ''),
      JsonHelper.getString(rec, 'target_entity_id', ''),
      JsonHelper.toMs(rec['created_at']),
      JsonHelper.toMs(rec['decided_at'])
    );
  }

  static parseList(text: string): Array<MemoryCandidateModel> {
    const result: Array<MemoryCandidateModel> = [];
    const rec = JsonHelper.parse(text);
    if (rec === null) {
      return result;
    }
    const items = JsonHelper.getRecordArray(rec, 'items');
    for (const item of items) {
      result.push(MemoryCandidateModel.fromRecord(item));
    }
    return result;
  }
}

/** 日积月累文件项（agent_files.py GET /memory/daily 元素） */
export class MemoryDailyFileModel {
  readonly filename: string;
  readonly date: string; // YYYY-MM-DD
  readonly size: number;
  readonly modifiedAtMs: number;

  constructor(filename: string, date: string, size: number, modifiedAtMs: number) {
    this.filename = filename;
    this.date = date;
    this.size = size;
    this.modifiedAtMs = modifiedAtMs;
  }

  static fromRecord(rec: Record<string, Object>): MemoryDailyFileModel {
    return new MemoryDailyFileModel(
      JsonHelper.getString(rec, 'filename', ''),
      JsonHelper.getString(rec, 'date', ''),
      JsonHelper.getNumber(rec, 'size', 0),
      JsonHelper.toMs(rec['modified_at'])
    );
  }
}

/** MEMORY.md / USER.md 文本档（strong/user memory 响应 {content, exists}） */
export class MemoryTextFileModel {
  readonly content: string;
  readonly exists: boolean;

  constructor(content: string, exists: boolean) {
    this.content = content;
    this.exists = exists;
  }

  static parse(text: string): MemoryTextFileModel {
    const rec = JsonHelper.parse(text);
    if (rec === null) {
      return new MemoryTextFileModel('', false);
    }
    return new MemoryTextFileModel(
      JsonHelper.getString(rec, 'content', ''),
      JsonHelper.getBool(rec, 'exists', false)
    );
  }
}

/** 手动文档核对结果（POST /memory/manual-review） */
export class ManualReviewModel {
  readonly status: string;
  readonly conflicts: number;
  readonly duplicates: number;
  readonly checked: number;
  readonly remaining: number;
  readonly candidateIds: string[];

  constructor(status: string, conflicts: number, duplicates: number, checked: number,
    remaining: number, candidateIds: string[]) {
    this.status = status;
    this.conflicts = conflicts;
    this.duplicates = duplicates;
    this.checked = checked;
    this.remaining = remaining;
    this.candidateIds = candidateIds;
  }

  static parse(text: string): ManualReviewModel {
    const rec = JsonHelper.parse(text);
    if (rec === null) {
      return new ManualReviewModel('unavailable', 0, 0, 0, 0, []);
    }
    return new ManualReviewModel(
      JsonHelper.getString(rec, 'status', 'unavailable'),
      JsonHelper.getNumber(rec, 'conflicts', 0),
      JsonHelper.getNumber(rec, 'duplicates', 0),
      JsonHelper.getNumber(rec, 'checked', 0),
      JsonHelper.getNumber(rec, 'remaining', 0),
      JsonHelper.getStringArray(rec, 'candidate_ids')
    );
  }
}

/** L3 实体（entities/list items 元素，octop_memory.types.Entity） */
export class MemoryEntityModel {
  readonly id: string;
  readonly entityType: string;
  readonly canonicalName: string;
  readonly aliases: string[];
  readonly atomCount: number;
  readonly createdAtMs: number;

  constructor(id: string, entityType: string, canonicalName: string, aliases: string[],
    atomCount: number, createdAtMs: number) {
    this.id = id;
    this.entityType = entityType;
    this.canonicalName = canonicalName;
    this.aliases = aliases;
    this.atomCount = atomCount;
    this.createdAtMs = createdAtMs;
  }

  static fromRecord(rec: Record<string, Object>): MemoryEntityModel {
    return new MemoryEntityModel(
      JsonHelper.getString(rec, 'id', ''),
      JsonHelper.getString(rec, 'entity_type', ''),
      JsonHelper.getString(rec, 'canonical_name', ''),
      JsonHelper.getStringArray(rec, 'aliases'),
      JsonHelper.getNumber(rec, 'atom_count', 0),
      JsonHelper.toMs(rec['created_at'])
    );
  }

  static parseList(text: string): Array<MemoryEntityModel> {
    const result: Array<MemoryEntityModel> = [];
    const rec = JsonHelper.parse(text);
    if (rec === null) {
      return result;
    }
    const items = JsonHelper.getRecordArray(rec, 'items');
    for (const item of items) {
      result.push(MemoryEntityModel.fromRecord(item));
    }
    return result;
  }
}

/** L2.5 情景日记（episodes/list items 元素，octop_memory.types.Episode） */
export class MemoryEpisodeModel {
  readonly id: string;
  readonly summary: string;
  readonly verbatimQuote: string;
  readonly emotion: string;
  readonly intensity: number; // 1-5
  readonly people: string[];
  readonly topics: string[];
  readonly occurredAtMs: number;
  readonly createdAtMs: number;

  constructor(id: string, summary: string, verbatimQuote: string, emotion: string,
    intensity: number, people: string[], topics: string[], occurredAtMs: number,
    createdAtMs: number) {
    this.id = id;
    this.summary = summary;
    this.verbatimQuote = verbatimQuote;
    this.emotion = emotion;
    this.intensity = intensity;
    this.people = people;
    this.topics = topics;
    this.occurredAtMs = occurredAtMs;
    this.createdAtMs = createdAtMs;
  }

  static fromRecord(rec: Record<string, Object>): MemoryEpisodeModel {
    return new MemoryEpisodeModel(
      JsonHelper.getString(rec, 'id', ''),
      JsonHelper.getString(rec, 'summary', ''),
      JsonHelper.getString(rec, 'verbatim_quote', ''),
      JsonHelper.getString(rec, 'emotion', 'neutral'),
      JsonHelper.getNumber(rec, 'intensity', 1),
      JsonHelper.getStringArray(rec, 'people'),
      JsonHelper.getStringArray(rec, 'topics'),
      JsonHelper.toMs(rec['occurred_at']),
      JsonHelper.toMs(rec['created_at'])
    );
  }

  static parseList(text: string): Array<MemoryEpisodeModel> {
    const result: Array<MemoryEpisodeModel> = [];
    const rec = JsonHelper.parse(text);
    if (rec === null) {
      return result;
    }
    const items = JsonHelper.getRecordArray(rec, 'items');
    for (const item of items) {
      result.push(MemoryEpisodeModel.fromRecord(item));
    }
    return result;
  }
}

/** L4 记忆变更审计（journal 元素，octop_memory.types.JournalEntry） */
export class MemoryJournalModel {
  readonly id: string;
  readonly timestampMs: number;
  readonly action: string;
  readonly actor: string; // auto / user / rule
  readonly targetAtomId: string;
  readonly targetCandidateId: string;
  readonly targetEntityId: string;
  readonly note: string;

  constructor(id: string, timestampMs: number, action: string, actor: string,
    targetAtomId: string, targetCandidateId: string, targetEntityId: string, note: string) {
    this.id = id;
    this.timestampMs = timestampMs;
    this.action = action;
    this.actor = actor;
    this.targetAtomId = targetAtomId;
    this.targetCandidateId = targetCandidateId;
    this.targetEntityId = targetEntityId;
    this.note = note;
  }

  static fromRecord(rec: Record<string, Object>): MemoryJournalModel {
    return new MemoryJournalModel(
      JsonHelper.getString(rec, 'id', ''),
      JsonHelper.toMs(rec['timestamp']),
      JsonHelper.getString(rec, 'action', ''),
      JsonHelper.getString(rec, 'actor', ''),
      JsonHelper.getString(rec, 'target_atom_id', ''),
      JsonHelper.getString(rec, 'target_candidate_id', ''),
      JsonHelper.getString(rec, 'target_entity_id', ''),
      JsonHelper.getString(rec, 'note', '')
    );
  }

  static parseList(text: string): Array<MemoryJournalModel> {
    const result: Array<MemoryJournalModel> = [];
    const rec = JsonHelper.parse(text);
    if (rec === null) {
      return result;
    }
    const items = JsonHelper.getRecordArray(rec, 'items');
    for (const item of items) {
      result.push(MemoryJournalModel.fromRecord(item));
    }
    return result;
  }
}

/** L0 原始事件（raw_events/list items 元素，octop_memory.types.RawEvent） */
export class MemoryRawEventModel {
  readonly id: string;
  readonly host: string;
  readonly eventType: string;
  readonly content: string;
  readonly user: string;
  readonly timestampMs: number;

  constructor(id: string, host: string, eventType: string, content: string,
    user: string, timestampMs: number) {
    this.id = id;
    this.host = host;
    this.eventType = eventType;
    this.content = content;
    this.user = user;
    this.timestampMs = timestampMs;
  }

  static fromRecord(rec: Record<string, Object>): MemoryRawEventModel {
    return new MemoryRawEventModel(
      JsonHelper.getString(rec, 'id', ''),
      JsonHelper.getString(rec, 'host', ''),
      JsonHelper.getString(rec, 'event_type', ''),
      JsonHelper.getString(rec, 'content', ''),
      JsonHelper.getString(rec, 'user', ''),
      JsonHelper.toMs(rec['timestamp'])
    );
  }

  static parseList(text: string): Array<MemoryRawEventModel> {
    const result: Array<MemoryRawEventModel> = [];
    const rec = JsonHelper.parse(text);
    if (rec === null) {
      return result;
    }
    const items = JsonHelper.getRecordArray(rec, 'items');
    for (const item of items) {
      result.push(MemoryRawEventModel.fromRecord(item));
    }
    return result;
  }
}

/** 记忆提取配置（memory.py GET/PUT /memory/extract-config） */
export class MemoryExtractConfigModel {
  readonly memoryEnabled: boolean;
  readonly extractOnSessionEnd: boolean;
  readonly extractTriggerMode: string; // idle / interval / session_end ...
  readonly extractIdleSeconds: number;
  readonly extractIntervalSeconds: number;
  readonly auxModel: string;

  constructor(memoryEnabled: boolean, extractOnSessionEnd: boolean, extractTriggerMode: string,
    extractIdleSeconds: number, extractIntervalSeconds: number, auxModel: string) {
    this.memoryEnabled = memoryEnabled;
    this.extractOnSessionEnd = extractOnSessionEnd;
    this.extractTriggerMode = extractTriggerMode;
    this.extractIdleSeconds = extractIdleSeconds;
    this.extractIntervalSeconds = extractIntervalSeconds;
    this.auxModel = auxModel;
  }

  static parse(text: string): MemoryExtractConfigModel {
    const rec = JsonHelper.parse(text);
    if (rec === null) {
      return new MemoryExtractConfigModel(true, true, 'idle', 90, 0, '');
    }
    return new MemoryExtractConfigModel(
      JsonHelper.getBool(rec, 'memory_enabled', true),
      JsonHelper.getBool(rec, 'extract_on_session_end', true),
      JsonHelper.getString(rec, 'extract_trigger_mode', 'idle'),
      JsonHelper.getNumber(rec, 'extract_idle_seconds', 90),
      JsonHelper.getNumber(rec, 'extract_interval_seconds', 0),
      JsonHelper.getString(rec, 'aux_model', '')
    );
  }
}

/** 记忆增长序列（stats/growth → {series:[{date,atoms,episodes,entities,turns}]}） */
export class MemoryGrowthPointModel {
  readonly date: string;
  readonly atoms: number;
  readonly episodes: number;
  readonly entities: number;
  readonly turns: number;

  constructor(date: string, atoms: number, episodes: number, entities: number, turns: number) {
    this.date = date;
    this.atoms = atoms;
    this.episodes = episodes;
    this.entities = entities;
    this.turns = turns;
  }

  static parseList(text: string): Array<MemoryGrowthPointModel> {
    const result: Array<MemoryGrowthPointModel> = [];
    const rec = JsonHelper.parse(text);
    if (rec === null) {
      return result;
    }
    const items = JsonHelper.getRecordArray(rec, 'series');
    for (const item of items) {
      result.push(new MemoryGrowthPointModel(
        JsonHelper.getString(item, 'date', ''),
        JsonHelper.getNumber(item, 'atoms', 0),
        JsonHelper.getNumber(item, 'episodes', 0),
        JsonHelper.getNumber(item, 'entities', 0),
        JsonHelper.getNumber(item, 'turns', 0)
      ));
    }
    return result;
  }
}

/** 记忆存储体检（memory_storage.py GET /memory/storage/check） */
export class MemoryStorageCheckModel {
  readonly backend: string;
  readonly maintenanceSupported: boolean;
  readonly blockedReason: string;
  readonly fileSize: number;
  readonly reclaimableBytes: number;
  readonly checkpointsAvailable: number;

  constructor(backend: string, maintenanceSupported: boolean, blockedReason: string,
    fileSize: number, reclaimableBytes: number, checkpointsAvailable: number) {
    this.backend = backend;
    this.maintenanceSupported = maintenanceSupported;
    this.blockedReason = blockedReason;
    this.fileSize = fileSize;
    this.reclaimableBytes = reclaimableBytes;
    this.checkpointsAvailable = checkpointsAvailable;
  }

  static parse(text: string): MemoryStorageCheckModel {
    const rec = JsonHelper.parse(text);
    if (rec === null) {
      return new MemoryStorageCheckModel('', false, '', 0, 0, 0);
    }
    return new MemoryStorageCheckModel(
      JsonHelper.getString(rec, 'backend', ''),
      JsonHelper.getBool(rec, 'maintenance_supported', false),
      JsonHelper.getString(rec, 'blocked_reason', ''),
      JsonHelper.getNumber(rec, 'file_size', 0),
      JsonHelper.getNumber(rec, 'reclaimable_bytes', 0),
      JsonHelper.getNumber(rec, 'checkpoints_available', 0)
    );
  }
}

/** 记忆存储备份项（GET /memory/storage/backups → {backups:[SqliteBackup]}） */
export class MemoryBackupModel {
  readonly backupId: string;
  readonly createdAtMs: number;
  readonly sizeBytes: number;
  readonly kind: string;

  constructor(backupId: string, createdAtMs: number, sizeBytes: number, kind: string) {
    this.backupId = backupId;
    this.createdAtMs = createdAtMs;
    this.sizeBytes = sizeBytes;
    this.kind = kind;
  }

  static parseList(text: string): Array<MemoryBackupModel> {
    const result: Array<MemoryBackupModel> = [];
    const rec = JsonHelper.parse(text);
    if (rec === null) {
      return result;
    }
    let items = JsonHelper.getRecordArray(rec, 'backups');
    if (items.length === 0) {
      items = JsonHelper.getRecordArray(rec, 'items');
    }
    for (const item of items) {
      result.push(new MemoryBackupModel(
        JsonHelper.getString(item, 'backup_id', ''),
        JsonHelper.toMs(item['created_at']),
        JsonHelper.getNumber(item, 'size_bytes', JsonHelper.getNumber(item, 'size', 0)),
        JsonHelper.getString(item, 'kind', '')
      ));
    }
    return result;
  }
}
