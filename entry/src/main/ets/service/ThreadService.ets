import { HttpClient } from '../net/HttpClient';
import { JsonHelper } from '../utils/JsonHelper';
import { ChatMessageModel } from '../model/MessageModels';
import { ContextUsageModel, CreateThreadResult, HistoryResult, ThreadModel } from '../model/ThreadModels';
import { HitlRequestModel } from '../model/HitlModels';

export class ThreadService {
  static async list(agentId: string, limit: number): Promise<Array<ThreadModel>> {
    const text: string = await HttpClient.getInstance().get(`/api/agents/${agentId}/threads?limit=${limit}`);
    return ThreadModel.parseList(text);
  }

  static async create(agentId: string): Promise<CreateThreadResult> {
    const text: string = await HttpClient.getInstance().post(`/api/agents/${agentId}/threads`, '{}');
    return CreateThreadResult.fromResponse(text);
  }

  /** 历史加载（含待审批卡 hitl_pending 解析）；offset 向前翻页（0=最新一页） */
  static async historyFull(agentId: string, threadId: string, offset: number = 0): Promise<HistoryResult> {
    const text: string = await HttpClient.getInstance().get(
      `/api/agents/${agentId}/threads/${threadId}/history?limit=200&offset=${offset}`);
    const messages: Array<ChatMessageModel> = ChatMessageModel.parseHistory(text);
    const rec = JsonHelper.parse(text);
    let hitlPending: HitlRequestModel | null = null;
    let hasMore: boolean = false;
    if (rec !== null) {
      const pendingRec: Record<string, Object> | null = JsonHelper.getRecord(rec, 'hitl_pending');
      hitlPending = HitlRequestModel.fromFrameRecord(pendingRec);
      hasMore = JsonHelper.getBool(rec, 'has_more', false);
    }
    return new HistoryResult(messages, hitlPending, hasMore);
  }

  /** 会话级组合器设置（PATCH threads：model_ref/reasoning_mode/reasoning_effort/conversation_mode/hitl_policy） */
  static async updateThreadSettings(agentId: string, threadId: string, bodyStr: string): Promise<void> {
    await HttpClient.getInstance().patch(`/api/agents/${agentId}/threads/${threadId}`, bodyStr);
  }

  static async rename(agentId: string, threadId: string, title: string): Promise<void> {
    const body: Record<string, Object> = { 'title': title };
    await HttpClient.getInstance().patch(`/api/agents/${agentId}/threads/${threadId}`, JSON.stringify(body));
  }

  /** 置顶/取消置顶会话 */
  static async setPinned(agentId: string, threadId: string, pinned: boolean): Promise<void> {
    const body: Record<string, Object> = { 'pinned': pinned };
    await HttpClient.getInstance().patch(`/api/agents/${agentId}/threads/${threadId}`, JSON.stringify(body));
  }

  static async remove(agentId: string, threadId: string): Promise<void> {
    await HttpClient.getInstance().delete(`/api/agents/${agentId}/threads/${threadId}`);
  }

  /** 清除线程未读（204），成功后 agent unread_count 归零 */
  static async markRead(agentId: string, threadId: string): Promise<void> {
    await HttpClient.getInstance().post(`/api/agents/${agentId}/threads/${threadId}/read`, '{}');
  }

  /** 从最后一条 assistant 消息分叉新会话，返回新 thread_id（失败返回空串） */
  static async forkFromLast(agentId: string, threadId: string): Promise<string> {
    const body: Record<string, Object> = { 'assistant_turns_from_end': 1 };
    const text: string =
      await HttpClient.getInstance().post(`/api/agents/${agentId}/threads/${threadId}/fork`,
        JSON.stringify(body));
    const rec = JsonHelper.parse(text);
    return rec === null ? '' : JsonHelper.getString(rec, 'thread_id', '');
  }

  /** 上下文窗口用量 */
  static async contextUsage(agentId: string, threadId: string): Promise<ContextUsageModel> {
    const text: string =
      await HttpClient.getInstance().get(`/api/agents/${agentId}/threads/${threadId}/context-usage`);
    return ContextUsageModel.parse(text);
  }

  // ---- 导出 / 会话重绑 / 历史迁移 ----

  /** 导出未渲染原始会话历史（GET history/export，返回原始 JSON 文本） */
  static async exportHistory(agentId: string, threadId: string): Promise<string> {
    return await HttpClient.getInstance().get(
      `/api/agents/${agentId}/threads/${threadId}/history/export`);
  }

  /** 重绑仪表盘会话（PATCH /api/agents/{id}/session；把活跃 session 指到指定 thread） */
  static async rebindSession(agentId: string, threadId: string): Promise<void> {
    const body: Record<string, Object> = { 'thread_id': threadId };
    await HttpClient.getInstance().patch(
      `/api/agents/${agentId}/session`, JSON.stringify(body));
  }

  /** 旧版历史迁移状态（GET /history-migration/status） */
  static async migrationStatus(agentId: string): Promise<string> {
    return await HttpClient.getInstance().get(
      `/api/agents/${agentId}/history-migration/status`);
  }

  /** 启动旧版历史迁移（POST /history-migration/start） */
  static async migrationStart(agentId: string): Promise<string> {
    return await HttpClient.getInstance().post(
      `/api/agents/${agentId}/history-migration/start`, '{}');
  }
}
