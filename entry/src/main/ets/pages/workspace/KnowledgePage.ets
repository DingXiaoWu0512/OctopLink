import { KnowledgeBaseModel } from '../../model/WorkspaceModels';
import { KnowledgeService } from '../../service/WorkspaceService';
import { OctopApiError } from '../../net/HttpClient';
import { EmptyView } from '../../components/EmptyView';
import { ErrorRetry } from '../../components/ErrorRetry';
import { KbCreateDialog } from '../../components/KbCreateDialog';
import { KnowledgeDocsNavParam } from './KnowledgeDocsPage';
import { PageHeader } from '../../components/PageHeader';
import { UiMaterialKit } from '../../components/UiMaterialKit';

/** 知识库列表（用户级） */
@Component
export struct KnowledgePage {
  @Consume('navStack') navStack: NavPathStack;
  @State bases: Array<KnowledgeBaseModel> = [];
  @State loading: boolean = true;
  @State refreshing: boolean = false;
  @State errorMsg: string = '';
  @State operating: boolean = false;
  private createController: CustomDialogController | null = null;

  aboutToAppear(): void {
    this.load();
  }

  private async load(): Promise<void> {
    this.loading = this.bases.length === 0;
    this.errorMsg = '';
    try {
      this.bases = await KnowledgeService.listBases();
    } catch (e) {
      this.errorMsg = e instanceof OctopApiError ? e.message : '知识库加载失败';
    } finally {
      this.loading = false;
      this.refreshing = false;
    }
  }

  private showCreate(): void {
    this.createController = new CustomDialogController({
      builder: KbCreateDialog({
        onCreated: (): void => {
          this.load();
        }
      }),
      autoCancel: true
    });
    this.createController.open();
  }

  private confirmDelete(base: KnowledgeBaseModel): void {
    this.getUIContext().showAlertDialog({
      title: '删除知识库',
      message: `删除「${base.name}」将同时删除全部文档与索引，确定吗？`,
      primaryButton: {
        value: $r('app.string.common_cancel'),
        action: (): void => {
        }
      },
      secondaryButton: {
        value: $r('app.string.common_confirm'),
        action: (): void => {
          this.deleteBase(base);
        }
      },
      alignment: DialogAlignment.Bottom
    });
  }

  private async deleteBase(base: KnowledgeBaseModel): Promise<void> {
    if (this.operating) {
      return;
    }
    this.operating = true;
    try {
      await KnowledgeService.removeBase(base.id);
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
      Stack({ alignContent: Alignment.BottomEnd }) {
        Column() {
          PageHeader({ title: '知识库' })

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
          } else if (this.bases.length === 0) {
            Column() {
              EmptyView({
                title: '暂无知识库',
                subtitle: '点击右下角按钮创建',
                icon: $r('sys.symbol.book')
              })
            }
            .layoutWeight(1)
            .width('100%')
            .justifyContent(FlexAlign.Center)
          } else {
            Refresh({ refreshing: $$this.refreshing }) {
              List({ space: 10 }) {
                ForEach(this.bases, (base: KnowledgeBaseModel) => {
                  ListItem() {
                    Row({ space: 12 }) {
                      Column() {
                        SymbolGlyph($r('sys.symbol.book'))
                          .fontSize(21)
                          .fontColor([$r('app.color.success')])
                      }
                      .width(44)
                      .height(44)
                      .justifyContent(FlexAlign.Center)
                      .backgroundColor($r('app.color.success_soft'))
                      .borderRadius(14)
                      Column({ space: 5 }) {
                        Row({ space: 6 }) {
                          Text(base.name)
                            .fontSize(16)
                            .fontWeight(FontWeight.Medium)
                            .fontColor($r('app.color.text_primary'))
                            .maxLines(1)
                            .textOverflow({ overflow: TextOverflow.Ellipsis })
                          if (base.shared) {
                            Text('共享')
                              .fontSize(10)
                              .fontColor($r('app.color.text_secondary'))
                              .backgroundColor($r('app.color.bg_input'))
                              .borderRadius(5)
                              .padding({ left: 6, right: 6, top: 2, bottom: 2 })
                          }
                        }
                        .width('100%')
                        if (base.description !== '') {
                          Text(base.description)
                            .fontSize(13)
                            .fontColor($r('app.color.text_secondary'))
                            .maxLines(2)
                            .textOverflow({ overflow: TextOverflow.Ellipsis })
                        }
                        Text(`${base.docCount} 篇文档`)
                          .fontSize(11)
                          .fontColor($r('app.color.success'))
                          .backgroundColor($r('app.color.success_soft'))
                          .borderRadius(6)
                          .padding({ left: 8, right: 8, top: 3, bottom: 3 })
                      }
                      .layoutWeight(1)
                      .alignItems(HorizontalAlign.Start)
                      SymbolGlyph($r('sys.symbol.chevron_right'))
                        .fontSize(14)
                        .fontColor([$r('app.color.text_tertiary')])
                    }
                    .width('100%')
                    .padding(14)
                    .borderRadius(16)
                    .backgroundColor($r('app.color.bg_card'))
                    .border({ width: 1, color: $r('app.color.card_stroke') })
                    .shadow({ radius: 10, color: '#0A000000', offsetY: 3 })
                    .onClick((): void => {
                      this.navStack.pushPath(new NavPathInfo('knowledgeDocs',
                        new KnowledgeDocsNavParam(base.id, base.name)));
                    })
                    .gesture(
                      LongPressGesture()
                        .onAction((event: GestureEvent): void => {
                          this.confirmDelete(base);
                        })
                    )
                  }
                }, (base: KnowledgeBaseModel) => base.id)
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

        Button({ type: ButtonType.Circle, stateEffect: true }) {
          SymbolGlyph($r('sys.symbol.plus'))
            .fontSize(28)
            .fontWeight(FontWeight.Medium)
            .fontColor([$r('app.color.brand')])
        }
        .width(58)
        .height(58)
        .backgroundColor($r('app.color.bg_card'))
        .border({ width: 1, color: $r('app.color.card_stroke') })
        .systemMaterial(UiMaterialKit.button())
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
  }
}
