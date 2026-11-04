import { HttpClient } from '../net/HttpClient';
import { JsonHelper } from '../utils/JsonHelper';
import {
  ActiveVoiceModel,
  VoicePresetModel,
  VoiceProviderInput,
  VoiceProviderModel,
  VoiceTestResultModel
} from '../model/VoiceModels';

/** 语音 TTS（/api/voice/*，源 voice.py；TTS 返回原始音频字节流） */
export class VoiceService {
  static async presets(): Promise<Array<VoicePresetModel>> {
    const text: string = await HttpClient.getInstance().get('/api/voice/presets');
    return VoicePresetModel.parseList(text);
  }

  static async providers(): Promise<Array<VoiceProviderModel>> {
    const text: string = await HttpClient.getInstance().get('/api/voice/providers');
    return VoiceProviderModel.parseList(text);
  }

  static async active(): Promise<ActiveVoiceModel> {
    const text: string = await HttpClient.getInstance().get('/api/voice/active');
    return ActiveVoiceModel.parse(text);
  }

  /** 切换生效 STT/TTS（名称为 provider 名或内置 preset id） */
  static async putActive(stt: string | null, tts: string | null): Promise<ActiveVoiceModel> {
    const body: Record<string, Object> = {};
    if (stt !== null) {
      body['stt'] = stt;
    }
    if (tts !== null) {
      body['tts'] = tts;
    }
    const text: string =
      await HttpClient.getInstance().put('/api/voice/active', JSON.stringify(body));
    return ActiveVoiceModel.parse(text);
  }

  /** 语音合成（返回音频字节：mimo → audio/wav，其余 → audio/mpeg） */
  static async tts(text: string, voiceId: string = '',
    speed: number = 1.0): Promise<ArrayBuffer> {
    // 服务器 TTSBody 限制：text 1~8000 字符、speed 0.5~2.0，超限返回 422
    const clipped: string = text.length > 8000 ? text.substring(0, 8000) : text;
    const safeSpeed: number = Math.min(Math.max(speed, 0.5), 2.0);
    const body: Record<string, Object> = {
      'text': clipped,
      'speed': safeSpeed
    };
    if (voiceId !== '') {
      body['voice_id'] = voiceId;
    }
    return await HttpClient.getInstance().postForBytes('/api/voice/tts', JSON.stringify(body));
  }

  /** 新建语音服务（POST /api/admin/voice/providers，需 voice 权限） */
  static async createProvider(input: VoiceProviderInput): Promise<VoiceProviderModel> {
    const text: string = await HttpClient.getInstance().post(
      '/api/admin/voice/providers', input.toBodyStr(null));
    const rec = JsonHelper.parse(text);
    if (rec === null) {
      throw new Error('voice provider create response parse failed');
    }
    return VoiceProviderModel.fromRecord(rec);
  }

  /** 更新语音服务（PATCH /api/admin/voice/providers/{id}，需 voice 权限） */
  static async patchProvider(providerId: string,
    input: VoiceProviderInput): Promise<VoiceProviderModel> {
    const text: string = await HttpClient.getInstance().patch(
      `/api/admin/voice/providers/${providerId}`, input.toPatchBodyStr());
    const rec = JsonHelper.parse(text);
    if (rec === null) {
      throw new Error('voice provider patch response parse failed');
    }
    return VoiceProviderModel.fromRecord(rec);
  }

  /** 未保存配置的连通性测试（POST .../providers/test-configuration，需 voice 权限） */
  static async testConfiguration(input: VoiceProviderInput,
    mode: string): Promise<VoiceTestResultModel> {
    const extra: Record<string, Object> = { 'mode': mode };
    const text: string = await HttpClient.getInstance().post(
      '/api/admin/voice/providers/test-configuration', input.toBodyStr(extra));
    return VoiceTestResultModel.parse(text);
  }
}
