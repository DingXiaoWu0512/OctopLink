import { HttpClient } from '../net/HttpClient';
import { JsonHelper } from '../utils/JsonHelper';
import {
  ManualReviewModel,
  MemoryAdoptSummaryModel,
  MemoryAtomModel,
  MemoryBackupModel,
  MemoryCandidateModel,
  MemoryDailyFileModel,
  MemoryEntityModel,
  MemoryEpisodeModel,
  MemoryExtractConfigModel,
  MemoryGrowthPointModel,
  MemoryJournalModel,
  MemoryRawEventModel,
  MemoryStatsCountsModel,
  MemoryStorageCheckModel,
  MemoryTextFileModel
} from '../model/MemoryModels';

/**
 * 专家记忆服务（/api/agents/{agent_id}/memory*，源 memory.py、memory_portable.py、
 * agent_files.py、memory_storage.py；引擎 octop_memory dashboard_data.py）：
 * - 记忆条目列表 / 新建 / 修正（replace）/ 删除（deprecate）
 * - 规模统计（stats/counts）+ 增长曲线（stats/growth）+ 类型分布（stats/atom_kinds）
 * - 候选审核：candidates/list + promote + reject
 * - 手动文档：MEMORY.md（strong）/ USER.md（user）读写 + manual-review 核对
 * - 日积月累：daily 列表 / 单篇 / 删除
 * - 记忆终端：about_me / current_focus / things_you_told_me / recent_stories / entities
 * - 审计与原始数据：journal、entities、episodes、raw_events
 * - 提取配置 extract-config；存储体检/维护/恢复/备份 storage/*
 * - 跨端迁移：导出 pack（二进制 .hmpkg）/ 导入 adopt（multipart 上传）/ doctor
 */
export class MemoryService {
  /** 记忆列表（query 关键词 + kind 类型过滤，kind 空串为全部；不含已废弃条目） */
  static async listAtoms(agentId: string, query: string, kind: string): Promise<Array<MemoryAtomModel>> {
    const body: Record<string, Object> = {
      'query': query,
      'include_deprecated': false,
      'order_by': 'created_at',
      'order': 'desc',
      'limit': 200
    };
    if (kind !== '') {
      body['candidate_type'] = kind;
    }
    const text: string = await HttpClient.getInstance().post(
      `/api/agents/${agentId}/memory/atoms/list`, JSON.stringify(body));
    const result: Array<MemoryAtomModel> = [];
    const rec = JsonHelper.parse(text);
    if (rec === null) {
      return result;
    }
    const items: Array<Record<string, Object>> = JsonHelper.getRecordArray(rec, 'items');
    for (const item of items) {
      result.push(MemoryAtomModel.fromRecord(item));
    }
    return result;
  }

  /** 新建长期记忆（actor=user；entityName 可选，为空时由服务端归入默认实体） */
  static async createAtom(agentId: string, assertion: string, kind: string,
    importance: string, entityName: string): Promise<void> {
    const body: Record<string, Object> = {
      'assertion': assertion,
      'kind': kind,
      'importance': importance
    };
    if (entityName !== '') {
      body['entity_name'] = entityName;
    }
    await HttpClient.getInstance().post(
      `/api/agents/${agentId}/memory/atoms`, JSON.stringify(body));
  }

  /** 修正记忆（创建后继 Atom 并废弃旧条目，仅支持修改内容） */
  static async replaceAtom(agentId: string, atomId: string, assertion: string): Promise<void> {
    const body: Record<string, Object> = {
      'assertion': assertion,
      'reason': '用户手动修正'
    };
    await HttpClient.getInstance().post(
      `/api/agents/${agentId}/memory/atoms/${encodeURIComponent(atomId)}:replace`,
      JSON.stringify(body));
  }

  /** 删除记忆（deprecate：标记废弃，不再参与回忆） */
  static async deprecateAtom(agentId: string, atomId: string): Promise<void> {
    const body: Record<string, Object> = { 'reason': '用户手动删除' };
    await HttpClient.getInstance().post(
      `/api/agents/${agentId}/memory/atoms/${encodeURIComponent(atomId)}:deprecate`,
      JSON.stringify(body));
  }

  /** 记忆规模统计 */
  static async statsCounts(agentId: string): Promise<MemoryStatsCountsModel> {
    const text: string = await HttpClient.getInstance().get(
      `/api/agents/${agentId}/memory/stats/counts`);
    const rec = JsonHelper.parse(text);
    return MemoryStatsCountsModel.fromRecord(rec === null ? {} : rec);
  }

  /** 导出记忆为 .hmpkg（二进制流，POST 返回字节） */
  static async pack(agentId: string): Promise<ArrayBuffer> {
    return await HttpClient.getInstance().postForBytes(
      `/api/agents/${agentId}/memory/portable/pack`, '{}');
  }

  /** 导入 .hmpkg（multipart 上传 pkg_file，默认 agent 宿主 / skip 冲突策略） */
  static async adopt(agentId: string, fileName: string, data: ArrayBuffer): Promise<MemoryAdoptSummaryModel> {
    const text: string = await HttpClient.getInstance().postMultipartFile(
      `/api/agents/${agentId}/memory/portable/adopt`,
      'pkg_file', fileName, 'application/octet-stream', data,
      {
        'target_host': 'agent',
        'on_conflict': 'skip',
        'host_rewrite': 'keep',
        'dry_run': 'false'
      });
    const rec = JsonHelper.parse(text);
    return MemoryAdoptSummaryModel.fromRecord(rec === null ? {} : rec);
  }

  // ---- 候选审核（L1 → L2 的确认闭环）----

  /** 候选记忆列表（status 空串=全部；type 空串=全部；query 关键词） */
  static async listCandidates(agentId: string, status: string, type: string,
    query: string, limit: number): Promise<Array<MemoryCandidateModel>> {
    const body: Record<string, Object> = { 'limit': limit };
    if (status !== '') {
      body['status'] = status;
    }
    if (type !== '') {
      body['candidate_type'] = type;
    }
    if (query !== '') {
      body['query'] = query;
    }
    const text: string = await HttpClient.getInstance().post(
      `/api/agents/${agentId}/memory/candidates/list`, JSON.stringify(body));
    return MemoryCandidateModel.parseList(text);
  }

  /** 采纳候选（promote：写入 L2 atom） */
  static async promoteCandidate(agentId: string, candidateId: string): Promise<void> {
    await HttpClient.getInstance().post(
      `/api/agents/${agentId}/memory/candidates/${encodeURIComponent(candidateId)}:promote`, '{}');
  }

  /** 拒绝候选（reason 可空） */
  static async rejectCandidate(agentId: string, candidateId: string, reason: string): Promise<void> {
    const body: Record<string, Object> = { 'actor': 'user' };
    if (reason !== '') {
      body['reason'] = reason;
    }
    await HttpClient.getInstance().post(
      `/api/agents/${agentId}/memory/candidates/${encodeURIComponent(candidateId)}:reject`,
      JSON.stringify(body));
  }

  // ---- 手动文档（MEMORY.md / USER.md）----

  /** 读取强记忆 MEMORY.md（GET /memory/strong） */
  static async getStrong(agentId: string): Promise<MemoryTextFileModel> {
    const text: string =
      await HttpClient.getInstance().get(`/api/agents/${agentId}/memory/strong`);
    return MemoryTextFileModel.parse(text);
  }

  /** 保存强记忆 MEMORY.md（PUT /memory/strong） */
  static async putStrong(agentId: string, content: string): Promise<void> {
    const body: Record<string, Object> = { 'content': content };
    await HttpClient.getInstance().put(
      `/api/agents/${agentId}/memory/strong`, JSON.stringify(body));
  }

  /** 读取用户画像 USER.md（GET /memory/user） */
  static async getUserProfile(agentId: string): Promise<MemoryTextFileModel> {
    const text: string =
      await HttpClient.getInstance().get(`/api/agents/${agentId}/memory/user`);
    return MemoryTextFileModel.parse(text);
  }

  /** 保存用户画像 USER.md（PUT /memory/user） */
  static async putUserProfile(agentId: string, content: string): Promise<void> {
    const body: Record<string, Object> = { 'content': content };
    await HttpClient.getInstance().put(
      `/api/agents/${agentId}/memory/user`, JSON.stringify(body));
  }

  /** 手动文档与普通记忆核对（POST /memory/manual-review） */
  static async manualReview(agentId: string): Promise<ManualReviewModel> {
    const text: string = await HttpClient.getInstance().post(
      `/api/agents/${agentId}/memory/manual-review`, '{}');
    return ManualReviewModel.parse(text);
  }

  // ---- 日积月累（daily/YYYY-MM-DD.md）----

  /** 日积月累文件列表（GET /memory/daily，按日期倒序） */
  static async listDaily(agentId: string): Promise<Array<MemoryDailyFileModel>> {
    const text: string =
      await HttpClient.getInstance().get(`/api/agents/${agentId}/memory/daily`);
    const result: Array<MemoryDailyFileModel> = [];
    const parsed = JsonHelper.parseArray(text);
    if (parsed === null) {
      return result;
    }
    for (const item of parsed) {
      result.push(MemoryDailyFileModel.fromRecord(item));
    }
    return result;
  }

  /** 读单篇日积月累（GET /memory/daily/{filename} → {filename,date,content}） */
  static async readDaily(agentId: string, filename: string): Promise<string> {
    const text: string = await HttpClient.getInstance().get(
      `/api/agents/${agentId}/memory/daily/${encodeURIComponent(filename)}`);
    const rec = JsonHelper.parse(text);
    if (rec === null) {
      return '';
    }
    return JsonHelper.getString(rec, 'content', '');
  }

  /** 删除单篇日积月累（DELETE /memory/daily/{filename}） */
  static async deleteDaily(agentId: string, filename: string): Promise<void> {
    await HttpClient.getInstance().delete(
      `/api/agents/${agentId}/memory/daily/${encodeURIComponent(filename)}`);
  }

  // ---- 记忆终端（终端聚合卡）----

  /** 终端卡通用取数（items 数组；about_me/current_focus/things_you_told_me → atoms） */
  static async terminalAtoms(agentId: string, which: string, limit: number): Promise<Array<MemoryAtomModel>> {
    const text: string = await HttpClient.getInstance().get(
      `/api/agents/${agentId}/memory/terminal/${which}?limit=${limit}`);
    const result: Array<MemoryAtomModel> = [];
    const rec = JsonHelper.parse(text);
    if (rec === null) {
      return result;
    }
    const items = JsonHelper.getRecordArray(rec, 'items');
    for (const item of items) {
      result.push(MemoryAtomModel.fromRecord(item));
    }
    return result;
  }

  /** 记忆终端·近期故事（recent_stories → episodes） */
  static async terminalStories(agentId: string, limit: number): Promise<Array<MemoryEpisodeModel>> {
    const text: string = await HttpClient.getInstance().get(
      `/api/agents/${agentId}/memory/terminal/recent_stories?limit=${limit}`);
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

  /** 记忆终端·人物/事物（entities → entities） */
  static async terminalEntities(agentId: string, limit: number): Promise<Array<MemoryEntityModel>> {
    const text: string = await HttpClient.getInstance().get(
      `/api/agents/${agentId}/memory/terminal/entities?limit=${limit}`);
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

  // ---- 审计 / 实体 / 情景 / 原始事件 ----

  /** 记忆变更审计（journal/recent；limit 1-100 默认 20） */
  static async recentJournal(agentId: string, limit: number): Promise<Array<MemoryJournalModel>> {
    const text: string = await HttpClient.getInstance().get(
      `/api/agents/${agentId}/memory/journal/recent?limit=${limit}`);
    return MemoryJournalModel.parseList(text);
  }

  /** 实体列表（entities/list；query/排序/分页） */
  static async listEntities(agentId: string, query: string, limit: number): Promise<Array<MemoryEntityModel>> {
    const body: Record<string, Object> = { 'limit': limit, 'order_by': 'atom_count', 'order': 'desc' };
    if (query !== '') {
      body['query'] = query;
    }
    const text: string = await HttpClient.getInstance().post(
      `/api/agents/${agentId}/memory/entities/list`, JSON.stringify(body));
    return MemoryEntityModel.parseList(text);
  }

  /** 情景日记列表（episodes/list；query/分页） */
  static async listEpisodes(agentId: string, query: string, limit: number): Promise<Array<MemoryEpisodeModel>> {
    const body: Record<string, Object> = { 'limit': limit };
    if (query !== '') {
      body['query'] = query;
    }
    const text: string = await HttpClient.getInstance().post(
      `/api/agents/${agentId}/memory/episodes/list`, JSON.stringify(body));
    return MemoryEpisodeModel.parseList(text);
  }

  /** 原始事件列表（raw_events/list；query/分页） */
  static async listRawEvents(agentId: string, query: string, limit: number): Promise<Array<MemoryRawEventModel>> {
    const body: Record<string, Object> = { 'limit': limit };
    if (query !== '') {
      body['query'] = query;
    }
    const text: string = await HttpClient.getInstance().post(
      `/api/agents/${agentId}/memory/raw_events/list`, JSON.stringify(body));
    return MemoryRawEventModel.parseList(text);
  }

  // ---- 提取配置 / 统计 ----

  /** 读取记忆提取配置（GET /memory/extract-config） */
  static async getExtractConfig(agentId: string): Promise<MemoryExtractConfigModel> {
    const text: string =
      await HttpClient.getInstance().get(`/api/agents/${agentId}/memory/extract-config`);
    return MemoryExtractConfigModel.parse(text);
  }

  /** 保存记忆提取配置（PUT /memory/extract-config，字段可空表示不改） */
  static async putExtractConfig(agentId: string, cfg: MemoryExtractConfigModel): Promise<void> {
    const body: Record<string, Object> = {
      'memory_enabled': cfg.memoryEnabled,
      'extract_on_session_end': cfg.extractOnSessionEnd,
      'extract_trigger_mode': cfg.extractTriggerMode,
      'extract_idle_seconds': cfg.extractIdleSeconds,
      'extract_interval_seconds': cfg.extractIntervalSeconds
    };
    if (cfg.auxModel !== '') {
      body['aux_model'] = cfg.auxModel;
    }
    await HttpClient.getInstance().put(
      `/api/agents/${agentId}/memory/extract-config`, JSON.stringify(body));
  }

  /** 增长曲线（GET /memory/stats/growth?days=N → series） */
  static async statsGrowth(agentId: string, days: number): Promise<Array<MemoryGrowthPointModel>> {
    const text: string = await HttpClient.getInstance().get(
      `/api/agents/${agentId}/memory/stats/growth?days=${days}`);
    return MemoryGrowthPointModel.parseList(text);
  }

  /** 类型分布（GET /memory/stats/atom_kinds → [{kind,count}]，返回原始文本交 UI 解析） */
  static async statsAtomKinds(agentId: string): Promise<string> {
    return await HttpClient.getInstance().get(
      `/api/agents/${agentId}/memory/stats/atom_kinds`);
  }

  // ---- 存储体检 / 维护 / 备份 ----

  /** 存储体检（GET /memory/storage/check） */
  static async storageCheck(agentId: string): Promise<MemoryStorageCheckModel> {
    const text: string =
      await HttpClient.getInstance().get(`/api/agents/${agentId}/memory/storage/check`);
    return MemoryStorageCheckModel.parse(text);
  }

  /** 存储维护（VACUUM 类清理；confirmed 必须为 true） */
  static async storageMaintain(agentId: string): Promise<string> {
    const body: Record<string, Object> = { 'confirmed': true };
    return await HttpClient.getInstance().post(
      `/api/agents/${agentId}/memory/storage/maintenance`, JSON.stringify(body));
  }

  /** 备份列表（GET /memory/storage/backups） */
  static async storageBackups(agentId: string): Promise<Array<MemoryBackupModel>> {
    const text: string =
      await HttpClient.getInstance().get(`/api/agents/${agentId}/memory/storage/backups`);
    return MemoryBackupModel.parseList(text);
  }

  /** 从备份恢复（confirmed + backup_id 必填） */
  static async storageRestore(agentId: string, backupId: string): Promise<string> {
    const body: Record<string, Object> = { 'confirmed': true, 'backup_id': backupId };
    return await HttpClient.getInstance().post(
      `/api/agents/${agentId}/memory/storage/restore`, JSON.stringify(body));
  }

  // ---- 跨端迁移：体检 ----

  /** 记忆包体检（multipart doctor：host_spec=agent；compare_pkg 可选 .hmpkg 上传） */
  static async doctor(agentId: string, fileName: string, data: ArrayBuffer): Promise<string> {
    return await HttpClient.getInstance().postMultipartFile(
      `/api/agents/${agentId}/memory/portable/doctor`,
      'compare_pkg', fileName, 'application/octet-stream', data,
      { 'host_spec': 'agent' });
  }
}
