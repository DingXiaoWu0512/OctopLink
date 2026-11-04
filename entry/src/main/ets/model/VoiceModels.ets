import { JsonHelper } from '../utils/JsonHelper';

/** 语音预设（GET /api/voice/presets；id: browser|edge|tencent|openai|mimo-stt|mimo-tts） */
export class VoicePresetModel {
  readonly id: string;
  readonly name: string;
  readonly kind: string; // browser|edge|tencent|openai|mimo
  readonly capability: string; // stt|tts|both
  readonly free: boolean;
  readonly requiresKey: boolean;
  readonly limitedFree: boolean;
  readonly description: string;

  constructor(id: string, name: string, kind: string, capability: string, free: boolean,
    requiresKey: boolean, limitedFree: boolean, description: string) {
    this.id = id;
    this.name = name;
    this.kind = kind;
    this.capability = capability;
    this.free = free;
    this.requiresKey = requiresKey;
    this.limitedFree = limitedFree;
    this.description = description;
  }

  static fromRecord(rec: Record<string, Object>): VoicePresetModel {
    return new VoicePresetModel(
      JsonHelper.getString(rec, 'id', ''),
      JsonHelper.getString(rec, 'name', ''),
      JsonHelper.getString(rec, 'kind', ''),
      JsonHelper.getString(rec, 'capability', ''),
      JsonHelper.getBool(rec, 'free', false),
      JsonHelper.getBool(rec, 'requires_key', false),
      JsonHelper.getBool(rec, 'limited_free', false),
      JsonHelper.getString(rec, 'description', '')
    );
  }

  static parseList(text: string): Array<VoicePresetModel> {
    const result: Array<VoicePresetModel> = [];
    const arr = JsonHelper.parseArray(text);
    if (arr === null) {
      return result;
    }
    for (const rec of arr) {
      result.push(VoicePresetModel.fromRecord(rec));
    }
    return result;
  }
}

/** 自定义语音服务（GET /api/voice/providers） */
export class VoiceProviderModel {
  readonly id: string;
  readonly name: string;
  readonly kind: string;
  readonly capability: string;
  readonly baseUrl: string;
  readonly apiKey: string;
  readonly extraJson: string;
  readonly note: string;
  readonly enabled: boolean;

  constructor(id: string, name: string, kind: string, capability: string, baseUrl: string,
    apiKey: string, extraJson: string, note: string, enabled: boolean) {
    this.id = id;
    this.name = name;
    this.kind = kind;
    this.capability = capability;
    this.baseUrl = baseUrl;
    this.apiKey = apiKey;
    this.extraJson = extraJson;
    this.note = note;
    this.enabled = enabled;
  }

  static fromRecord(rec: Record<string, Object>): VoiceProviderModel {
    const extra: Record<string, Object> | null = JsonHelper.getRecord(rec, 'extra');
    return new VoiceProviderModel(
      JsonHelper.getString(rec, 'id', ''),
      JsonHelper.getString(rec, 'name', ''),
      JsonHelper.getString(rec, 'kind', ''),
      JsonHelper.getString(rec, 'capability', ''),
      JsonHelper.getString(rec, 'base_url', ''),
      JsonHelper.getString(rec, 'api_key', ''),
      extra === null ? '{}' : JSON.stringify(extra),
      JsonHelper.getString(rec, 'note', ''),
      JsonHelper.getBool(rec, 'enabled', true)
    );
  }

  static parseList(text: string): Array<VoiceProviderModel> {
    const result: Array<VoiceProviderModel> = [];
    const arr = JsonHelper.parseArray(text);
    if (arr === null) {
      return result;
    }
    for (const rec of arr) {
      result.push(VoiceProviderModel.fromRecord(rec));
    }
    return result;
  }
}

/** 当前生效语音配置（GET /api/voice/active） */
export class ActiveVoiceModel {
  readonly stt: string;
  readonly tts: string;
  readonly sttRealtime: boolean;

  constructor(stt: string, tts: string, sttRealtime: boolean) {
    this.stt = stt;
    this.tts = tts;
    this.sttRealtime = sttRealtime;
  }

  static parse(text: string): ActiveVoiceModel {
    const rec = JsonHelper.parse(text);
    if (rec === null) {
      return new ActiveVoiceModel('browser', 'browser', false);
    }
    return new ActiveVoiceModel(
      JsonHelper.getString(rec, 'stt', 'browser'),
      JsonHelper.getString(rec, 'tts', 'browser'),
      JsonHelper.getBool(rec, 'stt_realtime', false)
    );
  }
}

/** 语音服务保存入参（POST /api/admin/voice/providers；name 取 preset id） */
export class VoiceProviderInput {
  readonly name: string;
  readonly kind: string;
  readonly capability: string;
  readonly baseUrl: string;
  readonly apiKey: string;
  readonly extraJson: string;
  readonly note: string;

  constructor(name: string, kind: string, capability: string, baseUrl: string,
    apiKey: string, extraJson: string, note: string) {
    this.name = name;
    this.kind = kind;
    this.capability = capability;
    this.baseUrl = baseUrl;
    this.apiKey = apiKey;
    this.extraJson = extraJson;
    this.note = note;
  }

  /** 创建体（含 name；test-configuration 复用，可追加额外字段） */
  toBodyStr(extra: Record<string, Object> | null): string {
    const body: Record<string, Object> = {
      'name': this.name,
      'kind': this.kind,
      'capability': this.capability,
      'extra_json': this.extraJson,
      'note': this.note
    };
    if (this.baseUrl !== '') {
      body['base_url'] = this.baseUrl;
    }
    if (this.apiKey !== '') {
      body['api_key'] = this.apiKey;
    }
    if (extra !== null) {
      const keys: Array<string> = ['mode'];
      for (const key of keys) {
        body[key] = extra[key];
      }
    }
    return JSON.stringify(body);
  }

  /** 更新体（PATCH 不接受 name；空串字段省略以保留旧值） */
  toPatchBodyStr(): string {
    const body: Record<string, Object> = {
      'kind': this.kind,
      'capability': this.capability,
      'extra_json': this.extraJson,
      'note': this.note
    };
    if (this.baseUrl !== '') {
      body['base_url'] = this.baseUrl;
    }
    if (this.apiKey !== '') {
      body['api_key'] = this.apiKey;
    }
    return JSON.stringify(body);
  }
}

/** 连通性测试结果（POST .../test 或 .../test-configuration → {ok, error?}） */
export class VoiceTestResultModel {
  readonly ok: boolean;
  readonly error: string;

  constructor(ok: boolean, error: string) {
    this.ok = ok;
    this.error = error;
  }

  static parse(text: string): VoiceTestResultModel {
    const rec = JsonHelper.parse(text);
    if (rec === null) {
      return new VoiceTestResultModel(false, '响应解析失败');
    }
    return new VoiceTestResultModel(
      JsonHelper.getBool(rec, 'ok', false),
      JsonHelper.getString(rec, 'error', '')
    );
  }
}
