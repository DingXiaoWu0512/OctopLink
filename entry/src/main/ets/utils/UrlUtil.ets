export class UrlUtil {
  /** 将 http(s) 地址转换为 ws(s) 地址 */
  static httpToWs(baseUrl: string): string {
    if (baseUrl.startsWith('https://')) {
      return `wss://${baseUrl.substring('https://'.length)}`;
    }
    if (baseUrl.startsWith('http://')) {
      return `ws://${baseUrl.substring('http://'.length)}`;
    }
    return baseUrl;
  }

  /** 归一化服务器地址：补协议、去尾部斜杠 */
  static normalizeServerUrl(raw: string): string {
    let url: string = raw.trim();
    if (url === '') {
      return '';
    }
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      url = `http://${url}`;
    }
    while (url.endsWith('/')) {
      url = url.substring(0, url.length - 1);
    }
    return url;
  }
}
