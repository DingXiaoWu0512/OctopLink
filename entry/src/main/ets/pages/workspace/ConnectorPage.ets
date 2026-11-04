import { ConnectorCatalogEntry, ConnectorInstanceModel, CustomMcpServerModel } from '../../model/WorkspaceModels';
import { ConnectorService } from '../../service/WorkspaceService';
import { OctopApiError } from '../../net/HttpClient';
import { pasteboard } from '@kit.BasicServicesKit';
import { EmptyView } from '../../components/EmptyView';
import { ErrorRetry } from '../../components/ErrorRetry';
import { PageHeader } from '../../components/PageHeader';
import { UiMaterialKit } from '../../components/UiMaterialKit';
import { JsonHelper } from '../../utils/JsonHelper';
import { MenuSheetContent, MenuSheetOption } from '../../components/MenuSheet';

/** 我的连接器：目录添加（凭证/OAuth）/实例管理/自定义 MCP 开关 */
@Component
export struct ConnectorPage {
  @State instances: Array<ConnectorInstanceModel> = [];
  @State mcpServers: Array<CustomMcpServerModel> = [];
  @State loading: boolean = true;
  @State refreshing: boolean = false;
  @State errorMsg: string = '';
  @State operating: boolean = false;
  @State sheetOpen: boolean = false;
  @State sheetMode: string = '';
  @State catalogLoading: boolean = false;
  @State catalog: Array<ConnectorCatalogEntry> = [];
  @State credEntry: ConnectorCatalogEntry | null = null;
  @State credName: string = '';
  @State credJson: string = '{}';
  @State credTesting: boolean = false;
  @State credCreating: boolean = false;
  @State oauthEntry: ConnectorCatalogEntry | null = null;
  @State oauthUrl: string = '';
  @State oauthStateId: string = '';
  @State oauthStatus: string = '';
  @State oauthPolling: boolean = false;
  @State menuOpen: boolean = false;
  @State menuTitle: string = '';
  @State menuMessage: string = '';
  @State menuOptions: Array<MenuSheetOption> = [];
  private menuActions: Array<() => void> = [];
  private oauthTries: number = 0;

  aboutToAppear(): void {
    this.load();
  }

  private async load(): Promise<void> {
    this.loading = this.instances.length === 0;
    this.errorMsg = '';
    try {
      this.instances = await ConnectorService.list();
    } catch (e) {
      this.errorMsg = e instanceof OctopApiError ? e.message : '连接器加载失败';
    } finally {
      this.loading = false;
      this.refreshing = false;
    }
    this.loadMcp();
  }

  /** 自定义 MCP 列表失败不阻断页面 */
  private async loadMcp(): Promise<void> {
    try {
      this.mcpServers = await ConnectorService.customMcpGet();
    } catch (e) {
      this.mcpServers = [];
    }
  }

  // ---- 目录与添加 ----

  private async openCatalog(): Promise<void> {
    this.sheetMode = 'catalog';
    this.sheetOpen = true;
    this.catalogLoading = this.catalog.length === 0;
    try {
      this.catalog = await ConnectorService.catalog();
    } catch (e) {
      const message: string = e instanceof OctopApiError ? e.message : '目录加载失败';
      this.getUIContext().getPromptAction().showToast({ message });
    }
    this.catalogLoading = false;
  }

  private pickEntry(entry: ConnectorCatalogEntry): void {
    if (!entry.available) {
      this.getUIContext().getPromptAction().showToast({ message: '该连接器当前不可用' });
      return;
    }
    if (entry.oauthConfigured) {
      this.startOauth(entry);
    } else {
      this.openCredSheet(entry);
    }
  }

  // ---- 凭证类添加 ----

  private openCredSheet(entry: ConnectorCatalogEntry): void {
    this.credEntry = entry;
    this.credName = entry.label;
    this.credJson = '{}';
    this.sheetMode = 'cred';
    this.sheetOpen = true;
  }

  private validCredJson(): boolean {
    return JsonHelper.parse(this.credJson) !== null;
  }

  private async testCred(): Promise<void> {
    if (this.credEntry === null || this.credTesting) {
      return;
    }
    if (!this.validCredJson()) {
      this.getUIContext().getPromptAction().showToast({ message: 'credentials 不是合法 JSON 对象' });
      return;
    }
    this.credTesting = true;
    try {
      await ConnectorService.testCredentials(this.credEntry.kind, this.credJson);
      this.getUIContext().getPromptAction().showToast({ message: '凭证可用' });
    } catch (e) {
      const message: string = e instanceof OctopApiError ? e.message : '凭证不可用';
      this.getUIContext().getPromptAction().showToast({ message });
    }
    this.credTesting = false;
  }

  private async createCred(): Promise<void> {
    if (this.credEntry === null || this.credCreating) {
      return;
    }
    const name: string = this.credName.trim();
    if (name === '') {
      this.getUIContext().getPromptAction().showToast({ message: '请填写显示名称' });
      return;
    }
    if (!this.validCredJson()) {
      this.getUIContext().getPromptAction().showToast({ message: 'credentials 不是合法 JSON 对象' });
      return;
    }
    this.credCreating = true;
    try {
      const credentials: Record<string, Object> | null = JsonHelper.parse(this.credJson);
      const emptyCredentials: Record<string, Object> = {};
      const emptyConfig: Record<string, Object> = {};
      const body: Record<string, Object> = {
        'kind': this.credEntry.kind,
        'display_name': name,
        'credentials': credentials === null ? emptyCredentials : credentials,
        'config': emptyConfig
      };
      await ConnectorService.createInstance(JSON.stringify(body));
      this.sheetOpen = false;
      this.getUIContext().getPromptAction().showToast({ message: '连接器已创建' });
      this.load();
    } catch (e) {
      const message: string = e instanceof OctopApiError ? e.message : '创建失败';
      this.getUIContext().getPromptAction().showToast({ message });
    }
    this.credCreating = false;
  }

  // ---- OAuth 类添加 ----

  private async startOauth(entry: ConnectorCatalogEntry): Promise<void> {
    this.oauthEntry = entry;
    this.oauthUrl = '';
    this.oauthStateId = '';
    this.oauthStatus = '正在发起授权…';
    this.oauthPolling = false;
    this.sheetMode = 'oauth';
    this.sheetOpen = true;
    try {
      const target: Record<string, Object> = { 'type': 'catalog', 'kind': entry.kind };
      const result = await ConnectorService.oauthStart(JSON.stringify(target));
      if (result.authorizeUrl === '' || result.stateId === '') {
        this.oauthStatus = '授权发起失败，请重试';
        return;
      }
      this.oauthUrl = result.authorizeUrl;
      this.oauthStateId = result.stateId;
      this.oauthStatus = '授权链接已复制，请在浏览器打开并完成授权';
      await this.copyText(result.authorizeUrl);
      this.oauthTries = 0;
      this.oauthPolling = true;
      this.scheduleOauthPoll(result.stateId);
    } catch (e) {
      this.oauthStatus = e instanceof OctopApiError ? e.message : '授权发起失败';
    }
  }

  private async copyText(text: string): Promise<void> {
    try {
      const board = pasteboard.getSystemPasteboard();
      const data = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, text);
      await board.setData(data);
    } catch (e) {
    }
  }

  /** 每 3s 轮询 pending；拿到 tokens 自动创建实例；超 5min 放弃 */
  private scheduleOauthPoll(stateId: string): void {
    setTimeout((): void => {
      this.pollOauthOnce(stateId);
    }, 3000);
  }

  private async pollOauthOnce(stateId: string): Promise<void> {
    if (!this.oauthPolling || !this.sheetOpen || this.sheetMode !== 'oauth' || stateId !== this.oauthStateId) {
      return;
    }
    if (this.oauthTries > 100) {
      this.oauthPolling = false;
      this.oauthStatus = '等待授权超时，请关闭后重试';
      return;
    }
    this.oauthTries += 1;
    try {
      const raw: string = await ConnectorService.oauthPending(stateId);
      if (!this.oauthPolling || stateId !== this.oauthStateId) {
        return;
      }
      const rec: Record<string, Object> | null = JsonHelper.parse(raw);
      const tokens: Record<string, Object> | null = JsonHelper.getRecord(rec, 'tokens');
      if (tokens !== null && this.oauthEntry !== null) {
        const kind: string = rec === null ? this.oauthEntry.kind :
          JsonHelper.getString(rec, 'kind', this.oauthEntry.kind);
        const emptyConfig: Record<string, Object> = {};
        const body: Record<string, Object> = {
          'kind': kind === '' ? this.oauthEntry.kind : kind,
          'display_name': this.oauthEntry.label,
          'credentials': tokens,
          'config': emptyConfig
        };
        await ConnectorService.createInstance(JSON.stringify(body));
        this.oauthPolling = false;
        this.sheetOpen = false;
        this.getUIContext().getPromptAction().showToast({ message: '授权成功，连接器已创建' });
        this.load();
        return;
      }
      this.scheduleOauthPoll(stateId);
    } catch (e) {
      if (this.oauthPolling) {
        this.scheduleOauthPoll(stateId);
      }
    }
  }

  // ---- 实例管理 ----

  private async test(instance: ConnectorInstanceModel): Promise<void> {
    if (this.operating) {
      return;
    }
    this.operating = true;
    try {
      await ConnectorService.test(instance.instanceId);
      this.getUIContext().getPromptAction().showToast({ message: '连接正常' });
    } catch (e) {
      const message: string = e instanceof OctopApiError ? e.message : '连接失败';
      this.getUIContext().getPromptAction().showToast({ message });
    } finally {
      this.operating = false;
    }
  }

  private async patchInstance(instance: ConnectorInstanceModel, bodyStr: string,
    successMsg: string): Promise<void> {
    if (this.operating) {
      return;
    }
    this.operating = true;
    try {
      await ConnectorService.patchInstance(instance.instanceId, bodyStr);
      this.getUIContext().getPromptAction().showToast({ message: successMsg });
      await this.load();
    } catch (e) {
      const message: string = e instanceof OctopApiError ? e.message : '操作失败';
      this.getUIContext().getPromptAction().showToast({ message });
    } finally {
      this.operating = false;
    }
  }

  private async refreshTokens(instance: ConnectorInstanceModel): Promise<void> {
    if (this.operating) {
      return;
    }
    this.operating = true;
    try {
      await ConnectorService.refreshToken(instance.instanceId);
      this.getUIContext().getPromptAction().showToast({ message: '令牌已刷新' });
    } catch (e) {
      const message: string = e instanceof OctopApiError ? e.message : '刷新失败';
      this.getUIContext().getPromptAction().showToast({ message });
    } finally {
      this.operating = false;
    }
  }

  private async toggleMcpServer(server: CustomMcpServerModel, on: boolean): Promise<void> {
    const body: Record<string, Object> = { 'enabled': on };
    try {
      await ConnectorService.customMcpPatchServer(server.name, JSON.stringify(body));
      await this.loadMcp();
    } catch (e) {
      const message: string = e instanceof OctopApiError ? e.message : '操作失败';
      this.getUIContext().getPromptAction().showToast({ message });
      this.loadMcp();
    }
  }

  private showMenu(instance: ConnectorInstanceModel): void {
    // ForEach 按 instanceId 复用组件时手势闭包可能持有旧对象，这里以最新列表数据为准
    const fresh: ConnectorInstanceModel | undefined = this.instances.find(
      (x: ConnectorInstanceModel): boolean => x.instanceId === instance.instanceId);
    const current: ConnectorInstanceModel = fresh !== undefined ? fresh : instance;
    const nextEnabled: boolean = current.status !== 'active';
    const options: Array<MenuSheetOption> = [
      new MenuSheetOption($r('sys.symbol.bolt'), '测试连通性', '', false)
    ];
    const actions: Array<() => void> = [
      (): void => {
        this.test(current);
      }
    ];
    if (current.canManage) {
      options.push(new MenuSheetOption(nextEnabled ? $r('sys.symbol.checkmark_circle') : $r('sys.symbol.xmark_circle'),
        nextEnabled ? '启用连接器' : '停用连接器', '', false));
      actions.push((): void => {
        // 服务器 PatchInstanceBody 无 enabled 字段，需用 status: active|disabled
        const body: Record<string, Object> = {
          'status': nextEnabled ? 'active' : 'disabled'
        };
        this.patchInstance(current, JSON.stringify(body), nextEnabled ? '已启用' : '已停用');
      });
      options.push(new MenuSheetOption($r('sys.symbol.person_2'),
        current.shared ? '取消共享' : '共享给他人', '', false));
      actions.push((): void => {
        const body: Record<string, Object> = { 'shared': !current.shared };
        this.patchInstance(current, JSON.stringify(body), current.shared ? '已取消共享' : '已共享');
      });
      options.push(new MenuSheetOption($r('sys.symbol.arrow_clockwise'), '刷新令牌', '', false));
      actions.push((): void => {
        this.refreshTokens(current);
      });
      options.push(new MenuSheetOption($r('sys.symbol.trash'), '删除连接器', '', true));
      actions.push((): void => {
        this.confirmDelete(current);
      });
    }
    this.menuTitle = instance.displayName;
    this.menuMessage = '选择要执行的操作';
    this.menuOptions = options;
    this.menuActions = actions;
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

  private confirmDelete(instance: ConnectorInstanceModel): void {
    this.getUIContext().showAlertDialog({
      title: '删除连接器',
      message: `删除「${instance.displayName}」将同时撤销授权，确定吗？`,
      primaryButton: {
        value: $r('app.string.common_cancel'),
        action: (): void => {
        }
      },
      secondaryButton: {
        value: $r('app.string.common_confirm'),
        action: (): void => {
          this.deleteInstance(instance);
        }
      },
      alignment: DialogAlignment.Bottom
    });
  }

  private async deleteInstance(instance: ConnectorInstanceModel): Promise<void> {
    if (this.operating) {
      return;
    }
    this.operating = true;
    try {
      await ConnectorService.remove(instance.instanceId);
      await this.load();
    } catch (e) {
      const message: string = e instanceof OctopApiError ? e.message : '删除失败';
      this.getUIContext().getPromptAction().showToast({ message });
    } finally {
      this.operating = false;
    }
  }

  /** 单 bindSheet 分发：catalog / cred / oauth */
  @Builder
  private sheetSwitchBuilder() {
    if (this.sheetMode === 'catalog') {
      this.catalogSheetBuilder()
    } else if (this.sheetMode === 'cred') {
      this.credSheetBuilder()
    } else if (this.sheetMode === 'oauth') {
      this.oauthSheetBuilder()
    }
  }

  @Builder
  private catalogSheetBuilder() {
    Column({ space: 12 }) {
      Text('添加连接器')
        .fontSize(17)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .width('100%')
      if (this.catalogLoading) {
        Column() {
          LoadingProgress()
            .width(32)
            .height(32)
            .color($r('app.color.brand'))
        }
        .width('100%')
        .padding({ top: 30, bottom: 30 })
      } else if (this.catalog.length === 0) {
        Text('暂无可用连接器')
          .fontSize(14)
          .fontColor($r('app.color.text_secondary'))
          .padding({ top: 30, bottom: 30 })
      } else {
        Scroll() {
          Column({ space: 8 }) {
            ForEach(this.catalog, (entry: ConnectorCatalogEntry) => {
              Row({ space: 12 }) {
                Column() {
                  SymbolGlyph($r('sys.symbol.link'))
                    .fontSize(18)
                    .fontColor([entry.available ? $r('app.color.brand') : $r('app.color.text_tertiary')])
                }
                .width(38)
                .height(38)
                .justifyContent(FlexAlign.Center)
                .backgroundColor($r('app.color.brand_light'))
                .borderRadius(12)
                Column({ space: 3 }) {
                  Row({ space: 6 }) {
                    Text(entry.label === '' ? entry.kind : entry.label)
                      .fontSize(15)
                      .fontWeight(FontWeight.Medium)
                      .fontColor($r('app.color.text_primary'))
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                    if (entry.oauthConfigured) {
                      Text('OAuth')
                        .fontSize(10)
                        .fontColor($r('app.color.brand'))
                        .backgroundColor($r('app.color.brand_light'))
                        .borderRadius(5)
                        .padding({ left: 6, right: 6, top: 2, bottom: 2 })
                    }
                    if (!entry.available) {
                      Text('不可用')
                        .fontSize(10)
                        .fontColor($r('app.color.text_tertiary'))
                        .backgroundColor($r('app.color.bg_input'))
                        .borderRadius(5)
                        .padding({ left: 6, right: 6, top: 2, bottom: 2 })
                    }
                  }
                  .width('100%')
                  if (entry.description !== '') {
                    Text(entry.description)
                      .fontSize(12)
                      .fontColor($r('app.color.text_secondary'))
                      .maxLines(2)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                  }
                }
                .layoutWeight(1)
                .alignItems(HorizontalAlign.Start)
                SymbolGlyph($r('sys.symbol.plus'))
                  .fontSize(16)
                  .fontColor([$r('app.color.text_tertiary')])
              }
              .width('100%')
              .padding(12)
              .borderRadius(14)
              .backgroundColor($r('app.color.bg_card'))
              .border({ width: 1, color: $r('app.color.card_stroke') })
              .onClick((): void => {
                this.pickEntry(entry);
              })
            }, (entry: ConnectorCatalogEntry) => `${entry.kind}-${entry.available}`)
          }
          .width('100%')
        }
        .align(Alignment.Top)
        .constraintSize({ maxHeight: 420 })
        .scrollBar(BarState.Auto)
      }
    }
    .padding({ left: 18, right: 18, top: 18, bottom: 30 })
    .width('100%')
  }

  @Builder
  private credSheetBuilder() {
    Column({ space: 12 }) {
      Text(this.credEntry === null ? '添加连接器' : `添加 ${this.credEntry.label}`)
        .fontSize(17)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .width('100%')
      TextInput({ text: this.credName, placeholder: '显示名称' })
        .fontSize(14)
        .height(42)
        .backgroundColor($r('app.color.bg_input'))
        .borderRadius(12)
        .onChange((value: string): void => {
          this.credName = value;
        })
      TextArea({ text: this.credJson, placeholder: 'credentials（JSON 对象）' })
        .fontSize(12)
        .fontFamily('monospace')
        .constraintSize({ minHeight: 110, maxHeight: 220 })
        .backgroundColor($r('app.color.bg_input'))
        .borderRadius(12)
        .width('100%')
        .onChange((value: string): void => {
          this.credJson = value;
        })
      Row({ space: 10 }) {
        Button(this.credTesting ? '测试中…' : '测试凭证')
          .fontSize(14)
          .height(42)
          .layoutWeight(1)
          .borderRadius(16)
          .backgroundColor($r('app.color.bg_input'))
          .fontColor($r('app.color.text_secondary'))
          .enabled(!this.credTesting)
          .onClick((): void => {
            this.testCred();
          })
        Button(this.credCreating ? '创建中…' : '创建')
          .fontSize(15)
          .fontWeight(FontWeight.Bold)
          .height(42)
          .layoutWeight(1)
          .borderRadius(16)
          .backgroundColor($r('app.color.brand'))
          .fontColor($r('app.color.text_on_brand'))
          .enabled(!this.credCreating)
          .onClick((): void => {
            this.createCred();
          })
      }
      .width('100%')
    }
    .padding({ left: 18, right: 18, top: 18, bottom: 30 })
    .width('100%')
  }

  @Builder
  private oauthSheetBuilder() {
    Column({ space: 14 }) {
      Text(this.oauthEntry === null ? 'OAuth 授权' : `授权 ${this.oauthEntry.label}`)
        .fontSize(17)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .width('100%')
      if (this.oauthUrl === '') {
        LoadingProgress()
          .width(36)
          .height(36)
          .color($r('app.color.brand'))
      } else {
        SymbolGlyph($r('sys.symbol.link'))
          .fontSize(44)
          .fontColor([$r('app.color.brand')])
        Text('1. 授权链接已复制到剪贴板，请在浏览器打开并登录授权\n2. 授权完成后本页将自动完成创建')
          .fontSize(13)
          .fontColor($r('app.color.text_secondary'))
          .lineHeight(20)
        Text(this.oauthUrl)
          .fontSize(11)
          .fontColor($r('app.color.brand'))
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
          .textAlign(TextAlign.Center)
        Button('重新复制链接')
          .fontSize(14)
          .height(38)
          .borderRadius(19)
          .backgroundColor($r('app.color.bg_input'))
          .fontColor($r('app.color.text_secondary'))
          .onClick((): void => {
            if (this.oauthUrl !== '') {
              this.copyText(this.oauthUrl);
              this.getUIContext().getPromptAction().showToast({ message: '已复制' });
            }
          })
      }
      Row({ space: 8 }) {
        if (this.oauthPolling) {
          LoadingProgress()
            .width(16)
            .height(16)
            .color($r('app.color.text_tertiary'))
        }
        Text(this.oauthPolling ? '等待授权完成…' : this.oauthStatus)
          .fontSize(13)
          .fontColor($r('app.color.text_secondary'))
      }
    }
    .padding({ left: 18, right: 18, top: 18, bottom: 30 })
    .width('100%')
  }

  build() {
    NavDestination() {
      Stack({ alignContent: Alignment.BottomEnd }) {
        Column() {
          PageHeader({ title: '连接器' })

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
          } else if (this.instances.length === 0 && this.mcpServers.length === 0) {
            Column() {
              EmptyView({
                title: '暂无连接器',
                subtitle: '点击右下角按钮添加外部工具与 MCP 服务',
                icon: $r('sys.symbol.link')
              })
            }
            .layoutWeight(1)
            .width('100%')
            .justifyContent(FlexAlign.Center)
          } else {
            Refresh({ refreshing: $$this.refreshing }) {
              List({ space: 10 }) {
                if (this.instances.length > 0) {
                  ListItem() {
                    Text('我的实例')
                      .fontSize(13)
                      .fontWeight(FontWeight.Medium)
                      .fontColor($r('app.color.text_tertiary'))
                      .width('100%')
                      .padding({ left: 4 })
                  }
                }
                ForEach(this.instances, (instance: ConnectorInstanceModel) => {
                  ListItem() {
                    Row({ space: 12 }) {
                      Column() {
                        SymbolGlyph($r('sys.symbol.link'))
                          .fontSize(20)
                          .fontColor([$r('app.color.brand')])
                      }
                      .width(44)
                      .height(44)
                      .justifyContent(FlexAlign.Center)
                      .backgroundColor($r('app.color.brand_light'))
                      .borderRadius(14)
                      Column({ space: 5 }) {
                        Row({ space: 6 }) {
                          Text(instance.displayName)
                            .fontSize(16)
                            .fontWeight(FontWeight.Medium)
                            .fontColor($r('app.color.text_primary'))
                            .maxLines(1)
                            .textOverflow({ overflow: TextOverflow.Ellipsis })
                          if (instance.status !== 'active') {
                            Text(instance.status)
                              .fontSize(10)
                              .fontColor($r('app.color.danger'))
                              .backgroundColor($r('app.color.danger_soft'))
                              .borderRadius(5)
                              .padding({ left: 6, right: 6, top: 2, bottom: 2 })
                          }
                        }
                        .width('100%')
                        Row({ space: 8 }) {
                          Text(instance.kind)
                            .fontSize(12)
                            .fontColor($r('app.color.text_tertiary'))
                          if (!instance.hasCredentials) {
                            Text('未配置凭证')
                              .fontSize(11)
                              .fontColor($r('app.color.warning'))
                              .backgroundColor($r('app.color.bg_input'))
                              .borderRadius(6)
                              .padding({ left: 8, right: 8, top: 3, bottom: 3 })
                          }
                          if (instance.shared) {
                            Text('共享')
                              .fontSize(11)
                              .fontColor($r('app.color.brand'))
                              .backgroundColor($r('app.color.brand_light'))
                              .borderRadius(6)
                              .padding({ left: 8, right: 8, top: 3, bottom: 3 })
                          }
                          if (instance.ownerUsername !== '') {
                            Text(`@${instance.ownerUsername}`)
                              .fontSize(11)
                              .fontColor($r('app.color.text_tertiary'))
                          }
                        }
                        if (instance.description !== '') {
                          Text(instance.description)
                            .fontSize(12)
                            .fontColor($r('app.color.text_secondary'))
                            .maxLines(1)
                            .textOverflow({ overflow: TextOverflow.Ellipsis })
                        }
                      }
                      .layoutWeight(1)
                      .alignItems(HorizontalAlign.Start)
                    }
                    .width('100%')
                    .padding(14)
                    .borderRadius(16)
                    .backgroundColor($r('app.color.bg_card'))
                    .border({ width: 1, color: $r('app.color.card_stroke') })
                    .shadow({ radius: 10, color: '#0A000000', offsetY: 3 })
                    .gesture(
                      LongPressGesture()
                        .onAction((event: GestureEvent): void => {
                          this.showMenu(instance);
                        })
                    )
                  }
                 }, (instance: ConnectorInstanceModel) =>
                   `${instance.instanceId}-${instance.status}-${instance.shared}-${instance.hasCredentials}-${instance.ownerUsername}`)

                if (this.mcpServers.length > 0) {
                  ListItem() {
                    Text('自定义 MCP 服务器')
                      .fontSize(13)
                      .fontWeight(FontWeight.Medium)
                      .fontColor($r('app.color.text_tertiary'))
                      .width('100%')
                      .padding({ left: 4, top: 10 })
                  }
                }
                ForEach(this.mcpServers, (server: CustomMcpServerModel) => {
                  ListItem() {
                    Row({ space: 12 }) {
                      Column({ space: 2 }) {
                        Text(server.name)
                          .fontSize(15)
                          .fontWeight(FontWeight.Medium)
                          .fontColor($r('app.color.text_primary'))
                          .maxLines(1)
                          .textOverflow({ overflow: TextOverflow.Ellipsis })
                        Row({ space: 8 }) {
                          if (server.shared) {
                            Text('共享')
                              .fontSize(11)
                              .fontColor($r('app.color.brand'))
                              .backgroundColor($r('app.color.brand_light'))
                              .borderRadius(6)
                              .padding({ left: 8, right: 8, top: 2, bottom: 2 })
                          }
                          if (server.defaultOpen) {
                            Text('默认开启')
                              .fontSize(11)
                              .fontColor($r('app.color.text_tertiary'))
                          }
                        }
                      }
                      .layoutWeight(1)
                      .alignItems(HorizontalAlign.Start)
                      Toggle({ type: ToggleType.Switch, isOn: server.enabled })
                        .onChange((isOn: boolean): void => {
                          this.toggleMcpServer(server, isOn);
                        })
                    }
                    .width('100%')
                    .padding(14)
                    .borderRadius(16)
                    .backgroundColor($r('app.color.bg_card'))
                    .border({ width: 1, color: $r('app.color.card_stroke') })
                    .shadow({ radius: 10, color: '#0A000000', offsetY: 3 })
                  }
                 }, (server: CustomMcpServerModel) =>
                   `${server.name}-${server.enabled}-${server.shared}-${server.defaultOpen}`)
              }
              .width('100%')
              .height('100%')
              .padding({ left: 12, right: 12, top: 4, bottom: 90 })
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
        .bindSheet($$this.sheetOpen, this.sheetSwitchBuilder, {
          systemMaterial: UiMaterialKit.sheet(),
          detents: [SheetSize.MEDIUM, SheetSize.LARGE],
          showClose: true,
          onDisappear: (): void => {
            this.sheetMode = '';
            this.oauthPolling = false;
            this.oauthUrl = '';
            this.oauthStateId = '';
            this.oauthStatus = '';
          }
        })

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
          this.openCatalog();
        })
      }
      .width('100%')
      .height('100%')
    }
    .hideTitleBar(true)
    .backgroundColor($r('app.color.bg_page'))
    .bindSheet($$this.menuOpen, this.menuSheetBuilder, {
      detents: [SheetSize.FIT_CONTENT],
      showClose: true,
      systemMaterial: UiMaterialKit.sheet()
    })
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
}
