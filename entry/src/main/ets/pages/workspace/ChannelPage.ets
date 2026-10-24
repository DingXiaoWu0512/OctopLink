import { ChannelModel } from '../../model/WorkspaceModels';
import { ChannelService } from '../../service/WorkspaceService';
import { OctopApiError } from '../../net/HttpClient';
import { SessionStore } from '../../store/SessionStore';
import { EmptyView } from '../../components/EmptyView';
import { ErrorRetry } from '../../components/ErrorRetry';
import { PageHeader } from '../../components/PageHeader';

/** 当前专家的渠道列表（启停/删除） */
@Component
export struct ChannelPage {
  @State channels: Array<ChannelModel> = [];
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
    this.loading = this.channels.length === 0;
    this.errorMsg = '';
    try {
      this.channels = await ChannelService.list(this.agentId);
    } catch (e) {
      this.errorMsg = e instanceof OctopApiError ? e.message : '渠道加载失败';
    } finally {
      this.loading = false;
    }
  }

  private async toggle(channel: ChannelModel, on: boolean): Promise<void> {
    if (this.operating) {
      return;
    }
    this.operating = true;
    try {
      await ChannelService.setEnabled(this.agentId, channel.id, on);
      await this.load();
    } catch (e) {
      const message: string = e instanceof OctopApiError ? e.message : '操作失败';
      this.getUIContext().getPromptAction().showToast({ message });
    } finally {
      this.operating = false;
    }
  }

  private confirmDelete(channel: ChannelModel): void {
    this.getUIContext().showAlertDialog({
      title: '删除渠道',
      message: `删除「${channel.name}」后将无法通过该渠道收发消息，确定吗？`,
      primaryButton: {
        value: $r('app.string.common_cancel'),
        action: (): void => {
        }
      },
      secondaryButton: {
        value: $r('app.string.common_confirm'),
        action: (): void => {
          this.deleteChannel(channel);
        }
      },
      alignment: DialogAlignment.Bottom
    });
  }

  private async deleteChannel(channel: ChannelModel): Promise<void> {
    if (this.operating) {
      return;
    }
    this.operating = true;
    try {
      await ChannelService.remove(this.agentId, channel.id);
      await this.load();
    } catch (e) {
      const message: string = e instanceof OctopApiError ? e.message : '删除失败';
      this.getUIContext().getPromptAction().showToast({ message });
    } finally {
      this.operating = false;
    }
  }

  build() {
    NavDestination() {
      Column() {
        PageHeader({ title: '渠道' })

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
        } else if (this.channels.length === 0) {
          Column() {
            EmptyView({
              title: '暂无渠道',
              subtitle: '在 Web 端为专家接入钉钉/企微/飞书等渠道',
              icon: $r('sys.symbol.dot_radiowaves_left_and_right')
            })
          }
          .layoutWeight(1)
          .width('100%')
          .justifyContent(FlexAlign.Center)
        } else {
           List({ space: 10 }) {
             ForEach(this.channels, (channel: ChannelModel) => {
               ListItem() {
                 Row({ space: 12 }) {
                   Column() {
                     SymbolGlyph($r('sys.symbol.dot_radiowaves_left_and_right'))
                       .fontSize(20)
                       .fontColor([channel.enabled ? $r('app.color.success') : $r('app.color.text_tertiary')])
                   }
                   .width(44)
                   .height(44)
                   .justifyContent(FlexAlign.Center)
                   .backgroundColor(channel.enabled ? $r('app.color.success_soft') : $r('app.color.bg_input'))
                   .borderRadius(14)
                   Column({ space: 5 }) {
                     Row({ space: 6 }) {
                       Text(channel.name)
                         .fontSize(16)
                         .fontWeight(FontWeight.Medium)
                         .fontColor($r('app.color.text_primary'))
                         .maxLines(1)
                         .textOverflow({ overflow: TextOverflow.Ellipsis })
                     }
                     .width('100%')
                     Row({ space: 8 }) {
                       Text(channel.kind)
                         .fontSize(12)
                         .fontColor($r('app.color.text_tertiary'))
                       Text(channel.enabled ? '已启用' : '已停用')
                         .fontSize(11)
                         .fontColor(channel.enabled ? $r('app.color.success') : $r('app.color.text_tertiary'))
                         .backgroundColor(channel.enabled
                           ? $r('app.color.success_soft') : $r('app.color.bg_input'))
                         .borderRadius(6)
                         .padding({ left: 8, right: 8, top: 3, bottom: 3 })
                     }
                   }
                   .layoutWeight(1)
                   .alignItems(HorizontalAlign.Start)
                   Toggle({ type: ToggleType.Switch, isOn: channel.enabled })
                     .onChange((isOn: boolean): void => {
                       this.toggle(channel, isOn);
                     })
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
                       this.confirmDelete(channel);
                     })
                 )
               }
             }, (channel: ChannelModel) => channel.id)
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
