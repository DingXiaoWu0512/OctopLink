import { KnowledgeBaseModel } from '../../model/WorkspaceModels';
import { KnowledgeService } from '../../service/WorkspaceService';
import { OctopApiError } from '../../net/HttpClient';
import { EmptyView } from '../../components/EmptyView';
import { ErrorRetry } from '../../components/ErrorRetry';
import { KbCreateDialog } from '../../components/KbCreateDialog';
import { KnowledgeDocsNavParam } from './KnowledgeDocsPage';
import { PageHeader } from '../../components/PageHeader';
import { UiMaterialKit } from '../../components/UiMaterialKit';
import { TimeFormat } from '../../utils/TimeFormat';
import { MenuSheetContent, MenuSheetOption } from '../../components/MenuSheet';
import { picker, fileIo } from '@kit.CoreFileKit';

/** 知识库列表（用户级） */
@Component
export struct KnowledgePage {
  @Consume('navStack') navStack: NavPathStack;
  @State bases: Array<KnowledgeBaseModel> = [];
  @State loading: boolean = true;
  @State refreshing: boolean = false;
  @State errorMsg: string = '';
  @State operating: boolean = false;
  @State menuOpen: boolean = false;
  @State menuTitle: string = '';
  @State menuMessage: string = '';
  @State menuOptions: Array<MenuSheetOption> = [];
  /** KB 头像版本号：上传/删除后自增以刷新 Image 缓存（key=kbId） */
  @State avatarRevs: Map<string, number> = new Map();
  /** 加载失败（无自定义头像）的 KB id 集合，回退显示默认图标 */
  @State avatarFailed: string[] = [];
  private avatarController: CustomDialogController | null = null;
  private menuActions: Array<() => void> = [];
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
        onSaved: (): void => {
          this.load();
        }
      }),
      autoCancel: true,
      systemMaterial: UiMaterialKit.sheet()
    });
    this.createController.open();
  }

  /** 编辑知识库（回填初值，PATCH 保存） */
  private editBase(base: KnowledgeBaseModel): void {
    this.createController = new CustomDialogController({
      builder: KbCreateDialog({
        kbId: base.id,
        initialName: base.name,
        initialDesc: base.description,
        initialShared: base.shared,
        initialDefaultOpen: base.defaultOpen,
        initialMaxDocs: base.maxDocuments,
        onSaved: (): void => {
          this.load();
        }
      }),
      autoCancel: true,
      systemMaterial: UiMaterialKit.sheet()
    });
    this.createController.open();
  }

  /** 长按库：操作菜单 */
  private showBaseMenu(base: KnowledgeBaseModel): void {
    this.menuTitle = base.name;
    this.menuMessage = '选择要执行的操作';
    this.menuOptions = [
      new MenuSheetOption($r('sys.symbol.square_and_pencil'), '编辑知识库', '名称、描述与共享设置', false),
      new MenuSheetOption($r('sys.symbol.trash'), '删除知识库', '将同时删除全部文档与索引', true)
    ];
    this.menuActions = [
      (): void => {
        this.editBase(base);
      },
      (): void => {
        this.confirmDelete(base);
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

  // ---- KB 头像 ----

  private avatarRevOf(kbId: string): number {
    const rev: number | undefined = this.avatarRevs.get(kbId);
    return rev === undefined ? 0 : rev;
  }

  private showAvatarMenu(base: KnowledgeBaseModel): void {
    this.menuTitle = base.name;
    this.menuMessage = '知识库头像';
    this.menuOptions = [
      new MenuSheetOption($r('sys.symbol.picture'), '上传头像', '从文件选取', false),
      new MenuSheetOption($r('sys.symbol.trash'), '删除头像', '恢复默认图标', true)
    ];
    this.menuActions = [
      (): void => {
        this.pickAndUploadAvatar(base.id);
      },
      (): void => {
        this.deleteAvatar(base.id);
      }
    ];
    this.menuOpen = true;
  }

  private async pickAndUploadAvatar(kbId: string): Promise<void> {
    const docPicker = new picker.DocumentViewPicker();
    const options = new picker.DocumentSelectOptions();
    options.maxSelectNumber = 1;
    let uris: Array<string> = [];
    try {
      uris = await docPicker.select(options);
    } catch (e) {
      return;
    }
    if (uris.length === 0) {
      return;
    }
    const uri: string = uris[0];
    const idx: number = uri.lastIndexOf('/');
    const fileName: string = idx >= 0 ? uri.substring(idx + 1) : 'avatar.png';
    try {
      const file = fileIo.openSync(uri, fileIo.OpenMode.READ_ONLY);
      let data: ArrayBuffer;
      try {
        const stat = fileIo.statSync(file.fd);
        data = new ArrayBuffer(stat.size);
        fileIo.readSync(file.fd, data);
      } finally {
        fileIo.closeSync(file.fd);
      }
      let contentType: string = 'application/octet-stream';
      const lower: string = fileName.toLowerCase();
      if (lower.endsWith('.png')) {
        contentType = 'image/png';
      } else if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) {
        contentType = 'image/jpeg';
      } else if (lower.endsWith('.webp')) {
        contentType = 'image/webp';
      }
      await KnowledgeService.uploadAvatar(kbId, fileName, contentType, data);
      const rev: number = this.avatarRevOf(kbId);
      const revs: Map<string, number> = new Map(this.avatarRevs);
      revs.set(kbId, rev + 1);
      this.avatarRevs = revs;
      this.avatarFailed = this.avatarFailed.filter((id: string): boolean => id !== kbId);
      this.getUIContext().getPromptAction().showToast({ message: '头像已更新' });
    } catch (e) {
      const message: string = e instanceof OctopApiError ? e.message : '头像上传失败';
      this.getUIContext().getPromptAction().showToast({ message });
    }
  }

  private async deleteAvatar(kbId: string): Promise<void> {
    try {
      await KnowledgeService.deleteAvatar(kbId);
      const rev: number = this.avatarRevOf(kbId);
      const revs: Map<string, number> = new Map(this.avatarRevs);
      revs.set(kbId, rev + 1);
      this.avatarRevs = revs;
      this.avatarFailed = this.avatarFailed.filter((id: string): boolean => id !== kbId);
      this.getUIContext().getPromptAction().showToast({ message: '头像已删除' });
    } catch (e) {
      const message: string = e instanceof OctopApiError ? e.message : '删除失败';
      this.getUIContext().getPromptAction().showToast({ message });
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
                      Stack() {
                        if (this.avatarFailed.indexOf(base.id) >= 0) {
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
                        }
                        Image(KnowledgeService.avatarUrlWithRev(base.id, this.avatarRevOf(base.id)))
                          .width(44)
                          .height(44)
                          .borderRadius(14)
                          .objectFit(ImageFit.Cover)
                          .opacity(this.avatarFailed.indexOf(base.id) >= 0 ? 0 : 1)
                          .onClick((): void => {
                            this.showAvatarMenu(base);
                          })
                          .onError((): void => {
                            if (this.avatarFailed.indexOf(base.id) < 0) {
                              const next: string[] = this.avatarFailed.slice();
                              next.push(base.id);
                              this.avatarFailed = next;
                            }
                          })
                      }
                      .width(44)
                      .height(44)
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
                        Row({ space: 8 }) {
                          Text(`${base.docCount} 篇文档`)
                            .fontSize(11)
                            .fontColor($r('app.color.success'))
                            .backgroundColor($r('app.color.success_soft'))
                            .borderRadius(6)
                            .padding({ left: 8, right: 8, top: 3, bottom: 3 })
                          if (base.ownerUsername !== '') {
                            Text(`@${base.ownerUsername}`)
                              .fontSize(11)
                              .fontColor($r('app.color.text_tertiary'))
                          }
                          if (base.createdAtMs > 0) {
                            Text(`创建于 ${TimeFormat.list(base.createdAtMs)}`)
                              .fontSize(11)
                              .fontColor($r('app.color.text_tertiary'))
                              .maxLines(1)
                          }
                        }
                        .width('100%')
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
                          this.showBaseMenu(base);
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
        .backgroundColor($r('app.color.fab_glass'))
        .backgroundBlurStyle(BlurStyle.COMPONENT_THICK)
        .border({ width: 1, color: $r('app.color.card_stroke') })
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
