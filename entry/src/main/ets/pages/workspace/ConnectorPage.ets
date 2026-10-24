import { ConnectorInstanceModel } from '../../model/WorkspaceModels';
import { ConnectorService } from '../../service/WorkspaceService';
import { OctopApiError } from '../../net/HttpClient';
import { EmptyView } from '../../components/EmptyView';
import { ErrorRetry } from '../../components/ErrorRetry';
import { PageHeader } from '../../components/PageHeader';

/** 我的连接器实例（测试/删除） */
@Component
export struct ConnectorPage {
  @State instances: Array<ConnectorInstanceModel> = [];
  @State loading: boolean = true;
  @State refreshing: boolean = false;
  @State errorMsg: string = '';
  @State operating: boolean = false;

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
  }

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

  private showMenu(instance: ConnectorInstanceModel): void {
    this.getUIContext().showActionSheet({
      title: instance.displayName,
      message: '选择要执行的操作',
      sheets: [
        {
          title: '测试连通性',
          action: (): void => {
            this.test(instance);
          }
        },
        {
          title: '删除连接器',
          action: (): void => {
            this.confirmDelete(instance);
          }
        }
      ]
    });
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

  build() {
    NavDestination() {
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
        } else if (this.instances.length === 0) {
          Column() {
            EmptyView({
              title: '暂无连接器',
              subtitle: '在 Web 端添加外部工具与 MCP 服务',
              icon: $r('sys.symbol.link')
            })
          }
          .layoutWeight(1)
          .width('100%')
          .justifyContent(FlexAlign.Center)
        } else {
          Refresh({ refreshing: $$this.refreshing }) {
            List({ space: 10 }) {
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
                        if (instance.defaultOpen) {
                          Text('默认开启')
                            .fontSize(11)
                            .fontColor($r('app.color.brand'))
                            .backgroundColor($r('app.color.brand_light'))
                            .borderRadius(6)
                            .padding({ left: 8, right: 8, top: 3, bottom: 3 })
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
              }, (instance: ConnectorInstanceModel) => instance.instanceId)
            }
            .width('100%')
            .height('100%')
            .padding({ left: 12, right: 12, top: 4, bottom: 20 })
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
  }
}
