/** TTS 后端选择与本机引擎参数模型（App 级全局、preferences 持久化） */
export class TtsSettingsModel {
  /** 本机引擎后端（CoreSpeechKit 端侧合成，零流量） */
  static readonly BACKEND_LOCAL: string = 'local';
  /** 服务器 TTS 后端（既有 VoiceService 链路） */
  static readonly BACKEND_SERVER: string = 'server';

  /** 当前朗读后端：'local' | 'server' */
  backend: string;
  /** 语速 0.5-2.0，步进 0.05 */
  speed: number;
  /** 音调 0.5-2.0，步进 0.05 */
  pitch: number;
  /** 音量 0-2，步进 0.1 */
  volume: number;
  /** 音色 ID（zh-CN：13 玲小姗 / 21 玲飞哲 / 0 默认女声） */
  person: number;
  /** 合成模式：1=离线（受支持）| 0=在线（引擎暂不支持） */
  online: number;

  constructor(backend: string, speed: number, pitch: number, volume: number, person: number, online: number) {
    this.backend = backend === TtsSettingsModel.BACKEND_LOCAL ?
      TtsSettingsModel.BACKEND_LOCAL : TtsSettingsModel.BACKEND_SERVER;
    this.speed = TtsSettingsModel.clamp(speed, 0.5, 2.0, 1.0);
    this.pitch = TtsSettingsModel.clamp(pitch, 0.5, 2.0, 1.0);
    this.volume = TtsSettingsModel.clamp(volume, 0, 2, 2);
    this.person = Math.round(TtsSettingsModel.clamp(person, 0, 9999, 13));
    this.online = online === 0 ? 0 : 1;
  }

  /** 默认设置（backend='server'，存量用户行为零变化） */
  static defaults(): TtsSettingsModel {
    return new TtsSettingsModel(TtsSettingsModel.BACKEND_SERVER, 1.0, 1.0, 2, 13, 1);
  }

  /** 数值归一：NaN 回退默认值，越界取边界 */
  private static clamp(value: number, min: number, max: number, def: number): number {
    if (Number.isNaN(value)) {
      return def;
    }
    return Math.min(max, Math.max(min, value));
  }

  isLocal(): boolean {
    return this.backend === TtsSettingsModel.BACKEND_LOCAL;
  }

  /** 防御性拷贝（调用方修改不影响服务内存缓存） */
  copy(): TtsSettingsModel {
    return new TtsSettingsModel(this.backend, this.speed, this.pitch, this.volume, this.person, this.online);
  }
}

/** 音色选项（配置面板列表项） */
export class VoiceOptionModel {
  /** 音色 ID */
  person: number;
  /** 展示名（如「玲小姗·女声·推荐」） */
  displayName: string;
  /** 状态：'INSTALLED' 已安装可选 | 'GA' 可下载 | 'EOM' 不可用 */
  status: string;

  constructor(person: number, displayName: string, status: string) {
    this.person = person;
    this.displayName = displayName;
    this.status = status;
  }

  isInstalled(): boolean {
    return this.status === 'INSTALLED';
  }

  isUnavailable(): boolean {
    return this.status === 'EOM';
  }

  /** 静态兜底音色清单（引擎不可用/查询失败时配置面板不空白） */
  static fallbackList(): Array<VoiceOptionModel> {
    const list: Array<VoiceOptionModel> = [];
    list.push(new VoiceOptionModel(13, '玲小姗·女声·推荐', 'INSTALLED'));
    list.push(new VoiceOptionModel(21, '玲飞哲·男声·需下载', 'GA'));
    list.push(new VoiceOptionModel(0, '默认女声', 'INSTALLED'));
    return list;
  }
}
