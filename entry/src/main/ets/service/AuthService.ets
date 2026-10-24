import { HttpClient } from '../net/HttpClient';
import { LoginResultModel, OctopUserModel, UserAccountModel, UserRoleModel } from '../model/AuthModels';
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

  /** 当前用户资料（GET /api/auth/me）：刷新昵称/角色/头像/权限等展示信息 */
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
      JsonHelper.getString(source, 'role', 'user'),
      JsonHelper.getString(source, 'avatar_url', ''),
      JsonHelper.getBool(source, 'has_password', false),
      JsonHelper.getBool(source, 'sso_linked', false),
      JsonHelper.getString(source, 'locale', ''),
      JsonHelper.getStringArray(source, 'permissions')
    );
  }
}

/** 用户管理（/api/users，需 users 权限） */
export class UserService {
  static async list(): Promise<Array<UserAccountModel>> {
    const text: string = await HttpClient.getInstance().get('/api/users');
    return UserAccountModel.parseList(text);
  }

  static async create(bodyStr: string): Promise<void> {
    await HttpClient.getInstance().post('/api/users', bodyStr);
  }

  static async patch(userId: number, bodyStr: string): Promise<void> {
    await HttpClient.getInstance().patch(`/api/users/${userId}`, bodyStr);
  }

  static async remove(userId: number): Promise<void> {
    await HttpClient.getInstance().delete(`/api/users/${userId}`);
  }

  static async unlockLogin(userId: number): Promise<void> {
    await HttpClient.getInstance().post(`/api/users/${userId}/unlock-login`, '{}');
  }

  static async resetPassword(userId: number, newPassword: string): Promise<void> {
    const body: Record<string, Object> = { 'new_password': newPassword };
    await HttpClient.getInstance().post(`/api/users/${userId}/reset-password`, JSON.stringify(body));
  }

  /** 批量操作：action = enable|disable|delete|set_token_quota|set_max_agents */
  static async batch(userIds: Array<number>, action: string,
    tokenQuota: number | null = null, maxAgents: number | null = null): Promise<void> {
    const ids: Array<Object> = [];
    for (const id of userIds) {
      ids.push(id);
    }
    const body: Record<string, Object> = {
      'user_ids': ids,
      'action': action
    };
    if (action === 'set_token_quota' && tokenQuota !== null) {
      body['token_quota'] = tokenQuota;
    }
    if (action === 'set_max_agents' && maxAgents !== null) {
      body['max_agents'] = maxAgents;
    }
    await HttpClient.getInstance().post('/api/users/batch', JSON.stringify(body));
  }
}

/** 角色模板（/api/users/roles，需 users 权限） */
export class UserRoleService {
  static async list(): Promise<Array<UserRoleModel>> {
    const text: string = await HttpClient.getInstance().get('/api/users/roles');
    return UserRoleModel.parseList(text);
  }

  static async create(bodyStr: string): Promise<void> {
    await HttpClient.getInstance().post('/api/users/roles', bodyStr);
  }

  static async patch(roleId: string, bodyStr: string): Promise<void> {
    await HttpClient.getInstance().patch(`/api/users/roles/${roleId}`, bodyStr);
  }

  static async remove(roleId: string): Promise<void> {
    await HttpClient.getInstance().delete(`/api/users/roles/${roleId}`);
  }
}
