import { HttpClient } from '../net/HttpClient';
import { JsonHelper } from '../utils/JsonHelper';
import { BridgeConnectionModel, BridgeProbeResultModel } from '../model/BridgeModels';

/** 桥接设备（/api/bridge/connections*，源 bridge.py；操作一律用 connection_id） */
export class BridgeService {
  static async list(): Promise<Array<BridgeConnectionModel>> {
    const text: string =
      await HttpClient.getInstance().get('/api/bridge/connections');
    return BridgeConnectionModel.parseList(text);
  }

  static async get(connectionId: string): Promise<BridgeConnectionModel> {
    const text: string =
      await HttpClient.getInstance().get(`/api/bridge/connections/${connectionId}`);
    const rec = JsonHelper.parse(text);
    return BridgeConnectionModel.fromRecord(rec === null ? {} : rec);
  }

  /** 探测对端 Octop：验证账密并拉取专家列表（不创建连接、不拨号） */
  static async probe(peerBaseUrl: string, peerUsername: string,
    password: string): Promise<BridgeProbeResultModel> {
    const body: Record<string, Object> = {
      'peer_base_url': peerBaseUrl,
      'peer_username': peerUsername,
      'password': password
    };
    const text: string =
      await HttpClient.getInstance().post('/api/bridge/probe', JSON.stringify(body));
    return BridgeProbeResultModel.parse(text);
  }

  /** 已存连接重探测（password 留空时使用存储凭据） */
  static async probeConnection(connectionId: string, peerBaseUrl: string,
    peerUsername: string, password: string): Promise<BridgeProbeResultModel> {
    const body: Record<string, Object> = {
      'peer_base_url': peerBaseUrl,
      'peer_username': peerUsername
    };
    if (password !== '') {
      body['password'] = password;
    }
    const text: string = await HttpClient.getInstance().post(
      `/api/bridge/connections/${connectionId}/probe`, JSON.stringify(body));
    return BridgeProbeResultModel.parse(text);
  }

  /** 创建连接（connect=true 时创建后立即拨号 Bridge WS） */
  static async create(peerBaseUrl: string, peerUsername: string, password: string,
    displayName: string, notes: string, connect: boolean): Promise<BridgeConnectionModel> {
    const body: Record<string, Object> = {
      'peer_base_url': peerBaseUrl,
      'peer_username': peerUsername,
      'password': password,
      'display_name': displayName,
      'connect': connect
    };
    if (notes !== '') {
      body['notes'] = notes;
    }
    const text: string = await HttpClient.getInstance().post(
      '/api/bridge/connections', JSON.stringify(body));
    const rec = JsonHelper.parse(text);
    return BridgeConnectionModel.fromRecord(rec === null ? {} : rec);
  }

  /** 更新连接设置（fields 按需携带 auto_reconnect/display_name/notes 等字段） */
  static async patch(connectionId: string,
    fields: Record<string, Object>): Promise<BridgeConnectionModel> {
    const text: string = await HttpClient.getInstance().patch(
      `/api/bridge/connections/${connectionId}`, JSON.stringify(fields));
    const rec = JsonHelper.parse(text);
    return BridgeConnectionModel.fromRecord(rec === null ? {} : rec);
  }

  /** 切换断线自动重连 */
  static async setAutoReconnect(connectionId: string,
    enabled: boolean): Promise<BridgeConnectionModel> {
    const fields: Record<string, Object> = { 'auto_reconnect': enabled };
    return await BridgeService.patch(connectionId, fields);
  }

  static async remove(connectionId: string): Promise<void> {
    await HttpClient.getInstance().delete(`/api/bridge/connections/${connectionId}`);
  }

  /** 拨号 / 重连 Bridge WS */
  static async connect(connectionId: string): Promise<BridgeConnectionModel> {
    const text: string = await HttpClient.getInstance().post(
      `/api/bridge/connections/${connectionId}/connect`, '{}');
    const rec = JsonHelper.parse(text);
    return BridgeConnectionModel.fromRecord(rec === null ? {} : rec);
  }

  /** 断开 Bridge WS */
  static async disconnect(connectionId: string): Promise<BridgeConnectionModel> {
    const text: string = await HttpClient.getInstance().post(
      `/api/bridge/connections/${connectionId}/disconnect`, '{}');
    const rec = JsonHelper.parse(text);
    return BridgeConnectionModel.fromRecord(rec === null ? {} : rec);
  }

  // ---- 对端资源隧道（经服务端 bridge 转发访问对端 Octop）----

  /** 列出对端可对话的专家（GET /bridge/connections/{id}/agents） */
  static async remoteAgents(connectionId: string): Promise<string> {
    return await HttpClient.getInstance().get(
      `/api/bridge/connections/${connectionId}/agents`);
  }

  /** 列出对端知识库（隧道） */
  static async peerKnowledgeBases(connectionId: string): Promise<string> {
    return await HttpClient.getInstance().get(
      `/api/bridge/connections/${connectionId}/knowledge-bases`);
  }

  /** 对端知识库能力（隧道） */
  static async peerKnowledgeCapability(connectionId: string): Promise<string> {
    return await HttpClient.getInstance().get(
      `/api/bridge/connections/${connectionId}/knowledge-bases/capability`);
  }

  /** 对端已解析模型列表（隧道） */
  static async peerResolvedModels(connectionId: string): Promise<string> {
    return await HttpClient.getInstance().get(
      `/api/bridge/connections/${connectionId}/providers/resolved`);
  }

  /** 对端当前生效模型（隧道） */
  static async peerActiveModel(connectionId: string): Promise<string> {
    return await HttpClient.getInstance().get(
      `/api/bridge/connections/${connectionId}/providers/active-model`);
  }

  /** 对端浏览器环境状态（隧道） */
  static async peerBrowserEnvStatus(connectionId: string): Promise<string> {
    return await HttpClient.getInstance().get(
      `/api/bridge/connections/${connectionId}/browser/env-status`);
  }

  /** 对端连接头像地址（Image 直连，access_token 查询参数鉴权） */
  static avatarUrl(connectionId: string): string {
    const base: string = HttpClient.getInstance().getBaseUrl();
    const token: string = HttpClient.getInstance().getToken();
    return `${base}/api/bridge/connections/${connectionId}/avatar?access_token=${encodeURIComponent(token)}`;
  }

  /** 上传对端连接头像（multipart 字段 file） */
  static async uploadAvatar(connectionId: string, fileName: string, contentType: string,
    data: ArrayBuffer): Promise<void> {
    await HttpClient.getInstance().postMultipartFile(
      `/api/bridge/connections/${connectionId}/avatar`, 'file', fileName, contentType, data);
  }

  /** 删除对端连接头像 */
  static async deleteAvatar(connectionId: string): Promise<void> {
    await HttpClient.getInstance().delete(
      `/api/bridge/connections/${connectionId}/avatar`);
  }
}
