import { HttpClient } from '../net/HttpClient';
import { JsonHelper } from '../utils/JsonHelper';

/**
 * 文本辅助（POST /api/text/assist，源 text_assist.py）。
 * kind 枚举（18 种）：chat.prompt、expert.description、expert.welcome_message、
 * team.description、team.welcome_message、skill_package.description、skill.description、
 * skill.label_zh、skill.label_en、skill.summary_zh、skill.summary_en、skill.body、
 * knowledge_base.description、connector.description、bridge.notes、user_group.description、
 * user_role.description。chat.prompt 必须传 text；其余必须传 context.name。
 */
export class TextAssistService {
  /** 通用入口：contextStr 为可选 JSON 对象文本 */
  static async assist(kind: string, text: string, contextStr: string = '',
    locale: string = 'zh', defaultModel: string = '',
    agentId: string = ''): Promise<string> {
    const body: Record<string, Object> = {
      'kind': kind,
      'text': text,
      'locale': locale
    };
    if (contextStr !== '') {
      const context: Record<string, Object> | null = JsonHelper.parse(contextStr);
      if (context !== null) {
        body['context'] = context;
      }
    }
    if (defaultModel !== '') {
      body['default_model'] = defaultModel;
    }
    if (agentId !== '') {
      body['agent_id'] = agentId;
    }
    const resp: string =
      await HttpClient.getInstance().post('/api/text/assist', JSON.stringify(body));
    const rec = JsonHelper.parse(resp);
    return rec === null ? '' : JsonHelper.getString(rec, 'text', '');
  }

  /** 提示词润色（chat.prompt） */
  static async polishPrompt(text: string, agentId: string = '',
    defaultModel: string = ''): Promise<string> {
    return await TextAssistService.assist('chat.prompt', text, '', 'zh', defaultModel, agentId);
  }

  /** 按 name 生成描述（如 expert.description / skill.description 等） */
  static async describe(kind: string, name: string, locale: string = 'zh'): Promise<string> {
    const context: Record<string, Object> = { 'name': name };
    return await TextAssistService.assist(kind, '', JSON.stringify(context), locale, '', '');
  }
}
