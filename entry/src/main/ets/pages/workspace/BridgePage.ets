import { BridgeConnectionModel } from '../../model/BridgeModels';
import { BridgeService } from '../../service/BridgeService';
import { JsonHelper } from '../../utils/JsonHelper';
import { OctopApiError } from '../../net/HttpClient';
import { EmptyView } from '../../components/EmptyView';
import { ErrorRetry } from '../../components/ErrorRetry';
import { BridgeCreateDialog } from '../../components/BridgeCreateDialog';
import { TimeFormat } from '../../utils/TimeFormat';
import { PageHeader } from '../../components/PageHeader';
import { UiMaterialKit } from '../../components/UiMaterialKit';
import { pasteboard } from '@kit.BasicServicesKit';
import { MenuSheetContent, MenuSheetOption } from '../../components/MenuSheet';

/** 桥接设备管理：对端 Octop 连接列表（状态徽章/连接/断开/自动重连/删除） */
@Component
export struct BridgePage {
  @State connections: Array<BridgeConnectionModel> = [];
  @State loading: boolean = true;
  @State refreshing: boolean = false;
  @State errorMsg: string = '';
  @State operating: boolean = false;
  @State menuOpen: boolean = false;
  @State menuTitle: string = '';
  @State menuMessage: string = '';
  @State menuOptions: Array<MenuSheetOption> = [];
  private menuActions: Array<() => void> = [];
  private pathStack: NavPathStack | null = null;
  private createController: CustomDialogController | null = null;

  // 对端专家（bridge 隧道）
  @State remoteAgentsOpen: boolean = false;
  @State remoteAgentsTitle: string = '';
  @State remoteAgentsLoading: boolean = false;
  @State remoteAgentNames: string[] = [];
  @State remoteAgentsError: string = '';

  onNavReady(ctx: NavDestinationContext): void {
    this.pathStack = ctx.pathStack;
    this.load(false);
  }

  private async load(silent: boolean): Promise<void> {
    if (!silent) {
      this.loading = true;
    }
    this.errorMsg = '';
    try {
      this.connections = await BridgeService.list();
    } catch (e) {
      this.errorMsg = e instanceof OctopApiError ? e.message : '桥接设备加载失败';
    } finally {
      this.loading = false;
      this.refreshing = false;
    }
  }

  private showCreate(): void {
    this.createController = new CustomDialogController({
      builder: BridgeCreateDialog({
        onSaved: (): void => {
          this.load(false);
        }
      }),
      autoCancel: true,
      systemMaterial: UiMaterialKit.sheet()
    });
    this.createController.open();
  }

  private showConnMenu(conn: BridgeConnectionModel): void {
    this.menuTitle = conn.displayTitle();
    this.menuMessage = '选择操作';
    this.menuOptions = [
      new MenuSheetOption($r('sys.symbol.person_2'), '查看对端专家', '', false),
      new MenuSheetOption($r('sys.symbol.arrow_clockwise'),
        conn.autoReconnect ? '关闭自动重连' : '开启自动重连', '', false),
      new MenuSheetOption($r('sys.symbol.doc_text'), '复制对端地址', conn.peerBaseUrl, false),
      new MenuSheetOption($r('sys.symbol.trash'), '删除', '', true)
    ];
    this.menuActions = [
      (): void => {
        this.showRemoteAgents(conn);
      },
      (): void => {
        this.toggleAutoReconnect(conn);
      },
      (): void => {
        this.copyAddress(conn);
      },
      (): void => {
        this.confirmDelete(conn);
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

  /** 拉取对端可对话专家列表（bridge 隧道）并以半模态展示 */
  private async showRemoteAgents(conn: BridgeConnectionModel): Promise<void> {
    if (this.remoteAgentsLoading) {
      return;
    }
    this.remoteAgentsTitle = conn.displayTitle();
    this.remoteAgentsError = '';
    this.remoteAgentNames = [];
    this.remoteAgentsLoading = true;
    this.remoteAgentsOpen = true;
    try {
      const text: string = await BridgeService.remoteAgents(conn.connectionId);
      const names: string[] = [];
      const arr = JsonHelper.parseArray(text);
      if (arr !== null) {
        for (const item of arr) {
          let label: string = JsonHelper.getString(item, 'label', '');
          if (label === '') {
            label = JsonHelper.getString(item, 'name', '');
          }
          if (label === '') {
            label = JsonHelper.getString(item, 'agent_id', '');
          }
          if (label === '') {
            label = JsonHelper.getString(item, 'id', '');
          }
          const desc: string = JsonHelper.getString(item, 'description', '');
          names.push(desc === '' ? label : `${label} — ${desc}`);
        }
      }
      this.remoteAgentNames = names;
      if (names.length === 0) {
        this.remoteAgentsError = '对端暂无可对话的专家';
      }
    } catch (e) {
      this.remoteAgentsError = e instanceof OctopApiError ? e.message : '获取对端专家失败';
    } finally {
      this.remoteAgentsLoading = false;
    }
  }

  private async toggleAutoReconnect(conn: BridgeConnectionModel): Promise<void> {
    if (this.operating) {
      return;
    }
    this.operating = true;
    try {
      await BridgeService.setAutoReconnect(conn.connectionId, !conn.autoReconnect);
      await this.load(true);
    } catch (e) {
      const message: string = e instanceof OctopApiError ? e.message : '操作失败';
      this.getUIContext().getPromptAction().showToast({ message });
    } finally {
      this.operating = false;
    }
  }

  private async copyAddress(conn: BridgeConnectionModel): Promise<void> {
    if (conn.peerBaseUrl === '') {
      return;
    }
    try {
      const board = pasteboard.getSystemPasteboard();
      const data = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, conn.peerBaseUrl);
      await board.setData(data);
      this.getUIContext().getPromptAction().showToast({ message: '地址已复制' });
    } catch (e) {
    }
  }

  private async connectConn(conn: BridgeConnectionModel): Promise<void> {
    if (this.operating) {
      return;
    }
    this.operating = true;
    try {
      await BridgeService.connect(conn.connectionId);
      this.getUIContext().getPromptAction().showToast({ message: '已发起连接' });
      await this.load(true);
    } catch (e) {
      const message: string = e instanceof OctopApiError ? e.message : '连接失败';
      this.getUIContext().getPromptAction().showToast({ message });
      await this.load(true);
    } finally {
      this.operating = false;
    }
  }

  private async disconnectConn(conn: BridgeConnectionModel): Promise<void> {
    if (this.operating) {
      return;
    }
    this.operating = true;
    try {
      await BridgeService.disconnect(conn.connectionId);
      this.getUIContext().getPromptAction().showToast({ message: '已断开连接' });
      await this.load(true);
    } catch (e) {
      const message: string = e instanceof OctopApiError ? e.message : '断开失败';
      this.getUIContext().getPromptAction().showToast({ message });
    } finally {
      this.operating = false;
    }
  }

  private confirmDelete(conn: BridgeConnectionModel): void {
    this.getUIContext().showAlertDialog({
      title: '删除桥接设备',
      message: `确定删除「${conn.displayTitle()}」吗？`,
      primaryButton: {
        value: $r('app.string.common_cancel'),
        action: (): void => {
        }
      },
      secondaryButton: {
        value: $r('app.string.common_confirm'),
        action: (): void => {
          this.deleteConn(conn);
        }
      },
      alignment: DialogAlignment.Bottom
    });
  }

  private async deleteConn(conn: BridgeConnectionModel): Promise<void> {
    if (this.operating) {
      return;
    }
    this.operating = true;
    try {
      await BridgeService.remove(conn.connectionId);
      await this.load(true);
    } catch (e) {
      const message: string = e instanceof OctopApiError ? e.message : '删除失败';
      this.getUIContext().getPromptAction().showToast({ message });
    } finally {
      this.operating = false;
    }
  }

  build() {
    NavDestination() {
      Stack({ alignContent: Alignment.BottomEnd }) {
        Column() {
          PageHeader({ title: '桥接设备' })

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
                  this.load(false);
                }
              })
            }
            .layoutWeight(1)
            .width('100%')
            .justifyContent(FlexAlign.Center)
          } else if (this.connections.length === 0) {
            Column() {
              EmptyView({
                title: '暂无桥接设备',
                subtitle: '连接其他 Octop 实例跨端协作',
                icon: $r('sys.symbol.dot_radiowaves_left_and_right')
              })
            }
            .layoutWeight(1)
            .width('100%')
            .justifyContent(FlexAlign.Center)
          } else {
            Refresh({ refreshing: $$this.refreshing }) {
              List({ space: 12 }) {
                ForEach(this.connections, (conn: BridgeConnectionModel) => {
                  ListItem() {
                    Row({ space: 12 }) {
                      Column() {
                        SymbolGlyph($r('sys.symbol.dot_radiowaves_left_and_right'))
                          .fontSize(20)
                          .fontColor([$r('app.color.brand')])
                      }
                      .width(42)
                      .height(42)
                      .borderRadius(13)
                      .backgroundColor($r('app.color.brand_light'))
                      .justifyContent(FlexAlign.Center)

                      Column({ space: 7 }) {
                        Row() {
                          Text(conn.displayTitle())
                            .fontSize(16)
                            .fontWeight(FontWeight.Medium)
                            .fontColor($r('app.color.text_primary'))
                            .maxLines(1)
                            .textOverflow({ overflow: TextOverflow.Ellipsis })
                            .layoutWeight(1)
                          Text(conn.statusText())
                            .fontSize(11)
                            .fontColor(conn.status === 'connected'
                              ? $r('app.color.success')
                              : conn.status === 'error'
                              ? $r('app.color.danger')
                              : conn.status === 'connecting'
                              ? $r('app.color.warning')
                              : $r('app.color.text_tertiary'))
                            .backgroundColor(conn.status === 'connected'
                              ? $r('app.color.success_soft')
                              : conn.status === 'error'
                              ? $r('app.color.danger_soft')
                              : conn.status === 'connecting'
                              ? $r('app.color.warning_soft')
                              : $r('app.color.bg_input'))
                            .borderRadius(6)
                            .padding({ left: 8, right: 8, top: 3, bottom: 3 })
                        }
                        .width('100%')

                        Text(`${conn.peerBaseUrl} · ${conn.peerUsername}`)
                          .fontSize(13)
                          .fontColor($r('app.color.text_secondary'))
                          .maxLines(1)
                          .textOverflow({ overflow: TextOverflow.Ellipsis })
                          .width('100%')

                        Row({ space: 8 }) {
                          if (conn.shared) {
                            Text('已共享')
                              .fontSize(11)
                              .fontColor($r('app.color.brand'))
                              .backgroundColor($r('app.color.brand_light'))
                              .borderRadius(6)
                              .padding({ left: 8, right: 8, top: 3, bottom: 3 })
                          }
                          if (!conn.isOwner && conn.ownerLabel() !== '') {
                            Text(`共享自 ${conn.ownerLabel()}`)
                              .fontSize(11)
                              .fontColor($r('app.color.text_tertiary'))
                              .maxLines(1)
                              .textOverflow({ overflow: TextOverflow.Ellipsis })
                          }
                          if (conn.autoReconnect) {
                            Text('自动重连')
                              .fontSize(11)
                              .fontColor($r('app.color.text_tertiary'))
                          }
                          if (conn.lastSeenAtMs > 0) {
                            Text(`活跃 ${TimeFormat.list(conn.lastSeenAtMs)}`)
                              .fontSize(11)
                              .fontColor($r('app.color.text_tertiary'))
                              .maxLines(1)
                          }
                          Blank()
                          Row({ space: 4 }) {
                            SymbolGlyph($r('sys.symbol.link'))
                              .fontSize(12)
                              .fontColor([$r('app.color.brand')])
                            Text(conn.status === 'connected' ? '断开' : '连接')
                              .fontSize(12)
                              .fontWeight(FontWeight.Medium)
                              .fontColor($r('app.color.brand'))
                          }
                          .onClick((): void => {
                            if (conn.status === 'connected') {
                              this.disconnectConn(conn);
                            } else {
                              this.connectConn(conn);
                            }
                          })
                        }
                        .width('100%')

                        if (conn.notes !== '') {
                          Text(conn.notes)
                            .fontSize(12)
                            .fontColor($r('app.color.text_tertiary'))
                            .maxLines(2)
                            .textOverflow({ overflow: TextOverflow.Ellipsis })
                            .width('100%')
                        }
                        if (conn.lastError !== '') {
                          Text(`最近错误：${conn.lastError}`)
                            .fontSize(11)
                            .fontColor($r('app.color.danger'))
                            .maxLines(2)
                            .textOverflow({ overflow: TextOverflow.Ellipsis })
                            .width('100%')
                            .lineHeight(15)
                        }
                      }
                      .layoutWeight(1)
                      .alignItems(HorizontalAlign.Start)
                    }
                    .width('100%')
                    .padding({ left: 14, right: 14, top: 14, bottom: 14 })
                    .borderRadius(16)
                    .backgroundColor($r('app.color.bg_card'))
                    .gesture(
                      LongPressGesture()
                        .onAction((event: GestureEvent): void => {
                          this.showConnMenu(conn);
                        })
                    )
                  }
                }, (conn: BridgeConnectionModel) => conn.connectionId)
              }
              .width('100%')
              .height('100%')
              .padding({ left: 14, right: 14, top: 4 })
              .scrollBar(BarState.Off)
            }
            .layoutWeight(1)
            .width('100%')
            .onRefreshing((): void => {
              this.load(true);
            })
          }
        }
        .width('100%')
        .height('100%')

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
        .margin(22)
        .onClick((): void => {
          this.showCreate();
        })
      }
      .width('100%')
      .height('100%')
    }
    .hideTitleBar(true)
    .backgroundColor($r('app.color.bg_page'))
    .onReady((ctx: NavDestinationContext): void => {
      this.onNavReady(ctx);
    })
    .bindSheet($$this.menuOpen, this.menuSheetBuilder, {
      detents: [SheetSize.FIT_CONTENT],
      showClose: true,
      systemMaterial: UiMaterialKit.sheet()
    })
    .bindSheet($$this.remoteAgentsOpen, this.remoteAgentsBuilder, {
      detents: [SheetSize.MEDIUM, SheetSize.LARGE],
      showClose: true,
      systemMaterial: UiMaterialKit.sheet()
    })
  }

  @Builder
  remoteAgentsBuilder() {
    Column({ space: 12 }) {
      Text(`对端专家 · ${this.remoteAgentsTitle}`)
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .width('100%')

      if (this.remoteAgentsLoading) {
        Column() {
          LoadingProgress()
            .width(32)
            .height(32)
            .color($r('app.color.brand'))
        }
        .width('100%')
        .padding({ top: 30, bottom: 30 })
      } else if (this.remoteAgentsError !== '') {
        Text(this.remoteAgentsError)
          .fontSize(13)
          .fontColor($r('app.color.text_secondary'))
          .width('100%')
          .padding({ top: 16, bottom: 16 })
      } else {
        List({ space: 8 }) {
          ForEach(this.remoteAgentNames, (name: string) => {
            ListItem() {
              Row({ space: 10 }) {
                SymbolGlyph($r('sys.symbol.person'))
                  .fontSize(16)
                  .fontColor([$r('app.color.brand')])
                Text(name)
                  .fontSize(14)
                  .fontColor($r('app.color.text_primary'))
                  .width('100%')
              }
              .width('100%')
              .padding({ left: 12, right: 12, top: 10, bottom: 10 })
              .borderRadius(12)
              .backgroundColor($r('app.color.bg_input'))
            }
          }, (name: string) => name)
        }
        .width('100%')
        .scrollBar(BarState.Off)
      }
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 12, bottom: 16 })
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
