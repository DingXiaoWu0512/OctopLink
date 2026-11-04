import { JsonHelper } from '../utils/JsonHelper';

/**
 * 对话轨迹域数据模型（源：octop/api/routers/chat/trajectory.py）：
 * - TrajectoryEventModel：单条轨迹事件（TrajectoryEventOut 列表投影）
 * - TrajectoryMetricsModel：会话指标汇总（TrajectoryMetricsOut）
 * - TrajectoryHistoryModel：事件分页结果（TrajectoryHistoryOut）
 */

/** 单条轨迹事件（列表投影：不含消息正文，tool args/result 已由服务端裁剪） */
export class TrajectoryEventModel {
  readonly eventId: string;
  readonly threadId: string;
  readonly agentId: string;
  readonly seq: number;
  readonly tsMs: number;
  readonly kind: string; // user | assistant | tool | context | compacted | system | unknown
  readonly turnId: string;
  readonly requestSeq: number;
  readonly isError: boolean;
  readonly summary: string;

  constructor(eventId: string, threadId: string, agentId: string, seq: number, tsMs: number,
    kind: string, turnId: string, requestSeq: number, isError: boolean, summary: string) {
    this.eventId = eventId;
    this.threadId = threadId;
    this.agentId = agentId;
    this.seq = seq;
    this.tsMs = tsMs;
    this.kind = kind;
    this.turnId = turnId;
    this.requestSeq = requestSeq;
    this.isError = isError;
    this.summary = summary;
  }

  static fromRecord(rec: Record<string, Object>): TrajectoryEventModel {
    return new TrajectoryEventModel(
      JsonHelper.getString(rec, 'event_id', ''),
      JsonHelper.getString(rec, 'thread_id', ''),
      JsonHelper.getString(rec, 'agent_id', ''),
      JsonHelper.getNumber(rec, 'seq', 0),
      JsonHelper.toMs(rec['ts']),
      JsonHelper.getString(rec, 'kind', 'unknown'),
      JsonHelper.getString(rec, 'turn_id', ''),
      JsonHelper.getNumber(rec, 'request_seq', -1),
      JsonHelper.getBool(rec, 'is_error', false),
      JsonHelper.getString(rec, 'summary', '')
    );
  }
}

/** 会话指标汇总（turns=用户消息数，steps=事件总数；服务端可空字段解析为 null） */
export class TrajectoryMetricsModel {
  readonly turns: number;
  readonly steps: number;
  readonly llmDurationMs: number | null;
  readonly toolDurationMs: number | null;
  readonly ttftAvgMs: number | null;
  readonly tokPerS: number | null;
  readonly cacheHitRatio: number | null;
  readonly inputTokens: number | null;
  readonly outputTokens: number | null;
  readonly cacheReadTokens: number | null;

  constructor(turns: number, steps: number, llmDurationMs: number | null,
    toolDurationMs: number | null, ttftAvgMs: number | null, tokPerS: number | null,
    cacheHitRatio: number | null, inputTokens: number | null, outputTokens: number | null,
    cacheReadTokens: number | null) {
    this.turns = turns;
    this.steps = steps;
    this.llmDurationMs = llmDurationMs;
    this.toolDurationMs = toolDurationMs;
    this.ttftAvgMs = ttftAvgMs;
    this.tokPerS = tokPerS;
    this.cacheHitRatio = cacheHitRatio;
    this.inputTokens = inputTokens;
    this.outputTokens = outputTokens;
    this.cacheReadTokens = cacheReadTokens;
  }

  static parse(text: string): TrajectoryMetricsModel {
    const rec: Record<string, Object> | null = JsonHelper.parse(text);
    if (rec === null) {
      return new TrajectoryMetricsModel(0, 0, null, null, null, null, null, null, null, null);
    }
    return new TrajectoryMetricsModel(
      JsonHelper.getNumber(rec, 'turns', 0),
      JsonHelper.getNumber(rec, 'steps', 0),
      TrajectoryMetricsModel.optionalNumber(rec, 'llm_duration_ms'),
      TrajectoryMetricsModel.optionalNumber(rec, 'tool_duration_ms'),
      TrajectoryMetricsModel.optionalNumber(rec, 'ttft_avg_ms'),
      TrajectoryMetricsModel.optionalNumber(rec, 'tok_per_s'),
      TrajectoryMetricsModel.optionalNumber(rec, 'cache_hit_ratio'),
      TrajectoryMetricsModel.optionalNumber(rec, 'input_tokens'),
      TrajectoryMetricsModel.optionalNumber(rec, 'output_tokens'),
      TrajectoryMetricsModel.optionalNumber(rec, 'cache_read_tokens')
    );
  }

  /** 服务端 None 字段保持 null，缺失时不显示 */
  private static optionalNumber(rec: Record<string, Object>, key: string): number | null {
    const value: Object | undefined = rec[key];
    if (typeof value === 'number') {
      return value;
    }
    return null;
  }
}

/** 事件分页结果（events 按时间倒序，next_before_seq 供加载更早一页） */
export class TrajectoryHistoryModel {
  readonly threadId: string;
  readonly events: Array<TrajectoryEventModel>;
  readonly nextBeforeSeq: number | null;
  readonly hasMore: boolean;

  constructor(threadId: string, events: Array<TrajectoryEventModel>,
    nextBeforeSeq: number | null, hasMore: boolean) {
    this.threadId = threadId;
    this.events = events;
    this.nextBeforeSeq = nextBeforeSeq;
    this.hasMore = hasMore;
  }

  static parse(text: string): TrajectoryHistoryModel {
    const events: Array<TrajectoryEventModel> = [];
    const rec: Record<string, Object> | null = JsonHelper.parse(text);
    if (rec === null) {
      return new TrajectoryHistoryModel('', events, null, false);
    }
    const eventRecords: Array<Record<string, Object>> = JsonHelper.getRecordArray(rec, 'events');
    for (const eventRec of eventRecords) {
      events.push(TrajectoryEventModel.fromRecord(eventRec));
    }
    let nextBeforeSeq: number | null = null;
    const rawNext: Object | undefined = rec['next_before_seq'];
    if (typeof rawNext === 'number') {
      nextBeforeSeq = rawNext;
    }
    return new TrajectoryHistoryModel(
      JsonHelper.getString(rec, 'thread_id', ''),
      events,
      nextBeforeSeq,
      JsonHelper.getBool(rec, 'has_more', false)
    );
  }
}
