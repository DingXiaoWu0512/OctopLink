import { HttpClient } from '../net/HttpClient';
import { JsonHelper } from '../utils/JsonHelper';
import { TrajectoryEventModel, TrajectoryHistoryModel, TrajectoryMetricsModel } from '../model/TrajectoryModels';

/** 会话轨迹（/api/agents/{agent_id}/threads/{thread_id}/trajectory*，源 trajectory.py） */
export class TrajectoryService {
  /** 事件分页（limit 服务端上限 200；before_seq 取上一页 next_before_seq；kinds 逗号拼接） */
  static async history(agentId: string, threadId: string, limit: number,
    beforeSeq: number | null, kinds: Array<string>): Promise<TrajectoryHistoryModel> {
    let params: string = `limit=${limit}`;
    if (beforeSeq !== null) {
      params += `&before_seq=${beforeSeq}`;
    }
    if (kinds.length > 0) {
      params += `&kinds=${encodeURIComponent(kinds.join(','))}`;
    }
    const text: string = await HttpClient.getInstance().get(
      `/api/agents/${agentId}/threads/${threadId}/trajectory?${params}`);
    return TrajectoryHistoryModel.parse(text);
  }

  /** 会话指标汇总 */
  static async metrics(agentId: string, threadId: string): Promise<TrajectoryMetricsModel> {
    const text: string = await HttpClient.getInstance().get(
      `/api/agents/${agentId}/threads/${threadId}/trajectory/metrics`);
    return TrajectoryMetricsModel.parse(text);
  }

  /** 全量导出（format: jsonl=逐行事件 | json=事件数组；返回二进制） */
  static async exportBlob(agentId: string, threadId: string, format: string): Promise<ArrayBuffer> {
    const normalized: string = format === 'json' ? 'json' : 'jsonl';
    return await HttpClient.getInstance().downloadGet(
      `/api/agents/${agentId}/threads/${threadId}/trajectory/export?format=${normalized}`);
  }

  /** 单条事件详情（含完整 payload） */
  static async event(agentId: string, threadId: string,
    eventId: string): Promise<TrajectoryEventModel> {
    const text: string = await HttpClient.getInstance().get(
      `/api/agents/${agentId}/threads/${threadId}/trajectory/events/${encodeURIComponent(eventId)}`);
    const rec: Record<string, Object> | null = JsonHelper.parse(text);
    return TrajectoryEventModel.fromRecord(rec === null ? {} : rec);
  }
}
