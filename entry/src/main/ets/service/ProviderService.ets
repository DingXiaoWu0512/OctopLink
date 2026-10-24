import { HttpClient } from '../net/HttpClient';
import { JsonHelper } from '../utils/JsonHelper';
import { ProviderModel, ResolvedModelEntry } from '../model/WorkspaceModels';

/** 全局默认模型（GET /api/providers/active-model） */
export class ActiveModel {
  readonly providerName: string;
  readonly model: string;

  constructor(providerName: string, model: string) {
    this.providerName = providerName;
    this.model = model;
  }

  static parse(text: string): ActiveModel {
    const rec = JsonHelper.parse(text);
    if (rec === null) {
      return new ActiveModel('', '');
    }
    return new ActiveModel(
      JsonHelper.getString(rec, 'provider_name', ''),
      JsonHelper.getString(rec, 'model', '')
    );
  }

  /** model_ref 形式："provider/model"；未设置返回空串 */
  ref(): string {
    if (this.providerName === '' || this.model === '') {
      return '';
    }
    return `${this.providerName}/${this.model}`;
  }
}

/**
 * 模型 Provider（契约 docs/api-contract-workspace.md §7）：
 * - 用户侧：resolved / presets / list / active-model（任意登录用户可读）
 * - 管理侧：/api/admin/providers CRUD + 试探（需 providers 权限）
 */
export class ProviderService {
  private static resolvedCache: Array<ResolvedModelEntry> | null = null;

  /** 使 resolved 缓存失效（provider 配置变更后调用） */
  static invalidateCache(): void {
    ProviderService.resolvedCache = null;
  }

  /** 所有启用 provider 的可用模型（模型选择器数据源，内存缓存） */
  static async resolvedModels(force: boolean = false): Promise<Array<ResolvedModelEntry>> {
    const cached: Array<ResolvedModelEntry> | null = ProviderService.resolvedCache;
    if (!force && cached !== null) {
      return cached;
    }
    const text: string = await HttpClient.getInstance().get('/api/providers/resolved');
    const list: Array<ResolvedModelEntry> = ResolvedModelEntry.parseList(text);
    ProviderService.resolvedCache = list;
    return list;
  }

  /** 内置 provider 预设（原始 JSON，调用方按需解析） */
  static async presetsRaw(): Promise<string> {
    return await HttpClient.getInstance().get('/api/providers/presets');
  }

  /** provider 列表（只读） */
  static async list(): Promise<Array<ProviderModel>> {
    const text: string = await HttpClient.getInstance().get('/api/providers');
    return ProviderModel.parseList(text);
  }

  /** 全局默认模型 */
  static async activeModelGet(): Promise<ActiveModel> {
    const text: string = await HttpClient.getInstance().get('/api/providers/active-model');
    return ActiveModel.parse(text);
  }

  /** 设置全局默认模型（需 providers 权限） */
  static async activeModelPut(providerName: string, model: string): Promise<void> {
    const body: Record<string, Object> = {
      'provider_name': providerName,
      'model': model
    };
    await HttpClient.getInstance().put('/api/providers/active-model', JSON.stringify(body));
  }

  // ---------- 管理侧（providers 权限） ----------

  static async adminList(): Promise<Array<ProviderModel>> {
    const text: string = await HttpClient.getInstance().get('/api/admin/providers');
    return ProviderModel.parseList(text);
  }

  static async adminCreate(bodyStr: string): Promise<void> {
    await HttpClient.getInstance().post('/api/admin/providers', bodyStr);
  }

  static async adminPatch(providerId: number, bodyStr: string): Promise<void> {
    await HttpClient.getInstance().patch(`/api/admin/providers/${providerId}`, bodyStr);
  }

  static async adminRemove(providerId: number): Promise<void> {
    await HttpClient.getInstance().delete(`/api/admin/providers/${providerId}`);
  }

  /** 试探未保存草稿，返回原始响应（成功/失败详情由调用方解析展示） */
  static async adminTestDraft(bodyStr: string): Promise<string> {
    return await HttpClient.getInstance().post('/api/admin/providers/test-draft', bodyStr);
  }

  /** OpenAI 兼容拉取 /models（仅 kind=openai），返回原始响应 */
  static async adminFetchModels(bodyStr: string): Promise<string> {
    return await HttpClient.getInstance().post('/api/admin/providers/fetch-models', bodyStr);
  }

  /** 试探已存 provider，返回原始响应 */
  static async adminTest(providerId: number, bodyStr: string): Promise<string> {
    return await HttpClient.getInstance().post(`/api/admin/providers/${providerId}/test`, bodyStr);
  }
}
