import { HttpClient } from '../net/HttpClient';
import { JsonHelper } from '../utils/JsonHelper';
import { ToolSettingItemModel } from '../model/SkillModels';

/** agent 工具开关（/api/agents/{id}/tool-settings，源 agent_tools.py） */
export class AgentToolSettingsService {
  static async list(agentId: string): Promise<Array<ToolSettingItemModel>> {
    const text: string =
      await HttpClient.getInstance().get(`/api/agents/${agentId}/tool-settings`);
    return ToolSettingItemModel.parseList(text);
  }

  /** 单工具开关切换（builtin：source=builtin；plugin：source=plugin + pluginId） */
  static async patchTool(agentId: string, toolName: string, enabled: boolean,
    source: string = 'builtin', pluginId: string = ''): Promise<void> {
    const body: Record<string, Object> = {
      'enabled': enabled,
      'source': source
    };
    if (source === 'plugin') {
      body['plugin_id'] = pluginId;
    }
    await HttpClient.getInstance().patch(
      `/api/agents/${agentId}/tool-settings/${toolName}`, JSON.stringify(body));
  }
}
