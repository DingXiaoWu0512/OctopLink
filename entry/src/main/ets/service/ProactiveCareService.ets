import { HttpClient } from '../net/HttpClient';
import { JsonHelper } from '../utils/JsonHelper';

/** 主动关怀配置（GET/PUT /api/agents/{id}/proactive-care） */
export class ProactiveCareModel {
  readonly enabled: boolean;
  readonly activeHoursStart: string; // "HH:MM"
  readonly activeHoursEnd: string; // "HH:MM"
  readonly minIntervalHours: number;
  readonly maxIntervalHours: number;

  constructor(enabled: boolean, activeHoursStart: string, activeHoursEnd: string,
    minIntervalHours: number, maxIntervalHours: number) {
    this.enabled = enabled;
    this.activeHoursStart = activeHoursStart;
    this.activeHoursEnd = activeHoursEnd;
    this.minIntervalHours = minIntervalHours;
    this.maxIntervalHours = maxIntervalHours;
  }

  static parse(text: string): ProactiveCareModel {
    const rec = JsonHelper.parse(text);
    if (rec === null) {
      return new ProactiveCareModel(false, '09:00', '21:00', 4, 24);
    }
    return new ProactiveCareModel(
      JsonHelper.getBool(rec, 'enabled', false),
      JsonHelper.getString(rec, 'active_hours_start', '09:00'),
      JsonHelper.getString(rec, 'active_hours_end', '21:00'),
      JsonHelper.getNumber(rec, 'min_interval_hours', 4),
      JsonHelper.getNumber(rec, 'max_interval_hours', 24)
    );
  }
}

/** 主动关怀（/api/agents/{agent_id}/proactive-care） */
export class ProactiveCareService {
  static async get(agentId: string): Promise<ProactiveCareModel> {
    const text: string =
      await HttpClient.getInstance().get(`/api/agents/${agentId}/proactive-care`);
    return ProactiveCareModel.parse(text);
  }

  static async put(agentId: string, care: ProactiveCareModel): Promise<ProactiveCareModel> {
    const body: Record<string, Object> = {
      'enabled': care.enabled,
      'active_hours_start': care.activeHoursStart,
      'active_hours_end': care.activeHoursEnd,
      'min_interval_hours': care.minIntervalHours,
      'max_interval_hours': care.maxIntervalHours
    };
    const text: string = await HttpClient.getInstance().put(
      `/api/agents/${agentId}/proactive-care`, JSON.stringify(body));
    return ProactiveCareModel.parse(text);
  }
}
