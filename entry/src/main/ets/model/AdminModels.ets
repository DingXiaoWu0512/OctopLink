import { JsonHelper } from '../utils/JsonHelper';

/**
 * 管理员控制台与 SSO 域数据模型（源：octop/api/routers/admin.py、
 * auth_oidc.py、auth_oauth.py、auth_ldap.py）：
 * - AdminOverviewModel / AdminOverviewUserModel / AdminOverviewAgentModel：系统概览
 * - AdminAuditLogModel：审计日志
 * - SsoProviderStatusModel：SSO 提供商登录入口状态
 * - OidcProviderConfigModel / OauthProviderConfigModel：OIDC 与 OAuth 提供商配置
 * - LdapProviderConfigModel：LDAP 目录配置
 * - SsoTestResultModel：连接测试结果
 */

/** 概览用户条目（admin.py overview users 元素） */
export class AdminOverviewUserModel {
  readonly username: string;
  readonly role: string;

  constructor(username: string, role: string) {
    this.username = username;
    this.role = role;
  }

  static fromRecord(rec: Record<string, Object>): AdminOverviewUserModel {
    return new AdminOverviewUserModel(
      JsonHelper.getString(rec, 'username', ''),
      JsonHelper.getString(rec, 'role', 'user')
    );
  }
}

/** 概览专家条目（admin.py overview agents 元素） */
export class AdminOverviewAgentModel {
  readonly id: string;
  readonly agentId: string;
  readonly name: string;
  readonly state: string;

  constructor(id: string, agentId: string, name: string, state: string) {
    this.id = id;
    this.agentId = agentId;
    this.name = name;
    this.state = state;
  }

  static fromRecord(rec: Record<string, Object>): AdminOverviewAgentModel {
    return new AdminOverviewAgentModel(
      JsonHelper.getString(rec, 'id', ''),
      JsonHelper.getString(rec, 'agent_id', ''),
      JsonHelper.getString(rec, 'name', ''),
      JsonHelper.getString(rec, 'state', 'unknown')
    );
  }
}

/** 系统概览（GET /api/admin/overview，需 admin_console 权限） */
export class AdminOverviewModel {
  readonly users: Array<AdminOverviewUserModel>;
  readonly agents: Array<AdminOverviewAgentModel>;
  readonly totalUsers: number;
  readonly totalAgents: number;

  constructor(users: Array<AdminOverviewUserModel>, agents: Array<AdminOverviewAgentModel>,
    totalUsers: number, totalAgents: number) {
    this.users = users;
    this.agents = agents;
    this.totalUsers = totalUsers;
    this.totalAgents = totalAgents;
  }

  /** 运行中的专家数（state=running） */
  runningAgents(): number {
    let count: number = 0;
    for (const agent of this.agents) {
      if (agent.state === 'running') {
        count++;
      }
    }
    return count;
  }

  static parse(text: string): AdminOverviewModel {
    const rec = JsonHelper.parse(text);
    if (rec === null) {
      return new AdminOverviewModel([], [], 0, 0);
    }
    const users: Array<AdminOverviewUserModel> = [];
    const userRecords: Array<Record<string, Object>> = JsonHelper.getRecordArray(rec, 'users');
    for (const userRec of userRecords) {
      users.push(AdminOverviewUserModel.fromRecord(userRec));
    }
    const agents: Array<AdminOverviewAgentModel> = [];
    const agentRecords: Array<Record<string, Object>> = JsonHelper.getRecordArray(rec, 'agents');
    for (const agentRec of agentRecords) {
      agents.push(AdminOverviewAgentModel.fromRecord(agentRec));
    }
    const totals: Record<string, Object> | null = JsonHelper.getRecord(rec, 'totals');
    return new AdminOverviewModel(
      users,
      agents,
      totals === null ? users.length : JsonHelper.getNumber(totals, 'users', users.length),
      totals === null ? agents.length : JsonHelper.getNumber(totals, 'agents', agents.length)
    );
  }
}

/** 审计日志条目（GET /api/admin/audit-log） */
export class AdminAuditLogModel {
  readonly id: string;
  readonly tsMs: number;
  readonly actor: string;
  readonly action: string;
  readonly target: string;

  constructor(id: string, tsMs: number, actor: string, action: string, target: string) {
    this.id = id;
    this.tsMs = tsMs;
    this.actor = actor;
    this.action = action;
    this.target = target;
  }

  static fromRecord(rec: Record<string, Object>): AdminAuditLogModel {
    return new AdminAuditLogModel(
      JsonHelper.getString(rec, 'id', ''),
      JsonHelper.toMs(rec['ts']),
      JsonHelper.getString(rec, 'actor', ''),
      JsonHelper.getString(rec, 'action', ''),
      JsonHelper.getString(rec, 'target', '')
    );
  }

  static parseList(text: string): Array<AdminAuditLogModel> {
    const result: Array<AdminAuditLogModel> = [];
    const arr = JsonHelper.parseArray(text);
    if (arr === null) {
      return result;
    }
    for (const rec of arr) {
      result.push(AdminAuditLogModel.fromRecord(rec));
    }
    return result;
  }
}

/** SSO 提供商登录入口状态（GET /api/auth/oauth/status providers 元素；ldap 用同构字段） */
export class SsoProviderStatusModel {
  readonly kind: string; // oidc | feishu | dingtalk | wecom | ldap
  readonly displayName: string;
  readonly enabled: boolean;

  constructor(kind: string, displayName: string, enabled: boolean) {
    this.kind = kind;
    this.displayName = displayName;
    this.enabled = enabled;
  }

  static fromRecord(rec: Record<string, Object>): SsoProviderStatusModel {
    return new SsoProviderStatusModel(
      JsonHelper.getString(rec, 'kind', ''),
      JsonHelper.getString(rec, 'display_name', ''),
      JsonHelper.getBool(rec, 'enabled', false)
    );
  }
}

/** OIDC 提供商配置（GET/PUT /api/auth/oidc/config；client_secret 只写不回显） */
export class OidcProviderConfigModel {
  readonly enabled: boolean;
  readonly displayName: string;
  readonly issuer: string;
  readonly clientId: string;
  readonly scopes: string;
  readonly dashboardOrigin: string;
  readonly hasClientSecret: boolean;
  readonly redirectUri: string;

  constructor(enabled: boolean, displayName: string, issuer: string, clientId: string,
    scopes: string, dashboardOrigin: string, hasClientSecret: boolean, redirectUri: string) {
    this.enabled = enabled;
    this.displayName = displayName;
    this.issuer = issuer;
    this.clientId = clientId;
    this.scopes = scopes;
    this.dashboardOrigin = dashboardOrigin;
    this.hasClientSecret = hasClientSecret;
    this.redirectUri = redirectUri;
  }

  static parse(text: string): OidcProviderConfigModel {
    const rec = JsonHelper.parse(text);
    if (rec === null) {
      return new OidcProviderConfigModel(false, '', '', '', '', '', false, '');
    }
    return new OidcProviderConfigModel(
      JsonHelper.getBool(rec, 'enabled', false),
      JsonHelper.getString(rec, 'display_name', ''),
      JsonHelper.getString(rec, 'issuer', ''),
      JsonHelper.getString(rec, 'client_id', ''),
      JsonHelper.getString(rec, 'scopes', ''),
      JsonHelper.getString(rec, 'dashboard_origin', ''),
      JsonHelper.getBool(rec, 'has_client_secret', false),
      JsonHelper.getString(rec, 'redirect_uri', '')
    );
  }
}

/** OAuth 提供商配置（GET/PUT /api/auth/oauth/providers/{kind}；feishu/dingtalk/wecom） */
export class OauthProviderConfigModel {
  readonly kind: string;
  readonly enabled: boolean;
  readonly displayName: string;
  readonly issuer: string;
  readonly clientId: string;
  readonly scopes: string;
  readonly dashboardOrigin: string;
  readonly hasClientSecret: boolean;
  readonly redirectUri: string;

  constructor(kind: string, enabled: boolean, displayName: string, issuer: string,
    clientId: string, scopes: string, dashboardOrigin: string, hasClientSecret: boolean,
    redirectUri: string) {
    this.kind = kind;
    this.enabled = enabled;
    this.displayName = displayName;
    this.issuer = issuer;
    this.clientId = clientId;
    this.scopes = scopes;
    this.dashboardOrigin = dashboardOrigin;
    this.hasClientSecret = hasClientSecret;
    this.redirectUri = redirectUri;
  }

  static parse(text: string): OauthProviderConfigModel {
    const rec = JsonHelper.parse(text);
    if (rec === null) {
      return new OauthProviderConfigModel('', false, '', '', '', '', '', false, '');
    }
    return new OauthProviderConfigModel(
      JsonHelper.getString(rec, 'kind', ''),
      JsonHelper.getBool(rec, 'enabled', false),
      JsonHelper.getString(rec, 'display_name', ''),
      JsonHelper.getString(rec, 'issuer', ''),
      JsonHelper.getString(rec, 'client_id', ''),
      JsonHelper.getString(rec, 'scopes', ''),
      JsonHelper.getString(rec, 'dashboard_origin', ''),
      JsonHelper.getBool(rec, 'has_client_secret', false),
      JsonHelper.getString(rec, 'redirect_uri', '')
    );
  }
}

/** LDAP 目录配置（GET/PUT /api/auth/ldap/config；bind_password 只写不回显） */
export class LdapProviderConfigModel {
  readonly enabled: boolean;
  readonly displayName: string;
  readonly serverUrl: string;
  readonly startTls: boolean;
  readonly verifyTls: boolean;
  readonly bindDn: string;
  readonly hasBindPassword: boolean;
  readonly userBaseDn: string;
  readonly userFilter: string;
  readonly usernameAttribute: string;
  readonly emailAttribute: string;
  readonly autoProvision: boolean;
  readonly timeoutSeconds: number;

  constructor(enabled: boolean, displayName: string, serverUrl: string, startTls: boolean,
    verifyTls: boolean, bindDn: string, hasBindPassword: boolean, userBaseDn: string,
    userFilter: string, usernameAttribute: string, emailAttribute: string,
    autoProvision: boolean, timeoutSeconds: number) {
    this.enabled = enabled;
    this.displayName = displayName;
    this.serverUrl = serverUrl;
    this.startTls = startTls;
    this.verifyTls = verifyTls;
    this.bindDn = bindDn;
    this.hasBindPassword = hasBindPassword;
    this.userBaseDn = userBaseDn;
    this.userFilter = userFilter;
    this.usernameAttribute = usernameAttribute;
    this.emailAttribute = emailAttribute;
    this.autoProvision = autoProvision;
    this.timeoutSeconds = timeoutSeconds;
  }

  static parse(text: string): LdapProviderConfigModel {
    const rec = JsonHelper.parse(text);
    if (rec === null) {
      return new LdapProviderConfigModel(false, '', '', false, false, '', false, '', '',
        '', '', false, 0);
    }
    return new LdapProviderConfigModel(
      JsonHelper.getBool(rec, 'enabled', false),
      JsonHelper.getString(rec, 'display_name', ''),
      JsonHelper.getString(rec, 'server_url', ''),
      JsonHelper.getBool(rec, 'start_tls', false),
      JsonHelper.getBool(rec, 'verify_tls', false),
      JsonHelper.getString(rec, 'bind_dn', ''),
      JsonHelper.getBool(rec, 'has_bind_password', false),
      JsonHelper.getString(rec, 'user_base_dn', ''),
      JsonHelper.getString(rec, 'user_filter', ''),
      JsonHelper.getString(rec, 'username_attribute', ''),
      JsonHelper.getString(rec, 'email_attribute', ''),
      JsonHelper.getBool(rec, 'auto_provision', false),
      JsonHelper.getNumber(rec, 'timeout_seconds', 0)
    );
  }
}

/** SSO 连接测试结果（POST .../test → {ok, detail}） */
export class SsoTestResultModel {
  readonly ok: boolean;
  readonly detail: string;

  constructor(ok: boolean, detail: string) {
    this.ok = ok;
    this.detail = detail;
  }

  static parse(text: string): SsoTestResultModel {
    const rec = JsonHelper.parse(text);
    if (rec === null) {
      return new SsoTestResultModel(false, '');
    }
    return new SsoTestResultModel(
      JsonHelper.getBool(rec, 'ok', false),
      JsonHelper.getString(rec, 'detail', '')
    );
  }
}
