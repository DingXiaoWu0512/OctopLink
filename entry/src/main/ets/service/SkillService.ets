import { HttpClient } from '../net/HttpClient';
import { JsonHelper } from '../utils/JsonHelper';
import {
  HubRankingSectionModel,
  HubSkillModel,
  SkillDetailModel,
  SkillFileModel,
  SkillPackageModel,
  SkillSummaryModel
} from '../model/SkillModels';

/** agent 技能（/api/agents/{agent_id}/skills*，源 skills.py；技能操作一律用 slug） */
export class SkillService {
  static async list(agentId: string): Promise<Array<SkillSummaryModel>> {
    const text: string =
      await HttpClient.getInstance().get(`/api/agents/${agentId}/skills`);
    return SkillSummaryModel.parseList(text);
  }

  static async get(agentId: string, slug: string): Promise<SkillDetailModel> {
    const text: string =
      await HttpClient.getInstance().get(`/api/agents/${agentId}/skills/${slug}`);
    return SkillDetailModel.parse(text);
  }

  /** 创建技能（files 与 content 至少其一非空，否则 400） */
  static async create(agentId: string, name: string, content: string,
    files: Array<SkillFileModel> | null, overwrite: boolean): Promise<SkillSummaryModel> {
    const body: Record<string, Object> = {
      'name': name,
      'content': content,
      'overwrite': overwrite
    };
    if (files !== null && files.length > 0) {
      const fileArr: Object[] = [];
      for (const file of files) {
        const rec: Record<string, Object> = {
          'path': file.path,
          'content_base64': file.contentBase64
        };
        fileArr.push(rec);
      }
      body['files'] = fileArr;
    }
    const text: string = await HttpClient.getInstance().post(
      `/api/agents/${agentId}/skills`, JSON.stringify(body));
    const rec = JsonHelper.parse(text);
    return SkillSummaryModel.fromRecord(rec === null ? {} : rec);
  }

  /** 更新技能：仅 content 时只重写 SKILL.md；files 非空时整目录替换 */
  static async update(agentId: string, slug: string, content: string,
    files: Array<SkillFileModel> | null): Promise<SkillSummaryModel> {
    const body: Record<string, Object> = { 'content': content };
    if (files !== null && files.length > 0) {
      const fileArr: Object[] = [];
      for (const file of files) {
        const rec: Record<string, Object> = {
          'path': file.path,
          'content_base64': file.contentBase64
        };
        fileArr.push(rec);
      }
      body['files'] = fileArr;
    }
    const text: string = await HttpClient.getInstance().put(
      `/api/agents/${agentId}/skills/${slug}`, JSON.stringify(body));
    const rec = JsonHelper.parse(text);
    return SkillSummaryModel.fromRecord(rec === null ? {} : rec);
  }

  static async remove(agentId: string, slug: string): Promise<void> {
    await HttpClient.getInstance().delete(`/api/agents/${agentId}/skills/${slug}`);
  }

  static async setEnabled(agentId: string, slug: string, enabled: boolean): Promise<void> {
    const action: string = enabled ? 'enable' : 'disable';
    await HttpClient.getInstance().post(
      `/api/agents/${agentId}/skills/${slug}/${action}`, '{}');
  }

  /** 从其他 agent 复制 workspace 技能 */
  static async copy(agentId: string, sourceAgentId: string, slug: string,
    overwrite: boolean = true): Promise<string> {
    const body: Record<string, Object> = {
      'source_agent_id': sourceAgentId,
      'slug': slug,
      'overwrite': overwrite
    };
    const text: string = await HttpClient.getInstance().post(
      `/api/agents/${agentId}/skills/copy`, JSON.stringify(body));
    const rec = JsonHelper.parse(text);
    return rec === null ? '' : JsonHelper.getString(rec, 'slug', '');
  }

  /** 从 URL 导入技能（201；失败 502 SKILL_IMPORT_FAILED） */
  static async importSkill(agentId: string, bundleUrl: string, version: string = '',
    enable: boolean = true, overwrite: boolean = false): Promise<SkillSummaryModel> {
    const body: Record<string, Object> = {
      'bundle_url': bundleUrl,
      'version': version,
      'enable': enable,
      'overwrite': overwrite
    };
    const text: string = await HttpClient.getInstance().post(
      `/api/agents/${agentId}/skills/import`, JSON.stringify(body));
    const rec = JsonHelper.parse(text);
    return SkillSummaryModel.fromRecord(rec === null ? {} : rec);
  }

  /** 导出单技能 ZIP */
  static async exportOne(agentId: string, slug: string): Promise<ArrayBuffer> {
    return await HttpClient.getInstance().downloadGet(
      `/api/agents/${agentId}/skills/${slug}/export`);
  }

  /** 导出多技能 ZIP（skills.zip 或单技能 <slug>.zip） */
  static async exportMany(agentId: string, slugs: Array<string>): Promise<ArrayBuffer> {
    const slugArr: Object[] = [];
    for (const slug of slugs) {
      slugArr.push(slug);
    }
    const body: Record<string, Object> = { 'slugs': slugArr };
    return await HttpClient.getInstance().postForBytes(
      `/api/agents/${agentId}/skills/export`, JSON.stringify(body));
  }

  // ---- SkillHub ----

  /** 市场搜索（agentId 为空走 /api/skills/hub/search） */
  static async hubSearch(agentId: string, query: string,
    limit: number = 50): Promise<Array<HubSkillModel>> {
    const params: string =
      `q=${encodeURIComponent(query)}&limit=${limit}`;
    const path: string = agentId === ''
      ? `/api/skills/hub/search?${params}`
      : `/api/agents/${agentId}/skills/hub/search?${params}`;
    const text: string = await HttpClient.getInstance().get(path);
    return HubSkillModel.parseList(text);
  }

  /** 市场推荐榜单（agentId 为空走 /api/skills/hub/rankings；type=recommended 时响应为单分区 {section, skills, total}） */
  static async hubRankings(agentId: string, type: string): Promise<Array<HubRankingSectionModel>> {
    const path: string = agentId === ''
      ? `/api/skills/hub/rankings?type=${encodeURIComponent(type)}`
      : `/api/agents/${agentId}/skills/hub/rankings?type=${encodeURIComponent(type)}`;
    const text: string = await HttpClient.getInstance().get(path);
    return HubRankingSectionModel.parseSections(text);
  }

  /** 从市场安装到 agent（201） */
  static async hubInstall(agentId: string, skillName: string, enable: boolean = true): Promise<void> {
    const body: Record<string, Object> = {
      'skill_name': skillName,
      'enable': enable
    };
    await HttpClient.getInstance().post(
      `/api/agents/${agentId}/skills/hub/install`, JSON.stringify(body));
  }

  // ---- agent 挂载技能包 ----

  /** agent 已挂载技能包 */
  static async listAgentPackages(agentId: string): Promise<Array<SkillPackageModel>> {
    const text: string =
      await HttpClient.getInstance().get(`/api/agents/${agentId}/skill-packages`);
    const result: Array<SkillPackageModel> = [];
    const rec = JsonHelper.parse(text);
    if (rec === null) {
      return result;
    }
    const packageRecords: Array<Record<string, Object>> =
      JsonHelper.getRecordArray(rec, 'packages');
    for (const packageRec of packageRecords) {
      result.push(SkillPackageModel.fromRecord(packageRec));
    }
    return result;
  }

  /** 设置 agent 挂载的技能包集合（全量替换） */
  static async putAgentPackages(agentId: string, packageIds: Array<string>): Promise<void> {
    const idArr: Object[] = [];
    for (const id of packageIds) {
      idArr.push(id);
    }
    const body: Record<string, Object> = { 'package_ids': idArr };
    await HttpClient.getInstance().put(
      `/api/agents/${agentId}/skill-packages`, JSON.stringify(body));
  }

  /** 从包复制技能到 agent workspace */
  static async copyPackageSkills(agentId: string, packageId: string,
    skillSlugs: Array<string>, overwrite: boolean = false): Promise<Array<string>> {
    const slugArr: Object[] = [];
    for (const slug of skillSlugs) {
      slugArr.push(slug);
    }
    const body: Record<string, Object> = { 'skill_slugs': slugArr, 'overwrite': overwrite };
    const text: string = await HttpClient.getInstance().post(
      `/api/agents/${agentId}/skill-packages/${packageId}/copy`, JSON.stringify(body));
    const rec = JsonHelper.parse(text);
    return rec === null ? [] : JsonHelper.getStringArray(rec, 'copied');
  }

  /** 把 workspace 技能推送到包 */
  static async pushToPackage(agentId: string, slug: string, packageId: string,
    overwrite: boolean = false): Promise<void> {
    const body: Record<string, Object> = { 'package_id': packageId, 'overwrite': overwrite };
    await HttpClient.getInstance().post(
      `/api/agents/${agentId}/skills/${slug}/push-to-package`, JSON.stringify(body));
  }
}
