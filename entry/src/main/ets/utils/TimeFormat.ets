export class TimeFormat {
  private static pad(n: number): string {
    return n < 10 ? `0${n}` : `${n}`;
  }

  /** 消息气泡内时间：HH:mm（入参为毫秒时间戳） */
  static short(tsMs: number): string {
    if (tsMs <= 0) {
      return '';
    }
    const date = new Date(tsMs);
    return `${TimeFormat.pad(date.getHours())}:${TimeFormat.pad(date.getMinutes())}`;
  }

  /** 会话列表时间：今天显示 HH:mm，今年显示 MM-dd，更早显示 yyyy-MM-dd */
  static list(tsMs: number): string {
    if (tsMs <= 0) {
      return '';
    }
    const date = new Date(tsMs);
    const now = new Date();
    const sameDay: boolean = date.getFullYear() === now.getFullYear() &&
      date.getMonth() === now.getMonth() && date.getDate() === now.getDate();
    if (sameDay) {
      return TimeFormat.short(tsMs);
    }
    if (date.getFullYear() === now.getFullYear()) {
      return `${TimeFormat.pad(date.getMonth() + 1)}-${TimeFormat.pad(date.getDate())}`;
    }
    return `${date.getFullYear()}-${TimeFormat.pad(date.getMonth() + 1)}-${TimeFormat.pad(date.getDate())}`;
  }

  /** 完整时间：yyyy-MM-dd HH:mm */
  static full(tsMs: number): string {
    if (tsMs <= 0) {
      return '';
    }
    const date = new Date(tsMs);
    return `${date.getFullYear()}-${TimeFormat.pad(date.getMonth() + 1)}-${TimeFormat.pad(date.getDate())} ` +
      `${TimeFormat.pad(date.getHours())}:${TimeFormat.pad(date.getMinutes())}`;
  }
}
