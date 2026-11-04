import { HttpClient } from '../net/HttpClient';
import { JsonHelper } from '../utils/JsonHelper';
import {
  LdapProviderConfigModel,
  OauthProviderConfigModel,
  OidcProviderConfigModel,
  SsoProviderStatusModel,
  SsoTestResultModel
} from '../model/AdminModels';

/**
 * SSO 配置服务（源：octop/api/routers/auth_oidc.py、auth_oauth.py、auth_ldap.py）：
 * - 登录入口状态（oauth status / ldap status，无需特殊权限）
 * - OIDC/OAuth 提供商配置读取与保存（需 sso_oidc / sso_feishu / sso_dingtalk / sso_wecom 权限）
 * - LDAP 目录配置读取与保存（需 sso_ldap 权限）
 * - secret 类字段只写不回显（has_client_secret / has_bind_password 标记已配置）
 */
export class SsoService {
  /** OAuth 系登录入口状态（GET /api/auth/oauth/status → {providers:[{kind,display_name,enabled}]}） */
  static async oauthStatus(): Promise<Array<SsoProviderStatusModel>> {
    const text: string = await HttpClient.getInstance().get('/api/auth/oauth/status');
    const result: Array<SsoProviderStatusModel> = [];
    const rec = JsonHelper.parse(text);
    if (rec === null) {
      return result;
    }
    const providerRecords: Array<Record<string, Object>> = JsonHelper.getRecordArray(rec, 'providers');
    for (const providerRec of providerRecords) {
      result.push(SsoProviderStatusModel.fromRecord(providerRec));
    }
    return result;
  }

  /** LDAP 登录入口状态（GET /api/auth/ldap/status → {enabled,display_name}） */
  static async ldapStatus(): Promise<SsoProviderStatusModel> {
    const text: string = await HttpClient.getInstance().get('/api/auth/ldap/status');
    const rec = JsonHelper.parse(text);
    if (rec === null) {
      return new SsoProviderStatusModel('ldap', '', false);
    }
    return new SsoProviderStatusModel(
      'ldap',
      JsonHelper.getString(rec, 'display_name', ''),
      JsonHelper.getBool(rec, 'enabled', false)
    );
  }

  /** 读取 OIDC 配置（GET /api/auth/oidc/config；不含 client_secret） */
  static async getOidcConfig(): Promise<OidcProviderConfigModel> {
    const text: string = await HttpClient.getInstance().get('/api/auth/oidc/config');
    return OidcProviderConfigModel.parse(text);
  }

  /** 保存 OIDC 配置（PUT /api/auth/oidc/config；client_secret 留空保持不变） */
  static async putOidcConfig(bodyStr: string): Promise<void> {
    await HttpClient.getInstance().put('/api/auth/oidc/config', bodyStr);
  }

  /** 测试 OIDC 发现端点连通性（POST /api/auth/oidc/config/test → {ok,detail}） */
  static async testOidc(): Promise<SsoTestResultModel> {
    const text: string = await HttpClient.getInstance().post('/api/auth/oidc/config/test', '{}');
    return SsoTestResultModel.parse(text);
  }

  /** 读取 OAuth 提供商配置（GET /api/auth/oauth/providers/{kind}；kind=feishu|dingtalk|wecom） */
  static async getOauthConfig(kind: string): Promise<OauthProviderConfigModel> {
    const text: string =
      await HttpClient.getInstance().get(`/api/auth/oauth/providers/${kind}`);
    return OauthProviderConfigModel.parse(text);
  }

  /** 保存 OAuth 提供商配置（PUT /api/auth/oauth/providers/{kind}；client_secret 留空保持不变） */
  static async putOauthConfig(kind: string, bodyStr: string): Promise<void> {
    await HttpClient.getInstance().put(`/api/auth/oauth/providers/${kind}`, bodyStr);
  }

  /** 测试 OAuth 提供商凭据（POST /api/auth/oauth/providers/{kind}/test → {ok,detail}） */
  static async testOauth(kind: string): Promise<SsoTestResultModel> {
    const text: string =
      await HttpClient.getInstance().post(`/api/auth/oauth/providers/${kind}/test`, '{}');
    return SsoTestResultModel.parse(text);
  }

  /** 读取 LDAP 配置（GET /api/auth/ldap/config；不含 bind_password） */
  static async getLdapConfig(): Promise<LdapProviderConfigModel> {
    const text: string = await HttpClient.getInstance().get('/api/auth/ldap/config');
    return LdapProviderConfigModel.parse(text);
  }

  /** 保存 LDAP 配置（PUT /api/auth/ldap/config；bind_password 留空保持已存值） */
  static async putLdapConfig(bodyStr: string): Promise<void> {
    await HttpClient.getInstance().put('/api/auth/ldap/config', bodyStr);
  }

  /** 测试 LDAP 目录连通性（POST /api/auth/ldap/config/test → {ok,detail,warnings}） */
  static async testLdap(): Promise<SsoTestResultModel> {
    const text: string =
      await HttpClient.getInstance().post('/api/auth/ldap/config/test', '{}');
    return SsoTestResultModel.parse(text);
  }

  // ---- 移动端 SSO 登录流（公开接口；浏览器承接 authorize，回跳后用 code 换 token）----

  /**
   * 发起 OAuth 登录（POST /api/auth/oauth/start，kind=oidc|feishu|dingtalk|wecom）。
   * 响应含 authorize 跳转地址（authorize_url / url / login_url 皆容错）。
   */
  static async oauthStart(kind: string): Promise<string> {
    const body: Record<string, Object> = { 'kind': kind };
    const text: string = await HttpClient.getInstance().post(
      '/api/auth/oauth/start', JSON.stringify(body));
    const rec = JsonHelper.parse(text);
    if (rec === null) {
      return '';
    }
    let url: string = JsonHelper.getString(rec, 'authorize_url', '');
    if (url === '') {
      url = JsonHelper.getString(rec, 'url', '');
    }
    if (url === '') {
      url = JsonHelper.getString(rec, 'login_url', '');
    }
    return url;
  }

  /** 用 authorize 回跳 code 换 token（POST /api/auth/oauth/exchange → login 同构包络） */
  static async oauthExchange(code: string): Promise<string> {
    const body: Record<string, Object> = { 'code': code };
    return await HttpClient.getInstance().post(
      '/api/auth/oauth/exchange', JSON.stringify(body));
  }

  /** 发起 OIDC 登录（POST /api/auth/oidc/start → authorize_url/url/login_url 容错） */
  static async oidcStart(): Promise<string> {
    const text: string = await HttpClient.getInstance().post('/api/auth/oidc/start', '{}');
    const rec = JsonHelper.parse(text);
    if (rec === null) {
      return '';
    }
    let url: string = JsonHelper.getString(rec, 'authorize_url', '');
    if (url === '') {
      url = JsonHelper.getString(rec, 'url', '');
    }
    if (url === '') {
      url = JsonHelper.getString(rec, 'login_url', '');
    }
    return url;
  }

  /** 用回跳 code 换 token（POST /api/auth/oidc/exchange → login 同构包络） */
  static async oidcExchange(code: string): Promise<string> {
    const body: Record<string, Object> = { 'code': code };
    return await HttpClient.getInstance().post(
      '/api/auth/oidc/exchange', JSON.stringify(body));
  }

  /** OIDC 登录按钮状态（GET /api/auth/oidc/status → {enabled,display_name}） */
  static async oidcStatus(): Promise<SsoProviderStatusModel> {
    const text: string = await HttpClient.getInstance().get('/api/auth/oidc/status');
    const rec = JsonHelper.parse(text);
    if (rec === null) {
      return new SsoProviderStatusModel('oidc', '', false);
    }
    return new SsoProviderStatusModel(
      'oidc',
      JsonHelper.getString(rec, 'display_name', ''),
      JsonHelper.getBool(rec, 'enabled', false)
    );
  }
}
