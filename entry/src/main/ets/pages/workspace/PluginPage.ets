import {
  AgentPluginModel,
  GlobalPluginModel,
  MarketPluginModel,
  PluginToolModel
} from '../../model/WorkspaceModels';
import { GlobalPluginService, PluginService } from '../../service/WorkspaceService';
import { OctopApiError } from '../../net/HttpClient';
import { SessionStore } from '../../store/SessionStore';
import { EmptyView } from '../../components/EmptyView';
import { ErrorRetry } from '../../components/ErrorRetry';
import { PageHeader } from '../../components/PageHeader';
import { UiMaterialKit } from '../../components/UiMaterialKit';

/** 插件管理：全局插件（启停/卸载/市场/URL 安装/重载）+ 此专家插件开关与工具配置 */
@Component
export struct PluginPage {
  @State globalPlugins: Array<GlobalPluginModel> = [];
  @State globalLoading: boolean = true;
  @State globalError: string = '';
  @State plugins: Array<AgentPluginModel> = [];
  @State loading: boolean = true;
  @State errorMsg: string = '';
  @State operating: boolean = false;
  @State sheetOpen: boolean = false;
  @State sheetMode: string = '';
  @State tools: Array<PluginToolModel> = [];
  @State toolsLoading: boolean = false;
  @State toolsError: string = '';
  @State marketList: Array<MarketPluginModel> = [];
  @State marketLoading: boolean = false;
  @State urlText: string = '';
  @State installing: boolean = false;
  private agentId: string = '';

  private onNavReady(ctx: NavDestinationContext): void {
    this.agentId = AppStorage.get<string>(SessionStore.KEY_AGENT_ID) ?? '';
    if (this.agentId === '') {
      this.loading = false;
      this.errorMsg = '未选择专家，请先在专家页选择';
      return;
    }
    this.load();
  }

  private async load(): Promise<void> {
    this.loadGlobal();
    this.loading = this.plugins.length === 0;
    this.errorMsg = '';
    try {
      this.plugins = await PluginService.listForAgent(this.agentId);
    } catch (e) {
      this.errorMsg = e instanceof OctopApiError ? e.message : '插件加载失败';
    } finally {
      this.loading = false;
    }
  }

  private async loadGlobal(): Promise<void> {
    this.globalLoading = this.globalPlugins.length === 0;
    this.globalError = '';
    try {
      this.globalPlugins = await GlobalPluginService.list();
    } catch (e) {
      this.globalError = e instanceof OctopApiError ? e.message : '全局插件加载失败';
    } finally {
      this.globalLoading = false;
    }
  }

  private toastError(e: Object, fallback: string): void {
    const message: string = e instanceof OctopApiError ? e.message : fallback;
    this.getUIContext().getPromptAction().showToast({ message });
  }

  private async toggleAgent(plugin: AgentPluginModel, on: boolean): Promise<void> {
    if (this.operating) {
      return;
    }
    this.operating = true;
    try {
      await PluginService.setAgentEnabled(this.agentId, plugin.id, on);
      this.plugins = await PluginService.listForAgent(this.agentId);
    } catch (e) {
      this.toastError(e, '操作失败');
    } finally {
      this.operating = false;
    }
  }

  private async toggleGlobal(plugin: GlobalPluginModel, on: boolean): Promise<void> {
    if (this.operating) {
      return;
    }
    this.operating = true;
    try {
      await GlobalPluginService.setEnabled(plugin.id, on);
      this.globalPlugins = await GlobalPluginService.list();
    } catch (e) {
      this.toastError(e, '操作失败');
    } finally {
      this.operating = false;
    }
  }

  private confirmUninstall(plugin: GlobalPluginModel): void {
    this.getUIContext().showAlertDialog({
      title: '卸载插件',
      message: `确定卸载「${plugin.name}」吗？所有专家的该插件都将停用。`,
      primaryButton: {
        value: $r('app.string.common_cancel'),
        action: (): void => {
        }
      },
      secondaryButton: {
        value: $r('app.string.common_confirm'),
        action: (): void => {
          this.uninstallPlugin(plugin);
        }
      },
      alignment: DialogAlignment.Bottom
    });
  }

  private async uninstallPlugin(plugin: GlobalPluginModel): Promise<void> {
    if (this.operating) {
      return;
    }
    this.operating = true;
    try {
      await GlobalPluginService.uninstall(plugin.id);
      this.getUIContext().getPromptAction().showToast({ message: '已卸载' });
      await this.load();
    } catch (e) {
      this.toastError(e, '卸载失败');
    } finally {
      this.operating = false;
    }
  }

  private async reloadPlugins(): Promise<void> {
    if (this.operating) {
      return;
    }
    this.operating = true;
    try {
      await GlobalPluginService.reload();
      this.getUIContext().getPromptAction().showToast({ message: '已从磁盘重载' });
      await this.load();
    } catch (e) {
      this.toastError(e, '重载失败');
    } finally {
      this.operating = false;
    }
  }

  private showInstallMenu(): void {
    this.getUIContext().showActionSheet({
      title: '安装插件',
      message: '选择安装方式',
      sheets: [
        {
          title: '从市场安装',
          action: (): void => {
            this.openMarket();
          }
        },
        {
          title: '通过 URL 安装',
          action: (): void => {
            this.urlText = '';
            this.sheetMode = 'url';
            this.sheetOpen = true;
          }
        }
      ]
    });
  }

  private async openMarket(): Promise<void> {
    this.sheetMode = 'market';
    this.sheetOpen = true;
    this.marketLoading = true;
    try {
      this.marketList = await GlobalPluginService.market();
    } catch (e) {
      this.sheetOpen = false;
      this.toastError(e, '市场加载失败');
    } finally {
      this.marketLoading = false;
    }
  }

  private confirmForceInstall(plugin: MarketPluginModel): void {
    this.getUIContext().showAlertDialog({
      title: '覆盖安装',
      message: `「${plugin.name}」已安装，确定覆盖为市场版本吗？`,
      primaryButton: {
        value: $r('app.string.common_cancel'),
        action: (): void => {
        }
      },
      secondaryButton: {
        value: $r('app.string.common_confirm'),
        action: (): void => {
          this.installMarket(plugin, true);
        }
      },
      alignment: DialogAlignment.Bottom
    });
  }

  private async installMarket(plugin: MarketPluginModel, force: boolean): Promise<void> {
    if (this.installing) {
      return;
    }
    this.installing = true;
    try {
      await GlobalPluginService.marketInstall(plugin.id, force);
      this.getUIContext().getPromptAction().showToast({ message: `已安装 ${plugin.name}` });
      this.sheetOpen = false;
      await this.load();
    } catch (e) {
      if (e instanceof OctopApiError &&
        (e.code === 'PLUGIN_ALREADY_EXISTS' || e.status === 409)) {
        this.installing = false;
        this.confirmForceInstall(plugin);
        return;
      }
      this.toastError(e, '安装失败');
    } finally {
      this.installing = false;
    }
  }

  private async installUrl(): Promise<void> {
    if (this.installing) {
      return;
    }
    const url: string = this.urlText.trim();
    if (url === '') {
      this.getUIContext().getPromptAction().showToast({ message: '请输入 ZIP 包 URL' });
      return;
    }
    this.installing = true;
    try {
      await GlobalPluginService.installUrl(url);
      this.getUIContext().getPromptAction().showToast({ message: '安装成功' });
      this.sheetOpen = false;
      await this.load();
    } catch (e) {
      this.toastError(e, '安装失败');
    } finally {
      this.installing = false;
    }
  }

  private async openTools(): Promise<void> {
    this.sheetMode = 'tools';
    this.sheetOpen = true;
    this.toolsLoading = true;
    this.toolsError = '';
    try {
      this.tools = await PluginService.getAgentTools(this.agentId);
    } catch (e) {
      this.toolsError = e instanceof OctopApiError ? e.message : '工具配置加载失败';
    } finally {
      this.toolsLoading = false;
    }
  }

  private async toggleTool(tool: PluginToolModel, on: boolean): Promise<void> {
    if (this.operating) {
      return;
    }
    this.operating = true;
    try {
      await PluginService.patchAgentTools(this.agentId, tool.pluginId, on);
      this.tools = await PluginService.getAgentTools(this.agentId);
    } catch (e) {
      this.toastError(e, '操作失败');
    } finally {
      this.operating = false;
    }
  }

  build() {
    NavDestination() {
      Column() {
        PageHeader({ title: '插件' })

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
          Scroll() {
            Column({ space: 12 }) {
              Row({ space: 10 }) {
                Text('全局插件')
                  .fontSize(14)
                  .fontWeight(FontWeight.Bold)
                  .fontColor($r('app.color.text_primary'))
                  .layoutWeight(1)
                Button('重载')
                  .fontSize(12)
                  .height(30)
                  .borderRadius(15)
                  .backgroundColor($r('app.color.bg_input'))
                  .fontColor($r('app.color.text_secondary'))
                  .onClick((): void => {
                    this.reloadPlugins();
                  })
                Button('安装')
                  .fontSize(12)
                  .height(30)
                  .borderRadius(15)
                  .linearGradient({
                    angle: 140,
                    colors: [[$r('app.color.brand_grad_start'), 0], [$r('app.color.brand_grad_end'), 1]]
                  })
                  .fontColor($r('app.color.text_on_brand'))
                  .onClick((): void => {
                    this.showInstallMenu();
                  })
              }
              .width('100%')

              if (this.globalLoading) {
                Row({ space: 8 }) {
                  LoadingProgress()
                    .width(16)
                    .height(16)
                    .color($r('app.color.text_tertiary'))
                  Text('加载中...')
                    .fontSize(12)
                    .fontColor($r('app.color.text_tertiary'))
                }
                .width('100%')
                .justifyContent(FlexAlign.Center)
                .padding(12)
              } else if (this.globalError !== '') {
                Text(this.globalError)
                  .fontSize(12)
                  .fontColor($r('app.color.danger'))
                  .width('100%')
                  .padding({ left: 4 })
              } else if (this.globalPlugins.length === 0) {
                Text('暂无已安装插件，可从市场或 URL 安装')
                  .fontSize(12)
                  .fontColor($r('app.color.text_tertiary'))
                  .width('100%')
                  .padding({ left: 4 })
              } else {
                ForEach(this.globalPlugins, (plugin: GlobalPluginModel) => {
                  Row({ space: 12 }) {
                    Column() {
                      SymbolGlyph($r('sys.symbol.puzzle'))
                        .fontSize(20)
                        .fontColor([$r('app.color.brand')])
                    }
                    .width(40)
                    .height(40)
                    .justifyContent(FlexAlign.Center)
                    .backgroundColor($r('app.color.brand_light'))
                    .borderRadius(13)
                    .opacity(plugin.enabled ? 1 : 0.5)
                    Column({ space: 4 }) {
                      Row({ space: 6 }) {
                        Text(plugin.name)
                          .fontSize(15)
                          .fontWeight(FontWeight.Medium)
                          .fontColor($r('app.color.text_primary'))
                          .maxLines(1)
                          .textOverflow({ overflow: TextOverflow.Ellipsis })
                        if (plugin.version !== '') {
                          Text(plugin.version)
                            .fontSize(10)
                            .fontColor($r('app.color.text_secondary'))
                            .backgroundColor($r('app.color.bg_input'))
                            .borderRadius(5)
                            .padding({ left: 6, right: 6, top: 2, bottom: 2 })
                        }
                        if (!plugin.loaded) {
                          Text('未加载')
                            .fontSize(10)
                            .fontColor($r('app.color.warning'))
                            .backgroundColor($r('app.color.bg_input'))
                            .borderRadius(5)
                            .padding({ left: 6, right: 6, top: 2, bottom: 2 })
                        }
                      }
                      .width('100%')
                      if (plugin.description !== '') {
                        Text(plugin.description)
                          .fontSize(11)
                          .fontColor($r('app.color.text_secondary'))
                          .maxLines(2)
                          .textOverflow({ overflow: TextOverflow.Ellipsis })
                      }
                    }
                    .layoutWeight(1)
                    .alignItems(HorizontalAlign.Start)
                    Toggle({ type: ToggleType.Switch, isOn: plugin.enabled })
                      .onChange((isOn: boolean): void => {
                        this.toggleGlobal(plugin, isOn);
                      })
                  }
                  .width('100%')
                  .padding(12)
                  .borderRadius(14)
                  .backgroundColor($r('app.color.bg_card'))
                  .border({ width: 1, color: $r('app.color.card_stroke') })
                  .gesture(
                    LongPressGesture()
                      .onAction((event: GestureEvent): void => {
                        this.confirmUninstall(plugin);
                      })
                  )
                }, (plugin: GlobalPluginModel) => plugin.id)
              }

              Row({ space: 10 }) {
                Text('此专家插件')
                  .fontSize(14)
                  .fontWeight(FontWeight.Bold)
                  .fontColor($r('app.color.text_primary'))
                  .layoutWeight(1)
                Button('工具配置')
                  .fontSize(12)
                  .height(30)
                  .borderRadius(15)
                  .backgroundColor($r('app.color.bg_input'))
                  .fontColor($r('app.color.text_secondary'))
                  .onClick((): void => {
                    this.openTools();
                  })
              }
              .width('100%')
              .margin({ top: 6 })

              if (this.plugins.length === 0) {
                Column({ space: 8 }) {
                  EmptyView({
                    title: '暂无插件',
                    subtitle: '在上方安装插件后可在此为专家启用',
                    icon: $r('sys.symbol.puzzle')
                  })
                }
                .width('100%')
                .padding({ top: 10, bottom: 10 })
              } else {
                ForEach(this.plugins, (plugin: AgentPluginModel) => {
                  Row({ space: 12 }) {
                    Column() {
                      SymbolGlyph($r('sys.symbol.puzzle'))
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
                        Text(plugin.name)
                          .fontSize(16)
                          .fontWeight(FontWeight.Medium)
                          .fontColor($r('app.color.text_primary'))
                          .maxLines(1)
                          .textOverflow({ overflow: TextOverflow.Ellipsis })
                        Text(plugin.kind)
                          .fontSize(10)
                          .fontColor($r('app.color.text_secondary'))
                          .backgroundColor($r('app.color.bg_input'))
                          .borderRadius(5)
                          .padding({ left: 6, right: 6, top: 2, bottom: 2 })
                        if (!plugin.globalEnabled) {
                          Text('全局已停用')
                            .fontSize(10)
                            .fontColor($r('app.color.danger'))
                            .backgroundColor($r('app.color.danger_soft'))
                            .borderRadius(5)
                            .padding({ left: 6, right: 6, top: 2, bottom: 2 })
                        }
                      }
                      .width('100%')
                      if (plugin.description !== '') {
                        Text(plugin.description)
                          .fontSize(12)
                          .fontColor($r('app.color.text_secondary'))
                          .maxLines(2)
                          .textOverflow({ overflow: TextOverflow.Ellipsis })
                      }
                    }
                    .layoutWeight(1)
                    .alignItems(HorizontalAlign.Start)
                    Toggle({ type: ToggleType.Switch, isOn: plugin.agentEnabled })
                      .enabled(plugin.globalEnabled)
                      .opacity(plugin.globalEnabled ? 1 : 0.4)
                      .onChange((isOn: boolean): void => {
                        this.toggleAgent(plugin, isOn);
                      })
                  }
                  .width('100%')
                  .padding(14)
                  .borderRadius(16)
                  .backgroundColor($r('app.color.bg_card'))
                  .border({ width: 1, color: $r('app.color.card_stroke') })
                  .shadow({ radius: 10, color: '#0A000000', offsetY: 3 })
                }, (plugin: AgentPluginModel) => plugin.id)
              }
            }
            .width('100%')
            .padding({ left: 14, right: 14, top: 4, bottom: 30 })
          }
          .layoutWeight(1)
          .width('100%')
          .scrollBar(BarState.Off)
          .bindSheet($$this.sheetOpen, this.sheetSwitchBuilder, {
            systemMaterial: UiMaterialKit.sheet(),
            detents: [SheetSize.MEDIUM, SheetSize.LARGE],
            showClose: true,
            onDisappear: (): void => {
              this.sheetMode = '';
            }
          })
        }
      }
      .width('100%')
      .height('100%')
    }
    .hideTitleBar(true)
    .backgroundColor($r('app.color.bg_page'))
    .onReady((ctx: NavDestinationContext): void => {
      this.onNavReady(ctx);
    })
  }

  /** 单 bindSheet 分发：market / url / tools */
  @Builder
  sheetSwitchBuilder() {
    if (this.sheetMode === 'market') {
      this.marketBuilder()
    } else if (this.sheetMode === 'url') {
      this.urlBuilder()
    } else if (this.sheetMode === 'tools') {
      this.toolsBuilder()
    }
  }

  @Builder
  marketBuilder() {
    Column({ space: 12 }) {
      Text('插件市场')
        .fontSize(17)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .width('100%')

      if (this.marketLoading) {
        Column() {
          LoadingProgress()
            .width(28)
            .height(28)
            .color($r('app.color.brand'))
        }
        .width('100%')
        .padding({ top: 30, bottom: 30 })
      } else if (this.marketList.length === 0) {
        Text('市场暂无可用插件')
          .fontSize(13)
          .fontColor($r('app.color.text_tertiary'))
          .width('100%')
          .padding({ top: 20, bottom: 20 })
      } else {
        Scroll() {
          Column({ space: 10 }) {
            ForEach(this.marketList, (plugin: MarketPluginModel) => {
              Row({ space: 12 }) {
                Column({ space: 4 }) {
                  Row({ space: 6 }) {
                    Text(plugin.name)
                      .fontSize(15)
                      .fontWeight(FontWeight.Medium)
                      .fontColor($r('app.color.text_primary'))
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                    if (plugin.version !== '') {
                      Text(plugin.version)
                        .fontSize(10)
                        .fontColor($r('app.color.text_secondary'))
                        .backgroundColor($r('app.color.bg_input'))
                        .borderRadius(5)
                        .padding({ left: 6, right: 6, top: 2, bottom: 2 })
                    }
                  }
                  if (plugin.description !== '') {
                    Text(plugin.description)
                      .fontSize(11)
                      .fontColor($r('app.color.text_secondary'))
                      .maxLines(2)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                  }
                }
                .layoutWeight(1)
                .alignItems(HorizontalAlign.Start)

                Button(this.installing ? '...' : '安装')
                  .fontSize(12)
                  .height(30)
                  .borderRadius(15)
                  .backgroundColor($r('app.color.brand_light'))
                  .fontColor($r('app.color.brand'))
                  .enabled(!this.installing)
                  .onClick((): void => {
                    this.installMarket(plugin, false);
                  })
              }
              .width('100%')
              .padding(12)
              .borderRadius(14)
              .backgroundColor($r('app.color.bg_card'))
              .border({ width: 1, color: $r('app.color.card_stroke') })
            }, (plugin: MarketPluginModel) => plugin.id)
          }
          .width('100%')
        }
        .layoutWeight(1)
        .width('100%')
        .scrollBar(BarState.Auto)
        .align(Alignment.TopStart)
      }
    }
    .padding({ left: 20, right: 20, top: 20, bottom: 24 })
    .width('100%')
    .height('100%')
  }

  @Builder
  urlBuilder() {
    Column({ space: 14 }) {
      Text('通过 URL 安装')
        .fontSize(17)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .width('100%')

      TextInput({
        text: this.urlText,
        placeholder: '插件 ZIP 包下载地址'
      })
        .fontSize(14)
        .height(44)
        .backgroundColor($r('app.color.bg_input'))
        .borderRadius(12)
        .onChange((value: string): void => {
          this.urlText = value;
        })

      Button(this.installing ? '安装中...' : '安装')
        .fontSize(14)
        .height(42)
        .borderRadius(21)
        .width('100%')
        .linearGradient({
          angle: 140,
          colors: [[$r('app.color.brand_grad_start'), 0], [$r('app.color.brand_grad_end'), 1]]
        })
        .fontColor($r('app.color.text_on_brand'))
        .enabled(!this.installing)
        .onClick((): void => {
          this.installUrl();
        })
    }
    .padding({ left: 20, right: 20, top: 20, bottom: 30 })
    .width('100%')
  }

  @Builder
  toolsBuilder() {
    Column({ space: 12 }) {
      Text('工具配置')
        .fontSize(17)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .width('100%')

      Text('控制当前专家可调用的插件工具，未显式关闭时默认启用')
        .fontSize(11)
        .fontColor($r('app.color.text_tertiary'))
        .width('100%')

      if (this.toolsLoading) {
        Column() {
          LoadingProgress()
            .width(28)
            .height(28)
            .color($r('app.color.brand'))
        }
        .width('100%')
        .padding({ top: 30, bottom: 30 })
      } else if (this.toolsError !== '') {
        Text(this.toolsError)
          .fontSize(13)
          .fontColor($r('app.color.danger'))
          .width('100%')
          .padding({ top: 16, bottom: 16 })
      } else if (this.tools.length === 0) {
        Text('当前专家没有可用工具')
          .fontSize(13)
          .fontColor($r('app.color.text_tertiary'))
          .width('100%')
          .padding({ top: 20, bottom: 20 })
      } else {
        Scroll() {
          Column({ space: 10 }) {
            ForEach(this.tools, (tool: PluginToolModel) => {
              Row({ space: 12 }) {
                Column({ space: 4 }) {
                  Row({ space: 6 }) {
                    Text(tool.name)
                      .fontSize(15)
                      .fontWeight(FontWeight.Medium)
                      .fontColor($r('app.color.text_primary'))
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                    if (tool.pluginId !== '') {
                      Text(tool.pluginId)
                        .fontSize(10)
                        .fontColor($r('app.color.text_secondary'))
                        .backgroundColor($r('app.color.bg_input'))
                        .borderRadius(5)
                        .padding({ left: 6, right: 6, top: 2, bottom: 2 })
                        .maxLines(1)
                    }
                  }
                  .width('100%')
                  if (tool.description !== '') {
                    Text(tool.description)
                      .fontSize(11)
                      .fontColor($r('app.color.text_secondary'))
                      .maxLines(2)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                  }
                }
                .layoutWeight(1)
                .alignItems(HorizontalAlign.Start)
                Toggle({ type: ToggleType.Switch, isOn: tool.enabled })
                  .onChange((isOn: boolean): void => {
                    this.toggleTool(tool, isOn);
                  })
              }
              .width('100%')
              .padding(12)
              .borderRadius(14)
              .backgroundColor($r('app.color.bg_card'))
              .border({ width: 1, color: $r('app.color.card_stroke') })
            }, (tool: PluginToolModel) => `${tool.pluginId}-${tool.name}`)
          }
          .width('100%')
        }
        .layoutWeight(1)
        .width('100%')
        .scrollBar(BarState.Auto)
        .align(Alignment.TopStart)
      }
    }
    .padding({ left: 20, right: 20, top: 20, bottom: 24 })
    .width('100%')
    .height('100%')
  }
}
