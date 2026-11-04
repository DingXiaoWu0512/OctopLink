import { HttpClient } from '../net/HttpClient';
import { JsonHelper } from '../utils/JsonHelper';
import {
  SkillFileModel,
  SkillPackageModel,
  SkillSummaryModel
} from '../model/SkillModels';

/** 技能包（/api/skill-packages，源 skill_packages.py） */
export class SkillPackageService {
  static async list(writableOnly: boolean = false): Promise<Array<SkillPackageModel>> {
    const text: string = await HttpClient.getInstance().get(
      `/api/skill-packages?writable_only=${writableOnly}`);
    return SkillPackageModel.parseList(text);
  }

  static async get(packageId: string): Promise<SkillPackageModel> {
    const text: string =
      await HttpClient.getInstance().get(`/api/skill-packages/${packageId}`);
    const rec = JsonHelper.parse(text);
    return SkillPackageModel.fromRecord(rec === null ? {} : rec);
  }

  static async create(name: string, description: string, shared: boolean = false,
    copyPolicy: string = 'snapshot'): Promise<SkillPackageModel> {
    const body: Record<string, Object> = {
      'name': name,
      'description': description,
      'shared': shared,
      'copy_policy': copyPolicy
    };
    const text: string =
      await HttpClient.getInstance().post('/api/skill-packages', JSON.stringify(body));
    const rec = JsonHelper.parse(text);
    return SkillPackageModel.fromRecord(rec === null ? {} : rec);
  }

  /** 部分更新（仅传需要改的字段 JSON） */
  static async patch(packageId: string, bodyStr: string): Promise<SkillPackageModel> {
    const text: string =
      await HttpClient.getInstance().patch(`/api/skill-packages/${packageId}`, bodyStr);
    const rec = JsonHelper.parse(text);
    return SkillPackageModel.fromRecord(rec === null ? {} : rec);
  }

  static async remove(packageId: string): Promise<void> {
    await HttpClient.getInstance().delete(`/api/skill-packages/${packageId}`);
  }

  /** 头像地址（Image 直连） */
  static avatarUrl(packageId: string): string {
    const base: string = HttpClient.getInstance().getBaseUrl();
    return `${base}/api/skill-packages/${packageId}/avatar`;
  }

  static async uploadAvatar(packageId: string, fileName: string, contentType: string,
    data: ArrayBuffer): Promise<void> {
    await HttpClient.getInstance().postMultipartFile(
      `/api/skill-packages/${packageId}/avatar`, 'file', fileName, contentType, data);
  }

  static async removeAvatar(packageId: string): Promise<void> {
    await HttpClient.getInstance().delete(`/api/skill-packages/${packageId}/avatar`);
  }

  // ---- 包内技能 ----

  static async listSkills(packageId: string): Promise<Array<SkillSummaryModel>> {
    const text: string =
      await HttpClient.getInstance().get(`/api/skill-packages/${packageId}/skills`);
    return SkillSummaryModel.parseList(text);
  }

  /** 包内技能详情（含 frontmatter/body/raw） */
  static async getSkill(packageId: string, slug: string): Promise<string> {
    return await HttpClient.getInstance().get(
      `/api/skill-packages/${packageId}/skills/${slug}`);
  }

  static async createSkill(packageId: string, name: string, content: string,
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
      `/api/skill-packages/${packageId}/skills`, JSON.stringify(body));
    const rec = JsonHelper.parse(text);
    return SkillSummaryModel.fromRecord(rec === null ? {} : rec);
  }

  static async updateSkill(packageId: string, slug: string, content: string,
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
      `/api/skill-packages/${packageId}/skills/${slug}`, JSON.stringify(body));
    const rec = JsonHelper.parse(text);
    return SkillSummaryModel.fromRecord(rec === null ? {} : rec);
  }

  static async removeSkill(packageId: string, slug: string): Promise<void> {
    await HttpClient.getInstance().delete(
      `/api/skill-packages/${packageId}/skills/${slug}`);
  }

  /** 从 SkillHub 直接安装到包（201，失败附 skipped_skills） */
  static async hubInstallSkill(packageId: string, skillName: string): Promise<void> {
    const body: Record<string, Object> = { 'skill_name': skillName };
    await HttpClient.getInstance().post(
      `/api/skill-packages/${packageId}/skills/hub/install`, JSON.stringify(body));
  }

  /** 从 SkillHub 以技能包形式导入（201） */
  static async fromSkillhub(slug: string, name: string, description: string,
    shared: boolean): Promise<SkillPackageModel> {
    const body: Record<string, Object> = {
      'slug': slug,
      'shared': shared
    };
    if (name !== '') {
      body['name'] = name;
    }
    if (description !== '') {
      body['description'] = description;
    }
    const text: string = await HttpClient.getInstance().post(
      '/api/skill-packages/from-skillhub', JSON.stringify(body));
    const rec = JsonHelper.parse(text);
    return SkillPackageModel.fromRecord(rec === null ? {} : rec);
  }

  /** 导出整包 ZIP（无下载权 → 403） */
  static async exportZip(packageId: string): Promise<ArrayBuffer> {
    return await HttpClient.getInstance().downloadGet(
      `/api/skill-packages/${packageId}/export`);
  }

  // ---- 包级 SkillHub 检索 / 包内技能文件 / URL 导入 ----

  /** SkillHub 搜索（GET /api/skill-packages/hub/search?q=&limit=，返回原始文本交 UI 解析） */
  static async hubSearch(query: string, limit: number): Promise<string> {
    return await HttpClient.getInstance().get(
      `/api/skill-packages/hub/search?q=${encodeURIComponent(query)}&limit=${limit}`);
  }

  /** SkillHub 排行（GET /api/skill-packages/hub/rankings?type=，返回原始文本交 UI 解析） */
  static async hubRankings(type: string): Promise<string> {
    return await HttpClient.getInstance().get(
      `/api/skill-packages/hub/rankings?type=${encodeURIComponent(type)}`);
  }

  /** 包内技能文件树（GET /skills/{slug}/tree?path=） */
  static async skillTree(packageId: string, slug: string, path: string): Promise<string> {
    const suffix: string = path === '' ? '' : `?path=${encodeURIComponent(path)}`;
    return await HttpClient.getInstance().get(
      `/api/skill-packages/${packageId}/skills/${slug}/tree${suffix}`);
  }

  /** 读包内技能 UTF-8 文件（GET /skills/{slug}/file?path=） */
  static async skillFile(packageId: string, slug: string, path: string): Promise<string> {
    return await HttpClient.getInstance().get(
      `/api/skill-packages/${packageId}/skills/${slug}/file?path=${encodeURIComponent(path)}`);
  }

  /** 下载包内技能文件字节（GET /skills/{slug}/download?path=） */
  static async skillDownload(packageId: string, slug: string, path: string): Promise<ArrayBuffer> {
    return await HttpClient.getInstance().downloadGet(
      `/api/skill-packages/${packageId}/skills/${slug}/download?path=${encodeURIComponent(path)}`);
  }

  /** 从 URL 导入技能到全局包（POST /skills/import，201） */
  static async importFromUrl(packageId: string, bundleUrl: string, version: string,
    overwrite: boolean): Promise<string> {
    const body: Record<string, Object> = { 'bundle_url': bundleUrl };
    if (version !== '') {
      body['version'] = version;
    }
    body['overwrite'] = overwrite;
    return await HttpClient.getInstance().post(
      `/api/skill-packages/${packageId}/skills/import`, JSON.stringify(body));
  }
}
