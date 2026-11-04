import { JsonHelper } from '../utils/JsonHelper';
import { OctopApiError } from '../net/HttpClient';

export class OctopUserModel {
  readonly id: string;
  readonly username: string;
  readonly displayName: string;
  readonly role: string;
  readonly avatarUrl: string;
  readonly hasPassword: boolean;
  readonly ssoLinked: boolean;
  readonly locale: string;
  readonly permissions: Array<string>;

  constructor(id: string, username: string, displayName: string, role: string,
    avatarUrl: string = '', hasPassword: boolean = false, ssoLinked: boolean = false,
    locale: string = '', permissions: Array<string> = []) {
    this.id = id;
    this.username = username;
    this.displayName = displayName === '' ? username : displayName;
    this.role = role;
    this.avatarUrl = avatarUrl;
    this.hasPassword = hasPassword;
    this.ssoLinked = ssoLinked;
    this.locale = locale;
    this.permissions = permissions;
  }

  /** 是否持有某权限（admin 视为全量） */
  hasPermission(key: string): boolean {
    if (this.role === 'admin') {
      return true;
    }
    for (const item of this.permissions) {
      if (item === key) {
        return true;
      }
    }
    return false;
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
      JsonHelper.getString(userRec, 'role', 'user'),
      JsonHelper.getString(userRec, 'avatar_url', ''),
      JsonHelper.getBool(userRec, 'has_password', false),
      JsonHelper.getBool(userRec, 'sso_linked', false),
      JsonHelper.getString(userRec, 'locale', ''),
      JsonHelper.getStringArray(userRec, 'permissions')
    );
    return new LoginResultModel(token, JsonHelper.getNumber(rec, 'expires_in', 3600), user);
  }
}

/** 用户管理条目（GET /api/users，需 users 权限） */
export class UserAccountModel {
  readonly id: number;
  readonly username: string;
  readonly displayName: string;
  readonly role: string;
  readonly roleName: string;
  readonly email: string;
  readonly hasPassword: boolean;
  readonly ssoLinked: boolean;
  readonly disabled: boolean;
  readonly loginLocked: boolean;
  readonly avatarUrl: string;
  /** -1 代表未设置限制（null） */
  readonly tokenQuota: number;
  readonly maxAgents: number;

  constructor(id: number, username: string, displayName: string, role: string, roleName: string,
    email: string, hasPassword: boolean, ssoLinked: boolean, disabled: boolean,
    loginLocked: boolean, avatarUrl: string, tokenQuota: number, maxAgents: number) {
    this.id = id;
    this.username = username;
    this.displayName = displayName === '' ? username : displayName;
    this.role = role;
    this.roleName = roleName;
    this.email = email;
    this.hasPassword = hasPassword;
    this.ssoLinked = ssoLinked;
    this.disabled = disabled;
    this.loginLocked = loginLocked;
    this.avatarUrl = avatarUrl;
    this.tokenQuota = tokenQuota;
    this.maxAgents = maxAgents;
  }

  static fromRecord(rec: Record<string, Object>): UserAccountModel {
    return new UserAccountModel(
      JsonHelper.getNumber(rec, 'id', 0),
      JsonHelper.getString(rec, 'username', ''),
      JsonHelper.getString(rec, 'display_name', ''),
      JsonHelper.getString(rec, 'role', 'user'),
      JsonHelper.getString(rec, 'role_name', ''),
      JsonHelper.getString(rec, 'email', ''),
      JsonHelper.getBool(rec, 'has_password', false),
      JsonHelper.getBool(rec, 'sso_linked', false),
      JsonHelper.getBool(rec, 'disabled', false),
      JsonHelper.getBool(rec, 'login_locked', false),
      JsonHelper.getString(rec, 'avatar_url', ''),
      JsonHelper.getOptionalNumber(rec, 'token_quota', -1),
      JsonHelper.getOptionalNumber(rec, 'max_agents', -1)
    );
  }

  static parseList(text: string): Array<UserAccountModel> {
    const result: Array<UserAccountModel> = [];
    const arr = JsonHelper.parseArray(text);
    if (arr !== null) {
      for (const rec of arr) {
        result.push(UserAccountModel.fromRecord(rec));
      }
      return result;
    }
    const obj = JsonHelper.parse(text);
    const items = JsonHelper.getRecordArray(obj, 'users');
    for (const rec of items) {
      result.push(UserAccountModel.fromRecord(rec));
    }
    return result;
  }
}

/** 角色模板（GET /api/users/roles） */
export class UserRoleModel {
  readonly id: string;
  readonly name: string;
  readonly description: string;
  readonly systemRole: string;
  readonly deletable: boolean;
  readonly immutable: boolean;

  constructor(id: string, name: string, description: string, systemRole: string,
    deletable: boolean, immutable: boolean) {
    this.id = id;
    this.name = name;
    this.description = description;
    this.systemRole = systemRole;
    this.deletable = deletable;
    this.immutable = immutable;
  }

  static fromRecord(rec: Record<string, Object>): UserRoleModel {
    return new UserRoleModel(
      JsonHelper.getString(rec, 'user_role_id', ''),
      JsonHelper.getString(rec, 'user_role_name', ''),
      JsonHelper.getString(rec, 'description', ''),
      JsonHelper.getString(rec, 'system_role', ''),
      JsonHelper.getBool(rec, 'deletable', false),
      JsonHelper.getBool(rec, 'immutable', false)
    );
  }

  static parseList(text: string): Array<UserRoleModel> {
    const result: Array<UserRoleModel> = [];
    const arr = JsonHelper.parseArray(text);
    if (arr !== null) {
      for (const rec of arr) {
        result.push(UserRoleModel.fromRecord(rec));
      }
      return result;
    }
    const obj = JsonHelper.parse(text);
    let items = JsonHelper.getRecordArray(obj, 'roles');
    if (items.length === 0) {
      items = JsonHelper.getRecordArray(obj, 'user_roles');
    }
    for (const rec of items) {
      result.push(UserRoleModel.fromRecord(rec));
    }
    return result;
  }
}

/** 登录验证码配置（GET /api/auth/captcha；slider 无 site_key） */
export class CaptchaConfigModel {
  readonly provider: string; // slider|tencent|turnstile|hcaptcha|recaptcha|recaptcha-v3|geetest-v4
  readonly siteKey: string;

  constructor(provider: string, siteKey: string) {
    this.provider = provider;
    this.siteKey = siteKey;
  }

  /** 无需前端挑战（slider 服务端忽略 token） */
  get noChallengeNeeded(): boolean {
    return this.provider === '' || this.provider === 'slider';
  }

  static parse(text: string): CaptchaConfigModel {
    const rec = JsonHelper.parse(text);
    if (rec === null) {
      return new CaptchaConfigModel('', '');
    }
    return new CaptchaConfigModel(
      JsonHelper.getString(rec, 'provider', ''),
      JsonHelper.getString(rec, 'site_key', '')
    );
  }
}

/** 服务器健康状态（GET /api/health，免鉴权） */
export class HealthStatusModel {
  readonly ok: boolean;
  readonly startedAtMs: number;
  readonly db: string;
  readonly usersLoaded: number;
  readonly agentsRunning: number;

  constructor(ok: boolean, startedAtMs: number, db: string, usersLoaded: number,
    agentsRunning: number) {
    this.ok = ok;
    this.startedAtMs = startedAtMs;
    this.db = db;
    this.usersLoaded = usersLoaded;
    this.agentsRunning = agentsRunning;
  }

  static parse(text: string): HealthStatusModel {
    const rec = JsonHelper.parse(text);
    if (rec === null) {
      return new HealthStatusModel(false, 0, '', 0, 0);
    }
    return new HealthStatusModel(
      JsonHelper.getBool(rec, 'ok', false),
      JsonHelper.toMs(rec['started_at']),
      JsonHelper.getString(rec, 'db', ''),
      JsonHelper.getNumber(rec, 'users_loaded', 0),
      JsonHelper.getNumber(rec, 'agents_running', 0)
    );
  }
}

/** 用户组（GET /api/user-groups，需 users 权限） */
export class UserGroupModel {
  readonly id: string;
  readonly name: string;
  readonly description: string;
  readonly enabled: boolean;
  readonly avatarIcon: string;
  readonly avatarUrl: string;
  readonly memberCount: number;
  readonly memberIds: Array<number>;
  readonly createdAtMs: number;
  readonly updatedAtMs: number;

  constructor(id: string, name: string, description: string, enabled: boolean,
    avatarIcon: string, avatarUrl: string, memberCount: number, memberIds: Array<number>,
    createdAtMs: number, updatedAtMs: number) {
    this.id = id;
    this.name = name;
    this.description = description;
    this.enabled = enabled;
    this.avatarIcon = avatarIcon;
    this.avatarUrl = avatarUrl;
    this.memberCount = memberCount;
    this.memberIds = memberIds;
    this.createdAtMs = createdAtMs;
    this.updatedAtMs = updatedAtMs;
  }

  static fromRecord(rec: Record<string, Object>): UserGroupModel {
    const memberIds: Array<number> = [];
    const rawIds: Array<string> = JsonHelper.getStringArray(rec, 'member_ids');
    for (const raw of rawIds) {
      const parsed: number = Number(raw);
      if (!Number.isNaN(parsed)) {
        memberIds.push(parsed);
      }
    }
    return new UserGroupModel(
      JsonHelper.getString(rec, 'user_group_id', ''),
      JsonHelper.getString(rec, 'name', ''),
      JsonHelper.getString(rec, 'description', ''),
      JsonHelper.getBool(rec, 'enabled', true),
      JsonHelper.getString(rec, 'avatar_icon', ''),
      JsonHelper.getString(rec, 'avatar_url', ''),
      JsonHelper.getNumber(rec, 'member_count', memberIds.length),
      memberIds,
      JsonHelper.toMs(rec['created_at']),
      JsonHelper.toMs(rec['updated_at'])
    );
  }

  static parseList(text: string): Array<UserGroupModel> {
    const result: Array<UserGroupModel> = [];
    const arr = JsonHelper.parseArray(text);
    if (arr === null) {
      return result;
    }
    for (const rec of arr) {
      result.push(UserGroupModel.fromRecord(rec));
    }
    return result;
  }
}
