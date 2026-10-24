/**
 * 会话摘要缓存（内存级，App 重启后失效）：
 * 会话列表副标题展示最后一条消息摘要与消息数，后端 threads 接口无此字段，由聊天页在
 * 流式结束/历史加载时写入。
 */
export class ThreadDigest {
  readonly threadId: string;
  readonly lastText: string;
  readonly count: number;

  constructor(threadId: string, lastText: string, count: number) {
    this.threadId = threadId;
    this.lastText = lastText;
    this.count = count;
  }
}

export class ThreadDigestCache {
  private static readonly map: Map<string, ThreadDigest> = new Map<string, ThreadDigest>();
  private static readonly MAX_TEXT: number = 60;

  static put(threadId: string, lastText: string, count: number): void {
    if (threadId === '') {
      return;
    }
    let text: string = lastText.trim();
    if (text.length > ThreadDigestCache.MAX_TEXT) {
      text = `${text.substring(0, ThreadDigestCache.MAX_TEXT)}…`;
    }
    ThreadDigestCache.map.set(threadId, new ThreadDigest(threadId, text, count));
  }

  static get(threadId: string): ThreadDigest | null {
    const digest = ThreadDigestCache.map.get(threadId);
    return digest === undefined ? null : digest;
  }
}
