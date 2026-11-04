import { media } from '@kit.MediaKit';
import { fileIo } from '@kit.CoreFileKit';
import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { Log } from '../utils/Logger';

/**
 * 语音播放封装（TTS 播放）：
 * - 播放：TTS 返回的 wav/mp3 字节落盘后交 AVPlayer 播放，结束/出错/被打断时回调并清理
 */
export class AudioIOService {
  private static player: media.AVPlayer | null = null;
  private static playbackEnd: (() => void) | null = null;
  private static playbackError: (() => void) | null = null;
  private static playbackFailed: boolean = false;
  private static playbackCleanup: (() => void) | null = null;

  /** 停止当前 TTS 播放（播放结束回调仍会触发，便于调用方复位 UI 状态） */
  static stopPlayback(): void {
    AudioIOService.finishPlayback();
  }

  private static finishPlayback(): void {
    const player: media.AVPlayer | null = AudioIOService.player;
    const end: (() => void) | null = AudioIOService.playbackEnd;
    const error: (() => void) | null = AudioIOService.playbackError;
    const failed: boolean = AudioIOService.playbackFailed;
    const cleanup: (() => void) | null = AudioIOService.playbackCleanup;
    AudioIOService.player = null;
    AudioIOService.playbackEnd = null;
    AudioIOService.playbackError = null;
    AudioIOService.playbackFailed = false;
    AudioIOService.playbackCleanup = null;
    if (player !== null) {
      try {
        player.release();
      } catch (ignored) {
      }
    }
    if (cleanup !== null) {
      cleanup();
    }
    if (failed && error !== null) {
      error();
    }
    if (end !== null) {
      end();
    }
  }

  /**
   * 播放 TTS 音频字节（按文件头识别 wav/mp3）：
   * 播放完成、出错或被新的 playTts/stopPlayback 打断时回调 onEnd 并清理临时文件；
   * prepare/play 失败或播放器报错时额外回调 onError（onEnd 仍触发以复位 UI 状态）。
   */
  static async playTts(context: common.Context, data: ArrayBuffer, onEnd: () => void,
    onError?: () => void): Promise<void> {
    AudioIOService.finishPlayback();
    AudioIOService.playbackFailed = false;
    const head: Uint8Array = new Uint8Array(data.slice(0, 4));
    const isWav: boolean =
      head[0] === 0x52 && head[1] === 0x49 && head[2] === 0x46 && head[3] === 0x46;
    const path: string =
      `${context.cacheDir}/tts_${Date.now().toString()}${isWav ? '.wav' : '.mp3'}`;
    const file: fileIo.File = fileIo.openSync(path,
      fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
    fileIo.writeSync(file.fd, data);
    AudioIOService.playbackCleanup = (): void => {
      try {
        fileIo.closeSync(file);
      } catch (ignored) {
      }
      try {
        fileIo.unlinkSync(path);
      } catch (ignored) {
      }
    };
    try {
      const player: media.AVPlayer = await media.createAVPlayer();
      AudioIOService.player = player;
      AudioIOService.playbackEnd = onEnd;
      if (onError !== undefined) {
        AudioIOService.playbackError = onError;
      }
      // url 设置后 idle→initialized 为异步迁移，prepare/play 须由 stateChange 状态机驱动
      player.on('stateChange', (state: media.AVPlayerState, reason: media.StateChangeReason): void => {
        if (state === 'initialized') {
          player.prepare().catch((): void => {
            Log.warn('tts prepare rejected');
            AudioIOService.playbackFailed = true;
            AudioIOService.finishPlayback();
          });
        } else if (state === 'prepared') {
          player.play().catch((): void => {
            Log.warn('tts play rejected');
            AudioIOService.playbackFailed = true;
            AudioIOService.finishPlayback();
          });
        } else if (state === 'completed' || state === 'stopped' || state === 'error' || state === 'released') {
          AudioIOService.finishPlayback();
        }
      });
      player.on('error', (err: BusinessError): void => {
        Log.warn(`tts player error: ${err.code}`);
        AudioIOService.playbackFailed = true;
        AudioIOService.finishPlayback();
      });
      player.url = `fd://${file.fd.toString()}`;
    } catch (e) {
      const err: BusinessError = e as BusinessError;
      Log.warn(`tts play failed: ${err.code} ${err.message} bytes=${data.byteLength} path=${path}`);
      AudioIOService.playbackFailed = true;
      AudioIOService.finishPlayback();
    }
  }
}
