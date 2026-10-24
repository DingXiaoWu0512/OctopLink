import { KnowledgeDocModel } from '../../model/WorkspaceModels';
import { KnowledgeService, DocPreview } from '../../service/WorkspaceService';
import { OctopApiError } from '../../net/HttpClient';
import { EmptyView } from '../../components/EmptyView';
import { ErrorRetry } from '../../components/ErrorRetry';
import { TextDocCreateDialog } from '../../components/TextDocCreateDialog';
import { PageHeader } from '../../components/PageHeader';
import { UiMaterialKit } from '../../components/UiMaterialKit';

/** 路由参数：目标知识库 */
export class KnowledgeDocsNavParam {
  readonly kbId: string;
  readonly kbName: string;

  constructor(kbId: string, kbName: string) {
    this.kbId = kbId;
    this.kbName = kbName;
  }
}

/** 知识库文档列表 */
@Component
export struct KnowledgeDocsPage {
  @State docs: Array<KnowledgeDocModel> = [];
  @State loading: boolean = true;
  @State refreshing: boolean = false;
  @State errorMsg: string = '';
  @State operating: boolean = false;
  @State previewing: boolean = false;
  private kbId: string = '';
  private createController: CustomDialogController | null = null;

  private onNavReady(ctx: NavDestinationContext): void {
    if (ctx.pathInfo.param instanceof KnowledgeDocsNavParam) {
      this.kbId = ctx.pathInfo.param.kbId;
      this.load();
    } else {
      this.loading = false;
      this.errorMsg = '页面参数错误';
    }
  }

  private async load(): Promise<void> {
    if (this.kbId === '') {
      return;
    }
    this.loading = this.docs.length === 0;
    this.errorMsg = '';
    try {
      this.docs = await KnowledgeService.listDocs(this.kbId);
    } catch (e) {
      this.errorMsg = e instanceof OctopApiError ? e.message : '文档列表加载失败';
    } finally {
      this.loading = false;
      this.refreshing = false;
    }
  }

  private showCreate(): void {
    this.createController = new CustomDialogController({
      builder: TextDocCreateDialog({
        kbId: this.kbId,
        onCreated: (): void => {
          this.load();
        }
      }),
      autoCancel: true
    });
    this.createController.open();
  }

  private async openPreview(doc: KnowledgeDocModel): Promise<void> {
    if (this.operating || doc.isDir) {
      return;
    }
    this.operating = true;
    this.previewing = true;
    try {
      const preview: DocPreview = await KnowledgeService.previewDoc(this.kbId, doc.id);
      this.getUIContext().showAlertDialog({
        title: preview.filename === '' ? doc.filename : preview.filename,
        message: preview.text === '' ? '（无可预览文本）' : preview.text,
        confirm: {
          value: $r('app.string.common_confirm'),
          action: (): void => {
          }
        }
      });
    } catch (e) {
      const message: string = e instanceof OctopApiError ? e.message : '预览失败';
      this.getUIContext().getPromptAction().showToast({ message });
    } finally {
      this.operating = false;
      this.previewing = false;
    }
  }

  private confirmDelete(doc: KnowledgeDocModel): void {
    this.getUIContext().showAlertDialog({
      title: '删除文档',
      message: `确定删除「${doc.filename}」吗？`,
      primaryButton: {
        value: $r('app.string.common_cancel'),
        action: (): void => {
        }
      },
      secondaryButton: {
        value: $r('app.string.common_confirm'),
        action: (): void => {
          this.deleteDoc(doc);
        }
      },
      alignment: DialogAlignment.Bottom
    });
  }

  private async deleteDoc(doc: KnowledgeDocModel): Promise<void> {
    if (this.operating) {
      return;
    }
    this.operating = true;
    try {
      await KnowledgeService.removeDoc(this.kbId, doc.id);
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
          PageHeader({ title: '文档' })

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
          } else if (this.docs.length === 0) {
            Column() {
              EmptyView({
                title: '暂无文档',
                subtitle: '点击右下角按钮创建 md/txt 文档\n（文件上传请使用 Web 端）',
                icon: $r('sys.symbol.doc_text')
              })
            }
            .layoutWeight(1)
            .width('100%')
            .justifyContent(FlexAlign.Center)
          } else {
            Refresh({ refreshing: $$this.refreshing }) {
              List({ space: 10 }) {
                ForEach(this.docs, (doc: KnowledgeDocModel) => {
                  ListItem() {
                    Row({ space: 12 }) {
                      Column() {
                        SymbolGlyph(doc.isDir ? $r('sys.symbol.folder_fill') : $r('sys.symbol.doc_text'))
                          .fontSize(19)
                          .fontColor([doc.isDir ? $r('app.color.warning') : $r('app.color.brand')])
                      }
                      .width(42)
                      .height(42)
                      .justifyContent(FlexAlign.Center)
                      .backgroundColor(doc.isDir ? $r('app.color.warning_soft') : $r('app.color.brand_light'))
                      .borderRadius(13)
                      Column({ space: 5 }) {
                        Text(doc.filename)
                          .fontSize(15)
                          .fontWeight(FontWeight.Medium)
                          .fontColor($r('app.color.text_primary'))
                          .maxLines(1)
                          .textOverflow({ overflow: TextOverflow.Ellipsis })
                        Row({ space: 8 }) {
                          Text(doc.isDir ? '' : doc.sizeDisplay())
                            .fontSize(12)
                            .fontColor($r('app.color.text_tertiary'))
                          if (!doc.isDir && doc.status !== 'ready') {
                            Text(doc.status)
                              .fontSize(11)
                              .fontColor(doc.status === 'error' ? $r('app.color.danger') : $r('app.color.brand'))
                              .backgroundColor(doc.status === 'error'
                                ? $r('app.color.danger_soft') : $r('app.color.brand_light'))
                              .borderRadius(6)
                              .padding({ left: 8, right: 8, top: 3, bottom: 3 })
                          }
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
                    .onClick((): void => {
                      this.openPreview(doc);
                    })
                    .gesture(
                      LongPressGesture()
                        .onAction((event: GestureEvent): void => {
                          this.confirmDelete(doc);
                        })
                    )
                  }
                }, (doc: KnowledgeDocModel) => doc.id)
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
    .onReady((ctx: NavDestinationContext): void => {
      this.onNavReady(ctx);
    })
  }
}
