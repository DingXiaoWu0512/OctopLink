import { JsonHelper } from '../utils/JsonHelper';

/** 用量汇总桶（usage.py bucket：key/label + 各 token 计数） */
export class UsageBucketModel {
  readonly key: string;
  readonly label: string;
  readonly inputTokens: number;
  readonly uncachedInputTokens: number;
  readonly cacheReadTokens: number;
  readonly cacheWriteTokens: number;
  readonly outputTokens: number;
  readonly reasoningTokens: number;
  readonly totalTokens: number;
  readonly modelCalls: number;
  readonly turns: number;

  constructor(key: string, label: string, inputTokens: number, uncachedInputTokens: number,
    cacheReadTokens: number, cacheWriteTokens: number, outputTokens: number,
    reasoningTokens: number, totalTokens: number, modelCalls: number, turns: number) {
    this.key = key;
    this.label = label;
    this.inputTokens = inputTokens;
    this.uncachedInputTokens = uncachedInputTokens;
    this.cacheReadTokens = cacheReadTokens;
    this.cacheWriteTokens = cacheWriteTokens;
    this.outputTokens = outputTokens;
    this.reasoningTokens = reasoningTokens;
    this.totalTokens = totalTokens;
    this.modelCalls = modelCalls;
    this.turns = turns;
  }

  static fromRecord(rec: Record<string, Object>): UsageBucketModel {
    return new UsageBucketModel(
      JsonHelper.getString(rec, 'key', ''),
      JsonHelper.getString(rec, 'label', ''),
      JsonHelper.getNumber(rec, 'input_tokens', 0),
      JsonHelper.getNumber(rec, 'uncached_input_tokens', 0),
      JsonHelper.getNumber(rec, 'cache_read_tokens', 0),
      JsonHelper.getNumber(rec, 'cache_write_tokens', 0),
      JsonHelper.getNumber(rec, 'output_tokens', 0),
      JsonHelper.getNumber(rec, 'reasoning_tokens', 0),
      JsonHelper.getNumber(rec, 'total_tokens', 0),
      JsonHelper.getNumber(rec, 'model_calls', 0),
      JsonHelper.getNumber(rec, 'turns', 0)
    );
  }
}

/** 用量汇总（GET /api/usage/summary；totals 扁平在顶层） */
export class UsageSummaryModel {
  readonly window: string;
  readonly granularity: string;
  readonly rangeStartSec: number;
  readonly rangeEndSec: number;
  readonly inputTokens: number;
  readonly uncachedInputTokens: number;
  readonly cacheReadTokens: number;
  readonly cacheWriteTokens: number;
  readonly outputTokens: number;
  readonly reasoningTokens: number;
  readonly totalTokens: number;
  readonly modelCalls: number;
  readonly turns: number;
  readonly avgPerTurn: number;
  readonly cacheHitPercent: number;
  readonly buckets: Array<UsageBucketModel>;

  constructor(window: string, granularity: string, rangeStartSec: number, rangeEndSec: number,
    inputTokens: number, uncachedInputTokens: number, cacheReadTokens: number,
    cacheWriteTokens: number, outputTokens: number, reasoningTokens: number, totalTokens: number,
    modelCalls: number, turns: number, avgPerTurn: number, cacheHitPercent: number,
    buckets: Array<UsageBucketModel>) {
    this.window = window;
    this.granularity = granularity;
    this.rangeStartSec = rangeStartSec;
    this.rangeEndSec = rangeEndSec;
    this.inputTokens = inputTokens;
    this.uncachedInputTokens = uncachedInputTokens;
    this.cacheReadTokens = cacheReadTokens;
    this.cacheWriteTokens = cacheWriteTokens;
    this.outputTokens = outputTokens;
    this.reasoningTokens = reasoningTokens;
    this.totalTokens = totalTokens;
    this.modelCalls = modelCalls;
    this.turns = turns;
    this.avgPerTurn = avgPerTurn;
    this.cacheHitPercent = cacheHitPercent;
    this.buckets = buckets;
  }

  static parse(text: string): UsageSummaryModel {
    const rec = JsonHelper.parse(text);
    if (rec === null) {
      return new UsageSummaryModel('', '', 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, []);
    }
    const buckets: Array<UsageBucketModel> = [];
    const bucketRecords: Array<Record<string, Object>> = JsonHelper.getRecordArray(rec, 'buckets');
    for (const bucketRec of bucketRecords) {
      buckets.push(UsageBucketModel.fromRecord(bucketRec));
    }
    return new UsageSummaryModel(
      JsonHelper.getString(rec, 'window', ''),
      JsonHelper.getString(rec, 'granularity', ''),
      JsonHelper.getNumber(rec, 'range_start', 0),
      JsonHelper.getNumber(rec, 'range_end', 0),
      JsonHelper.getNumber(rec, 'input_tokens', 0),
      JsonHelper.getNumber(rec, 'uncached_input_tokens', 0),
      JsonHelper.getNumber(rec, 'cache_read_tokens', 0),
      JsonHelper.getNumber(rec, 'cache_write_tokens', 0),
      JsonHelper.getNumber(rec, 'output_tokens', 0),
      JsonHelper.getNumber(rec, 'reasoning_tokens', 0),
      JsonHelper.getNumber(rec, 'total_tokens', 0),
      JsonHelper.getNumber(rec, 'model_calls', 0),
      JsonHelper.getNumber(rec, 'turns', 0),
      JsonHelper.getNumber(rec, 'avg_per_turn', 0),
      JsonHelper.getNumber(rec, 'cache_hit_percent', 0),
      buckets
    );
  }
}
