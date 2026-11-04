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
import { SlashCommandSpec } from '../model/SlashModels';
import { TextAssistService } from './TextAssistService';
import { HeartbeatConfigModel } from '../model/AgentModels';
import { JsonHelper } from '../utils/JsonHelper';

export class AgentService {
  /** 已安装智能体列表（自己的 + 共享的） */
  static async listMine(): Promise<Array<AgentModel>> {
    const text: string = await HttpClient.getInstance().get('/api/agents?scope=mine');
    return AgentModel.parseList(text);
  }

  /** 原生斜杠命令列表（服务端动态下发，空列表时调用方走内置回退） */
  static async listSlashCommands(): Promise<Array<SlashCommandSpec>> {
    const text: string = await HttpClient.getInstance().get('/api/slash/commands?origin=ui');
    return SlashCommandSpec.parseList(text);
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

  /** 媒体预览地址（Image/Video 直连；source 为 file:// URL 或工作区相对路径） */
  static mediaPreviewUrl(agentId: string, source: string, mimeType: string = ''): string {
    const base: string = HttpClient.getInstance().getBaseUrl();
    const token: string = HttpClient.getInstance().getToken();
    let url: string = `${base}/api/agents/${agentId}/media/preview` +
      `?source=${encodeURIComponent(source)}&access_token=${encodeURIComponent(token)}`;
    if (mimeType !== '') {
      url += `&mime_type=${encodeURIComponent(mimeType)}`;
    }
    return url;
  }

  /** 媒体预览字节（走 Authorization 头，用于保存/大文件） */
  static async mediaPreviewBytes(agentId: string, source: string,
    mimeType: string = ''): Promise<ArrayBuffer> {
    let path: string =
      `/api/agents/${agentId}/media/preview?source=${encodeURIComponent(source)}`;
    if (mimeType !== '') {
      path += `&mime_type=${encodeURIComponent(mimeType)}`;
    }
    return await HttpClient.getInstance().downloadGet(path);
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

  /** 安装用户发布的私有专家模板（201；服务器 InstallPublishedExpertBody 要求 name ≥1 字符） */
  static async installPublished(publishedId: string, name: string): Promise<void> {
    const safeName: string = name.trim() !== '' ? name.trim() : publishedId;
    const body: Record<string, Object> = { 'name': safeName };
    await HttpClient.getInstance().post(
      `/api/experts/published/${publishedId}/install`, JSON.stringify(body));
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

  /** 提示词润色（已迁移 POST /api/text/assist，kind=chat.prompt）→ {"text": "..."} */
  static async polishPrompt(agentId: string, text: string): Promise<string> {
    return await TextAssistService.polishPrompt(text, agentId);
  }

  /** 聊天附件上传（multipart POST /api/agents/{id}/upload，字段名 file） */
  static async uploadAttachment(agentId: string, fileName: string, contentType: string,
    data: ArrayBuffer): Promise<ChatAttachmentModel> {
    const text: string = await HttpClient.getInstance().postMultipartFile(
      `/api/agents/${agentId}/upload`, 'file', fileName, contentType, data);
    return ChatAttachmentModel.fromResponse(text);
  }

  // ---- 心跳主动唤醒（agent_files.py heartbeat-config）----

  /** 读取心跳配置（GET /api/agents/{id}/heartbeat-config） */
  static async getHeartbeatConfig(agentId: string): Promise<HeartbeatConfigModel> {
    const text: string =
      await HttpClient.getInstance().get(`/api/agents/${agentId}/heartbeat-config`);
    return HeartbeatConfigModel.parse(text);
  }

  /** 保存心跳配置（PUT，body 六字段全量必填） */
  static async putHeartbeatConfig(agentId: string, cfg: HeartbeatConfigModel): Promise<void> {
    const body: Record<string, Object> = {
      'enabled': cfg.enabled,
      'every': cfg.every,
      'target': cfg.target,
      'active_hours_enabled': cfg.activeHoursEnabled,
      'active_hours_start': cfg.activeHoursStart,
      'active_hours_end': cfg.activeHoursEnd
    };
    await HttpClient.getInstance().put(
      `/api/agents/${agentId}/heartbeat-config`, JSON.stringify(body));
  }

  // ---- 标记已读 / 工具开关批量 / 发布为专家 ----

  /** 标记整个智能体已读（POST /api/agents/{id}/read，清未读徽标） */
  static async markRead(agentId: string): Promise<void> {
    await HttpClient.getInstance().post(`/api/agents/${agentId}/read`, '{}');
  }

  /** 内置工具停用清单 + 插件工具开关批量保存（PUT /api/agents/{id}/tool-settings） */
  static async putToolSettings(agentId: string, disabledBuiltin: string[],
    plugins: Record<string, Object> | null): Promise<void> {
    const body: Record<string, Object> = { 'disabled_builtin': disabledBuiltin };
    if (plugins !== null) {
      body['plugins'] = plugins;
    }
    await HttpClient.getInstance().put(
      `/api/agents/${agentId}/tool-settings`, JSON.stringify(body));
  }

  /** 把该智能体工作区发布为专家模板（POST /api/agents/{id}/publish-expert，201） */
  static async publishExpert(agentId: string, name: string, description: string,
    slug: string, welcomeMessage: string, quickPrompts: string[]): Promise<string> {
    const body: Record<string, Object> = { 'name': name };
    if (description !== '') {
      body['description'] = description;
    }
    if (slug !== '') {
      body['slug'] = slug;
    }
    if (welcomeMessage !== '') {
      body['welcome_message'] = welcomeMessage;
    }
    if (quickPrompts.length > 0) {
      body['quick_prompts'] = quickPrompts;
    }
    return await HttpClient.getInstance().post(
      `/api/agents/${agentId}/publish-expert`, JSON.stringify(body));
  }

  // ---- 已发布专家管理 ----

  /** 已发布专家详情（GET /api/experts/published/{id}） */
  static async getPublishedDetail(expertId: string): Promise<ExpertDetailModel> {
    const text: string =
      await HttpClient.getInstance().get(`/api/experts/published/${expertId}`);
    return ExpertDetailModel.parse(text);
  }

  /** 下架已发布专家（DELETE /api/experts/published/{id}） */
  static async unpublishExpert(expertId: string): Promise<void> {
    await HttpClient.getInstance().delete(`/api/experts/published/${expertId}`);
  }

  /** 刷新已发布专家快照（POST .../refresh） */
  static async refreshPublishedExpert(expertId: string): Promise<string> {
    return await HttpClient.getInstance().post(
      `/api/experts/published/${expertId}/refresh`, '{}');
  }

  /** 已发布专家头像地址（Image 直连，access_token 查询参数鉴权） */
  static publishedAvatarUrl(expertId: string): string {
    const base: string = HttpClient.getInstance().getBaseUrl();
    const token: string = HttpClient.getInstance().getToken();
    return `${base}/api/experts/published/${expertId}/avatar?access_token=${encodeURIComponent(token)}`;
  }

  /** 专家市场列表（GET /api/experts/hub?query=&scene=，返回原始文本交 UI 解析） */
  static async listHubExpertsRaw(query: string, scene: string): Promise<string> {
    const params: string[] = [];
    if (query !== '') {
      params.push(`query=${encodeURIComponent(query)}`);
    }
    if (scene !== '') {
      params.push(`scene=${encodeURIComponent(scene)}`);
    }
    const suffix: string = params.length > 0 ? `?${params.join('&')}` : '';
    return await HttpClient.getInstance().get(`/api/experts/hub${suffix}`);
  }
}
