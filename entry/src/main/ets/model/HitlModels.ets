import { JsonHelper } from '../utils/JsonHelper';

/** HITL 审批动作项（action_requests 元素的容错解析） */
export class HitlActionModel {
  readonly name: string;
  readonly description: string;
  readonly argsPreview: string;

  constructor(name: string, description: string, argsPreview: string) {
    this.name = name;
    this.description = description;
    this.argsPreview = argsPreview;
  }
}

/**
 * HITL 待审批请求：
 * - WS hitl_required 帧：{request: {action_requests: [...], pending_id}}
 * - 历史 hitl_pending 字段：审批卡对象（request 结构）
 * 字段名容错解析，服务端结构演进时不崩溃。
 */
export class HitlRequestModel {
  readonly pendingId: string;
  readonly actions: Array<HitlActionModel>;

  constructor(pendingId: string, actions: Array<HitlActionModel>) {
    this.pendingId = pendingId;
    this.actions = actions;
  }

  static fromRecord(rec: Record<string, Object> | null): HitlRequestModel | null {
    if (rec === null) {
      return null;
    }
    const pendingId: string = JsonHelper.getString(rec, 'pending_id', '');
    const actionRecs: Array<Record<string, Object>> = JsonHelper.getRecordArray(rec, 'action_requests');
    if (pendingId === '' && actionRecs.length === 0) {
      return null;
    }
    const actions: Array<HitlActionModel> = [];
    for (const actionRec of actionRecs) {
      actions.push(HitlRequestModel.parseAction(actionRec));
    }
    return new HitlRequestModel(pendingId, actions);
  }

  /** 兼容 {request:{...}} 包装与裸对象两种形态 */
  static fromFrameRecord(rec: Record<string, Object> | null): HitlRequestModel | null {
    if (rec === null) {
      return null;
    }
    const inner: Record<string, Object> | null = JsonHelper.getRecord(rec, 'request');
    return HitlRequestModel.fromRecord(inner !== null ? inner : rec);
  }

  private static parseAction(rec: Record<string, Object>): HitlActionModel {
    const name: string = HitlRequestModel.firstString(rec, ['name', 'action', 'tool', 'tool_name', 'title']);
    const description: string =
      HitlRequestModel.firstString(rec, ['description', 'summary', 'intro', 'reason', 'prompt']);
    let argsPreview: string = HitlRequestModel.firstString(rec, ['args_preview', 'preview', 'content']);
    if (argsPreview === '') {
      const argsKeys: Array<string> = ['args', 'input', 'arguments'];
      for (const key of argsKeys) {
        const value: Object | undefined = rec[key];
        if (value !== undefined && value !== null) {
          const raw: string = JSON.stringify(value);
          argsPreview = raw.length > 200 ? `${raw.substring(0, 200)}…` : raw;
          break;
        }
      }
    }
    return new HitlActionModel(name, description, argsPreview);
  }

  private static firstString(rec: Record<string, Object>, keys: Array<string>): string {
    for (const key of keys) {
      const value: string = JsonHelper.getString(rec, key, '');
      if (value !== '') {
        return value;
      }
    }
    return '';
  }
}
