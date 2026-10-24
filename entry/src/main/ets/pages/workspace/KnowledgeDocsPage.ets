import { KnowledgeDocModel, KnowledgeCapability } from '../../model/WorkspaceModels';
import { KnowledgeService, DocPreview } from '../../service/WorkspaceService';
import { OctopApiError } from '../../net/HttpClient';
import { EmptyView } from '../../components/EmptyView';
import { ErrorRetry } from '../../components/ErrorRetry';
import { TextDocCreateDialog } from '../../components/TextDocCreateDialog';
import { PageHeader } from '../../components/PageHeader';
import { UiMaterialKit } from '../../components/UiMaterialKit';
import { fileIo, picker } from '@kit.CoreFileKit';

/** 路由参数：目标知识库 */
export class KnowledgeDocsNavParam {
  readonly kbId: string;
  readonly kbName: string;

  constructor(kbId: string, kbName: string) {
    this.kbId = kbId;
    this.kbName = kbName;
  }
}

/** 知识库文档列表：上传/文件夹/在线文档 + 预览/编辑/重命名/重建索引/下载 */
@Component
export struct KnowledgeDocsPage {
  @State docs: Array<KnowledgeDocModel> = [];
  @State loading: boolean = true;
  @State refreshing: boolean = false;
  @State errorMsg: string = '';
  @State operating: boolean = false;
  @State previewing: boolean = false;
  @State uploadingCount: number = 0;
  @State maxDocs: number = 0;
  @State docCount: number = 0;
  @State folderSheetOpen: boolean = false;
  @State folderPath: string = '';
  @State renameSheetOpen: boolean = false;
  @State renameText: string = '';
  @State editSheetOpen: boolean = false;
  @State editText: string = '';
  @State editSaving: boolean = false;
  private kbId: string = '';
  private kbName: string = '';
  private createController: CustomDialogController | null = null;
  private renameTargetId: string = '';
  private editTargetId: string = '';
  private editTargetName: string = '';

  private onNavReady(ctx: NavDestinationContext): void {
    if (ctx.pathInfo.param instanceof KnowledgeDocsNavParam) {
      this.kbId = ctx.pathInfo.param.kbId;
      this.kbName = ctx.pathInfo.param.kbName;
      this.load();
      this.loadCapability();
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
      this.docCount = this.docs.filter((doc: KnowledgeDocModel): boolean => !doc.isDir).length;
    } catch (e) {
      this.errorMsg = e instanceof OctopApiError ? e.message : '文档列表加载失败';
    } finally {
      this.loading = false;
      this.refreshing = false;
    }
  }

  /** 配额：capability.limits.max_docs_per_kb（0=不限） */
  private async loadCapability(): Promise<void> {
    try {
      const capability: KnowledgeCapability = await KnowledgeService.capability();
      this.maxDocs = capability.maxDocsPerKb;
    } catch (e) {
      this.maxDocs = 0;
    }
  }

  /** 配额文案（maxDocs=0 不限） */
  private quotaText(): string {
    if (this.maxDocs <= 0) {
      return `${this.docCount} 篇文档`;
    }
    return `${this.docCount}/${this.maxDocs} 篇文档`;
  }

  private quotaPercent(): number {
    if (this.maxDocs <= 0 || this.docCount === 0) {
      return 0;
    }
    return Math.min(100, Math.round(this.docCount * 100 / this.maxDocs));
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

  /** FAB 菜单：创建在线文档 / 上传文件 / 新建文件夹 */
  private showAddMenu(): void {
    this.getUIContext().showActionSheet({
      title: '添加内容',
      message: '选择要添加的类型',
      sheets: [
        {
          title: '创建 md/txt 文档',
          action: (): void => {
            this.showCreate();
          }
        },
        {
          title: '上传文件',
          action: (): void => {
            this.pickAndUpload();
          }
        },
        {
          title: '新建文件夹',
          action: (): void => {
            this.folderPath = '';
            this.folderSheetOpen = true;
          }
        }
      ]
    });
  }

  /** 多选文件并逐个上传 */
  private async pickAndUpload(): Promise<void> {
    const docPicker = new picker.DocumentViewPicker();
    const options = new picker.DocumentSelectOptions();
    options.maxSelectNumber = 10;
    let uris: Array<string> = [];
    try {
      uris = await docPicker.select(options);
    } catch (e) {
      return;
    }
    for (const uri of uris) {
      await this.uploadOne(uri);
    }
    if (this.uploadingCount > 0) {
      this.getUIContext().getPromptAction().showToast({ message: '上传完成' });
    }
    this.uploadingCount = 0;
    this.load();
  }

  private async uploadOne(uri: string): Promise<void> {
    const fileName: string = this.fileNameFromUri(uri);
    this.uploadingCount += 1;
    try {
      const file = fileIo.openSync(uri, fileIo.OpenMode.READ_ONLY);
      let data: ArrayBuffer;
      try {
        const stat = fileIo.statSync(file.fd);
        data = new ArrayBuffer(stat.size);
        fileIo.readSync(file.fd, data);
      } finally {
        fileIo.closeSync(file);
      }
      await KnowledgeService.uploadDocument(
        this.kbId, fileName, this.contentTypeFor(fileName), data);
    } catch (e) {
      const message: string = e instanceof OctopApiError ?
        `「${fileName}」${e.message}` : `「${fileName}」上传失败`;
      this.getUIContext().getPromptAction().showToast({ message });
    }
  }

  private fileNameFromUri(uri: string): string {
    const idx: number = uri.lastIndexOf('/');
    const name: string = idx >= 0 ? uri.substring(idx + 1) : uri;
    if (name === '') {
      return 'document';
    }
    try {
      return decodeURIComponent(name);
    } catch (e) {
      return name;
    }
  }

  private contentTypeFor(fileName: string): string {
    const lower: string = fileName.toLowerCase();
    if (lower.endsWith('.png')) {
      return 'image/png';
    }
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) {
      return 'image/jpeg';
    }
    if (lower.endsWith('.webp')) {
      return 'image/webp';
    }
    if (lower.endsWith('.pdf')) {
      return 'application/pdf';
    }
    if (lower.endsWith('.doc') || lower.endsWith('.docx') || lower.endsWith('.wps')) {
      return 'application/msword';
    }
    if (lower.endsWith('.pptx')) {
      return 'application/vnd.ms-powerpoint';
    }
    if (lower.endsWith('.xls') || lower.endsWith('.xlsx') || lower.endsWith('.xlsm')) {
      return 'application/vnd.ms-excel';
    }
    if (lower.endsWith('.json') || lower.endsWith('.jsonl')) {
      return 'application/json';
    }
    if (lower.endsWith('.csv')) {
      return 'text/csv';
    }
    if (lower.endsWith('.yaml') || lower.endsWith('.yml')) {
      return 'text/yaml';
    }
    return 'text/plain';
  }

  /** 长按文档菜单 */
  private showDocMenu(doc: KnowledgeDocModel): void {
    const sheets: Array<SheetInfo> = [];
    if (!doc.isDir) {
      sheets.push({
        title: '预览文本',
        action: (): void => {
          this.openPreview(doc);
        }
      });
      if (this.isTextDoc(doc.filename)) {
        sheets.push({
          title: '编辑内容',
          action: (): void => {
            this.openEdit(doc);
          }
        });
      }
      sheets.push({
        title: '下载原件',
        action: (): void => {
          this.downloadDoc(doc);
        }
      });
      sheets.push({
        title: '重建索引',
        action: (): void => {
          this.reindexDoc(doc);
        }
      });
    }
    sheets.push({
      title: '重命名',
      action: (): void => {
        this.openRename(doc);
      }
    });
    sheets.push({
      title: '删除',
      action: (): void => {
        this.confirmDelete(doc);
      }
    });
    this.getUIContext().showActionSheet({
      title: doc.filename,
      message: '选择要执行的操作',
      sheets: sheets
    });
  }

  private isTextDoc(fileName: string): boolean {
    const lower: string = fileName.toLowerCase();
    return lower.endsWith('.md') || lower.endsWith('.txt');
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

  /** 打开 md/txt 内容编辑 sheet */
  private async openEdit(doc: KnowledgeDocModel): Promise<void> {
    if (this.operating) {
      return;
    }
    this.operating = true;
    try {
      this.editText = await KnowledgeService.getDocContent(this.kbId, doc.id);
      this.editTargetId = doc.id;
      this.editTargetName = doc.filename;
      this.editSheetOpen = true;
    } catch (e) {
      const message: string = e instanceof OctopApiError ? e.message : '内容加载失败';
      this.getUIContext().getPromptAction().showToast({ message });
    }
    this.operating = false;
  }

  private async saveEdit(): Promise<void> {
    if (this.editSaving || this.editTargetId === '') {
      return;
    }
    this.editSaving = true;
    try {
      await KnowledgeService.putDocContent(this.kbId, this.editTargetId, this.editText);
      this.editSheetOpen = false;
      this.getUIContext().getPromptAction().showToast({ message: '内容已保存并重建索引' });
      this.load();
    } catch (e) {
      const message: string = e instanceof OctopApiError ? e.message : '保存失败';
      this.getUIContext().getPromptAction().showToast({ message });
    }
    this.editSaving = false;
  }

  private openRename(doc: KnowledgeDocModel): void {
    this.renameTargetId = doc.id;
    this.renameText = doc.filename;
    this.renameSheetOpen = true;
  }

  private async saveRename(): Promise<void> {
    const name: string = this.renameText.trim();
    if (this.operating || this.renameTargetId === '') {
      return;
    }
    if (name === '') {
      this.getUIContext().getPromptAction().showToast({ message: '名称不能为空' });
      return;
    }
    this.operating = true;
    try {
      await KnowledgeService.renameDoc(this.kbId, this.renameTargetId, name);
      this.renameSheetOpen = false;
      await this.load();
    } catch (e) {
      const message: string = e instanceof OctopApiError ? e.message : '重命名失败';
      this.getUIContext().getPromptAction().showToast({ message });
    }
    this.operating = false;
  }

  private async createFolder(): Promise<void> {
    const path: string = this.folderPath.trim();
    if (path === '') {
      this.getUIContext().getPromptAction().showToast({ message: '请填写文件夹路径' });
      return;
    }
    this.operating = true;
    try {
      await KnowledgeService.createFolder(this.kbId, path);
      this.folderSheetOpen = false;
      await this.load();
    } catch (e) {
      const message: string = e instanceof OctopApiError ? e.message : '创建失败';
      this.getUIContext().getPromptAction().showToast({ message });
    }
    this.operating = false;
  }

  private async reindexDoc(doc: KnowledgeDocModel): Promise<void> {
    if (this.operating) {
      return;
    }
    this.operating = true;
    try {
      await KnowledgeService.reindexDoc(this.kbId, doc.id);
      this.getUIContext().getPromptAction().showToast({ message: '已提交重建索引' });
      await this.load();
    } catch (e) {
      const message: string = e instanceof OctopApiError ? e.message : '重建索引失败';
      this.getUIContext().getPromptAction().showToast({ message });
    }
    this.operating = false;
  }

  /** 下载原件到应用缓存目录，toast 展示本地路径 */
  private async downloadDoc(doc: KnowledgeDocModel): Promise<void> {
    if (this.operating) {
      return;
    }
    this.operating = true;
    try {
      const data: ArrayBuffer = await KnowledgeService.downloadDoc(this.kbId, doc.id, 'attachment');
      const cacheDir: string = getContext(this).cacheDir;
      const localPath: string = `${cacheDir}/${doc.filename}`;
      const file = fileIo.openSync(localPath,
        fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
      try {
        fileIo.writeSync(file.fd, data);
      } finally {
        fileIo.closeSync(file);
      }
      this.getUIContext().getPromptAction().showToast({ message: `已下载：${doc.filename}` });
    } catch (e) {
      const message: string = e instanceof OctopApiError ? e.message : '下载失败';
      this.getUIContext().getPromptAction().showToast({ message });
    }
    this.operating = false;
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

  @Builder
  private folderSheetBuilder() {
    Column({ space: 12 }) {
      Text('新建文件夹')
        .fontSize(17)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .width('100%')
      TextInput({ text: this.folderPath, placeholder: '文件夹路径，如：资料/产品手册' })
        .fontSize(14)
        .backgroundColor($r('app.color.bg_input'))
        .borderRadius(12)
        .onChange((value: string): void => {
          this.folderPath = value;
        })
      Button('创建')
        .fontSize(15)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_on_brand'))
        .backgroundColor($r('app.color.brand'))
        .borderRadius(16)
        .height(42)
        .width('100%')
        .onClick((): void => {
          this.createFolder();
        })
    }
    .padding({ left: 18, right: 18, top: 18, bottom: 30 })
    .width('100%')
  }

  @Builder
  private renameSheetBuilder() {
    Column({ space: 12 }) {
      Text('重命名')
        .fontSize(17)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .width('100%')
      TextInput({ text: this.renameText, placeholder: '新名称' })
        .fontSize(14)
        .backgroundColor($r('app.color.bg_input'))
        .borderRadius(12)
        .onChange((value: string): void => {
          this.renameText = value;
        })
      Button('保存')
        .fontSize(15)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_on_brand'))
        .backgroundColor($r('app.color.brand'))
        .borderRadius(16)
        .height(42)
        .width('100%')
        .onClick((): void => {
          this.saveRename();
        })
    }
    .padding({ left: 18, right: 18, top: 18, bottom: 30 })
    .width('100%')
  }

  @Builder
  private editSheetBuilder() {
    Column({ space: 12 }) {
      Text(`编辑：${this.editTargetName}`)
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
      TextArea({ text: this.editText })
        .fontSize(13)
        .fontFamily('monospace')
        .constraintSize({ minHeight: 220, maxHeight: 420 })
        .backgroundColor($r('app.color.bg_input'))
        .borderRadius(12)
        .width('100%')
        .onChange((value: string): void => {
          this.editText = value;
        })
      Button(this.editSaving ? '保存中…' : '保存并重建索引')
        .fontSize(15)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_on_brand'))
        .backgroundColor($r('app.color.brand'))
        .borderRadius(16)
        .height(42)
        .width('100%')
        .enabled(!this.editSaving)
        .onClick((): void => {
          this.saveEdit();
        })
    }
    .padding({ left: 18, right: 18, top: 18, bottom: 30 })
    .width('100%')
  }

  build() {
    NavDestination() {
      Stack({ alignContent: Alignment.BottomEnd }) {
        Column() {
          PageHeader({ title: this.kbName === '' ? '文档' : this.kbName })

          if (this.maxDocs > 0) {
            Column({ space: 5 }) {
              Row() {
                Text(this.quotaText())
                  .fontSize(12)
                  .fontColor(this.quotaPercent() >= 80 ?
                    $r('app.color.warning') : $r('app.color.text_secondary'))
                Blank()
                Text(`${this.quotaPercent()}%`)
                  .fontSize(12)
                  .fontColor(this.quotaPercent() >= 80 ?
                    $r('app.color.warning') : $r('app.color.text_tertiary'))
              }
              .width('100%')
              Progress({ value: this.quotaPercent(), total: 100, type: ProgressType.Linear })
                .color(this.quotaPercent() >= 80 ? $r('app.color.warning') : $r('app.color.brand'))
                .width('100%')
                .height(4)
            }
            .width('100%')
            .padding({ left: 16, right: 16, top: 4, bottom: 4 })
          }

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
                subtitle: '点击右下角按钮创建文档、上传文件或新建文件夹',
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
                          if (!doc.isDir) {
                            Text(doc.sizeDisplay())
                              .fontSize(12)
                              .fontColor($r('app.color.text_tertiary'))
                          }
                          if (!doc.isDir && doc.status === 'ready' && doc.chunkCount > 0) {
                            Text(`${doc.chunkCount} 块`)
                              .fontSize(11)
                              .fontColor($r('app.color.text_tertiary'))
                              .backgroundColor($r('app.color.bg_input'))
                              .borderRadius(6)
                              .padding({ left: 8, right: 8, top: 3, bottom: 3 })
                          }
                          if (!doc.isDir && doc.status !== 'ready' && doc.status !== '') {
                            Text(doc.status)
                              .fontSize(11)
                              .fontColor(doc.status === 'error' ? $r('app.color.danger') : $r('app.color.brand'))
                              .backgroundColor(doc.status === 'error'
                                ? $r('app.color.danger_soft') : $r('app.color.brand_light'))
                              .borderRadius(6)
                              .padding({ left: 8, right: 8, top: 3, bottom: 3 })
                          }
                          if (doc.path !== '' && doc.path !== doc.filename) {
                            Text(doc.path)
                              .fontSize(11)
                              .fontColor($r('app.color.text_tertiary'))
                              .maxLines(1)
                              .textOverflow({ overflow: TextOverflow.Ellipsis })
                              .constraintSize({ maxWidth: 120 })
                          }
                        }
                        if (doc.status === 'error' && doc.errorMessage !== '') {
                          Text(doc.errorMessage)
                            .fontSize(11)
                            .fontColor($r('app.color.danger'))
                            .maxLines(2)
                            .textOverflow({ overflow: TextOverflow.Ellipsis })
                            .width('100%')
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
                      if (doc.isDir) {
                        return;
                      }
                      this.openPreview(doc);
                    })
                    .gesture(
                      LongPressGesture()
                        .onAction((event: GestureEvent): void => {
                          this.showDocMenu(doc);
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
        .bindSheet($$this.folderSheetOpen, this.folderSheetBuilder, {
          height: 240,
          showClose: true
        })
        .bindSheet($$this.renameSheetOpen, this.renameSheetBuilder, {
          height: 240,
          showClose: true
        })
        .bindSheet($$this.editSheetOpen, this.editSheetBuilder, {
          detents: [SheetSize.MEDIUM, SheetSize.LARGE]
        })

        if (this.uploadingCount > 0) {
          Row({ space: 8 }) {
            LoadingProgress()
              .width(16)
              .height(16)
              .color($r('app.color.brand'))
            Text(`正在上传 ${this.uploadingCount} 个文件…`)
              .fontSize(13)
              .fontColor($r('app.color.text_secondary'))
          }
          .padding({ left: 14, right: 14, top: 8, bottom: 8 })
          .borderRadius(18)
          .backgroundColor($r('app.color.bg_card'))
          .border({ width: 1, color: $r('app.color.card_stroke') })
          .margin({ bottom: 92 })
        }

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
          this.showAddMenu();
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
