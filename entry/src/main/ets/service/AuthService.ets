import { HttpClient } from '../net/HttpClient';
import { LoginResultModel, OctopUserModel } from '../model/AuthModels';
import { JsonHelper } from '../utils/JsonHelper';
import { OctopApiError } from '../net/HttpClient';
import { UrlUtil } from '../utils/UrlUtil';

export class AuthService {
  /** 登录并返回解析后的会话结果（captchaToken：验证码开启时必填，暂不集成时传空串） */
  static async login(rawBaseUrl: string, username: string, password: string,
    captchaToken: string = ''): Promise<LoginResultModel> {
    const baseUrl = UrlUtil.normalizeServerUrl(rawBaseUrl);
    const client = HttpClient.getInstance();
    client.setBaseUrl(baseUrl);
    client.setToken('');
    const body: Record<string, Object> = {
      'username': username,
      'password': password
    };
    if (captchaToken !== '') {
      body['captcha_token'] = captchaToken;
    }
    const text: string = await client.post('/api/auth/login', JSON.stringify(body));
    return LoginResultModel.fromResponse(text);
  }

  /** 修改密码（204；旧密码错误等服务端以错误包络返回） */
  static async changePassword(oldPassword: string, newPassword: string): Promise<void> {
    const body: Record<string, Object> = {
      'old_password': oldPassword,
      'new_password': newPassword
    };
    await HttpClient.getInstance().post('/api/auth/change-password', JSON.stringify(body));
  }

  /** 当前用户资料（GET /api/auth/me）：刷新昵称/角色等展示信息 */
  static async me(): Promise<OctopUserModel> {
    const text: string = await HttpClient.getInstance().get('/api/auth/me');
    const rec = JsonHelper.parse(text);
    if (rec === null) {
      throw new OctopApiError('用户资料响应格式错误', 0, 'BAD_RESPONSE');
    }
    // 兼容顶层字段与 {user:{...}} 包装两种形态
    const userRec: Record<string, Object> | null = JsonHelper.getRecord(rec, 'user');
    const source: Record<string, Object> = userRec !== null ? userRec : rec;
    return new OctopUserModel(
      JsonHelper.getString(source, 'id', ''),
      JsonHelper.getString(source, 'username', ''),
      JsonHelper.getString(source, 'display_name', ''),
      JsonHelper.getString(source, 'role', 'user')
    );
  }
}
