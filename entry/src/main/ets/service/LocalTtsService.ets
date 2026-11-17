import { textToSpeech } from '@kit.CoreSpeechKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { TtsSettingsModel, VoiceOptionModel } from '../model/TtsModels';
import { AppPrefs } from '../store/AppPrefs';
import { Log } from '../utils/Logger';

/** 本机朗读回调：驱动消息气泡按钮三态（合成中/播放中停止态/复位）与错误提示 */
export interface LocalTtsCallbacks {
  onStart(): void;
  onComplete(): void;
  onStop(): void;
  onError(message: string): void;
}

/** 当前活动朗读请求登记（SpeakListener 按 requestId 分发到此处回调） */
class ActiveTtsRequest {
  readonly requestId: string;
  readonly callbacks: LocalTtsCallbacks;

  constructor(requestId: string, callbacks: LocalTtsCallbacks) {
    this.requestId = requestId;
    this.callbacks = callbacks;
  }
}

/** CoreSpeechKit textToSpeech 封装：引擎懒创建/复用、设置内存缓存与持久化、单活动请求打断语义 */
export class LocalTtsService {
  /** 单次朗读文本上限（SDK 限制：文本不超过 10000 字符） */
  private static readonly MAX_TEXT_LENGTH: number = 10000;

  private static settings: TtsSettingsModel = TtsSettingsModel.defaults();
  private static loaded: boolean = false;
  private static loading: Promise<void> | null = null;
  private static engine: textToSpeech.TextToSpeechEngine | null = null;
  private static engineCreating: Promise<textToSpeech.TextToSpeechEngine | null> | null = null;
  /** 最近一次 createEngine 失败标记（不可用降级提示用） */
  private static engineUnavailable: boolean = false;
  /** person/online 变更标记：下一次 speak 前重建引擎（两参数仅在 createEngine 时生效） */
  private static engineNeedRebuild: boolean = false;
  private static activeRequest: ActiveTtsRequest | null = null;
  private static requestIdSeq: number = 0;

  /** 幂等：首次调用从 preferences 加载设置到内存缓存，之后 getSettings 同步读 */
  static ensureLoaded(): Promise<void> {
    if (LocalTtsService.loaded) {
      return Promise.resolve();
    }
    const existing = LocalTtsService.loading;
    if (existing !== null) {
      return existing;
    }
    const promise = LocalTtsService.loadSettings();
    LocalTtsService.loading = promise;
    return promise;
  }

  private static async loadSettings(): Promise<void> {
    try {
      const prefs = AppPrefs.getInstance();
      const speed = await prefs.getTtsSpeed();
      const pitch = await prefs.getTtsPitch();
      const volume = await prefs.getTtsVolume();
      const person = await prefs.getTtsPerson();
      const online = await prefs.getTtsOnline();
      LocalTtsService.settings = new TtsSettingsModel(speed, pitch, volume, person, online);
    } catch (e) {
      Log.error('local tts settings load failed, keep defaults');
    } finally {
      LocalTtsService.loaded = true;
      LocalTtsService.loading = null;
    }
  }

  /** 同步读设置缓存（须在 ensureLoaded 后调用），返回防御性拷贝 */
  static getSettings(): TtsSettingsModel {
    return LocalTtsService.settings.copy();
  }

  /** 更新设置：clamp 校验 → 内存缓存 → 落盘；person/online 变化置引擎重建标记 */
  static async setSettings(next: TtsSettingsModel): Promise<void> {
    const clamped: TtsSettingsModel = next.copy();
    const cur = LocalTtsService.settings;
    if (clamped.person !== cur.person || clamped.online !== cur.online) {
      LocalTtsService.engineNeedRebuild = true;
    }
    LocalTtsService.settings = clamped;
    const prefs = AppPrefs.getInstance();
    await prefs.setTtsSpeed(clamped.speed);
    await prefs.setTtsPitch(clamped.pitch);
    await prefs.setTtsVolume(clamped.volume);
    await prefs.setTtsPerson(clamped.person);
    await prefs.setTtsOnline(clamped.online);
  }

  /**
   * 端侧合成并播放（playType=1 引擎自播，无需 AVPlayer）：
   * 打断当前活动请求 → 引擎懒创建（不可用 reject）→ 发起朗读。
   * 状态经 callbacks 回传：onStart（出声）/onComplete（播完）/onStop（停止打断）/onError（失败）。
   */
  static async speak(text: string, callbacks: LocalTtsCallbacks): Promise<void> {
    if (text === '') {
      return;
    }
    let content: string = text;
    if (content.length > LocalTtsService.MAX_TEXT_LENGTH) {
      content = content.substring(0, LocalTtsService.MAX_TEXT_LENGTH);
    }
    // 单活动请求语义：新请求先停旧请求（同步触发旧回调 onStop 复位）
    LocalTtsService.stop();
    const engine = await LocalTtsService.ensureEngine();
    if (engine === null) {
      throw new Error('local tts engine unavailable');
    }
    // ensureEngine await 期间可能有新请求登记，注册前再兜底停一次
    LocalTtsService.stop();
    const requestId: string = LocalTtsService.nextRequestId();
    LocalTtsService.activeRequest = new ActiveTtsRequest(requestId, callbacks);
    const s = LocalTtsService.settings;
    const speakParams: textToSpeech.SpeakParams = {
      requestId: requestId,
      extraParams: {
        'queueMode': 0,
        'speed': s.speed,
        'volume': s.volume,
        'pitch': s.pitch,
        'languageContext': 'zh-CN',
        'audioType': 'pcm',
        'playType': 1
      }
    };
    try {
      engine.speak(content, speakParams);
    } catch (e) {
      // 1002300001：文本为空/超长等参数错误，speak 同步抛出
      const req = LocalTtsService.activeRequest;
      if (req !== null && req.requestId === requestId) {
        LocalTtsService.activeRequest = null;
        callbacks.onError('朗读失败');
      }
      Log.error('local tts speak threw');
    }
  }

  /** 停止当前活动朗读（无活动则空操作）；同步触发旧请求 onStop 回调复位 */
  static stop(): void {
    const engine = LocalTtsService.engine;
    const req = LocalTtsService.activeRequest;
    LocalTtsService.activeRequest = null;
    if (engine !== null) {
      try {
        engine.stop();
      } catch (e) {
        Log.warn('local tts stop failed, ignore');
      }
    }
    if (req !== null) {
      req.callbacks.onStop();
    }
  }

  /** 停止并释放引擎实例（极端兜底用；常规停止用 stop 保留实例复用，规避 3 实例上限） */
  static release(): void {
    LocalTtsService.stop();
    const engine = LocalTtsService.engine;
    LocalTtsService.engine = null;
    LocalTtsService.engineNeedRebuild = false;
    LocalTtsService.engineUnavailable = false;
    LocalTtsService.engineCreating = null;
    if (engine !== null) {
      try {
        engine.shutdown();
      } catch (e) {
        Log.warn('local tts shutdown failed, ignore');
      }
    }
  }

  /** 引擎可用性：canIUse 静态能力 + 最近一次 createEngine 结果 */
  static isEngineAvailable(): boolean {
    if (!canIUse('SystemCapability.AI.TextToSpeech')) {
      return false;
    }
    return LocalTtsService.engine !== null || !LocalTtsService.engineUnavailable;
  }

  /** 查询离线 zh-CN 音色；引擎不可用/查询失败回退静态兜底清单 */
  static async listVoices(): Promise<Array<VoiceOptionModel>> {
    const engine = await LocalTtsService.ensureEngine();
    if (engine === null) {
      return VoiceOptionModel.fallbackList();
    }
    try {
      const query: textToSpeech.VoiceQuery = {
        requestId: LocalTtsService.nextRequestId(),
        online: 1
      };
      const voices: Array<textToSpeech.VoiceInfo> = await engine.listVoices(query);
      const result: Array<VoiceOptionModel> = [];
      for (const info of voices) {
        if (info.language !== 'zh-CN' && info.language !== 'zh_CN') {
          continue;
        }
        let status: string = info.status ?? 'GA';
        if (status === '') {
          status = 'GA';
        }
        const name: string = info.description !== '' ? info.description : `音色 ${info.person}`;
        result.push(new VoiceOptionModel(info.person, name, status));
      }
      if (result.length === 0) {
        return VoiceOptionModel.fallbackList();
      }
      return result;
    } catch (e) {
      Log.warn('local tts listVoices failed, fallback to static voices');
      return VoiceOptionModel.fallbackList();
    }
  }

  /** requestId 仅允许字母/数字/汉字（SDK 约束，不含下划线等符号） */
  private static nextRequestId(): string {
    LocalTtsService.requestIdSeq++;
    return `octop${Date.now()}${LocalTtsService.requestIdSeq}`;
  }

  /** 引擎懒创建/复用：person/online 变更（重建标记）时先 shutdown 旧实例再建新实例 */
  private static ensureEngine(): Promise<textToSpeech.TextToSpeechEngine | null> {
    if (!canIUse('SystemCapability.AI.TextToSpeech')) {
      LocalTtsService.engineUnavailable = true;
      return Promise.resolve(null);
    }
    if (LocalTtsService.engine !== null && !LocalTtsService.engineNeedRebuild) {
      return Promise.resolve(LocalTtsService.engine);
    }
    const existing = LocalTtsService.engineCreating;
    if (existing !== null) {
      return existing;
    }
    const oldEngine = LocalTtsService.engine;
    LocalTtsService.engine = null;
    // 标记在建新实例前同步清除：若创建期间设置又变更，标记会被重新置位，下次 speak 仍会重建
    LocalTtsService.engineNeedRebuild = false;
    if (oldEngine !== null) {
      try {
        oldEngine.shutdown();
      } catch (e) {
        Log.warn('local tts old engine shutdown failed, ignore');
      }
    }
    const s = LocalTtsService.settings;
    const createParams: textToSpeech.CreateEngineParams = {
      language: 'zh-CN',
      person: s.person,
      online: s.online,
      extraParams: {
        'style': 'interaction-broadcast',
        'locate': 'CN',
        'name': 'octop'
      }
    };
    const promise: Promise<textToSpeech.TextToSpeechEngine | null> =
      textToSpeech.createEngine(createParams)
        .then((engine: textToSpeech.TextToSpeechEngine): textToSpeech.TextToSpeechEngine => {
          // SpeakListener 单次注册：按 requestId 分发到当前活动请求回调
          engine.setListener(LocalTtsService.buildListener());
          LocalTtsService.engine = engine;
          LocalTtsService.engineUnavailable = false;
          LocalTtsService.engineCreating = null;
          return engine;
        })
        .catch((e: BusinessError): textToSpeech.TextToSpeechEngine | null => {
          LocalTtsService.engineUnavailable = true;
          LocalTtsService.engineCreating = null;
          Log.error(`local tts createEngine failed: ${e.code}`);
          return null;
        });
    LocalTtsService.engineCreating = promise;
    return promise;
  }

  /** SpeakListener 仅引擎创建时注册一次：按 requestId 分发到当前活动请求回调 */
  private static buildListener(): textToSpeech.SpeakListener {
    const listener: textToSpeech.SpeakListener = {
      onStart: (requestId: string, _response: textToSpeech.StartResponse): void => {
        const req = LocalTtsService.activeRequest;
        if (req !== null && req.requestId === requestId) {
          req.callbacks.onStart();
        }
      },
      onComplete: (requestId: string, response: textToSpeech.CompleteResponse): void => {
        const req = LocalTtsService.activeRequest;
        if (req === null || req.requestId !== requestId) {
          return;
        }
        if (response.type === 1) {
          // 播放完成 → 复位；type=0 仅合成完成（playType=1 引擎自播，等待播放完成回调）
          LocalTtsService.activeRequest = null;
          req.callbacks.onComplete();
        }
      },
      onStop: (requestId: string, _response: textToSpeech.StopResponse): void => {
        // stop() 已同步触发旧回调并清空登记，此处兜底处理引擎侧迟到的 onStop
        const req = LocalTtsService.activeRequest;
        if (req !== null && req.requestId === requestId) {
          LocalTtsService.activeRequest = null;
          req.callbacks.onStop();
        }
      },
      onError: (requestId: string, errorCode: number, errorMessage: string): void => {
        const req = LocalTtsService.activeRequest;
        if (req === null || req.requestId !== requestId) {
          return;
        }
        LocalTtsService.activeRequest = null;
        Log.error(`local tts onError: ${errorCode} ${errorMessage}`);
        req.callbacks.onError('朗读失败');
      }
    };
    return listener;
  }
}
