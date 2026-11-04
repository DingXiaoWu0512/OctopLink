import { WorkspaceEntryModel, WorkspaceGrepMatchModel } from '../../model/WorkspaceFileModels';
import { WorkspaceFileService } from '../../service/WorkspaceFileService';
import { OctopApiError } from '../../net/HttpClient';
import { SessionStore } from '../../store/SessionStore';
import { EmptyView } from '../../components/EmptyView';
import { ErrorRetry } from '../../components/ErrorRetry';
import { PageHeader } from '../../components/PageHeader';
import { UiMaterialKit } from '../../components/UiMaterialKit';
import { fileIo, picker } from '@kit.CoreFileKit';
import { MenuSheetContent, MenuSheetOption } from '../../components/MenuSheet';

/** 新建文件夹对话框 */
@CustomDialog
struct WorkspaceMkdirDialog {
  controller?: CustomDialogController;
  agentId: string = '';
  parentPath: string = '/';
  onCreated: () => void = (): void => {
  };
  @State folderName: string = '';
  @State submitting: boolean = false;

  private submitLabel(): string {
    return this.submitting ? '创建中...' : '创建';
  }

  private async submit(): Promise<void> {
    if (this.submitting) {
      return;
    }
    const name: string = this.folderName.trim();
    if (name === '') {
      this.getUIContext().getPromptAction().showToast({ message: '请输入文件夹名称' });
      return;
    }
    const target: string = this.parentPath === '/' ? `/${name}` : `${this.parentPath}/${name}`;
    this.submitting = true;
    try {
      await WorkspaceFileService.mkdir(this.agentId, target);
      this.controller?.close();
      this.getUIContext().getPromptAction().showToast({ message: '文件夹已创建' });
      this.onCreated();
    } catch (e) {
      const message: string = e instanceof OctopApiError ? e.message : '创建失败';
      this.getUIContext().getPromptAction().showToast({ message });
    }
    this.submitting = false;
  }

  build() {
    Column({ space: 14 }) {
      Text('新建文件夹')
        .fontSize(17)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .width('100%')
        .textAlign(TextAlign.Start)

      Text(`位置：${this.parentPath}`)
        .fontSize(11)
        .fontColor($r('app.color.text_tertiary'))
        .width('100%')

      TextInput({
        text: this.folderName,
        placeholder: '文件夹名称'
      })
        .fontSize(14)
        .height(42)
        .backgroundColor($r('app.color.bg_input'))
        .borderRadius(12)
        .onChange((value: string): void => {
          this.folderName = value;
        })

      Row({ space: 12 }) {
        Button($r('app.string.common_cancel'))
          .fontSize(14)
          .height(38)
          .layoutWeight(1)
          .borderRadius(19)
          .backgroundColor($r('app.color.bg_input'))
          .fontColor($r('app.color.text_secondary'))
          .onClick((): void => {
            this.controller?.close();
          })
        Button(this.submitLabel())
          .fontSize(14)
          .height(38)
          .layoutWeight(1)
          .borderRadius(19)
          .backgroundColor($r('app.color.brand'))
          .fontColor($r('app.color.bg_page'))
          .enabled(!this.submitting)
          .onClick((): void => {
            this.submit();
          })
      }
      .width('100%')
    }
    .padding(20)
    .width('100%')
  }
}

/** 重命名/移动对话框（destination 为工作区相对路径） */
@CustomDialog
struct WorkspaceMoveDialog {
  controller?: CustomDialogController;
  agentId: string = '';
  entryPath: string = '';
  onMoved: () => void = (): void => {
  };
  @State destText: string = '';
  @State submitting: boolean = false;

  aboutToAppear(): void {
    this.destText = this.entryPath;
  }

  private submitLabel(): string {
    return this.submitting ? '保存中...' : '确定';
  }

  private async submit(): Promise<void> {
    if (this.submitting) {
      return;
    }
    const destination: string = this.destText.trim();
    if (destination === '') {
      this.getUIContext().getPromptAction().showToast({ message: '请输入目标路径' });
      return;
    }
    this.submitting = true;
    try {
      await WorkspaceFileService.move(this.agentId, this.entryPath, destination);
      this.controller?.close();
      this.getUIContext().getPromptAction().showToast({ message: '已保存' });
      this.onMoved();
    } catch (e) {
      const message: string = e instanceof OctopApiError ? e.message : '操作失败';
      this.getUIContext().getPromptAction().showToast({ message });
    }
    this.submitting = false;
  }

  build() {
    Column({ space: 14 }) {
      Text('重命名/移动')
        .fontSize(17)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .width('100%')
        .textAlign(TextAlign.Start)

      Text(`当前：${this.entryPath}`)
        .fontSize(11)
        .fontColor($r('app.color.text_tertiary'))
        .width('100%')

      TextInput({
        text: this.destText,
        placeholder: '目标路径，如 /docs/notes.md'
      })
        .fontSize(14)
        .height(42)
        .backgroundColor($r('app.color.bg_input'))
        .borderRadius(12)
        .onChange((value: string): void => {
          this.destText = value;
        })

      Row({ space: 12 }) {
        Button($r('app.string.common_cancel'))
          .fontSize(14)
          .height(38)
          .layoutWeight(1)
          .borderRadius(19)
          .backgroundColor($r('app.color.bg_input'))
          .fontColor($r('app.color.text_secondary'))
          .onClick((): void => {
            this.controller?.close();
          })
        Button(this.submitLabel())
          .fontSize(14)
          .height(38)
          .layoutWeight(1)
          .borderRadius(19)
          .backgroundColor($r('app.color.brand'))
          .fontColor($r('app.color.bg_page'))
          .enabled(!this.submitting)
          .onClick((): void => {
            this.submit();
          })
      }
      .width('100%')
    }
    .padding(20)
    .width('100%')
  }
}

/** 内容搜索（grep）对话框 */
@CustomDialog
struct WorkspaceGrepDialog {
  controller?: CustomDialogController;
  agentId: string = '';
  searchPath: string = '/';
  onSearched: (results: Array<WorkspaceGrepMatchModel>) => void =
    (results: Array<WorkspaceGrepMatchModel>): void => {
    };
  @State patternText: string = '';
  @State searching: boolean = false;

  private submitLabel(): string {
    return this.searching ? '搜索中...' : '搜索';
  }

  private async submit(): Promise<void> {
    if (this.searching) {
      return;
    }
    const pattern: string = this.patternText.trim();
    if (pattern === '') {
      this.getUIContext().getPromptAction().showToast({ message: '请输入搜索关键词' });
      return;
    }
    this.searching = true;
    try {
      const results: Array<WorkspaceGrepMatchModel> =
        await WorkspaceFileService.grep(this.agentId, pattern, this.searchPath);
      this.controller?.close();
      this.onSearched(results);
    } catch (e) {
      const message: string = e instanceof OctopApiError ? e.message : '搜索失败';
      this.getUIContext().getPromptAction().showToast({ message });
    }
    this.searching = false;
  }

  build() {
    Column({ space: 14 }) {
      Text('搜索内容')
        .fontSize(17)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .width('100%')
        .textAlign(TextAlign.Start)

      Text(`范围：${this.searchPath}`)
        .fontSize(11)
        .fontColor($r('app.color.text_tertiary'))
        .width('100%')

      TextInput({
        text: this.patternText,
        placeholder: '关键词，如 TODO'
      })
        .fontSize(14)
        .height(42)
        .backgroundColor($r('app.color.bg_input'))
        .borderRadius(12)
        .onChange((value: string): void => {
          this.patternText = value;
        })

      Row({ space: 12 }) {
        Button($r('app.string.common_cancel'))
          .fontSize(14)
          .height(38)
          .layoutWeight(1)
          .borderRadius(19)
          .backgroundColor($r('app.color.bg_input'))
          .fontColor($r('app.color.text_secondary'))
          .onClick((): void => {
            this.controller?.close();
          })
        Button(this.submitLabel())
          .fontSize(14)
          .height(38)
          .layoutWeight(1)
          .borderRadius(19)
          .backgroundColor($r('app.color.brand'))
          .fontColor($r('app.color.bg_page'))
          .enabled(!this.searching)
          .onClick((): void => {
            this.submit();
          })
      }
      .width('100%')
    }
    .padding(20)
    .width('100%')
  }
}

/** 智能体工作区文件浏览器：目录导航 + 文本预览编辑 + 上传/下载/搜索 */
@Component
export struct WorkspaceFilesPage {
  @State currentPath: string = '/';
  @State entries: Array<WorkspaceEntryModel> = [];
  @State loading: boolean = true;
  @State refreshing: boolean = false;
  @State errorMsg: string = '';
  @State operating: boolean = false;
  @State viewing: boolean = false;
  @State viewingPath: string = '';
  @State viewingContent: string = '';
  @State grepOpen: boolean = false;
  @State grepResults: Array<WorkspaceGrepMatchModel> = [];
  @State menuOpen: boolean = false;
  @State menuTitle: string = '';
  @State menuMessage: string = '';
  @State menuOptions: Array<MenuSheetOption> = [];
  private menuActions: Array<() => void> = [];
  private agentId: string = '';
  private pathStack: NavPathStack | null = null;
  private mkdirController: CustomDialogController | null = null;
  private moveController: CustomDialogController | null = null;
  private grepController: CustomDialogController | null = null;

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
    this.loading = this.entries.length === 0;
    this.errorMsg = '';
    try {
      const list: Array<WorkspaceEntryModel> =
        await WorkspaceFileService.tree(this.agentId, this.currentPath);
      list.sort((a: WorkspaceEntryModel, b: WorkspaceEntryModel): number => {
        if (a.isDir !== b.isDir) {
          return a.isDir ? -1 : 1;
        }
        const aName: string = a.displayName();
        const bName: string = b.displayName();
        if (aName === bName) {
          return 0;
        }
        return aName < bName ? -1 : 1;
      });
      this.entries = list;
    } catch (e) {
      this.errorMsg = e instanceof OctopApiError ? e.message : '文件列表加载失败';
    } finally {
      this.loading = false;
      this.refreshing = false;
    }
  }

  private joinPath(name: string): string {
    return this.currentPath === '/' ? `/${name}` : `${this.currentPath}/${name}`;
  }

  private parentOf(path: string): string {
    const idx: number = path.lastIndexOf('/');
    if (idx <= 0) {
      return '/';
    }
    return path.substring(0, idx);
  }

  private formatSize(size: number): string {
    if (size < 1024) {
      return `${size} B`;
    }
    if (size < 1048576) {
      return `${(size / 1024).toFixed(1)} KB`;
    }
    if (size < 1073741824) {
      return `${(size / 1048576).toFixed(1)} MB`;
    }
    return `${(size / 1073741824).toFixed(1)} GB`;
  }

  private entryIcon(entry: WorkspaceEntryModel): Resource {
    return entry.isDir ? $r('sys.symbol.folder') : $r('sys.symbol.doc_text');
  }

  private entryIconTint(entry: WorkspaceEntryModel): Array<Resource> {
    return entry.isDir ? [$r('app.color.brand')] : [$r('app.color.icon_secondary')];
  }

  private entryIconBg(entry: WorkspaceEntryModel): Resource {
    return entry.isDir ? $r('app.color.brand_light') : $r('app.color.bg_input');
  }

  private entryMeta(entry: WorkspaceEntryModel): string {
    if (entry.isDir) {
      return '文件夹';
    }
    return this.formatSize(entry.size);
  }

  private viewingName(): string {
    const parts: Array<string> = this.viewingPath.split('/');
    return parts.length > 0 ? parts[parts.length - 1] : this.viewingPath;
  }

  private grepTitle(): string {
    return `搜索结果（${this.grepResults.length} 条）`;
  }

  private matchLocation(match: WorkspaceGrepMatchModel): string {
    return `${match.path}:${match.line}`;
  }

  private openEntry(entry: WorkspaceEntryModel): void {
    if (entry.isDir) {
      this.openFolder(entry);
    } else {
      this.openFile(entry);
    }
  }

  private openFolder(entry: WorkspaceEntryModel): void {
    this.currentPath = entry.path;
    this.entries = [];
    this.load();
  }

  private goUp(): void {
    if (this.currentPath === '/') {
      return;
    }
    this.currentPath = this.parentOf(this.currentPath);
    this.entries = [];
    this.load();
  }

  private async openFile(entry: WorkspaceEntryModel): Promise<void> {
    if (this.operating) {
      return;
    }
    this.operating = true;
    try {
      const content: string = await WorkspaceFileService.readFile(this.agentId, entry.path);
      this.viewingPath = entry.path;
      this.viewingContent = content;
      this.viewing = true;
    } catch (e) {
      const message: string = e instanceof OctopApiError ? e.message : '该文件不支持文本预览';
      this.getUIContext().getPromptAction().showToast({ message });
    }
    this.operating = false;
  }

  private async saveViewing(): Promise<void> {
    if (this.operating) {
      return;
    }
    this.operating = true;
    try {
      await WorkspaceFileService.writeFile(this.agentId, this.viewingPath, this.viewingContent);
      this.getUIContext().getPromptAction().showToast({ message: '已保存' });
    } catch (e) {
      const message: string = e instanceof OctopApiError ? e.message : '保存失败';
      this.getUIContext().getPromptAction().showToast({ message });
    }
    this.operating = false;
  }

  private showMkdir(): void {
    this.mkdirController = new CustomDialogController({
      builder: WorkspaceMkdirDialog({
        agentId: this.agentId,
        parentPath: this.currentPath,
        onCreated: (): void => {
          this.load();
        }
      }),
      autoCancel: true,
      systemMaterial: UiMaterialKit.sheet()
    });
    this.mkdirController.open();
  }

  private showMove(entry: WorkspaceEntryModel): void {
    this.moveController = new CustomDialogController({
      builder: WorkspaceMoveDialog({
        agentId: this.agentId,
        entryPath: entry.path,
        onMoved: (): void => {
          this.load();
        }
      }),
      autoCancel: true,
      systemMaterial: UiMaterialKit.sheet()
    });
    this.moveController.open();
  }

  private showGrep(): void {
    this.grepController = new CustomDialogController({
      builder: WorkspaceGrepDialog({
        agentId: this.agentId,
        searchPath: this.currentPath,
        onSearched: (results: Array<WorkspaceGrepMatchModel>): void => {
          this.grepResults = results;
          this.grepOpen = true;
        }
      }),
      autoCancel: true,
      systemMaterial: UiMaterialKit.sheet()
    });
    this.grepController.open();
  }

  private showEntryMenu(entry: WorkspaceEntryModel): void {
    const options: Array<MenuSheetOption> = [
      new MenuSheetOption($r('sys.symbol.pencil_line'), '重命名/移动', '', false)
    ];
    const actions: Array<() => void> = [
      (): void => {
        this.showMove(entry);
      }
    ];
    if (!entry.isDir) {
      options.push(new MenuSheetOption($r('sys.symbol.square_and_arrow_down'), '下载', '保存到本机', false));
      actions.push((): void => {
        this.downloadEntry(entry);
      });
    }
    options.push(new MenuSheetOption($r('sys.symbol.trash'), '删除', '', true));
    actions.push((): void => {
      this.confirmDelete(entry);
    });
    this.menuTitle = entry.displayName();
    this.menuMessage = '选择操作';
    this.menuOptions = options;
    this.menuActions = actions;
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

  private confirmDelete(entry: WorkspaceEntryModel): void {
    this.getUIContext().showAlertDialog({
      title: entry.isDir ? '删除文件夹' : '删除文件',
      message: `确定删除「${entry.displayName()}」吗？`,
      primaryButton: {
        value: $r('app.string.common_cancel'),
        action: (): void => {
        }
      },
      secondaryButton: {
        value: $r('app.string.common_confirm'),
        action: (): void => {
          this.deleteEntry(entry);
        }
      },
      alignment: DialogAlignment.Bottom
    });
  }

  private async deleteEntry(entry: WorkspaceEntryModel): Promise<void> {
    if (this.operating) {
      return;
    }
    this.operating = true;
    try {
      await WorkspaceFileService.remove(this.agentId, entry.path);
      await this.load();
    } catch (e) {
      const message: string = e instanceof OctopApiError ? e.message : '删除失败';
      this.getUIContext().getPromptAction().showToast({ message });
    }
    this.operating = false;
  }

  private fileNameFromUri(uri: string): string {
    const idx: number = uri.lastIndexOf('/');
    const name: string = idx >= 0 ? uri.substring(idx + 1) : uri;
    if (name === '') {
      return 'file';
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
    if (lower.endsWith('.gif')) {
      return 'image/gif';
    }
    if (lower.endsWith('.pdf')) {
      return 'application/pdf';
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
    if (lower.endsWith('.md')) {
      return 'text/markdown';
    }
    if (lower.endsWith('.txt')) {
      return 'text/plain';
    }
    if (lower.endsWith('.zip')) {
      return 'application/zip';
    }
    return 'application/octet-stream';
  }

  private async pickAndUpload(): Promise<void> {
    if (this.operating) {
      return;
    }
    const docPicker = new picker.DocumentViewPicker();
    const options = new picker.DocumentSelectOptions();
    options.maxSelectNumber = 5;
    let uris: Array<string> = [];
    try {
      uris = await docPicker.select(options);
    } catch (e) {
      return;
    }
    this.operating = true;
    let okCount: number = 0;
    for (const uri of uris) {
      const ok: boolean = await this.uploadOne(uri);
      if (ok) {
        okCount += 1;
      }
    }
    this.operating = false;
    if (okCount > 0) {
      this.getUIContext().getPromptAction().showToast({ message: '上传完成' });
    }
    this.load();
  }

  private async uploadOne(uri: string): Promise<boolean> {
    const fileName: string = this.fileNameFromUri(uri);
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
      await WorkspaceFileService.upload(this.agentId, fileName, this.contentTypeFor(fileName),
        data, this.joinPath(fileName));
      return true;
    } catch (e) {
      const message: string = e instanceof OctopApiError ?
        `「${fileName}」${e.message}` : `「${fileName}」上传失败`;
      this.getUIContext().getPromptAction().showToast({ message });
      return false;
    }
  }

  private async downloadEntry(entry: WorkspaceEntryModel): Promise<void> {
    if (this.operating) {
      return;
    }
    this.operating = true;
    try {
      const data: ArrayBuffer = await WorkspaceFileService.download(this.agentId, entry.path);
      const docPicker = new picker.DocumentViewPicker();
      const saveOptions = new picker.DocumentSaveOptions();
      saveOptions.newFileNames = [entry.displayName()];
      const uris: Array<string> = await docPicker.save(saveOptions);
      if (uris.length > 0) {
        const file = fileIo.openSync(uris[0],
          fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.TRUNC);
        try {
          fileIo.writeSync(file.fd, data);
        } finally {
          fileIo.closeSync(file);
        }
        this.getUIContext().getPromptAction().showToast({ message: '已保存' });
      }
    } catch (e) {
      const message: string = e instanceof OctopApiError ? e.message : '下载失败';
      this.getUIContext().getPromptAction().showToast({ message });
    }
    this.operating = false;
  }

  build() {
    NavDestination() {
      Column() {
        PageHeader({ title: '工作区文件' })

        Row({ space: 8 }) {
          Text(this.currentPath)
            .fontSize(13)
            .fontColor($r('app.color.text_secondary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
            .onClick((): void => {
              this.goUp();
            })
          Text('新建文件夹')
            .fontSize(12)
            .fontColor($r('app.color.brand'))
            .height(30)
            .padding({ left: 10, right: 10 })
            .borderRadius(15)
            .backgroundColor($r('app.color.brand_light'))
            .onClick((): void => {
              this.showMkdir();
            })
          Text('上传文件')
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))
            .height(30)
            .padding({ left: 10, right: 10 })
            .borderRadius(15)
            .backgroundColor($r('app.color.bg_input'))
            .onClick((): void => {
              this.pickAndUpload();
            })
          Text('搜索内容')
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))
            .height(30)
            .padding({ left: 10, right: 10 })
            .borderRadius(15)
            .backgroundColor($r('app.color.bg_input'))
            .onClick((): void => {
              this.showGrep();
            })
        }
        .width('100%')
        .padding({ left: 14, right: 14, top: 2, bottom: 8 })

        if (this.viewing) {
          Column({ space: 12 }) {
            Row({ space: 12 }) {
              Column({ space: 3 }) {
                Text(this.viewingName())
                  .fontSize(16)
                  .fontWeight(FontWeight.Medium)
                  .fontColor($r('app.color.text_primary'))
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .width('100%')
                Text(this.viewingPath)
                  .fontSize(11)
                  .fontColor($r('app.color.text_tertiary'))
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .width('100%')
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)

              Button('关闭')
                .fontSize(13)
                .height(32)
                .borderRadius(16)
                .padding({ left: 14, right: 14 })
                .backgroundColor($r('app.color.bg_input'))
                .fontColor($r('app.color.text_secondary'))
                .onClick((): void => {
                  this.viewing = false;
                })
            }
            .width('100%')

            TextArea({
              text: this.viewingContent,
              placeholder: '（无内容）'
            })
              .fontSize(13)
              .width('100%')
              .layoutWeight(1)
              .backgroundColor($r('app.color.bg_input'))
              .borderRadius(12)
              .onChange((value: string): void => {
                this.viewingContent = value;
              })

            Button('编辑保存')
              .fontSize(14)
              .fontWeight(FontWeight.Medium)
              .height(38)
              .borderRadius(19)
              .width('100%')
              .backgroundColor($r('app.color.brand'))
              .fontColor($r('app.color.bg_page'))
              .enabled(!this.operating)
              .onClick((): void => {
                this.saveViewing();
              })
          }
          .layoutWeight(1)
          .width('100%')
          .padding({ left: 14, right: 14, top: 4, bottom: 14 })
        } else if (this.grepOpen) {
          Column({ space: 12 }) {
            Row({ space: 12 }) {
              Text(this.grepTitle())
                .fontSize(16)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.text_primary'))
                .maxLines(1)
                .layoutWeight(1)

              Button('关闭')
                .fontSize(13)
                .height(32)
                .borderRadius(16)
                .padding({ left: 14, right: 14 })
                .backgroundColor($r('app.color.bg_input'))
                .fontColor($r('app.color.text_secondary'))
                .onClick((): void => {
                  this.grepOpen = false;
                })
            }
            .width('100%')

            if (this.grepResults.length === 0) {
              Column() {
                EmptyView({
                  title: '无匹配结果',
                  subtitle: '换个关键词试试',
                  icon: $r('sys.symbol.magnifyingglass')
                })
              }
              .layoutWeight(1)
              .width('100%')
              .justifyContent(FlexAlign.Center)
            } else {
              Scroll() {
                Column({ space: 10 }) {
                  ForEach(this.grepResults, (match: WorkspaceGrepMatchModel) => {
                    Column({ space: 3 }) {
                      Text(this.matchLocation(match))
                        .fontSize(11)
                        .fontColor($r('app.color.brand'))
                        .maxLines(1)
                        .textOverflow({ overflow: TextOverflow.Ellipsis })
                        .width('100%')
                      Text(match.text)
                        .fontSize(13)
                        .fontColor($r('app.color.text_secondary'))
                        .maxLines(2)
                        .textOverflow({ overflow: TextOverflow.Ellipsis })
                        .width('100%')
                        .lineHeight(18)
                    }
                    .width('100%')
                    .alignItems(HorizontalAlign.Start)
                    .padding({ left: 12, right: 12, top: 10, bottom: 10 })
                    .borderRadius(12)
                    .backgroundColor($r('app.color.bg_card'))
                  }, (match: WorkspaceGrepMatchModel, index: number) =>
                    `${index}-${match.path}-${match.line}`)
                }
                .width('100%')
              }
              .layoutWeight(1)
              .width('100%')
              .scrollBar(BarState.Auto)
            }
          }
          .layoutWeight(1)
          .width('100%')
          .padding({ left: 14, right: 14, top: 4, bottom: 14 })
        } else if (this.loading) {
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
        } else if (this.entries.length === 0) {
          Column() {
            EmptyView({
              title: '空目录',
              subtitle: '使用上方按钮上传或新建',
              icon: $r('sys.symbol.folder')
            })
          }
          .layoutWeight(1)
          .width('100%')
          .justifyContent(FlexAlign.Center)
        } else {
          Refresh({ refreshing: $$this.refreshing }) {
            List({ space: 10 }) {
              ForEach(this.entries, (entry: WorkspaceEntryModel) => {
                ListItem() {
                  Row({ space: 12 }) {
                    Column() {
                      SymbolGlyph(this.entryIcon(entry))
                        .fontSize(20)
                        .fontColor(this.entryIconTint(entry))
                    }
                    .width(42)
                    .height(42)
                    .borderRadius(13)
                    .backgroundColor(this.entryIconBg(entry))
                    .justifyContent(FlexAlign.Center)

                    Column({ space: 4 }) {
                      Text(entry.displayName())
                        .fontSize(15)
                        .fontWeight(FontWeight.Medium)
                        .fontColor($r('app.color.text_primary'))
                        .maxLines(1)
                        .textOverflow({ overflow: TextOverflow.Ellipsis })
                        .width('100%')
                      Text(this.entryMeta(entry))
                        .fontSize(11)
                        .fontColor($r('app.color.text_tertiary'))
                        .maxLines(1)
                        .width('100%')
                    }
                    .layoutWeight(1)
                    .alignItems(HorizontalAlign.Start)

                    SymbolGlyph($r('sys.symbol.chevron_right'))
                      .fontSize(14)
                      .fontColor([$r('app.color.text_tertiary')])
                  }
                  .width('100%')
                  .padding({ left: 14, right: 14, top: 14, bottom: 14 })
                  .borderRadius(16)
                  .backgroundColor($r('app.color.bg_card'))
                  .onClick((): void => {
                    this.openEntry(entry);
                  })
                  .gesture(
                    LongPressGesture()
                      .onAction((event: GestureEvent): void => {
                        this.showEntryMenu(entry);
                      })
                  )
                }
              }, (entry: WorkspaceEntryModel) => entry.path)
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
