import { http } from '@kit.NetworkKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { JsonHelper } from '../utils/JsonHelper';
import { Log } from '../utils/Logger';
import { TokenVault } from '../store/TokenVault';

/** 统一业务错误：携带 HTTP 状态码与 Octop ErrorCode */
export class OctopApiError extends Error {
  readonly status: number;
  readonly code: string;

  constructor(message: string, status: number, code: string) {
    super(message);
    this.name = 'OctopApiError';
    this.status = status;
    this.code = code;
  }
}

const HEADER_RENEWED_TOKEN = 'X-Octop-Access-Token';
const HEADER_RENEWED_TOKEN_LOWER = 'x-octop-access-token';

/**
 * Octop REST 客户端（单例）：
 * - 自动注入 Bearer Token
 * - 解析统一错误包络 {"error":{code,message,details}}
 * - 处理 X-Octop-Access-Token 滑动续期
 * - 401（非登录接口）触发全局登出回调
 */
export class HttpClient {
  private static instance: HttpClient | null = null;
  private baseUrl: string = '';
  private token: string = '';
  private unauthorizedHandler: (() => void) | null = null;

  static getInstance(): HttpClient {
    if (HttpClient.instance === null) {
      HttpClient.instance = new HttpClient();
    }
    return HttpClient.instance;
  }

  setBaseUrl(url: string): void {
    let normalized: string = url.trim();
    while (normalized.endsWith('/')) {
      normalized = normalized.substring(0, normalized.length - 1);
    }
    this.baseUrl = normalized;
  }

  getBaseUrl(): string {
    return this.baseUrl;
  }

  setToken(token: string): void {
    this.token = token;
  }

  getToken(): string {
    return this.token;
  }

  setUnauthorizedHandler(handler: () => void): void {
    this.unauthorizedHandler = handler;
  }

  async get(path: string, extraHeaders?: Record<string, string>): Promise<string> {
    return await this.request(path, http.RequestMethod.GET, null, extraHeaders);
  }

  async post(path: string, bodyStr: string | null, extraHeaders?: Record<string, string>): Promise<string> {
    return await this.request(path, http.RequestMethod.POST, bodyStr, extraHeaders);
  }

  async patch(path: string, bodyStr: string | null, extraHeaders?: Record<string, string>): Promise<string> {
    return await this.request(path, http.RequestMethod.PATCH, bodyStr, extraHeaders);
  }

  async put(path: string, bodyStr: string | null, extraHeaders?: Record<string, string>): Promise<string> {
    return await this.request(path, http.RequestMethod.PUT, bodyStr, extraHeaders);
  }

  async delete(path: string, extraHeaders?: Record<string, string>): Promise<string> {
    return await this.request(path, http.RequestMethod.DELETE, null, extraHeaders);
  }

  /** multipart/form-data 文件上传（multiFormDataList 由网络栈自动设置边界）；formFields 为附加普通表单字段 */
  async postMultipartFile(path: string, fieldName: string, fileName: string, contentType: string,
    data: ArrayBuffer, formFields?: Record<string, string>): Promise<string> {
    if (this.baseUrl === '') {
      throw new OctopApiError('服务器地址未配置', 0, 'NO_SERVER');
    }
    const client = http.createHttp();
    try {
      const header: Record<string, string> = {
        'Accept': 'application/json'
      };
      if (this.token !== '') {
        header['Authorization'] = `Bearer ${this.token}`;
      }
      const formItems: Array<http.MultiFormData> = [{
        name: fieldName,
        contentType: contentType,
        remoteFileName: fileName,
        data: data
      }];
      if (formFields !== undefined) {
        const keys: Array<string> = Object.keys(formFields);
        for (const k of keys) {
          formItems.push({
            name: k,
            contentType: 'text/plain',
            data: formFields[k]
          });
        }
      }
      const options: http.HttpRequestOptions = {
        method: http.RequestMethod.POST,
        header: header,
        multiFormDataList: formItems,
        expectDataType: http.HttpDataType.STRING,
        connectTimeout: 10000,
        readTimeout: 120000,
        usingCache: false
      };
      const startTime: number = Date.now();
      const resp: http.HttpResponse = await client.request(`${this.baseUrl}${path}`, options);
      Log.debug(`POST(multipart) ${path} -> ${resp.responseCode} (${Date.now() - startTime}ms)`);
      this.maybeRenewToken(resp.header);
      const status: number = resp.responseCode;
      const body: string = typeof resp.result === 'string' ? resp.result : '';
      if (status >= 200 && status < 300) {
        return body;
      }
      throw HttpClient.buildApiError(status, body, path, this.token);
    } catch (e) {
      if (e instanceof OctopApiError) {
        throw e;
      }
      const err = e as BusinessError;
      Log.error(`HTTP POST(multipart) ${path} failed: ${err.code} ${err.message}`);
      throw new OctopApiError('无法连接服务器，请检查网络与地址', 0, 'NETWORK_ERROR');
    } finally {
      client.destroy();
    }
  }

  /** 二进制下载（GET，返回原始字节；错误响应仍走统一包络解析） */
  async downloadGet(path: string): Promise<ArrayBuffer> {
    if (this.baseUrl === '') {
      throw new OctopApiError('服务器地址未配置', 0, 'NO_SERVER');
    }
    const client = http.createHttp();
    try {
      const header: Record<string, string> = {
        'Accept': '*/*'
      };
      if (this.token !== '') {
        header['Authorization'] = `Bearer ${this.token}`;
      }
      const options: http.HttpRequestOptions = {
        method: http.RequestMethod.GET,
        header: header,
        expectDataType: http.HttpDataType.ARRAY_BUFFER,
        connectTimeout: 10000,
        readTimeout: 120000,
        usingCache: false
      };
      const resp: http.HttpResponse = await client.request(`${this.baseUrl}${path}`, options);
      this.maybeRenewToken(resp.header);
      const status: number = resp.responseCode;
      if (status >= 200 && status < 300) {
        if (resp.result instanceof ArrayBuffer) {
          return resp.result;
        }
        return new ArrayBuffer(0);
      }
      const raw: Object = resp.result;
      const body: string = typeof raw === 'string' ? raw : '';
      throw HttpClient.buildApiError(status, body, path, this.token);
    } catch (e) {
      if (e instanceof OctopApiError) {
        throw e;
      }
      const err = e as BusinessError;
      Log.error(`HTTP GET(binary) ${path} failed: ${err.code} ${err.message}`);
      throw new OctopApiError('无法连接服务器，请检查网络与地址', 0, 'NETWORK_ERROR');
    } finally {
      client.destroy();
    }
  }

  async request(path: string, method: http.RequestMethod, bodyStr: string | null,
    extraHeaders?: Record<string, string>): Promise<string> {
    if (this.baseUrl === '') {
      throw new OctopApiError('服务器地址未配置', 0, 'NO_SERVER');
    }
    const client = http.createHttp();
    try {
      const header: Record<string, string> = {
        'Content-Type': 'application/json',
        'Accept': 'application/json'
      };
      if (extraHeaders !== undefined) {
        const keys: Array<string> = Object.keys(extraHeaders);
        for (const k of keys) {
          header[k] = extraHeaders[k];
        }
      }
      if (this.token !== '') {
        header['Authorization'] = `Bearer ${this.token}`;
      }
      const options: http.HttpRequestOptions = {
        method: method,
        header: header,
        extraData: bodyStr === null ? undefined : bodyStr,
        expectDataType: http.HttpDataType.STRING,
        connectTimeout: 10000,
        readTimeout: 30000,
        usingCache: false
      };
      const startTime: number = Date.now();
      const resp: http.HttpResponse = await client.request(`${this.baseUrl}${path}`, options);
      Log.debug(`${method} ${path} -> ${resp.responseCode} (${Date.now() - startTime}ms)`);
      this.maybeRenewToken(resp.header);
      const status: number = resp.responseCode;
      const body: string = typeof resp.result === 'string' ? resp.result : '';
      if (status >= 200 && status < 300) {
        return body;
      }
      throw HttpClient.buildApiError(status, body, path, this.token);
    } catch (e) {
      if (e instanceof OctopApiError) {
        throw e;
      }
      const err = e as BusinessError;
      Log.error(`HTTP ${method} ${path} failed: ${err.code} ${err.message}`);
      throw new OctopApiError('无法连接服务器，请检查网络与地址', 0, 'NETWORK_ERROR');
    } finally {
      client.destroy();
    }
  }

  /** 解析错误包络并生成异常；登录外的 401 触发全局登出 */
  static buildApiError(status: number, body: string, path: string, token: string): OctopApiError {
    const rec = JsonHelper.parse(body);
    let message: string = '';
    let code: string = '';
    if (rec !== null) {
      const errRec = JsonHelper.getRecord(rec, 'error');
      if (errRec !== null) {
        code = JsonHelper.getString(errRec, 'code', '');
        message = JsonHelper.getString(errRec, 'message', '');
      } else {
        // 兼容 FastAPI 默认 {"detail":"..."} 包络
        message = JsonHelper.getString(rec, 'detail', '');
      }
    }
    if (message === '') {
      message = status === 401 ? '登录已过期，请重新登录' : `请求失败 (${status})`;
    }
    if (status === 401 && path !== '/api/auth/login' && token !== '') {
      const client = HttpClient.getInstance();
      const handler = client.unauthorizedHandler;
      if (handler !== null) {
        handler();
      }
    }
    return new OctopApiError(message, status, code === '' ? `HTTP_${status}` : code);
  }

  /** 检查滑动续期响应头，静默替换本地 token */
  private maybeRenewToken(header: Object): void {
    if (header === undefined || header === null) {
      return;
    }
    const headers: Record<string, Object> = header as Record<string, Object>;
    const v1: Object | undefined = headers[HEADER_RENEWED_TOKEN];
    const v2: Object | undefined = headers[HEADER_RENEWED_TOKEN_LOWER];
    let renewed: string = '';
    if (typeof v1 === 'string') {
      renewed = v1;
    } else if (typeof v2 === 'string') {
      renewed = v2;
    }
    if (renewed !== '' && renewed !== this.token) {
      this.token = renewed;
      TokenVault.saveToken(renewed);
      Log.info('Access token renewed via response header');
    }
  }
}
