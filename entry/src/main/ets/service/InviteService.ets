import { HttpClient } from '../net/HttpClient';
import { JsonHelper } from '../utils/JsonHelper';
import { InviteModel } from '../model/InviteModels';

/** 邀请码校验结果（POST /api/auth/invite/validate） */
export class InviteValidateResult {
  readonly valid: boolean;
  readonly note: string;
  readonly expiresAtMs: number;
  readonly createdBy: string;

  constructor(valid: boolean, note: string, expiresAtMs: number, createdBy: string) {
    this.valid = valid;
    this.note = note;
    this.expiresAtMs = expiresAtMs;
    this.createdBy = createdBy;
  }

  static parse(text: string): InviteValidateResult {
    const rec = JsonHelper.parse(text);
    if (rec === null) {
      return new InviteValidateResult(false, '响应解析失败', 0, '');
    }
    return new InviteValidateResult(
      JsonHelper.getBool(rec, 'valid', false),
      JsonHelper.getString(rec, 'note', ''),
      JsonHelper.toMs(rec['expires_at']),
      JsonHelper.getString(rec, 'created_by', '')
    );
  }
}

/**
 * 邀请码服务：
 * - /api/users/invites*：管理员创建/吊销/列表（需 users 权限）
 * - /api/auth/invite/*：免登录注册（校验 + 兑换创建用户，返回与 login 同构的 token 包络）
 */
export class InviteService {
  static async list(): Promise<Array<InviteModel>> {
    const text: string =
      await HttpClient.getInstance().get('/api/users/invites');
    return InviteModel.parseList(text);
  }

  /** 创建邀请码（note 可选；expiresInDays 1-90，服务端默认 7） */
  static async create(note: string, expiresInDays: number): Promise<InviteModel> {
    const body: Record<string, Object> = { 'expires_in_days': expiresInDays };
    if (note !== '') {
      body['note'] = note;
    }
    const text: string = await HttpClient.getInstance().post(
      '/api/users/invites', JSON.stringify(body));
    const rec = JsonHelper.parse(text);
    return InviteModel.fromRecord(rec === null ? {} : rec);
  }

  /** 吊销未使用的邀请码（仅 pending 状态可吊销） */
  static async revoke(inviteId: number): Promise<InviteModel> {
    const text: string = await HttpClient.getInstance().post(
      `/api/users/invites/${inviteId}/revoke`, '{}');
    const rec = JsonHelper.parse(text);
    return InviteModel.fromRecord(rec === null ? {} : rec);
  }

  // ---- 免登录注册（公开接口，无需 token）----

  /** 校验邀请码（POST /api/auth/invite/validate） */
  static async validate(code: string): Promise<InviteValidateResult> {
    const body: Record<string, Object> = { 'code': code };
    const text: string = await HttpClient.getInstance().post(
      '/api/auth/invite/validate', JSON.stringify(body));
    return InviteValidateResult.parse(text);
  }

  /**
   * 兑换邀请码注册用户（POST /api/auth/invite/redeem）。
   * 响应与 login 同构：access_token/token_type/expires_in/user，由调用方走统一登录落地。
   */
  static async redeem(code: string, username: string, password: string,
    displayName: string, email: string): Promise<string> {
    const body: Record<string, Object> = {
      'code': code,
      'username': username,
      'password': password
    };
    if (displayName !== '') {
      body['display_name'] = displayName;
    }
    if (email !== '') {
      body['email'] = email;
    }
    return await HttpClient.getInstance().post(
      '/api/auth/invite/redeem', JSON.stringify(body));
  }
}
