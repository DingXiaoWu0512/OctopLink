import { HttpClient } from '../net/HttpClient';
import { AgentModel } from '../model/AgentModels';
import {
  BuiltinExpertModel,
  ExpertDetailModel,
  HubExpertListModel,
  HubExpertModel,
  PublishedExpertModel,
  WelcomeCardModel
} from '../model/ExpertModels';
import { ChatAttachmentModel } from '../model/MessageModels';
import { JsonHelper } from '../utils/JsonHelper';

export class AgentService {
  /** 已安装智能体列表（自己的 + 共享的） */
  static async listMine(): Promise<Array<AgentModel>> {
    const text: string = await HttpClient.getInstance().get('/api/agents?scope=mine');
    return AgentModel.parseList(text);
  }

  /** 全部智能体（需 users 权限） */
  static async listAll(): Promise<Array<AgentModel>> {
    const text: string = await HttpClient.getInstance().get('/api/agents?scope=all');
    return AgentModel.parseList(text);
  }

  /** 单个智能体详情 */
  static async get(agentId: string): Promise<AgentModel> {
    const text: string = await HttpClient.getInstance().get(`/api/agents/${agentId}`);
    return AgentModel.parseOne(text);
  }

  /** 创建智能体（POST /api/agents，bodyStr 为 AgentCreateBody JSON） */
  static async create(bodyStr: string): Promise<void> {
    await HttpClient.getInstance().post('/api/agents', bodyStr);
  }

  /** 更新智能体（PATCH） */
  static async update(agentId: string, bodyStr: string): Promise<void> {
    await HttpClient.getInstance().patch(`/api/agents/${agentId}`, bodyStr);
  }

  /** 删除智能体 */
  static async remove(agentId: string): Promise<void> {
    await HttpClient.getInstance().delete(`/api/agents/${agentId}`);
  }

  /** 头像地址（Image 直连，access_token 查询参数鉴权） */
  static avatarUrl(agentId: string): string {
    const base: string = HttpClient.getInstance().getBaseUrl();
    const token: string = HttpClient.getInstance().getToken();
    return `${base}/api/agents/${agentId}/avatar?access_token=${encodeURIComponent(token)}`;
  }

  /** 相对资源路径转绝对地址（icon_url 等以 / 开头的相对路径） */
  static assetUrl(path: string): string {
    if (path === '' || path.startsWith('http://') || path.startsWith('https://')) {
      return path;
    }
    const base: string = HttpClient.getInstance().getBaseUrl();
    const normalized: string = path.startsWith('/') ? path : `/${path}`;
    return `${base}${normalized}`;
  }

  /** 上传头像（multipart，字段名 file） */
  static async uploadAvatar(agentId: string, fileName: string, contentType: string,
    data: ArrayBuffer): Promise<void> {
    await HttpClient.getInstance().postMultipartFile(
      `/api/agents/${agentId}/avatar`, 'file', fileName, contentType, data);
  }

  /** 删除头像 */
  static async deleteAvatar(agentId: string): Promise<void> {
    await HttpClient.getInstance().delete(`/api/agents/${agentId}/avatar`);
  }

  /** 启动智能体 */
  static async start(agentId: string): Promise<void> {
    await HttpClient.getInstance().post(`/api/agents/${agentId}/start`, '{}');
  }

  /** 停止智能体 */
  static async stop(agentId: string): Promise<void> {
    await HttpClient.getInstance().post(`/api/agents/${agentId}/stop`, '{}');
  }

  /** 重载智能体 */
  static async reload(agentId: string): Promise<void> {
    await HttpClient.getInstance().post(`/api/agents/${agentId}/reload`, '{}');
  }

  /** 运行状态原始响应（GET /status） */
  static async getStatus(agentId: string): Promise<string> {
    return await HttpClient.getInstance().get(`/api/agents/${agentId}/status`);
  }

  /** 内置专家模板列表（GET /api/experts） */
  static async listBuiltinExperts(): Promise<Array<BuiltinExpertModel>> {
    const text: string = await HttpClient.getInstance().get('/api/experts');
    return BuiltinExpertModel.parseList(text);
  }

  /** 内置模板详情（GET /api/experts/{id}，含 file_contents） */
  static async getExpertDetail(expertId: string): Promise<ExpertDetailModel> {
    const text: string = await HttpClient.getInstance().get(`/api/experts/${expertId}`);
    return ExpertDetailModel.parse(text);
  }

  /** 专家市场（GET /api/experts/hub） */
  static async listHubExperts(query: string, scene: string): Promise<HubExpertListModel> {
    const params: string[] = [];
    if (query !== '') {
      params.push(`q=${encodeURIComponent(query)}`);
    }
    if (scene !== '') {
      params.push(`scene=${encodeURIComponent(scene)}`);
    }
    const suffix: string = params.length > 0 ? `?${params.join('&')}` : '';
    const text: string = await HttpClient.getInstance().get(`/api/experts/hub${suffix}`);
    return HubExpertListModel.parse(text);
  }

  /** 市场专家详情（GET /api/experts/hub/{slug}） */
  static async getHubDetail(slug: string): Promise<ExpertDetailModel> {
    const text: string = await HttpClient.getInstance().get(`/api/experts/hub/${slug}`);
    return ExpertDetailModel.parse(text);
  }

  /** 用户发布的私有专家模板列表 */
  static async publishedList(): Promise<Array<PublishedExpertModel>> {
    const text: string = await HttpClient.getInstance().get('/api/experts/published');
    return PublishedExpertModel.parseList(text);
  }

  /** 安装用户发布的私有专家模板（201） */
  static async installPublished(publishedId: string): Promise<void> {
    await HttpClient.getInstance().post(`/api/experts/published/${publishedId}/install`, '{}');
  }

  /** 从内置专家模板创建智能体（201） */
  static async createFromBuiltinExpert(expertId: string, name: string): Promise<void> {
    const body: Record<string, Object> = {};
    if (name !== '') {
      body['name'] = name;
    }
    await HttpClient.getInstance().post(`/api/agents/from-expert/${expertId}`, JSON.stringify(body));
  }

  /** 从市场专家安装智能体（201） */
  static async installHubExpert(slug: string): Promise<void> {
    await HttpClient.getInstance().post(`/api/experts/hub/${slug}/install`, '{}');
  }

  /** 空会话欢迎卡片（GET /api/agents/{id}/chat/welcome） */
  static async getWelcomeCard(agentId: string): Promise<WelcomeCardModel> {
    const text: string = await HttpClient.getInstance().get(`/api/agents/${agentId}/chat/welcome`);
    return WelcomeCardModel.parse(text);
  }

  /** 提示词润色（POST /api/agents/{id}/chat/polish）→ {"text": "..."} */
  static async polishPrompt(agentId: string, text: string): Promise<string> {
    const body: Record<string, Object> = { 'text': text };
    const resp: string =
      await HttpClient.getInstance().post(`/api/agents/${agentId}/chat/polish`, JSON.stringify(body));
    const rec = JsonHelper.parse(resp);
    return rec === null ? '' : JsonHelper.getString(rec, 'text', '');
  }

  /** 聊天附件上传（multipart POST /api/agents/{id}/upload，字段名 file） */
  static async uploadAttachment(agentId: string, fileName: string, contentType: string,
    data: ArrayBuffer): Promise<ChatAttachmentModel> {
    const text: string = await HttpClient.getInstance().postMultipartFile(
      `/api/agents/${agentId}/upload`, 'file', fileName, contentType, data);
    return ChatAttachmentModel.fromResponse(text);
  }
}
