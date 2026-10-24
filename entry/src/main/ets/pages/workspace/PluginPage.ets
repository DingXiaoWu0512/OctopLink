import { AgentPluginModel } from '../../model/WorkspaceModels';
import { PluginService } from '../../service/WorkspaceService';
import { OctopApiError } from '../../net/HttpClient';
import { SessionStore } from '../../store/SessionStore';
import { EmptyView } from '../../components/EmptyView';
import { ErrorRetry } from '../../components/ErrorRetry';
import { PageHeader } from '../../components/PageHeader';

/** 当前专家的插件开关 */
@Component
export struct PluginPage {
  @State plugins: Array<AgentPluginModel> = [];
  @State loading: boolean = true;
  @State errorMsg: string = '';
  @State operating: boolean = false;
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

  private async toggle(plugin: AgentPluginModel, on: boolean): Promise<void> {
    if (this.operating) {
      return;
    }
    this.operating = true;
    try {
      await PluginService.setAgentEnabled(this.agentId, plugin.id, on);
      await this.load();
    } catch (e) {
      const message: string = e instanceof OctopApiError ? e.message : '操作失败';
      this.getUIContext().getPromptAction().showToast({ message });
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
        } else if (this.plugins.length === 0) {
          Column() {
            EmptyView({
              title: '暂无插件',
              subtitle: '在 Web 端安装插件后可在此为专家启用',
              icon: $r('sys.symbol.puzzle')
            })
          }
          .layoutWeight(1)
          .width('100%')
          .justifyContent(FlexAlign.Center)
        } else {
          List({ space: 10 }) {
            ForEach(this.plugins, (plugin: AgentPluginModel) => {
              ListItem() {
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
                      this.toggle(plugin, isOn);
                    })
                }
                .width('100%')
                .padding(14)
                .borderRadius(16)
                .backgroundColor($r('app.color.bg_card'))
                .border({ width: 1, color: $r('app.color.card_stroke') })
                .shadow({ radius: 10, color: '#0A000000', offsetY: 3 })
              }
            }, (plugin: AgentPluginModel) => plugin.id)
          }
          .width('100%')
          .layoutWeight(1)
          .padding({ left: 12, right: 12, top: 4, bottom: 20 })
          .scrollBar(BarState.Off)
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
}
