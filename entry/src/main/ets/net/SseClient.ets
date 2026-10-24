import { http } from '@kit.NetworkKit';
import { util } from '@kit.ArkTS';

/**
 * 简易 SSE 客户端：POST + requestInStream 流式读取。
 * 按 `data:` 行回调帧 JSON 文本，支持跨 chunk 的事件分帧。
 */
export class SseClient {
  private request: http.HttpRequest | null = null;
  private decoder: util.TextDecoder = util.TextDecoder.create('utf-8');
  private buffer: string = '';
  private aborted: boolean = false;

  /**
   * 发起 SSE POST 请求，流式回调每帧 data 载荷；
   * Promise 在整个响应结束后以 HTTP 状态码 resolve。
   */
  async post(url: string, headers: Record<string, string>, bodyStr: string,
    onFrame: (data: string) => void): Promise<number> {
    const req = http.createHttp();
    this.request = req;
    req.on('dataReceive', (chunk: ArrayBuffer): void => {
      if (this.aborted) {
        return;
      }
      const piece: string = this.decoder.decodeWithStream(new Uint8Array(chunk), { stream: true });
      this.buffer += piece.replace(/\r\n/g, '\n');
      this.drainBuffer(onFrame);
    });
    try {
      const options: http.HttpRequestOptions = {
        method: http.RequestMethod.POST,
        header: headers,
        extraData: bodyStr,
        expectDataType: http.HttpDataType.STRING,
        connectTimeout: 10000,
        readTimeout: 300000,
        usingCache: false
      };
      const code: number = await req.requestInStream(url, options);
      this.flushRemaining(onFrame);
      return code;
    } finally {
      req.destroy();
      this.request = null;
    }
  }

  abort(): void {
    this.aborted = true;
    const req = this.request;
    if (req !== null) {
      req.destroy();
      this.request = null;
    }
  }

  /** 按 \n\n 分帧；未完成的块留在缓冲区 */
  private drainBuffer(onFrame: (data: string) => void): void {
    let idx: number = this.buffer.indexOf('\n\n');
    while (idx >= 0) {
      const block: string = this.buffer.substring(0, idx);
      this.buffer = this.buffer.substring(idx + 2);
      this.emitBlock(block, onFrame);
      idx = this.buffer.indexOf('\n\n');
    }
  }

  private flushRemaining(onFrame: (data: string) => void): void {
    const rest: string = this.buffer;
    this.buffer = '';
    if (rest.trim() !== '') {
      this.emitBlock(rest, onFrame);
    }
  }

  /** 解析单个 SSE 事件块，提取 data: 行载荷 */
  private emitBlock(block: string, onFrame: (data: string) => void): void {
    const lines: Array<string> = block.split('\n');
    for (let i = 0; i < lines.length; i++) {
      const line: string = lines[i];
      if (line.startsWith('data:')) {
        const payload: string = line.substring(5).trim();
        if (payload !== '') {
          onFrame(payload);
        }
      }
    }
  }
}
