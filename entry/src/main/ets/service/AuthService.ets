import { HttpClient } from '../net/HttpClient';
import {
  CaptchaConfigModel,
  HealthStatusModel,
  LoginResultModel,
  OctopUserModel,
  UserAccountModel,
  UserGroupModel,
  UserRoleModel
} from '../model/AuthModels';
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

  /** 公开登录验证码配置（无需登录；slider provider 无需前端挑战） */
  static async captchaConfig(): Promise<CaptchaConfigModel> {
    const text: string = await HttpClient.getInstance().get('/api/auth/captcha');
    return CaptchaConfigModel.parse(text);
  }

  /** 服务器健康检查（免鉴权；连通性/数据库/运行中智能体数） */
  static async health(): Promise<HealthStatusModel> {
    const text: string = await HttpClient.getInstance().get('/api/health');
    return HealthStatusModel.parse(text);
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

  /** 编辑个人资料（PATCH /api/auth/me；null 语义字段传空串表示不修改，displayName/locale 至少其一） */
  static async updateMe(displayName: string, locale: string): Promise<void> {
    const body: Record<string, Object> = {};
    if (displayName !== '') {
      body['display_name'] = displayName;
    }
    if (locale !== '') {
      body['locale'] = locale;
    }
    await HttpClient.getInstance().patch('/api/auth/me', JSON.stringify(body));
  }

  /** 上传我的头像（multipart file，≤5MiB，201 → {avatar_url}） */
  static async uploadMyAvatar(fileName: string, contentType: string,
    data: ArrayBuffer): Promise<string> {
    const text: string = await HttpClient.getInstance().postMultipartFile(
      '/api/auth/me/avatar', 'file', fileName, contentType, data);
    const rec = JsonHelper.parse(text);
    return rec === null ? '' : JsonHelper.getString(rec, 'avatar_url', '');
  }

  /** 删除我的头像 */
  static async deleteMyAvatar(): Promise<void> {
    await HttpClient.getInstance().delete('/api/auth/me/avatar');
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

  /** 上传用户头像（multipart file，≤5MiB，201 → {avatar_url}） */
  static async uploadAvatar(userId: number, fileName: string, contentType: string,
    data: ArrayBuffer): Promise<string> {
    const text: string = await HttpClient.getInstance().postMultipartFile(
      `/api/users/${userId}/avatar`, 'file', fileName, contentType, data);
    const rec = JsonHelper.parse(text);
    return rec === null ? '' : JsonHelper.getString(rec, 'avatar_url', '');
  }

  /** 删除用户头像 */
  static async deleteAvatar(userId: number): Promise<void> {
    await HttpClient.getInstance().delete(`/api/users/${userId}/avatar`);
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
  /** 可分配权限目录（GET /api/users/permissions，数组原始文本交 UI 解析） */
  static async permissionCatalog(): Promise<string> {
    return await HttpClient.getInstance().get('/api/users/permissions');
  }

  /** 单个用户详情（GET /api/users/{id}） */
  static async getUser(userId: number): Promise<UserAccountModel> {
    const text: string = await HttpClient.getInstance().get(`/api/users/${userId}`);
    const rec = JsonHelper.parse(text);
    return UserAccountModel.fromRecord(rec === null ? {} : rec);
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

  /** 上传角色头像（multipart file，201） */
  static async uploadAvatar(roleId: string, fileName: string, contentType: string,
    data: ArrayBuffer): Promise<void> {
    await HttpClient.getInstance().postMultipartFile(
      `/api/users/roles/${roleId}/avatar`, 'file', fileName, contentType, data);
  }

  /** 删除角色头像 */
  static async deleteAvatar(roleId: string): Promise<void> {
    await HttpClient.getInstance().delete(`/api/users/roles/${roleId}/avatar`);
  }
}

/** 用户组（/api/user-groups，需 users 权限） */
export class UserGroupService {
  static async list(): Promise<Array<UserGroupModel>> {
    const text: string = await HttpClient.getInstance().get('/api/user-groups');
    return UserGroupModel.parseList(text);
  }

  /** 创建（userGroupId 可省略由服务端分配短 id） */
  static async create(name: string, description: string, enabled: boolean = true,
    userGroupId: string = ''): Promise<UserGroupModel> {
    const body: Record<string, Object> = {
      'name': name,
      'description': description,
      'enabled': enabled
    };
    if (userGroupId !== '') {
      body['user_group_id'] = userGroupId;
    }
    const text: string =
      await HttpClient.getInstance().post('/api/user-groups', JSON.stringify(body));
    const rec = JsonHelper.parse(text);
    return UserGroupModel.fromRecord(rec === null ? {} : rec);
  }

  static async patch(userGroupId: string, bodyStr: string): Promise<void> {
    await HttpClient.getInstance().patch(`/api/user-groups/${userGroupId}`, bodyStr);
  }

  static async remove(userGroupId: string): Promise<void> {
    await HttpClient.getInstance().delete(`/api/user-groups/${userGroupId}`);
  }

  /** 成员 id 列表 */
  static async members(userGroupId: string): Promise<Array<number>> {
    const text: string =
      await HttpClient.getInstance().get(`/api/user-groups/${userGroupId}/members`);
    const rec = JsonHelper.parse(text);
    if (rec === null) {
      return [];
    }
    const ids: Array<number> = [];
    const rawIds: Array<string> = JsonHelper.getStringArray(rec, 'user_ids');
    for (const raw of rawIds) {
      const parsed: number = Number(raw);
      if (!Number.isNaN(parsed)) {
        ids.push(parsed);
      }
    }
    return ids;
  }

  /** 全量替换成员 */
  static async replaceMembers(userGroupId: string, userIds: Array<number>): Promise<void> {
    const ids: Array<Object> = [];
    for (const id of userIds) {
      ids.push(id);
    }
    const body: Record<string, Object> = { 'user_ids': ids };
    await HttpClient.getInstance().put(
      `/api/user-groups/${userGroupId}/members`, JSON.stringify(body));
  }

  /** 上传用户组头像（multipart file，201） */
  static async uploadAvatar(userGroupId: string, fileName: string, contentType: string,
    data: ArrayBuffer): Promise<void> {
    await HttpClient.getInstance().postMultipartFile(
      `/api/user-groups/${userGroupId}/avatar`, 'file', fileName, contentType, data);
  }

  /** 删除用户组头像 */
  static async deleteAvatar(userGroupId: string): Promise<void> {
    await HttpClient.getInstance().delete(`/api/user-groups/${userGroupId}/avatar`);
  }
}
