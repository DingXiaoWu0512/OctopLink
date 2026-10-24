/**
 * JSON 解析辅助：所有来自网络的 JSON 均先转为 Record<string, Object>，
 * 再通过本类的类型安全取值方法读取字段，避免使用 any/断言散落各处。
 */
export class JsonHelper {
  /** 将不透明对象归一化为 Record，失败返回 null */
  static toRecord(value: Object | undefined | null): Record<string, Object> | null {
    if (value === null || value === undefined || typeof value !== 'object' || Array.isArray(value)) {
      return null;
    }
    return value as Record<string, Object>;
  }

  /** 解析 JSON 文本为 Record，失败返回 null */
  static parse(text: string): Record<string, Object> | null {
    try {
      const parsed: Object | null = JSON.parse(text);
      return JsonHelper.toRecord(parsed);
    } catch (e) {
      return null;
    }
  }

  /** 解析 JSON 文本为 Record 数组（顶层为数组），失败返回 null */
  static parseArray(text: string): Array<Record<string, Object>> | null {
    try {
      const parsed: Object | null = JSON.parse(text);
      if (parsed === null || !Array.isArray(parsed)) {
        return null;
      }
      const result: Array<Record<string, Object>> = [];
      const arr: Object[] = parsed as Object[];
      for (let i = 0; i < arr.length; i++) {
        const item: Record<string, Object> | null = JsonHelper.toRecord(arr[i]);
        if (item !== null) {
          result.push(item);
        }
      }
      return result;
    } catch (e) {
      return null;
    }
  }

  /** 取子对象 */
  static getRecord(rec: Record<string, Object> | null, key: string): Record<string, Object> | null {
    if (rec === null) {
      return null;
    }
    return JsonHelper.toRecord(rec[key]);
  }

  /** 取字符串，缺失或类型不符时返回默认值 */
  static getString(rec: Record<string, Object> | null, key: string, def: string): string {
    if (rec === null) {
      return def;
    }
    const value: Object | undefined = rec[key];
    if (typeof value === 'string') {
      return value;
    }
    if (typeof value === 'number' || typeof value === 'boolean') {
      return `${value}`;
    }
    return def;
  }

  /** 取数值，缺失或类型不符时返回默认值 */
  static getNumber(rec: Record<string, Object> | null, key: string, def: number): number {
    if (rec === null) {
      return def;
    }
    const value: Object | undefined = rec[key];
    if (typeof value === 'number') {
      return value;
    }
    return def;
  }

  /** 取布尔，缺失或类型不符时返回默认值 */
  static getBool(rec: Record<string, Object> | null, key: string, def: boolean): boolean {
    if (rec === null) {
      return def;
    }
    const value: Object | undefined = rec[key];
    if (typeof value === 'boolean') {
      return value;
    }
    return def;
  }

  /** 取可空数字：null/缺失/类型不符时返回 def（用于 token_quota 等可空字段） */
  static getOptionalNumber(rec: Record<string, Object> | null, key: string, def: number): number {
    return JsonHelper.getNumber(rec, key, def);
  }

  /** 取 Record 数组字段 */
  static getRecordArray(rec: Record<string, Object> | null, key: string): Array<Record<string, Object>> {
    const result: Array<Record<string, Object>> = [];
    if (rec === null) {
      return result;
    }
    const value: Object | undefined = rec[key];
    if (value === undefined || value === null || !Array.isArray(value)) {
      return result;
    }
    const arr: Object[] = value as Object[];
    for (let i = 0; i < arr.length; i++) {
      const item: Record<string, Object> | null = JsonHelper.toRecord(arr[i]);
      if (item !== null) {
        result.push(item);
      }
    }
    return result;
  }

  /** 将秒/毫秒数值或 ISO 字符串统一归一化为毫秒时间戳，失败返回 0 */
  static toMs(value: Object | undefined): number {
    if (typeof value === 'number') {
      return value > 1000000000000 ? value : value * 1000;
    }
    if (typeof value === 'string' && value !== '') {
      const parsed: number = Date.parse(value);
      return parsed !== parsed ? 0 : parsed;
    }
    return 0;
  }

  /** 取字符串数组字段 */
  static getStringArray(rec: Record<string, Object> | null, key: string): Array<string> {
    const result: Array<string> = [];
    if (rec === null) {
      return result;
    }
    const value: Object | undefined = rec[key];
    if (value === undefined || value === null || !Array.isArray(value)) {
      return result;
    }
    const arr: Object[] = value as Object[];
    for (let i = 0; i < arr.length; i++) {
      const item: Object = arr[i];
      if (typeof item === 'string') {
        result.push(item);
      }
    }
    return result;
  }
}
