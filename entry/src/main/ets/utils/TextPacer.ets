/**
 * 通用打字机缓冲器（纯逻辑类，无 ArkUI 依赖）。
 *
 * 流式 delta 帧按网络批次到达，直连落盘会"停顿后整段跳出"（一堆一堆跳）。
 * TextPacer 将 delta 先入缓冲，由定频 tick 小步落盘：
 * 每 tick 输出 min(16, 2 + ceil(积压量/8)) 字——积压小时稳定慢速打字，
 * 积压大时渐进加速追赶（上限 16 字/tick），永不整段跳跃。
 *
 * 三入口：
 * - push(delta)：入缓冲并确保定时器运行（空串直接返回）
 * - finish()：停表并将剩余缓冲整体一次性落盘（收尾全量，零丢失）
 * - cancel()：停表并丢弃缓冲（切会话/切专家防串写）
 *
 * 定时器使用 ArkTS 全局 setInterval/clearInterval（返回 number，-1 表示未运行）。
 */
export class TextPacer {
  /** 待落盘缓冲（未落盘的 delta 累积） */
  private buffer: string = '';
  /** 定时器 id（-1 表示未运行） */
  private timerId: number = -1;
  /** tick 间隔（ms），40ms ≈ 25 次/秒落盘 */
  private readonly intervalMs: number;
  /** 落盘回调：接收本 tick/finish 释放的文本块 */
  private readonly onFlush: (chunk: string) => void;

  constructor(intervalMs: number, onFlush: (chunk: string) => void) {
    this.intervalMs = intervalMs;
    this.onFlush = onFlush;
  }

  /** delta 入缓冲；定时器未运行时启动 tick */
  push(delta: string): void {
    if (delta === '') {
      return;
    }
    this.buffer += delta;
    if (this.timerId === -1) {
      this.timerId = setInterval((): void => {
        this.tick();
      }, this.intervalMs);
    }
  }

  /** 收尾全量落盘：停表后剩余缓冲整体一次性 onFlush（零丢失） */
  finish(): void {
    this.stopTimer();
    if (this.buffer !== '') {
      const chunk: string = this.buffer;
      this.buffer = '';
      this.onFlush(chunk);
    }
  }

  /** 停表并丢弃缓冲（防跨会话串写） */
  cancel(): void {
    this.stopTimer();
    this.buffer = '';
  }

  /** 停止定时器（幂等：未运行时无操作） */
  private stopTimer(): void {
    if (this.timerId !== -1) {
      clearInterval(this.timerId);
      this.timerId = -1;
    }
  }

  /** 定频 tick：自适应落盘 n = min(16, 2 + ceil(积压/8))，再以缓冲长度封顶；排空后停表 */
  private tick(): void {
    if (this.buffer === '') {
      this.stopTimer();
      return;
    }
    let n: number = Math.min(16, 2 + Math.ceil(this.buffer.length / 8));
    n = Math.min(n, this.buffer.length);
    const chunk: string = this.buffer.substring(0, n);
    this.buffer = this.buffer.substring(n);
    this.onFlush(chunk);
    if (this.buffer === '') {
      this.stopTimer();
    }
  }
}
