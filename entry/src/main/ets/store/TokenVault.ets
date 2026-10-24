import { asset } from '@kit.AssetStoreKit';
import { util } from '@kit.ArkTS';
import { BusinessError } from '@kit.BasicServicesKit';
import { Log } from '../utils/Logger';

const TOKEN_ALIAS = 'octop_link_access_token';
const ERR_ASSET_EXISTS = 24000003;

/**
 * JWT 安全存储：基于系统 AssetStore（硬件加密），
 * 应用沙箱内也不落明文，符合敏感凭据存储要求。
 */
export class TokenVault {
  private static encoder: util.TextEncoder = new util.TextEncoder();
  private static decoder: util.TextDecoder = new util.TextDecoder();

  /** 保存 token（存在则更新），失败返回 false */
  static saveToken(token: string): boolean {
    if (token === '') {
      return false;
    }
    const aliasBytes: Uint8Array = TokenVault.encoder.encodeInto(TOKEN_ALIAS);
    const secretBytes: Uint8Array = TokenVault.encoder.encodeInto(token);
    const attr: asset.AssetMap = new Map<asset.Tag, asset.Value>();
    attr.set(asset.Tag.ALIAS, aliasBytes);
    attr.set(asset.Tag.SECRET, secretBytes);
    try {
      asset.addSync(attr);
      return true;
    } catch (e) {
      const err = e as BusinessError;
      if (err.code === ERR_ASSET_EXISTS) {
        try {
          const query: asset.AssetMap = new Map<asset.Tag, asset.Value>();
          query.set(asset.Tag.ALIAS, aliasBytes);
          const upd: asset.AssetMap = new Map<asset.Tag, asset.Value>();
          upd.set(asset.Tag.SECRET, secretBytes);
          asset.updateSync(query, upd);
          return true;
        } catch (e2) {
          const err2 = e2 as BusinessError;
          Log.error(`TokenVault update failed: ${err2.code} ${err2.message}`);
          return false;
        }
      }
      Log.error(`TokenVault add failed: ${err.code} ${err.message}`);
      return false;
    }
  }

  /** 读取 token，不存在或失败返回空串 */
  static loadToken(): string {
    const query: asset.AssetMap = new Map<asset.Tag, asset.Value>();
    query.set(asset.Tag.ALIAS, TokenVault.encoder.encodeInto(TOKEN_ALIAS));
    query.set(asset.Tag.RETURN_TYPE, asset.ReturnType.ALL);
    try {
      const result: Array<asset.AssetMap> = asset.querySync(query);
      if (result.length === 0) {
        return '';
      }
      const secret: asset.Value | undefined = result[0].get(asset.Tag.SECRET);
      if (secret === undefined || !(secret instanceof Uint8Array)) {
        return '';
      }
      return TokenVault.decoder.decodeToString(secret);
    } catch (e) {
      const err = e as BusinessError;
      Log.warn(`TokenVault load failed: ${err.code} ${err.message}`);
      return '';
    }
  }

  /** 清除 token */
  static clearToken(): void {
    const query: asset.AssetMap = new Map<asset.Tag, asset.Value>();
    query.set(asset.Tag.ALIAS, TokenVault.encoder.encodeInto(TOKEN_ALIAS));
    try {
      asset.removeSync(query);
    } catch (e) {
      // 不存在视为已清除，其余错误仅记录
      const err = e as BusinessError;
      Log.debug(`TokenVault clear: ${err.code}`);
    }
  }
}
