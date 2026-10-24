import { JsonHelper } from '../utils/JsonHelper';
import { OctopApiError } from '../net/HttpClient';

export class OctopUserModel {
  readonly id: string;
  readonly username: string;
  readonly displayName: string;
  readonly role: string;

  constructor(id: string, username: string, displayName: string, role: string) {
    this.id = id;
    this.username = username;
    this.displayName = displayName === '' ? username : displayName;
    this.role = role;
  }
}

export class LoginResultModel {
  readonly token: string;
  readonly expiresInSeconds: number;
  readonly user: OctopUserModel;

  constructor(token: string, expiresInSeconds: number, user: OctopUserModel) {
    this.token = token;
    this.expiresInSeconds = expiresInSeconds;
    this.user = user;
  }

  /** 解析 POST /api/auth/login 响应 */
  static fromResponse(text: string): LoginResultModel {
    const rec = JsonHelper.parse(text);
    if (rec === null) {
      throw new OctopApiError('登录响应格式错误', 0, 'BAD_RESPONSE');
    }
    const token: string = JsonHelper.getString(rec, 'access_token', '');
    if (token === '') {
      throw new OctopApiError('登录响应缺少令牌', 0, 'BAD_RESPONSE');
    }
    const userRec: Record<string, Object> | null = JsonHelper.getRecord(rec, 'user');
    const user = new OctopUserModel(
      JsonHelper.getString(userRec, 'id', ''),
      JsonHelper.getString(userRec, 'username', ''),
      JsonHelper.getString(userRec, 'display_name', ''),
      JsonHelper.getString(userRec, 'role', 'user')
    );
    return new LoginResultModel(token, JsonHelper.getNumber(rec, 'expires_in', 3600), user);
  }
}
