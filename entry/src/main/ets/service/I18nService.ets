import { HttpClient } from '../net/HttpClient';
import { JsonHelper } from '../utils/JsonHelper';
import { Log } from '../utils/Logger';

/**
 * 本地化标签（/api/i18n/*）：
 * 服务端按用户偏好/Accept-Language 返回工具与内置技能的显示名；
 * 静态缓存 + labelFor 回退原名，供消息气泡工具名等展示使用。
 */
export class I18nService {
  private static toolLabels: Record<string, Object> = {};
  private static skillLabels: Record<string, Object> = {};
  private static loaded: boolean = false;
  private static loading: boolean = false;

  /** 登录后预热一次（失败静默，labelFor 回退原名） */
  static warmup(): void {
    if (I18nService.loaded || I18nService.loading) {
      return;
    }
    I18nService.loading = true;
    const tasks: Array<Promise<void>> = [];
    tasks.push(I18nService.fetchTools());
    tasks.push(I18nService.fetchSkills());
    Promise.all(tasks).then((): void => {
      I18nService.loaded = true;
    }).catch((): void => {
      Log.debug('i18n labels load failed, fallback to raw names');
    }).finally((): void => {
      I18nService.loading = false;
    });
  }

  private static async fetchTools(): Promise<void> {
    const text: string = await HttpClient.getInstance().get('/api/i18n/tools');
    const rec = JsonHelper.parse(text);
    if (rec !== null) {
      const labels = JsonHelper.getRecord(rec, 'labels');
      if (labels !== null) {
        I18nService.toolLabels = labels;
      }
    }
  }

  private static async fetchSkills(): Promise<void> {
    const text: string = await HttpClient.getInstance().get('/api/i18n/skills');
    const rec = JsonHelper.parse(text);
    if (rec !== null) {
      const labels = JsonHelper.getRecord(rec, 'labels');
      if (labels !== null) {
        I18nService.skillLabels = labels;
      }
    }
  }

  /** 工具名 → 本地化显示名（未命中回退原名） */
  static toolLabel(name: string): string {
    if (name === '') {
      return name;
    }
    const value: Object = I18nService.toolLabels[name];
    if (typeof value === 'string' && value !== '') {
      return value;
    }
    return name;
  }

  /** 内置技能 slug → 本地化显示名（未命中回退原名） */
  static skillLabel(name: string): string {
    if (name === '') {
      return name;
    }
    const value: Object = I18nService.skillLabels[name];
    if (typeof value === 'string' && value !== '') {
      return value;
    }
    return name;
  }
}
