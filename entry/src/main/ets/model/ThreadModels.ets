import { JsonHelper } from '../utils/JsonHelper';
import { OctopApiError } from '../net/HttpClient';
import { ChatMessageModel } from './MessageModels';
import { HitlRequestModel } from './HitlModels';

/** 会话线程（GET /api/agents/{id}/threads 列表项） */
export class ThreadModel {
  readonly threadId: string;
  readonly title: string;
  readonly lastActiveMs: number;
  readonly createdAtMs: number;
  readonly hasMessages: boolean;
  readonly pinned: boolean;
  readonly turnActive: boolean;
  readonly awaitingUser: boolean;
  readonly modelRef: string;
  readonly reasoningMode: string;
  readonly reasoningEffort: string;
  readonly conversationMode: string;
  readonly hitlPolicyMode: string;

  constructor(threadId: string, title: string, lastActiveMs: number, createdAtMs: number,
    hasMessages: boolean, pinned: boolean, turnActive: boolean, awaitingUser: boolean,
    modelRef: string, reasoningMode: string, reasoningEffort: string, conversationMode: string,
    hitlPolicyMode: string) {
    this.threadId = threadId;
    this.title = title;
    this.lastActiveMs = lastActiveMs;
    this.createdAtMs = createdAtMs;
    this.hasMessages = hasMessages;
    this.pinned = pinned;
    this.turnActive = turnActive;
    this.awaitingUser = awaitingUser;
    this.modelRef = modelRef;
    this.reasoningMode = reasoningMode;
    this.reasoningEffort = reasoningEffort;
    this.conversationMode = conversationMode;
    this.hitlPolicyMode = hitlPolicyMode;
  }

  static fromRecord(rec: Record<string, Object>): ThreadModel {
    const hitlPolicy: Record<string, Object> | null = JsonHelper.getRecord(rec, 'hitl_policy');
    return new ThreadModel(
      JsonHelper.getString(rec, 'thread_id', ''),
      JsonHelper.getString(rec, 'title', ''),
      JsonHelper.toMs(rec['last_active']),
      JsonHelper.toMs(rec['created_at']),
      JsonHelper.getBool(rec, 'has_messages', false),
      JsonHelper.getBool(rec, 'pinned', false),
      JsonHelper.getBool(rec, 'turn_active', false),
      JsonHelper.getBool(rec, 'awaiting_user', false),
      JsonHelper.getString(rec, 'model_ref', ''),
      JsonHelper.getString(rec, 'reasoning_mode', ''),
      JsonHelper.getString(rec, 'reasoning_effort', ''),
      JsonHelper.getString(rec, 'conversation_mode', ''),
      hitlPolicy === null ? '' : JsonHelper.getString(hitlPolicy, 'mode', '')
    );
  }

  /** 解析列表：兼容顶层数组与 {threads:[...]} 两种形态 */
  static parseList(text: string): Array<ThreadModel> {
    const result: Array<ThreadModel> = [];
    const arr = JsonHelper.parseArray(text);
    if (arr !== null) {
      for (const rec of arr) {
        result.push(ThreadModel.fromRecord(rec));
      }
      return result;
    }
    const obj = JsonHelper.parse(text);
    const items = JsonHelper.getRecordArray(obj, 'threads');
    for (const rec of items) {
      result.push(ThreadModel.fromRecord(rec));
    }
    return result;
  }
}

/** POST /api/agents/{id}/threads 创建结果 */
export class CreateThreadResult {
  readonly threadId: string;
  readonly sessionKey: string;

  constructor(threadId: string, sessionKey: string) {
    this.threadId = threadId;
    this.sessionKey = sessionKey;
  }

  static fromResponse(text: string): CreateThreadResult {
    const rec = JsonHelper.parse(text);
    if (rec === null) {
      throw new OctopApiError('创建会话响应格式错误', 0, 'BAD_RESPONSE');
    }
    const threadId: string = JsonHelper.getString(rec, 'thread_id', '');
    if (threadId === '') {
      throw new OctopApiError('创建会话响应缺少 thread_id', 0, 'BAD_RESPONSE');
    }
    return new CreateThreadResult(threadId, JsonHelper.getString(rec, 'session_key', ''));
  }
}

/** GET .../threads/{id}/context-usage 上下文窗口用量 */
export class ContextUsageModel {
  readonly maxTokens: number;
  readonly usedTokens: number;

  constructor(maxTokens: number, usedTokens: number) {
    this.maxTokens = maxTokens;
    this.usedTokens = usedTokens;
  }

  static parse(text: string): ContextUsageModel {
    const rec = JsonHelper.parse(text);
    if (rec === null) {
      throw new OctopApiError('上下文用量响应格式错误', 0, 'BAD_RESPONSE');
    }
    return new ContextUsageModel(
      JsonHelper.getNumber(rec, 'max_tokens', 0),
      JsonHelper.getNumber(rec, 'used_tokens', 0)
    );
  }

  percent(): number {
    return this.maxTokens > 0 ? Math.round(this.usedTokens * 100 / this.maxTokens) : 0;
  }
}

/** 历史加载结果：消息列表 + 待审批卡（hitl_pending 非空时）+ 是否还有更早消息 */
export class HistoryResult {
  readonly messages: Array<ChatMessageModel>;
  readonly hitlPending: HitlRequestModel | null;
  readonly hasMore: boolean;

  constructor(messages: Array<ChatMessageModel>, hitlPending: HitlRequestModel | null, hasMore: boolean) {
    this.messages = messages;
    this.hitlPending = hitlPending;
    this.hasMore = hasMore;
  }
}
