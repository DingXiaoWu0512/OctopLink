import { ToolSettingItemModel } from '../../model/SkillModels';
import { AgentToolSettingsService } from '../../service/AgentToolSettingsService';
import { SettingsService } from '../../service/WorkspaceService';
import { OctopApiError } from '../../net/HttpClient';
import { JsonHelper } from '../../utils/JsonHelper';
import { SessionStore } from '../../store/SessionStore';
import { EmptyView } from '../../components/EmptyView';
import { ErrorRetry } from '../../components/ErrorRetry';
import { PageHeader } from '../../components/PageHeader';

/** 工具开关（当前专家，源 agent_tools.py） */
@Component
export struct ToolSettingsPage {
  @State tools: Array<ToolSettingItemModel> = [];
  @State loading: boolean = true;
  @State refreshing: boolean = false;
  @State errorMsg: string = '';
  @State operating: boolean = false;
  /** 不可用手机工具的服务端原因（/api/mobile/status 的 reason；失败回退通用文案；空=不显示） */
  @State mobileReason: string = '';
  private mobileReasonFetching: boolean = false;
  private agentId: string = '';
  private pathStack: NavPathStack | null = null;

  private onNavReady(ctx: NavDestinationContext): void {
    this.pathStack = ctx.pathStack;
    this.agentId = AppStorage.get<string>(SessionStore.KEY_AGENT_ID) ?? '';
    if (this.agentId === '') {
      this.loading = false;
      this.errorMsg = '未选择专家，请先在专家页选择';
      return;
    }
    this.load();
  }

  private async load(): Promise<void> {
    this.loading = true;
    this.errorMsg = '';
    try {
      this.tools = await AgentToolSettingsService.list(this.agentId);
      // 存在不可用手机工具时异步补拉服务端原因（不阻断列表首屏渲染）
      this.fetchMobileReason();
    } catch (e) {
      this.errorMsg = e instanceof OctopApiError ? e.message : '工具设置加载失败';
    } finally {
      this.loading = false;
    }
  }

  /** 是否存在不可用手机系列工具（mobile_*：截图/点击/滑动/启动应用/界面结构/交给用户） */
  private hasUnavailableMobileTool(): boolean {
    for (const tool of this.tools) {
      if (!tool.available && tool.name.startsWith('mobile_')) {
        return true;
      }
    }
    return false;
  }

  /** 从 /api/settings/capabilities 的 mobile 节点判断远程手机能力；失败回退通用文案 */
  private async fetchMobileReason(): Promise<void> {
    if (this.mobileReasonFetching || !this.hasUnavailableMobileTool()) {
      return;
    }
    this.mobileReasonFetching = true;
    try {
      const cap = await SettingsService.getMobileCapability();
      this.mobileReason = cap.enabled
        ? '手机工具不可用，请检查专家与手机的连接状态'
        : '服务器未启用远程手机能力，请在服务器配置中开启后重试';
    } catch (e) {
      this.mobileReason = '服务器未启用远程手机能力，请在服务器配置中开启后重试';
    } finally {
      this.mobileReasonFetching = false;
    }
  }

  private async toggleTool(tool: ToolSettingItemModel, on: boolean): Promise<void> {
    if (this.operating) {
      return;
    }
    this.operating = true;
    try {
      await AgentToolSettingsService.patchTool(
        this.agentId, tool.name, on, tool.source, tool.pluginId);
      await this.load();
    } catch (e) {
      const message: string = e instanceof OctopApiError ? e.message : '操作失败';
      this.getUIContext().getPromptAction().showToast({ message });
      await this.load();
    } finally {
      this.operating = false;
    }
  }

  private toolLabel(tool: ToolSettingItemModel): string {
    if (tool.label !== '') {
      return tool.label;
    }
    return tool.name;
  }

  private pluginBadge(tool: ToolSettingItemModel): string {
    if (tool.pluginName !== '') {
      return tool.pluginName;
    }
    return tool.pluginId;
  }

  build() {
    NavDestination() {
      Column() {
        PageHeader({ title: '工具开关' })

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
        } else if (this.tools.length === 0) {
          Column() {
            EmptyView({
              title: '暂无可用工具',
              subtitle: '为专家配置模型或插件后出现',
              icon: $r('sys.symbol.gearshape')
            })
          }
          .layoutWeight(1)
          .width('100%')
          .justifyContent(FlexAlign.Center)
        } else {
          Refresh({ refreshing: $$this.refreshing }) {
            List({ space: 12 }) {
              ForEach(this.tools, (tool: ToolSettingItemModel) => {
                ListItem() {
                  Row({ space: 12 }) {
                    Column() {
                      SymbolGlyph($r('sys.symbol.wrench_and_screwdriver'))
                        .fontSize(20)
                        .fontColor([tool.available ? $r('app.color.brand') : $r('app.color.text_tertiary')])
                    }
                    .width(42)
                    .height(42)
                    .borderRadius(13)
                    .backgroundColor($r('app.color.brand_light'))
                    .justifyContent(FlexAlign.Center)
                    .opacity(tool.available ? 1 : 0.5)

                    Column({ space: 6 }) {
                      Text(this.toolLabel(tool))
                        .fontSize(15)
                        .fontWeight(FontWeight.Medium)
                        .fontColor(tool.available ? $r('app.color.text_primary') : $r('app.color.text_tertiary'))
                        .maxLines(1)
                        .textOverflow({ overflow: TextOverflow.Ellipsis })
                        .width('100%')
                      if (tool.description !== '') {
                        Text(tool.description)
                          .fontSize(12)
                          .fontColor($r('app.color.text_secondary'))
                          .maxLines(2)
                          .textOverflow({ overflow: TextOverflow.Ellipsis })
                          .width('100%')
                          .lineHeight(17)
                      }
                      Row({ space: 8 }) {
                        if (tool.category !== '') {
                          Text(tool.category)
                            .fontSize(11)
                            .fontColor($r('app.color.brand'))
                            .backgroundColor($r('app.color.brand_light'))
                            .borderRadius(6)
                            .padding({ left: 8, right: 8, top: 3, bottom: 3 })
                            .maxLines(1)
                        }
                        if (tool.source === 'plugin') {
                          Text(this.pluginBadge(tool))
                            .fontSize(11)
                            .fontColor($r('app.color.warning'))
                            .backgroundColor($r('app.color.warning_soft'))
                            .borderRadius(6)
                            .padding({ left: 8, right: 8, top: 3, bottom: 3 })
                            .maxLines(1)
                            .textOverflow({ overflow: TextOverflow.Ellipsis })
                            .constraintSize({ maxWidth: 150 })
                        }
                        if (!tool.available) {
                          Text('不可用')
                            .fontSize(11)
                            .fontColor($r('app.color.danger'))
                            .backgroundColor($r('app.color.danger_soft'))
                            .borderRadius(6)
                            .padding({ left: 8, right: 8, top: 3, bottom: 3 })
                        } else if (!tool.disableable) {
                          Text('常开')
                            .fontSize(11)
                            .fontColor($r('app.color.text_tertiary'))
                            .backgroundColor($r('app.color.bg_input'))
                            .borderRadius(6)
                            .padding({ left: 8, right: 8, top: 3, bottom: 3 })
                        }
                      }
                      .width('100%')
                      if (!tool.available && tool.name.startsWith('mobile_') && this.mobileReason !== '') {
                        // 不可用手机工具原因（服务端 /api/mobile/status 的 reason，灰色小字）
                        Text(this.mobileReason)
                          .fontSize(11)
                          .fontColor($r('app.color.text_tertiary'))
                          .width('100%')
                          .lineHeight(16)
                      }
                    }
                    .layoutWeight(1)
                    .alignItems(HorizontalAlign.Start)

                    if (tool.available && tool.disableable) {
                      Toggle({ type: ToggleType.Switch, isOn: tool.enabled })
                        .onChange((isOn: boolean): void => {
                          this.toggleTool(tool, isOn);
                        })
                    }
                  }
                  .width('100%')
                  .padding({ left: 14, right: 14, top: 14, bottom: 14 })
                  .borderRadius(16)
                  .backgroundColor($r('app.color.bg_card'))
                }
              }, (tool: ToolSettingItemModel) => `${tool.source}:${tool.name}`)
            }
            .width('100%')
            .height('100%')
            .padding({ left: 14, right: 14, top: 4 })
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
    }
    .hideTitleBar(true)
    .backgroundColor($r('app.color.bg_page'))
    .onReady((ctx: NavDestinationContext): void => {
      this.onNavReady(ctx);
    })
  }
}
