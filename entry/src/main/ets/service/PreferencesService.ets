import { HttpClient } from '../net/HttpClient';
import { UserPreferencesModel } from '../model/MemoryModels';

/**
 * 用户偏好服务（/api/preferences，源 preferences.py）：
 * 实际契约为 GET / PATCH（任务描述中的 PUT 以服务端源码为准）。
 * timezone 传空串表示清除（PATCH 发送 null），preferredModel 为空时不发送该字段。
 */
export class PreferencesService {
  static async get(): Promise<UserPreferencesModel> {
    const text: string = await HttpClient.getInstance().get('/api/preferences');
    return UserPreferencesModel.parse(text);
  }

  /**
   * 更新偏好：locale 必填（zh/en）；timezone 空串清除偏好时区；
   * preferredModel 为空串表示不修改（服务端要求该字段必须是已启用模型）。
   * 请求体手工拼接以携带显式 null（ArkTS Record 无法存 null 值）。
   */
  static async patch(locale: string, timezone: string, preferredModel: string): Promise<UserPreferencesModel> {
    const parts: Array<string> = [];
    parts.push(`"locale":${JSON.stringify(locale)}`);
    if (timezone === '') {
      parts.push('"timezone":null');
    } else {
      parts.push(`"timezone":${JSON.stringify(timezone)}`);
    }
    if (preferredModel !== '') {
      parts.push(`"preferred_model":${JSON.stringify(preferredModel)}`);
    }
    const text: string = await HttpClient.getInstance().patch(
      '/api/preferences', `{${parts.join(',')}}`);
    return UserPreferencesModel.parse(text);
  }
}
