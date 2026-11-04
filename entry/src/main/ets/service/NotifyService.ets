import { OctopWsClient } from '../net/WsClient';
import { HttpClient } from '../net/HttpClient';
import { JsonHelper } from '../utils/JsonHelper';
import { UrlUtil } from '../utils/UrlUtil';

/** 通知推送消息（WS dashboard_push 帧） */
export class PushMessage {
  readonly agentId: string;
  readonly threadId: string;
  readonly text: string;
  readonly agentName: string;

  constructor(agentId: string, threadId: string, text: string, agentName: string) {
    this.agentId = agentId;
    this.threadId = threadId;
    this.text = text;
    this.agentName = agentName;
  }
}

/**
 * 通知 WebSocket 单例（/api/notifications/ws?token=）。
 * 服务端仅两种帧：dashboard_push / pong；close 4001=token 无效、1011=服务未就绪。
 * 登录成功后 start()，登出/切服时 stop()；断线自动指数退避重连。
 */
export class NotifyService {
  private static ws: OctopWsClient | null = null;
  private static pushHandler: ((msg: PushMessage) => void) | null = null;
  private static stopped: boolean = true;
  private static reconnectDelayMs: number = 2000;
  private static reconnectTimer: number = -1;

  static setPushHandler(handler: ((msg: PushMessage) => void) | null): void {
    NotifyService.pushHandler = handler;
  }

  static isRunning(): boolean {
    return NotifyService.ws !== null && !NotifyService.stopped;
  }

  /** 登录后启动通知连接 */
  static start(): void {
    NotifyService.stopped = false;
    NotifyService.reconnectDelayMs = 2000;
    NotifyService.connect();
  }

  /** 登出/切服务器时停止并取消重连 */
  static stop(): void {
    NotifyService.stopped = true;
    if (NotifyService.reconnectTimer >= 0) {
      clearTimeout(NotifyService.reconnectTimer);
      NotifyService.reconnectTimer = -1;
    }
    if (NotifyService.ws !== null) {
      NotifyService.ws.close();
      NotifyService.ws = null;
    }
  }

  private static connect(): void {
    if (NotifyService.stopped) {
      return;
    }
    const baseUrl: string = HttpClient.getInstance().getBaseUrl();
    const token: string = HttpClient.getInstance().getToken();
    if (baseUrl === '' || token === '') {
      return;
    }
    const ws = new OctopWsClient();
    NotifyService.ws = ws;
    ws.setTextMessageHandler((text: string): void => {
      const rec = JsonHelper.parse(text);
      if (rec === null) {
        return;
      }
      const type: string = JsonHelper.getString(rec, 'type', '');
      if (type === 'dashboard_push') {
        const handler = NotifyService.pushHandler;
        if (handler !== null) {
          handler(new PushMessage(
            JsonHelper.getString(rec, 'agent_id', ''),
            JsonHelper.getString(rec, 'thread_id', ''),
            JsonHelper.getString(rec, 'text', ''),
            JsonHelper.getString(rec, 'agent_name', '')
          ));
        }
      }
      // pong：忽略
    });
    ws.setClosedHandler((code: number, reason: string): void => {
      if (NotifyService.ws === ws) {
        NotifyService.ws = null;
      }
      if (NotifyService.stopped) {
        return;
      }
      // 4001 token 无效：不重连（等重新登录后 start）
      if (code === 4001) {
        NotifyService.stopped = true;
        return;
      }
      NotifyService.scheduleReconnect();
    });
    ws.connect(`${UrlUtil.httpToWs(baseUrl)}/api/notifications/ws?token=${encodeURIComponent(token)}`)
      .then((): void => {
        if (NotifyService.stopped && NotifyService.ws === ws) {
          ws.close();
          NotifyService.ws = null;
          return;
        }
        NotifyService.reconnectDelayMs = 2000;
      })
      .catch((): void => {
        if (NotifyService.ws === ws) {
          NotifyService.ws = null;
        }
        if (!NotifyService.stopped) {
          NotifyService.scheduleReconnect();
        }
      });
  }

  private static scheduleReconnect(): void {
    if (NotifyService.reconnectTimer >= 0) {
      return;
    }
    const delay: number = NotifyService.reconnectDelayMs;
    NotifyService.reconnectDelayMs = Math.min(delay * 2, 60000);
    NotifyService.reconnectTimer = setTimeout((): void => {
      NotifyService.reconnectTimer = -1;
      NotifyService.connect();
    }, delay);
  }
}
