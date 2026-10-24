import { HttpClient } from '../net/HttpClient';
import { AgentModel } from '../model/AgentModels';
import { BuiltinExpertModel, HubExpertListModel, WelcomeCardModel } from '../model/ExpertModels';
import { ChatAttachmentModel } from '../model/MessageModels';
import { JsonHelper } from '../utils/JsonHelper';

export class AgentService {
  /** 已安装智能体列表（自己的 + 共享的） */
  static async listMine(): Promise<Array<AgentModel>> {
    const text: string = await HttpClient.getInstance().get('/api/agents?scope=mine');
    return AgentModel.parseList(text);
  }

  /** 单个智能体详情 */
  static async get(agentId: string): Promise<AgentModel> {
    const text: string = await HttpClient.getInstance().get(`/api/agents/${agentId}`);
    return AgentModel.parseOne(text);
  }

  /** 更新智能体（PATCH） */
  static async update(agentId: string, bodyStr: string): Promise<void> {
    await HttpClient.getInstance().patch(`/api/agents/${agentId}`, bodyStr);
  }

  /** 删除智能体 */
  static async remove(agentId: string): Promise<void> {
    await HttpClient.getInstance().delete(`/api/agents/${agentId}`);
  }

  /** 启动智能体 */
  static async start(agentId: string): Promise<void> {
    await HttpClient.getInstance().post(`/api/agents/${agentId}/start`, '{}');
  }

  /** 停止智能体 */
  static async stop(agentId: string): Promise<void> {
    await HttpClient.getInstance().post(`/api/agents/${agentId}/stop`, '{}');
  }

  /** 内置专家模板列表（GET /api/experts） */
  static async listBuiltinExperts(): Promise<Array<BuiltinExpertModel>> {
    const text: string = await HttpClient.getInstance().get('/api/experts');
    return BuiltinExpertModel.parseList(text);
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
