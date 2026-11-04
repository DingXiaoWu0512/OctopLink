import { ProviderModel, ProviderPresetModel } from '../../model/WorkspaceModels';
import { ActiveModel, ProviderService } from '../../service/ProviderService';
import { AuthService } from '../../service/AuthService';
import { OctopUserModel } from '../../model/AuthModels';
import { OctopApiError } from '../../net/HttpClient';
import { JsonHelper } from '../../utils/JsonHelper';
import { EmptyView } from '../../components/EmptyView';
import { ErrorRetry } from '../../components/ErrorRetry';
import { ModelPickerSheet } from '../../components/ModelPickerSheet';
import { PageHeader } from '../../components/PageHeader';
import { UiMaterialKit } from '../../components/UiMaterialKit';
import { MenuSheetContent, MenuSheetOption } from '../../components/MenuSheet';

/**
 * 模型配置页（路由 'providers'）：
 * - 全局默认模型卡（active-model 读写，ModelPickerSheet 选择）
 * - provider 列表（providers 权限 adminList 可管理；无权限 list 只读）
 * - 新建/编辑 provider 表单（预设预填 + 草稿试连 + 拉取模型）
 */
@Component
export struct ProvidersPage {
  @State loading: boolean = true;
  @State refreshing: boolean = false;
  @State errorMsg: string = '';
  @State providers: Array<ProviderModel> = [];
  @State activeProviderName: string = '';
  @State activeModelId: string = '';
  @State canManage: boolean = false;
  // 单 bindSheet 分发：'' | 'model'（模型选择）| 'form'（新建/编辑表单）
  @State sheetOpen: boolean = false;
  @State sheetMode: string = '';
  // 长按操作菜单
  @State menuOpen: boolean = false;
  @State menuTitle: string = '';
  @State menuMessage: string = '';
  @State menuOptions: Array<MenuSheetOption> = [];
  private menuActions: Array<() => void> = [];
  // 新建/编辑表单
  @State formEditId: number = 0;
  @State formName: string = '';
  @State formKind: string = '';
  @State formBaseUrl: string = '';
  @State formApiKey: string = '';
  @State formModels: string = '';
  @State formNote: string = '';
  @State formEnabled: boolean = true;
  @State formSaving: boolean = false;
  @State formTesting: boolean = false;
  @State presets: Array<ProviderPresetModel> = [];
  @State presetsLoading: boolean = false;
  private pathStack: NavPathStack | null = null;

  private onNavReady(ctx: NavDestinationContext): void {
    this.pathStack = ctx.pathStack;
    this.load();
  }

  /** 权限判定：admin 或持 providers 权限可管理；失败按只读降级 */
  private async loadPermissions(): Promise<boolean> {
    try {
      const user: OctopUserModel = await AuthService.me();
      return user.hasPermission('providers');
    } catch (e) {
      return false;
    }
  }

  private async load(): Promise<void> {
    this.loading = this.providers.length === 0;
    this.errorMsg = '';
    const canManage: boolean = await this.loadPermissions();
    this.canManage = canManage;
    try {
      this.providers = canManage ? await ProviderService.adminList() : await ProviderService.list();
    } catch (e) {
      this.errorMsg = e instanceof OctopApiError ? e.message : 'Provider 列表加载失败';
    }
    try {
      const active: ActiveModel = await ProviderService.activeModelGet();
      this.activeProviderName = active.providerName;
      this.activeModelId = active.model;
    } catch (e) {
      this.activeProviderName = '';
      this.activeModelId = '';
    }
    this.loading = false;
    this.refreshing = false;
  }

  private activeModelText(): string {
    if (this.activeProviderName === '' || this.activeModelId === '') {
      return '未设置';
    }
    return `${this.activeProviderName}/${this.activeModelId}`;
  }

  /** 打开全局默认模型选择（无权限只读提示） */
  private openActiveModelPicker(): void {
    if (!this.canManage) {
      this.getUIContext().getPromptAction().showToast({ message: '需要 providers 权限' });
      return;
    }
    this.sheetMode = 'model';
    this.sheetOpen = true;
  }

  /** PUT active-model：ref = "provider/model" */
  private async saveActiveModel(ref: string): Promise<void> {
    const idx: number = ref.indexOf('/');
    if (idx <= 0 || idx >= ref.length - 1) {
      return;
    }
    const providerName: string = ref.substring(0, idx);
    const model: string = ref.substring(idx + 1);
    this.sheetOpen = false;
    try {
      await ProviderService.activeModelPut(providerName, model);
      this.activeProviderName = providerName;
      this.activeModelId = model;
      this.getUIContext().getPromptAction().showToast({ message: '全局默认模型已保存' });
    } catch (e) {
      const message: string = e instanceof OctopApiError ? e.message : '保存失败';
      this.getUIContext().getPromptAction().showToast({ message });
    }
  }

  // ---- 长按操作菜单 ----

  private showProviderMenu(provider: ProviderModel): void {
    if (!this.canManage) {
      return;
    }
    this.menuTitle = provider.name === '' ? `#${provider.id}` : provider.name;
    this.menuMessage = provider.baseUrl === '' ? provider.kind : `${provider.kind} · ${provider.baseUrl}`;
    this.menuOptions = [
      new MenuSheetOption($r('sys.symbol.bolt'), '测试连通性', '试探已保存的 provider', false),
      new MenuSheetOption($r('sys.symbol.magnifyingglass'), '拉取模型列表', 'OpenAI 兼容 /models 接口', false),
      new MenuSheetOption(provider.enabled ? $r('sys.symbol.xmark_circle') : $r('sys.symbol.checkmark_circle'),
        provider.enabled ? '停用' : '启用', '', false),
      new MenuSheetOption($r('sys.symbol.square_and_pencil'), '编辑', '修改接口地址、密钥与模型', false),
      new MenuSheetOption($r('sys.symbol.trash'), '删除', '', true)
    ];
    this.menuActions = [
      (): void => {
        this.testProvider(provider);
      },
      (): void => {
        this.fetchProviderModels(provider);
      },
      (): void => {
        this.toggleProvider(provider);
      },
      (): void => {
        this.openEditForm(provider);
      },
      (): void => {
        this.confirmDelete(provider);
      }
    ];
    this.menuOpen = true;
  }

  /** 菜单选中：先关半模态再执行预置动作（越界保护） */
  private onMenuSelect(index: number): void {
    this.menuOpen = false;
    if (index < 0 || index >= this.menuActions.length) {
      return;
    }
    const action: () => void = this.menuActions[index];
    action();
  }

  /** 试探已存 provider：解析 ok/status/message 组装结果提示 */
  private async testProvider(provider: ProviderModel): Promise<void> {
    let text: string = '';
    try {
      text = await ProviderService.adminTest(provider.id, '{}');
    } catch (e) {
      const message: string = e instanceof OctopApiError ? e.message : '试探请求失败';
      this.getUIContext().getPromptAction().showToast({ message });
      return;
    }
    this.getUIContext().showAlertDialog({
      title: `测试 ${provider.name}`,
      message: this.testResultText(text),
      confirm: {
        value: $r('app.string.common_confirm'),
        action: (): void => {
        }
      }
    });
  }

  /** 试探响应 → 可读文案（ok/status/latency/message 容错） */
  private testResultText(text: string): string {
    const rec = JsonHelper.parse(text);
    if (rec === null) {
      return '响应格式错误';
    }
    const ok: boolean = JsonHelper.getBool(rec, 'ok', false) ||
      JsonHelper.getString(rec, 'status', '') === 'ok';
    const message: string = JsonHelper.getString(rec, 'message', '');
    const error: string = JsonHelper.getString(rec, 'error', '');
    const latency: number = JsonHelper.getNumber(rec, 'latency_ms', -1);
    if (ok) {
      const latencyText: string = latency >= 0 ? `，耗时 ${latency}ms` : '';
      return `连接正常${latencyText}${message === '' ? '' : `\n${message}`}`;
    }
    return `连接失败：${error !== '' ? error : (message !== '' ? message : '未知错误')}`;
  }

  /** 拉取 OpenAI 兼容模型列表并展示 */
  private async fetchProviderModels(provider: ProviderModel): Promise<void> {
    if (provider.kind !== 'openai') {
      this.getUIContext().getPromptAction().showToast({ message: '仅 OpenAI 兼容类型支持拉取' });
      return;
    }
    const body: Record<string, Object> = {
      'kind': provider.kind,
      'name': provider.name,
      'base_url': provider.baseUrl
    };
    let text: string = '';
    try {
      text = await ProviderService.adminFetchModels(JSON.stringify(body));
    } catch (e) {
      const message: string = e instanceof OctopApiError ? e.message : '拉取失败';
      this.getUIContext().getPromptAction().showToast({ message });
      return;
    }
    const models: Array<string> = this.parseModelIds(text);
    const preview: string = models.length === 0
      ? '未解析到模型列表'
      : models.slice(0, 30).join('、') + (models.length > 30 ? ' …' : '');
    this.getUIContext().showAlertDialog({
      title: `${provider.name} 模型（${models.length}）`,
      message: preview,
      confirm: {
        value: $r('app.string.common_confirm'),
        action: (): void => {
        }
      }
    });
  }

  /** /models 响应 → 模型 id 列表（数组 或 {models:[...]}，元素 string 或 {id}） */
  private parseModelIds(text: string): Array<string> {
    const result: Array<string> = [];
    const arr = JsonHelper.parseArray(text);
    if (arr !== null) {
      for (const rec of arr) {
        const id: string = JsonHelper.getString(rec, 'id', '');
        if (id !== '') {
          result.push(id);
        }
      }
      return result;
    }
    const obj = JsonHelper.parse(text);
    const recs = JsonHelper.getRecordArray(obj, 'models');
    for (const rec of recs) {
      const id: string = JsonHelper.getString(rec, 'id', '');
      if (id !== '') {
        result.push(id);
      }
    }
    if (result.length === 0) {
      const raw = JsonHelper.getStringArray(obj, 'models');
      for (const item of raw) {
        const id: string = item.trim();
        if (id !== '') {
          result.push(id);
        }
      }
    }
    return result;
  }

  private async toggleProvider(provider: ProviderModel): Promise<void> {
    const body: Record<string, Object> = { 'enabled': !provider.enabled };
    try {
      await ProviderService.adminPatch(provider.id, JSON.stringify(body));
      ProviderService.invalidateCache();
      await this.load();
    } catch (e) {
      const message: string = e instanceof OctopApiError ? e.message : '操作失败';
      this.getUIContext().getPromptAction().showToast({ message });
    }
  }

  private confirmDelete(provider: ProviderModel): void {
    this.getUIContext().showAlertDialog({
      title: '删除 Provider',
      message: `确定删除「${provider.name}」吗？仍被专家引用时将无法删除。`,
      primaryButton: {
        value: $r('app.string.common_cancel'),
        action: (): void => {
        }
      },
      secondaryButton: {
        value: $r('app.string.common_confirm'),
        action: (): void => {
          this.deleteProvider(provider);
        }
      },
      alignment: DialogAlignment.Bottom
    });
  }

  private async deleteProvider(provider: ProviderModel): Promise<void> {
    try {
      await ProviderService.adminRemove(provider.id);
      this.getUIContext().getPromptAction().showToast({ message: '已删除' });
      ProviderService.invalidateCache();
      await this.load();
    } catch (e) {
      const message: string = e instanceof OctopApiError ? e.message : '删除失败';
      this.getUIContext().getPromptAction().showToast({ message });
    }
  }

  // ---- 新建 / 编辑表单 ----

  private async openCreateForm(): Promise<void> {
    this.formEditId = 0;
    this.formName = '';
    this.formKind = 'openai';
    this.formBaseUrl = '';
    this.formApiKey = '';
    this.formModels = '';
    this.formNote = '';
    this.formEnabled = true;
    if (this.presets.length === 0) {
      this.presetsLoading = true;
      try {
        const raw: string = await ProviderService.presetsRaw();
        this.presets = ProviderPresetModel.parseList(raw);
      } catch (e) {
        this.presets = [];
      }
      this.presetsLoading = false;
    }
    this.sheetMode = 'form';
    this.sheetOpen = true;
  }

  private openEditForm(provider: ProviderModel): void {
    this.formEditId = provider.id;
    this.formName = provider.name;
    this.formKind = provider.kind;
    this.formBaseUrl = provider.baseUrl;
    this.formApiKey = '';
    this.formModels = provider.models.join(', ');
    this.formNote = provider.note;
    this.formEnabled = provider.enabled;
    this.sheetMode = 'form';
    this.sheetOpen = true;
  }

  /** 应用预设：预填名称/kind/接口地址（模型列表在编辑模式下保留现值） */
  private applyPreset(preset: ProviderPresetModel): void {
    this.formName = preset.name;
    this.formKind = preset.kind === '' ? 'openai' : preset.kind;
    this.formBaseUrl = preset.baseUrl;
    if (preset.models.length > 0) {
      this.formModels = preset.models.join(', ');
    }
  }

  /** 表单模型列表文本 → id 数组（逗号/换行/分号分隔） */
  private parseFormModels(): Array<string> {
    const result: Array<string> = [];
    const parts: Array<string> = this.formModels.split(/[,;\n]/);
    for (const part of parts) {
      const id: string = part.trim();
      if (id !== '') {
        result.push(id);
      }
    }
    return result;
  }

  /** 草稿试连（test-draft，model_id 取表单首个模型） */
  private async testDraft(): Promise<void> {
    const models: Array<string> = this.parseFormModels();
    if (this.formName.trim() === '' || models.length === 0) {
      this.getUIContext().getPromptAction().showToast({ message: '请先填写名称与模型列表' });
      return;
    }
    this.formTesting = true;
    const body: Record<string, Object> = {
      'name': this.formName.trim(),
      'kind': this.formKind,
      'api_key': this.formApiKey,
      'model_id': models[0]
    };
    if (this.formBaseUrl.trim() !== '') {
      body['base_url'] = this.formBaseUrl.trim();
    }
    try {
      const text: string = await ProviderService.adminTestDraft(JSON.stringify(body));
      this.getUIContext().showAlertDialog({
        title: '试连结果',
        message: this.testResultText(text),
        confirm: {
          value: $r('app.string.common_confirm'),
          action: (): void => {
          }
        }
      });
    } catch (e) {
      const message: string = e instanceof OctopApiError ? e.message : '试连失败';
      this.getUIContext().getPromptAction().showToast({ message });
    }
    this.formTesting = false;
  }

  private async saveForm(): Promise<void> {
    if (this.formSaving) {
      return;
    }
    const name: string = this.formName.trim();
    if (name === '') {
      this.getUIContext().getPromptAction().showToast({ message: '请填写名称' });
      return;
    }
    this.formSaving = true;
    try {
      const models: Array<string> = this.parseFormModels();
      if (this.formEditId === 0) {
        const body: Record<string, Object> = {
          'name': name,
          'kind': this.formKind,
          'stream_usage': false
        };
        if (this.formBaseUrl.trim() !== '') {
          body['base_url'] = this.formBaseUrl.trim();
        }
        if (this.formApiKey.trim() !== '') {
          body['api_key'] = this.formApiKey.trim();
        }
        if (models.length > 0) {
          body['models'] = models;
        }
        if (this.formNote.trim() !== '') {
          body['note'] = this.formNote.trim();
        }
        await ProviderService.adminCreate(JSON.stringify(body));
      } else {
        const body: Record<string, Object> = {
          'name': name,
          'kind': this.formKind,
          'enabled': this.formEnabled
        };
        if (this.formBaseUrl.trim() !== '') {
          body['base_url'] = this.formBaseUrl.trim();
        }
        if (this.formApiKey.trim() !== '') {
          body['api_key'] = this.formApiKey.trim();
        }
        if (models.length > 0) {
          body['models'] = models;
        }
        if (this.formNote.trim() !== '') {
          body['note'] = this.formNote.trim();
        }
        await ProviderService.adminPatch(this.formEditId, JSON.stringify(body));
      }
      this.sheetOpen = false;
      this.getUIContext().getPromptAction().showToast({
        message: this.formEditId === 0 ? 'Provider 已创建' : 'Provider 已更新'
      });
      ProviderService.invalidateCache();
      await this.load();
    } catch (e) {
      const message: string = e instanceof OctopApiError ? e.message : '保存失败';
      this.getUIContext().getPromptAction().showToast({ message });
    }
    this.formSaving = false;
  }

  // ---- 视图 ----

  @Builder
  activeModelCard() {
    Row({ space: 12 }) {
      Column() {
        SymbolGlyph($r('sys.symbol.star'))
          .fontSize(20)
          .fontColor([$r('app.color.brand')])
      }
      .width(42)
      .height(42)
      .borderRadius(13)
      .backgroundColor($r('app.color.brand_light'))
      .justifyContent(FlexAlign.Center)

      Column({ space: 4 }) {
        Text('全局默认模型')
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
        Text(this.canManage ? '点击切换全局默认模型' : '由管理员配置（只读）')
          .fontSize(12)
          .fontColor($r('app.color.text_tertiary'))
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      Column({ space: 2 }) {
        Text(this.activeModelText())
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.activeProviderName === '' ? $r('app.color.text_tertiary') : $r('app.color.brand'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .constraintSize({ maxWidth: 160 })
        if (this.canManage) {
          SymbolGlyph($r('sys.symbol.chevron_right'))
            .fontSize(12)
            .fontColor([$r('app.color.text_tertiary')])
        }
      }
      .alignItems(HorizontalAlign.End)
    }
    .width('100%')
    .padding(14)
    .borderRadius(16)
    .backgroundColor($r('app.color.bg_card'))
    .border({ width: 1, color: $r('app.color.card_stroke') })
    .shadow({ radius: 10, color: '#0A000000', offsetY: 3 })
    .onClick((): void => {
      this.openActiveModelPicker();
    })
  }

  @Builder
  providerCard(provider: ProviderModel) {
    Row({ space: 12 }) {
      Column() {
        SymbolGlyph($r('sys.symbol.square_stack_3d'))
          .fontSize(20)
          .fontColor([$r('app.color.brand')])
      }
      .width(42)
      .height(42)
      .borderRadius(13)
      .backgroundColor($r('app.color.brand_light'))
      .justifyContent(FlexAlign.Center)
      .opacity(provider.enabled ? 1 : 0.5)

      Column({ space: 6 }) {
        Row() {
          Text(provider.name === '' ? `#${provider.id}` : provider.name)
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor(provider.enabled ? $r('app.color.text_primary') : $r('app.color.text_tertiary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
          Text(provider.enabled ? '已启用' : '已停用')
            .fontSize(11)
            .fontColor(provider.enabled ? $r('app.color.success') : $r('app.color.text_tertiary'))
            .backgroundColor(provider.enabled ? $r('app.color.success_soft') : $r('app.color.bg_input'))
            .borderRadius(6)
            .padding({ left: 8, right: 8, top: 3, bottom: 3 })
        }
        .width('100%')

        if (provider.baseUrl !== '') {
          Text(provider.baseUrl)
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
        }

        Row({ space: 8 }) {
          Text(provider.kind)
            .fontSize(11)
            .fontColor($r('app.color.brand'))
            .backgroundColor($r('app.color.brand_light'))
            .borderRadius(6)
            .padding({ left: 8, right: 8, top: 3, bottom: 3 })
          Text(`${provider.modelCount} 个模型`)
            .fontSize(11)
            .fontColor($r('app.color.text_tertiary'))
          if (provider.hasApiKey) {
            Text('密钥已配置')
              .fontSize(11)
              .fontColor($r('app.color.text_tertiary'))
          } else {
            Text('未配置密钥')
              .fontSize(11)
              .fontColor($r('app.color.warning'))
          }
          if (provider.streamUsage) {
            Text('流式用量')
              .fontSize(11)
              .fontColor($r('app.color.text_tertiary'))
          }
        }
        .width('100%')

        if (provider.note !== '') {
          Text(provider.note)
            .fontSize(11)
            .fontColor($r('app.color.text_tertiary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .padding({ left: 14, right: 14, top: 14, bottom: 14 })
    .borderRadius(16)
    .backgroundColor($r('app.color.bg_card'))
    .border({ width: 1, color: $r('app.color.card_stroke') })
    .shadow({ radius: 10, color: '#0A000000', offsetY: 3 })
    .onClick((): void => {
      this.showProviderMenu(provider);
    })
    .gesture(
      LongPressGesture()
        .onAction((event: GestureEvent): void => {
          this.showProviderMenu(provider);
        })
    )
  }

  @Builder
  formFieldLabel(label: string) {
    Text(label)
      .fontSize(13)
      .fontColor($r('app.color.text_secondary'))
      .width('100%')
  }

  /** 新建/编辑 provider 表单（预设预填 / 试连 / 保存） */
  @Builder
  formSheetBuilder() {
    Column({ space: 12 }) {
      Text(this.formEditId === 0 ? '新建 Provider' : '编辑 Provider')
        .fontSize(17)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .width('100%')

      if (this.formEditId === 0 && this.presets.length > 0) {
        Scroll() {
          Row({ space: 8 }) {
            ForEach(this.presets, (preset: ProviderPresetModel) => {
              Text(preset.name === '' ? preset.kind : preset.name)
                .fontSize(12)
                .fontColor($r('app.color.brand'))
                .backgroundColor($r('app.color.brand_light'))
                .borderRadius(12)
                .padding({ left: 12, right: 12, top: 7, bottom: 7 })
                .onClick((): void => {
                  this.applyPreset(preset);
                })
            }, (preset: ProviderPresetModel) => `${preset.id}_${preset.name}_${preset.kind}`)
          }
        }
        .scrollable(ScrollDirection.Horizontal)
        .scrollBar(BarState.Off)
        .width('100%')
      } else if (this.formEditId === 0 && this.presetsLoading) {
        Text('预设加载中…')
          .fontSize(12)
          .fontColor($r('app.color.text_tertiary'))
          .width('100%')
      }

      this.formFieldLabel('名称')
      TextInput({ text: this.formName, placeholder: '如 openai' })
        .fontSize(14)
        .height(42)
        .backgroundColor($r('app.color.bg_input'))
        .borderRadius(12)
        .onChange((value: string): void => {
          this.formName = value;
        })

      this.formFieldLabel('类型 kind')
      TextInput({ text: this.formKind, placeholder: 'openai' })
        .fontSize(14)
        .height(42)
        .backgroundColor($r('app.color.bg_input'))
        .borderRadius(12)
        .onChange((value: string): void => {
          this.formKind = value.trim();
        })

      this.formFieldLabel('接口地址 base_url')
      TextInput({ text: this.formBaseUrl, placeholder: 'https://api.example.com/v1' })
        .fontSize(14)
        .height(42)
        .backgroundColor($r('app.color.bg_input'))
        .borderRadius(12)
        .onChange((value: string): void => {
          this.formBaseUrl = value;
        })

      this.formFieldLabel(this.formEditId === 0 ? '密钥 api_key' : '密钥 api_key（留空 = 不修改）')
      TextInput({
        text: this.formApiKey,
        placeholder: this.formEditId === 0 ? 'sk-…' : '不修改则留空'
      })
        .fontSize(14)
        .height(42)
        .type(InputType.Password)
        .backgroundColor($r('app.color.bg_input'))
        .borderRadius(12)
        .onChange((value: string): void => {
          this.formApiKey = value;
        })

      this.formFieldLabel('模型列表（逗号或换行分隔）')
      TextArea({ text: this.formModels, placeholder: 'gpt-4o, gpt-4o-mini' })
        .fontSize(14)
        .height(64)
        .backgroundColor($r('app.color.bg_input'))
        .borderRadius(12)
        .onChange((value: string): void => {
          this.formModels = value;
        })

      this.formFieldLabel('备注（可选）')
      TextInput({ text: this.formNote, placeholder: '' })
        .fontSize(14)
        .height(42)
        .backgroundColor($r('app.color.bg_input'))
        .borderRadius(12)
        .onChange((value: string): void => {
          this.formNote = value;
        })

      if (this.formEditId !== 0) {
        Row() {
          Text('启用')
            .fontSize(14)
            .fontColor($r('app.color.text_primary'))
          Blank()
          Toggle({ type: ToggleType.Switch, isOn: this.formEnabled })
            .selectedColor($r('app.color.brand'))
            .onChange((on: boolean): void => {
              this.formEnabled = on;
            })
        }
        .width('100%')
      }

      Row({ space: 10 }) {
        Button(this.formTesting ? '试连中…' : '试连')
          .fontSize(14)
          .height(42)
          .layoutWeight(1)
          .borderRadius(21)
          .backgroundColor($r('app.color.bg_input'))
          .fontColor($r('app.color.text_primary'))
          .enabled(!this.formTesting && !this.formSaving)
          .onClick((): void => {
            this.testDraft();
          })
        Button(this.formSaving ? '保存中…' : '保存')
          .fontSize(15)
          .fontWeight(FontWeight.Bold)
          .height(42)
          .layoutWeight(1)
          .borderRadius(21)
          .backgroundColor($r('app.color.brand'))
          .fontColor($r('app.color.text_on_brand'))
          .enabled(!this.formSaving && !this.formTesting)
          .onClick((): void => {
            this.saveForm();
          })
      }
      .width('100%')
    }
    .padding({ left: 18, right: 18, top: 18, bottom: 30 })
    .width('100%')
  }

  @Builder
  menuSheetBuilder() {
    MenuSheetContent({
      title: this.menuTitle,
      message: this.menuMessage,
      options: this.menuOptions,
      onSelect: (index: number): void => {
        this.onMenuSelect(index);
      }
    })
  }

  build() {
    NavDestination() {
      Stack({ alignContent: Alignment.BottomEnd }) {
        Column() {
          PageHeader({ title: '模型配置' })

          if (this.loading) {
            Column() {
              LoadingProgress()
                .width(36)
                .height(36)
                .color($r('app.color.brand'))
            }
            .layoutWeight(1)
            .width('100%')
            .justifyContent(FlexAlign.Center)
          } else if (this.errorMsg !== '') {
            Column() {
              ErrorRetry({
                message: this.errorMsg,
                onRetry: (): void => {
                  this.load();
                }
              })
            }
            .layoutWeight(1)
            .width('100%')
            .justifyContent(FlexAlign.Center)
          } else {
            Refresh({ refreshing: $$this.refreshing }) {
              Scroll() {
                Column({ space: 12 }) {
                  this.activeModelCard()

                  if (this.providers.length === 0) {
                    Column() {
                      EmptyView({
                        title: this.canManage ? '暂无 Provider' : '暂无可用的 Provider',
                        subtitle: this.canManage ? '点击右下角按钮新建' : '请联系管理员配置',
                        icon: $r('sys.symbol.square_stack_3d')
                      })
                    }
                    .width('100%')
                    .padding({ top: 40 })
                  } else {
                    ForEach(this.providers, (provider: ProviderModel) => {
                      this.providerCard(provider)
                    }, (provider: ProviderModel) => `${provider.id}_${provider.enabled}_${provider.modelCount}_${provider.hasApiKey}`)
                  }
                }
                .width('100%')
                .padding({ left: 14, right: 14, top: 4, bottom: 90 })
                .alignItems(HorizontalAlign.Start)
              }
              .width('100%')
              .height('100%')
              .align(Alignment.Top)
              .scrollBar(BarState.Off)
            }
            .layoutWeight(1)
            .width('100%')
            .onRefreshing((): void => {
              this.load();
            })
          }
        }
        .width('100%')
        .height('100%')
        .bindSheet($$this.menuOpen, this.menuSheetBuilder, {
          detents: [SheetSize.FIT_CONTENT],
          showClose: true,
          systemMaterial: UiMaterialKit.sheet()
        })

        if (this.canManage) {
          Button({ type: ButtonType.Circle, stateEffect: true }) {
            SymbolGlyph($r('sys.symbol.plus'))
              .fontSize(28)
              .fontWeight(FontWeight.Medium)
              .fontColor([$r('app.color.brand')])
          }
          .width(58)
          .height(58)
          .backgroundColor($r('app.color.fab_glass'))
          .backgroundBlurStyle(BlurStyle.COMPONENT_THICK)
          .border({ width: 1, color: $r('app.color.card_stroke') })
          .margin(22)
          .onClick((): void => {
            this.openCreateForm();
          })
        }
      }
      .width('100%')
      .height('100%')
      // 单 bindSheet 分发：同节点多链 bindSheet 后者覆盖前者（全局默认模型点击失效的回归根因），
      // 改为 open + mode 分发（参照 PluginPage sheetSwitchBuilder 模式）
      .bindSheet($$this.sheetOpen, this.sheetSwitchBuilder, {
        systemMaterial: UiMaterialKit.sheet(),
        detents: this.sheetMode === 'form' ? [SheetSize.LARGE] : [SheetSize.MEDIUM, SheetSize.LARGE],
        showClose: true,
        onDisappear: (): void => {
          this.sheetMode = '';
        }
      })
    }
    .hideTitleBar(true)
    .backgroundColor($r('app.color.bg_page'))
    .onReady((ctx: NavDestinationContext): void => {
      this.onNavReady(ctx);
    })
  }

  /** 单 bindSheet 分发：model（模型选择面板）/ form（新建/编辑表单） */
  @Builder
  sheetSwitchBuilder() {
    if (this.sheetMode === 'model') {
      this.modelSheetBuilder()
    } else if (this.sheetMode === 'form') {
      this.formSheetBuilder()
    }
  }

  @Builder
  modelSheetBuilder() {
    ModelPickerSheet({
      allowAuto: false,
      onPick: (ref: string, label: string): void => {
        this.saveActiveModel(ref);
      }
    })
  }
}
