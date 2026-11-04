import { JsonHelper } from '../utils/JsonHelper';

/**
 * 邀请码域数据模型（源：octop/api/routers/invites.py）：
 * - InviteModel：一次性用户邀请码（invite_status_payload + invite_url/invite_path 扩展）
 */

/** 邀请码（status: pending | used | expired | revoked） */
export class InviteModel {
  readonly id: number;
  readonly code: string;
  readonly note: string;
  readonly createdAtMs: number;
  readonly expiresAtMs: number;
  readonly usedAtMs: number;
  readonly revokedAtMs: number;
  readonly status: string;
  readonly roleName: string;
  readonly inviteUrl: string;

  constructor(id: number, code: string, note: string, createdAtMs: number, expiresAtMs: number,
    usedAtMs: number, revokedAtMs: number, status: string, roleName: string, inviteUrl: string) {
    this.id = id;
    this.code = code;
    this.note = note;
    this.createdAtMs = createdAtMs;
    this.expiresAtMs = expiresAtMs;
    this.usedAtMs = usedAtMs;
    this.revokedAtMs = revokedAtMs;
    this.status = status;
    this.roleName = roleName;
    this.inviteUrl = inviteUrl;
  }

  /** 状态中文文案 */
  statusText(): string {
    if (this.status === 'pending') {
      return '待使用';
    }
    if (this.status === 'used') {
      return '已使用';
    }
    if (this.status === 'expired') {
      return '已过期';
    }
    return '已吊销';
  }

  static fromRecord(rec: Record<string, Object>): InviteModel {
    return new InviteModel(
      JsonHelper.getNumber(rec, 'id', 0),
      JsonHelper.getString(rec, 'code', ''),
      JsonHelper.getString(rec, 'note', ''),
      JsonHelper.toMs(rec['created_at']),
      JsonHelper.toMs(rec['expires_at']),
      JsonHelper.toMs(rec['used_at']),
      JsonHelper.toMs(rec['revoked_at']),
      JsonHelper.getString(rec, 'status', 'pending'),
      JsonHelper.getString(rec, 'role_name', ''),
      JsonHelper.getString(rec, 'invite_url', '')
    );
  }

  static parseList(text: string): Array<InviteModel> {
    const result: Array<InviteModel> = [];
    const arr = JsonHelper.parseArray(text);
    if (arr === null) {
      return result;
    }
    for (const rec of arr) {
      result.push(InviteModel.fromRecord(rec));
    }
    return result;
  }
}
