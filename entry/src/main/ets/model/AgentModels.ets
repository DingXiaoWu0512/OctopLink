import { JsonHelper } from '../utils/JsonHelper';
import { OctopApiError } from '../net/HttpClient';

/** 已安装智能体（GET /api/agents?scope=mine 列表项 / GET /api/agents/{id} 详情） */
export class AgentModel {
  readonly agentId: string;
  readonly name: string;
  readonly description: string;
  readonly welcomeMessage: string;
  readonly personaMbti: string;
  readonly systemPrompt: string;
  readonly defaultModel: string;
  readonly state: string;
  readonly isShared: boolean;
  readonly isOwner: boolean;
  readonly ownerUsername: string;
  readonly unreadCount: number;
  readonly kind: string;
  readonly color: string;
  readonly iconName: string;
  readonly iconUrl: string;
  readonly templateName: string;

  constructor(agentId: string, name: string, description: string, welcomeMessage: string,
    personaMbti: string, systemPrompt: string, defaultModel: string, state: string,
    isShared: boolean, isOwner: boolean, ownerUsername: string, unreadCount: number,
    kind: string, color: string, iconName: string, iconUrl: string, templateName: string) {
    this.agentId = agentId;
    this.name = name === '' ? '智能体' : name;
    this.description = description;
    this.welcomeMessage = welcomeMessage;
    this.personaMbti = personaMbti;
    this.systemPrompt = systemPrompt;
    this.defaultModel = defaultModel;
    this.state = state;
    this.isShared = isShared;
    this.isOwner = isOwner;
    this.ownerUsername = ownerUsername;
    this.unreadCount = unreadCount;
    this.kind = kind;
    this.color = color;
    this.iconName = iconName;
    this.iconUrl = iconUrl;
    this.templateName = templateName;
  }

  static fromRecord(rec: Record<string, Object>): AgentModel {
    // welcome_message 可能为字符串或 {zh,en} 本地化对象
    let welcome: string = JsonHelper.getString(rec, 'welcome_message', '');
    if (welcome === '') {
      const wmRec: Record<string, Object> | null = JsonHelper.getRecord(rec, 'welcome_message');
      welcome = JsonHelper.getString(wmRec, 'zh', '');
      if (welcome === '') {
        welcome = JsonHelper.getString(wmRec, 'en', '');
      }
    }
    return new AgentModel(
      JsonHelper.getString(rec, 'agent_id', ''),
      JsonHelper.getString(rec, 'name', ''),
      JsonHelper.getString(rec, 'description', ''),
      welcome,
      JsonHelper.getString(rec, 'persona_mbti', ''),
      JsonHelper.getString(rec, 'system_prompt', ''),
      JsonHelper.getString(rec, 'default_model', ''),
      JsonHelper.getString(rec, 'state', ''),
      JsonHelper.getBool(rec, 'is_shared', false),
      JsonHelper.getBool(rec, 'is_owner', true),
      JsonHelper.getString(rec, 'owner_username', ''),
      JsonHelper.getNumber(rec, 'unread_count', 0),
      JsonHelper.getString(rec, 'kind', 'expert'),
      JsonHelper.getString(rec, 'color', ''),
      JsonHelper.getString(rec, 'icon_name', ''),
      JsonHelper.getString(rec, 'icon_url', ''),
      JsonHelper.getString(rec, 'template_name', '')
    );
  }

  /** 解析单个 agent 详情（GET /api/agents/{id}） */
  static parseOne(text: string): AgentModel {
    const rec = JsonHelper.parse(text);
    if (rec === null) {
      throw new OctopApiError('智能体信息响应格式错误', 0, 'BAD_RESPONSE');
    }
    return AgentModel.fromRecord(rec);
  }

  /** 解析列表：兼容顶层数组与 {agents:[...]} 两种形态 */
  static parseList(text: string): Array<AgentModel> {
    const result: Array<AgentModel> = [];
    const arr = JsonHelper.parseArray(text);
    if (arr !== null) {
      for (const rec of arr) {
        result.push(AgentModel.fromRecord(rec));
      }
      return result;
    }
    const obj = JsonHelper.parse(text);
    const items = JsonHelper.getRecordArray(obj, 'agents');
    for (const rec of items) {
      result.push(AgentModel.fromRecord(rec));
    }
    return result;
  }
}
