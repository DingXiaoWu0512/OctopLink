import { webSocket } from '@kit.NetworkKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { OctopApiError } from './HttpClient';
import { Log } from '../utils/Logger';

const PING_INTERVAL_MS = 30000;
const PING_FRAME = '{"type":"ping"}';
const ALIVE_TIMEOUT_MS = 75000;

/**
 * WebSocket 封装：连接、心跳（30s ping）、存活看门狗（超时强制断开）、文本帧收发、关闭回调。
 * 连接阶段的失败以 Promise reject 表达；运行期断开通过 closedHandler 通知。
 */
export class OctopWsClient {
  private ws: webSocket.WebSocket | null = null;
  private pingTimer: number = -1;
  private lastAliveMs: number = 0;
  private textMessageHandler: ((text: string) => void) | null = null;
  private closedHandler: ((code: number, reason: string) => void) | null = null;

  isConnected(): boolean {
    return this.ws !== null;
  }

  setTextMessageHandler(handler: (text: string) => void): void {
    this.textMessageHandler = handler;
  }

  setClosedHandler(handler: (code: number, reason: string) => void): void {
    this.closedHandler = handler;
  }

  async connect(url: string): Promise<void> {
    this.closeInternal();
    const ws = webSocket.createWebSocket();
    this.ws = ws;
    return new Promise<void>((resolve: () => void, reject: (error: OctopApiError) => void) => {
      let settled = false;
      ws.on('open', (err: BusinessError, value: Object) => {
        if (settled) {
          return;
        }
        settled = true;
        this.startPing();
        resolve();
      });
      ws.on('message', (err: BusinessError, value: string | ArrayBuffer) => {
        this.lastAliveMs = Date.now();
        if (typeof value === 'string' && this.textMessageHandler !== null) {
          this.textMessageHandler(value);
        }
      });
      ws.on('close', (err: BusinessError, value: webSocket.CloseResult) => {
        this.stopPing();
        if (this.ws === ws) {
          this.ws = null;
        }
        if (!settled) {
          settled = true;
          reject(new OctopApiError(`连接已关闭：${value.code} ${value.reason}`, 0, 'WS_CLOSED'));
          return;
        }
        Log.warn(`WS closed: ${value.code} ${value.reason}`);
        if (this.closedHandler !== null) {
          this.closedHandler(value.code, value.reason);
        }
      });
      ws.on('error', (err: BusinessError) => {
        Log.error(`WS error: ${err.message}`);
      });
      ws.connect(url, (err: BusinessError, value: boolean) => {
        if (err) {
          if (!settled) {
            settled = true;
            reject(new OctopApiError('WebSocket 连接失败', 0, 'WS_CONNECT_FAILED'));
          }
        }
      });
    });
  }

  async send(text: string): Promise<void> {
    const ws = this.ws;
    if (ws === null) {
      throw new OctopApiError('连接未就绪', 0, 'WS_NOT_CONNECTED');
    }
    try {
      await ws.send(text);
    } catch (e) {
      throw new OctopApiError('消息发送失败', 0, 'WS_SEND_FAILED');
    }
  }

  close(): void {
    this.closeInternal();
  }

  private closeInternal(): void {
    this.stopPing();
    const ws = this.ws;
    this.ws = null;
    if (ws === null) {
      return;
    }
    try {
      ws.off('open');
    } catch (e) {
    }
    try {
      ws.off('message');
    } catch (e) {
    }
    try {
      ws.off('close');
    } catch (e) {
    }
    try {
      ws.off('error');
    } catch (e) {
    }
    try {
      ws.close();
    } catch (e) {
    }
  }

  private startPing(): void {
    this.stopPing();
    this.lastAliveMs = Date.now();
    this.pingTimer = setInterval(() => {
      this.send(PING_FRAME).catch((): void => {
      });
      // 存活看门狗：超过阈值未收到任何消息视为半开连接，强制断开交给上层重连
      if (Date.now() - this.lastAliveMs > ALIVE_TIMEOUT_MS) {
        Log.warn('WS alive watchdog triggered, forcing close');
        this.forceClose();
      }
    }, PING_INTERVAL_MS);
  }

  private stopPing(): void {
    if (this.pingTimer !== -1) {
      clearInterval(this.pingTimer);
      this.pingTimer = -1;
    }
  }

  /** 看门狗超时强制断开：按运行期断开通知 closedHandler（触发上层重连） */
  private forceClose(): void {
    this.closeInternal();
    if (this.closedHandler !== null) {
      this.closedHandler(4000, 'alive timeout');
    }
  }
}
