import { HttpClient } from '../net/HttpClient';
import { UsageSummaryModel } from '../model/UsageModels';

/** 用量（/api/usage/*，源 usage.py；window 见 UsageWindow 常量） */
export class UsageService {
  static readonly WINDOWS: Array<string> =
    ['today', 'yesterday', 'last_7d', 'last_30d', 'all'];
  static readonly GRANULARITIES: Array<string> = ['total', 'by_day', 'by_agent', 'by_model'];

  static readonly WINDOW_LABELS: Record<string, string> = {
    'today': '今天',
    'yesterday': '昨天',
    'last_7d': '近 7 天',
    'last_30d': '近 30 天',
    'all': '全部'
  };

  static readonly GRANULARITY_LABELS: Record<string, string> = {
    'total': '汇总',
    'by_day': '按天',
    'by_agent': '按智能体',
    'by_model': '按模型'
  };

  /** 汇总（window 亦支持 day:/month:/range: 形式） */
  static async summary(window: string, granularity: string,
    agentId: string = ''): Promise<UsageSummaryModel> {
    const params: string[] = [`window=${encodeURIComponent(window)}`,
      `granularity=${encodeURIComponent(granularity)}`];
    if (agentId !== '') {
      params.push(`agent_id=${encodeURIComponent(agentId)}`);
    }
    const text: string =
      await HttpClient.getInstance().get(`/api/usage/summary?${params.join('&')}`);
    return UsageSummaryModel.parse(text);
  }

  /** 导出 xlsx（二进制，保存由调用方处理） */
  static async exportXlsx(window: string, agentId: string = ''): Promise<ArrayBuffer> {
    const params: string[] = [`window=${encodeURIComponent(window)}`];
    if (agentId !== '') {
      params.push(`agent_id=${encodeURIComponent(agentId)}`);
    }
    return await HttpClient.getInstance().downloadGet(
      `/api/usage/export.xlsx?${params.join('&')}`);
  }
}
