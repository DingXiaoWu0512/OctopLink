import { HttpClient } from '../net/HttpClient';
import { JsonHelper } from '../utils/JsonHelper';
import {
  InstalledSubagentModel,
  SubagentCatalogItemModel,
  SubagentDivisionModel
} from '../model/SkillModels';

/** 子代理目录与安装（/api/subagent-catalog*，源 subagents.py） */
export class SubagentService {
  static async divisions(): Promise<Array<SubagentDivisionModel>> {
    const text: string =
      await HttpClient.getInstance().get('/api/subagent-catalog/divisions');
    return SubagentDivisionModel.parseList(text);
  }

  /** 目录（division/q/locale 均可选过滤） */
  static async catalog(division: string = '', query: string = '',
    locale: string = ''): Promise<Array<SubagentCatalogItemModel>> {
    const params: string[] = [];
    if (division !== '') {
      params.push(`division=${encodeURIComponent(division)}`);
    }
    if (query !== '') {
      params.push(`q=${encodeURIComponent(query)}`);
    }
    if (locale !== '') {
      params.push(`locale=${encodeURIComponent(locale)}`);
    }
    const suffix: string = params.length > 0 ? `?${params.join('&')}` : '';
    const text: string =
      await HttpClient.getInstance().get(`/api/subagent-catalog${suffix}`);
    return SubagentCatalogItemModel.parseList(text);
  }

  /** 目录详情（含 content locale map） */
  static async detail(slug: string): Promise<SubagentCatalogItemModel> {
    const text: string =
      await HttpClient.getInstance().get(`/api/subagent-catalog/${slug}`);
    const rec = JsonHelper.parse(text);
    return SubagentCatalogItemModel.fromRecord(rec === null ? {} : rec);
  }

  /** agent 已安装子代理 */
  static async listInstalled(agentId: string): Promise<Array<InstalledSubagentModel>> {
    const text: string =
      await HttpClient.getInstance().get(`/api/agents/${agentId}/subagents`);
    return InstalledSubagentModel.parseList(text);
  }

  /** 安装目录子代理到 agent（201；安装后自动 reload agent） */
  static async install(agentId: string, slug: string, locale: string = ''): Promise<void> {
    const body: Record<string, Object> = { 'slug': slug };
    if (locale !== '') {
      body['locale'] = locale;
    }
    await HttpClient.getInstance().post(
      `/api/agents/${agentId}/subagents/install`, JSON.stringify(body));
  }
}
