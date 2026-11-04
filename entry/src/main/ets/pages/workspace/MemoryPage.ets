import { ManualReviewModel, MemoryAdoptSummaryModel, MemoryAtomModel, MemoryCandidateModel, MemoryDailyFileModel, MemoryEntityModel, MemoryEpisodeModel, MemoryKindFilterItem, MemoryStatsCountsModel, MemoryTextFileModel, UserPreferencesModel } from '../../model/MemoryModels';
import { MemoryService } from '../../service/MemoryService';
import { PreferencesService } from '../../service/PreferencesService';
import { OctopApiError } from '../../net/HttpClient';
import { SessionStore } from '../../store/SessionStore';
import { EmptyView } from '../../components/EmptyView';
import { ErrorRetry } from '../../components/ErrorRetry';
import { PageHeader } from '../../components/PageHeader';
import { UiMaterialKit } from '../../components/UiMaterialKit';
import { TimeFormat } from '../../utils/TimeFormat';
import { Log } from '../../utils/Logger';
import { picker, fileIo } from '@kit.CoreFileKit';
import { MenuSheetContent, MenuSheetOption } from '../../components/MenuSheet';

/** 记忆页分区：记忆条目 / 候选审核 / 日积月累 / 手动档案 / 记忆终端 */
const MEMORY_SCOPES: string[] = ['atoms', 'candidates', 'daily', 'docs', 'terminal'];

/** 候选审核状态筛选（status 空串=全部） */
class CandidateFilterItem {
  readonly status: string;
  readonly label: string;

  constructor(status: string, label: string) {
    this.status = status;
    this.label = label;
  }

  static all(): Array<CandidateFilterItem> {
    return [
      new CandidateFilterItem('pending', '待定'),
      new CandidateFilterItem('needs_review', '需审核'),
      new CandidateFilterItem('conflict', '冲突'),
      new CandidateFilterItem('promoted', '已采纳'),
      new CandidateFilterItem('rejected', '已拒绝'),
      new CandidateFilterItem('', '全部')
    ];
  }
}

const CANDIDATE_FILTERS: Array<CandidateFilterItem> = CandidateFilterItem.all();

function memoryScopeLabel(scope: string): string {
  if (scope === 'candidates') {
    return '待审核';
  }
  if (scope === 'daily') {
    return '日积月累';
  }
  if (scope === 'docs') {
    return '档案';
  }
  if (scope === 'terminal') {
    return '终端';
  }
  return '记忆';
}

/** 专家记忆管理 + 用户偏好：列表（搜索/分类）、增删改、.hmpkg 导入导出、偏好卡片、
 *  候选审核（promote/reject）、日积月累、MEMORY.md/USER.md 手动档案、记忆终端五卡 */
@Component
export struct MemoryPage {
  @State scope: string = 'atoms';
  @State atoms: Array<MemoryAtomModel> = [];
  @State stats: MemoryStatsCountsModel | null = null;
  @State prefs: UserPreferencesModel | null = null;
  @State kindFilter: string = '';
  @State searchText: string = '';
  @State loading: boolean = true;
  @State refreshing: boolean = false;
  @State errorMsg: string = '';
  @State operating: boolean = false;
  @State portSheetOpen: boolean = false;
  @State menuOpen: boolean = false;
  @State menuTitle: string = '';
  @State menuMessage: string = '';
  @State menuOptions: Array<MenuSheetOption> = [];

  // 候选审核
  @State candidates: Array<MemoryCandidateModel> = [];
  @State candFilter: string = 'pending';

  // 日积月累
  @State dailyFiles: Array<MemoryDailyFileModel> = [];
  @State dailyViewOpen: boolean = false;
  @State dailyViewDate: string = '';
  @State dailyViewContent: string = '';
  @State dailyViewFilename: string = '';

  // 手动档案（MEMORY.md / USER.md）
  @State strongDoc: MemoryTextFileModel | null = null;
  @State userDoc: MemoryTextFileModel | null = null;

  // 记忆终端
  @State terminalAbout: Array<MemoryAtomModel> = [];
  @State terminalFocus: Array<MemoryAtomModel> = [];
  @State terminalTold: Array<MemoryAtomModel> = [];
  @State terminalStories: Array<MemoryEpisodeModel> = [];
  @State terminalEntities: Array<MemoryEntityModel> = [];
  @State terminalLoaded: boolean = false;

  private menuActions: Array<() => void> = [];
  private kindFilters: Array<MemoryKindFilterItem> = MemoryKindFilterItem.all();
  private agentId: string = '';
  private pathStack: NavPathStack | null = null;
  private dialogController: CustomDialogController | null = null;
  private searchTimer: number = -1;

  onNavReady(ctx: NavDestinationContext): void {
    this.pathStack = ctx.pathStack;
    this.agentId = AppStorage.get<string>(SessionStore.KEY_AGENT_ID) ?? '';
    if (this.agentId === '') {
      this.loading = false;
      this.errorMsg = '未选择专家，请先在专家页选择';
      return;
    }
    this.load();
    this.loadPrefs();
  }

  private async load(): Promise<void> {
    if (this.agentId === '') {
      this.loading = false;
      this.errorMsg = '未选择专家，请先在专家页选择';
      return;
    }
    this.loading = true;
    this.errorMsg = '';
    try {
      this.atoms = await MemoryService.listAtoms(this.agentId, this.searchText.trim(), this.kindFilter);
      this.stats = await MemoryService.statsCounts(this.agentId);
    } catch (e) {
      this.errorMsg = e instanceof OctopApiError ? e.message : '记忆加载失败';
    } finally {
      this.loading = false;
    }
  }

  private async loadPrefs(): Promise<void> {
    try {
      this.prefs = await PreferencesService.get();
    } catch (e) {
      Log.warn('MemoryPage load preferences failed');
    }
  }

  /** 分区切换 + 懒加载 */
  private setScope(scope: string): void {
    if (this.scope === scope) {
      return;
    }
    this.scope = scope;
    this.errorMsg = '';
    if (scope === 'atoms') {
      this.load();
    } else if (scope === 'candidates') {
      this.loadCandidates();
    } else if (scope === 'daily') {
      this.loadDaily();
    } else if (scope === 'docs') {
      this.loadDocs();
    } else if (scope === 'terminal') {
      this.loadTerminal();
    }
  }

  // ---- 候选审核 ----

  private async loadCandidates(): Promise<void> {
    this.loading = true;
    this.errorMsg = '';
    try {
      this.candidates = await MemoryService.listCandidates(
        this.agentId, this.candFilter, '', '', 100);
      this.stats = await MemoryService.statsCounts(this.agentId);
    } catch (e) {
      this.errorMsg = e instanceof OctopApiError ? e.message : '候选记忆加载失败';
    } finally {
      this.loading = false;
    }
  }

  private setCandFilter(status: string): void {
    if (this.candFilter === status) {
      return;
    }
    this.candFilter = status;
    this.loadCandidates();
  }

  private async promoteCandidate(c: MemoryCandidateModel): Promise<void> {
    if (this.operating) {
      return;
    }
    this.operating = true;
    try {
      await MemoryService.promoteCandidate(this.agentId, c.id);
      this.getUIContext().getPromptAction().showToast({ message: '已采纳为长期记忆' });
      this.loadCandidates();
    } catch (e) {
      this.getUIContext().getPromptAction().showToast({
        message: e instanceof OctopApiError ? e.message : '采纳失败'
      });
    } finally {
      this.operating = false;
    }
  }

  private async rejectCandidate(c: MemoryCandidateModel): Promise<void> {
    if (this.operating) {
      return;
    }
    this.operating = true;
    try {
      await MemoryService.rejectCandidate(this.agentId, c.id, '');
      this.getUIContext().getPromptAction().showToast({ message: '已拒绝该候选' });
      this.loadCandidates();
    } catch (e) {
      this.getUIContext().getPromptAction().showToast({
        message: e instanceof OctopApiError ? e.message : '拒绝失败'
      });
    } finally {
      this.operating = false;
    }
  }

  // ---- 日积月累 ----

  private async loadDaily(): Promise<void> {
    this.loading = true;
    this.errorMsg = '';
    try {
      this.dailyFiles = await MemoryService.listDaily(this.agentId);
    } catch (e) {
      this.errorMsg = e instanceof OctopApiError ? e.message : '日积月累加载失败';
    } finally {
      this.loading = false;
    }
  }

  private async openDaily(f: MemoryDailyFileModel): Promise<void> {
    try {
      const content: string = await MemoryService.readDaily(this.agentId, f.filename);
      this.dailyViewFilename = f.filename;
      this.dailyViewDate = f.date;
      this.dailyViewContent = content;
      this.dailyViewOpen = true;
    } catch (e) {
      this.getUIContext().getPromptAction().showToast({
        message: e instanceof OctopApiError ? e.message : '读取失败'
      });
    }
  }

  private async deleteDaily(f: MemoryDailyFileModel): Promise<void> {
    if (this.operating) {
      return;
    }
    this.operating = true;
    try {
      await MemoryService.deleteDaily(this.agentId, f.filename);
      this.getUIContext().getPromptAction().showToast({ message: '已删除' });
      this.loadDaily();
    } catch (e) {
      this.getUIContext().getPromptAction().showToast({
        message: e instanceof OctopApiError ? e.message : '删除失败'
      });
    } finally {
      this.operating = false;
    }
  }

  // ---- 手动档案 ----

  private async loadDocs(): Promise<void> {
    this.loading = true;
    this.errorMsg = '';
    try {
      this.strongDoc = await MemoryService.getStrong(this.agentId);
      this.userDoc = await MemoryService.getUserProfile(this.agentId);
    } catch (e) {
      this.errorMsg = e instanceof OctopApiError ? e.message : '档案加载失败';
    } finally {
      this.loading = false;
    }
  }

  /** 编辑 MEMORY.md / USER.md；kind='strong'|'user' */
  private editDoc(kind: string): void {
    const initial: string = kind === 'strong'
      ? (this.strongDoc === null ? '' : this.strongDoc.content)
      : (this.userDoc === null ? '' : this.userDoc.content);
    const title: string = kind === 'strong' ? 'MEMORY.md（强记忆）' : 'USER.md（用户画像）';
    this.dialogController = new CustomDialogController({
      builder: MemoryDocEditDialog({
        title: title,
        initialContent: initial,
        onSaved: (): void => {
          this.loadDocs();
        },
        onSave: async (content: string): Promise<void> => {
          if (kind === 'strong') {
            await MemoryService.putStrong(this.agentId, content);
          } else {
            await MemoryService.putUserProfile(this.agentId, content);
          }
        }
      }),
      autoCancel: true,
      systemMaterial: UiMaterialKit.sheet()
    });
    this.dialogController.open();
  }

  /** 手动文档与普通记忆核对 */
  private async runManualReview(): Promise<void> {
    if (this.operating) {
      return;
    }
    this.operating = true;
    try {
      const review: ManualReviewModel = await MemoryService.manualReview(this.agentId);
      this.getUIContext().getPromptAction().showToast({
        message: `核对完成：检查 ${review.checked}，冲突 ${review.conflicts}，重复 ${review.duplicates}`
      });
    } catch (e) {
      this.getUIContext().getPromptAction().showToast({
        message: e instanceof OctopApiError ? e.message : '核对失败'
      });
    } finally {
      this.operating = false;
    }
  }

  // ---- 记忆终端 ----

  private async loadTerminal(): Promise<void> {
    this.loading = true;
    this.errorMsg = '';
    try {
      this.terminalAbout = await MemoryService.terminalAtoms(this.agentId, 'about_me', 5);
      this.terminalFocus = await MemoryService.terminalAtoms(this.agentId, 'current_focus', 5);
      this.terminalTold = await MemoryService.terminalAtoms(this.agentId, 'things_you_told_me', 5);
      this.terminalStories = await MemoryService.terminalStories(this.agentId, 5);
      this.terminalEntities = await MemoryService.terminalEntities(this.agentId, 8);
      this.terminalLoaded = true;
    } catch (e) {
      this.errorMsg = e instanceof OctopApiError ? e.message : '记忆终端加载失败';
    } finally {
      this.loading = false;
    }
  }

  /** 搜索输入防抖：400ms 后触发列表刷新 */
  private onSearchChange(text: string): void {
    this.searchText = text;
    if (this.searchTimer >= 0) {
      clearTimeout(this.searchTimer);
    }
    this.searchTimer = setTimeout((): void => {
      this.searchTimer = -1;
      this.load();
    }, 400);
  }

  private setKindFilter(kind: string): void {
    if (this.kindFilter === kind) {
      return;
    }
    this.kindFilter = kind;
    this.load();
  }

  private showCreate(): void {
    this.dialogController = new CustomDialogController({
      builder: MemoryAtomEditDialog({
        agentId: this.agentId,
        atomId: '',
        initialAssertion: '',
        onSaved: (): void => {
          this.load();
        }
      }),
      autoCancel: true,
      systemMaterial: UiMaterialKit.sheet()
    });
    this.dialogController.open();
  }

  private showEdit(atom: MemoryAtomModel): void {
    this.dialogController = new CustomDialogController({
      builder: MemoryAtomEditDialog({
        agentId: this.agentId,
        atomId: atom.id,
        initialAssertion: atom.assertion,
        onSaved: (): void => {
          this.load();
        }
      }),
      autoCancel: true,
      systemMaterial: UiMaterialKit.sheet()
    });
    this.dialogController.open();
  }

  private showPrefsDialog(): void {
    if (this.prefs === null) {
      return;
    }
    const prefs: UserPreferencesModel = this.prefs;
    this.dialogController = new CustomDialogController({
      builder: MemoryPrefsDialog({
        initialLocale: prefs.locale,
        initialTimezone: prefs.timezone,
        initialPreferredModel: prefs.preferredModel,
        onSaved: (): void => {
          this.loadPrefs();
        }
      }),
      autoCancel: true,
      systemMaterial: UiMaterialKit.sheet()
    });
    this.dialogController.open();
  }

  private showAtomMenu(atom: MemoryAtomModel): void {
    this.menuTitle = atom.kindLabel();
    this.menuMessage = '选择操作';
    this.menuOptions = [
      new MenuSheetOption($r('sys.symbol.pencil_line'), '编辑', '修改这条记忆', false),
      new MenuSheetOption($r('sys.symbol.trash'), '删除', '', true)
    ];
    this.menuActions = [
      (): void => {
        this.showEdit(atom);
      },
      (): void => {
        this.confirmDelete(atom);
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

  /** 记忆迁移入口：bindSheet 半模态（导出/导入 .hmpkg，两选项行带图标与说明） */
  private showPortMenu(): void {
    this.portSheetOpen = true;
  }

  private confirmDelete(atom: MemoryAtomModel): void {
    this.getUIContext().showAlertDialog({
      title: '删除记忆',
      message: '确定删除这条记忆吗？删除后将不再参与回忆。',
      primaryButton: {
        value: $r('app.string.common_cancel'),
        action: (): void => {
        }
      },
      secondaryButton: {
        value: $r('app.string.common_confirm'),
        action: (): void => {
          this.deleteAtom(atom);
        }
      },
      alignment: DialogAlignment.Bottom
    });
  }

  private async deleteAtom(atom: MemoryAtomModel): Promise<void> {
    if (this.operating) {
      return;
    }
    this.operating = true;
    try {
      await MemoryService.deprecateAtom(this.agentId, atom.id);
      await this.load();
    } catch (e) {
      const message: string = e instanceof OctopApiError ? e.message : '删除失败';
      this.getUIContext().getPromptAction().showToast({ message });
    } finally {
      this.operating = false;
    }
  }

  /** 导出：pack 拉取 .hmpkg 字节流，DocumentViewPicker 保存 */
  private async exportPackage(): Promise<void> {
    if (this.operating) {
      return;
    }
    this.operating = true;
    try {
      const buffer: ArrayBuffer = await MemoryService.pack(this.agentId);
      this.saveHmpkg(buffer);
    } catch (e) {
      const message: string = e instanceof OctopApiError ? e.message : '导出失败';
      this.getUIContext().getPromptAction().showToast({ message });
    } finally {
      this.operating = false;
    }
  }

  private saveHmpkg(buffer: ArrayBuffer): void {
    const docPicker = new picker.DocumentViewPicker();
    const saveOptions = new picker.DocumentSaveOptions();
    saveOptions.newFileNames = [`${this.agentId}.hmpkg`];
    docPicker.save(saveOptions).then(async (uris: Array<string>): Promise<void> => {
      if (uris.length > 0) {
        const file = fileIo.openSync(uris[0], fileIo.OpenMode.READ_WRITE);
        try {
          fileIo.writeSync(file.fd, buffer);
        } finally {
          fileIo.closeSync(file);
        }
        this.getUIContext().getPromptAction().showToast({ message: '记忆包已导出' });
      }
    }).catch((): void => {
    });
  }

  /** 导入：DocumentViewPicker 选取 .hmpkg，读取后 multipart 上传 adopt */
  private async importPackage(): Promise<void> {
    if (this.operating) {
      return;
    }
    const docPicker = new picker.DocumentViewPicker();
    const selectOptions = new picker.DocumentSelectOptions();
    selectOptions.maxSelectNumber = 1;
    let uris: Array<string> = [];
    try {
      uris = await docPicker.select(selectOptions);
    } catch (e) {
      return;
    }
    if (uris.length === 0) {
      return;
    }
    this.operating = true;
    try {
      const uri: string = uris[0];
      const fileName: string = this.fileNameFromUri(uri);
      const file = fileIo.openSync(uri, fileIo.OpenMode.READ_ONLY);
      let data: ArrayBuffer;
      try {
        const stat = fileIo.statSync(file.fd);
        data = new ArrayBuffer(stat.size);
        fileIo.readSync(file.fd, data);
      } finally {
        fileIo.closeSync(file);
      }
      const summary: MemoryAdoptSummaryModel =
        await MemoryService.adopt(this.agentId, fileName === '' ? 'memory.hmpkg' : fileName, data);
      this.getUIContext().getPromptAction().showToast({
        message: `导入完成：写入 ${summary.applied} 条，跳过 ${summary.skipped} 条`
      });
      await this.load();
    } catch (e) {
      const message: string = e instanceof OctopApiError ? e.message : '导入失败';
      this.getUIContext().getPromptAction().showToast({ message });
    } finally {
      this.operating = false;
    }
  }

  private fileNameFromUri(uri: string): string {
    const idx: number = uri.lastIndexOf('/');
    return idx >= 0 ? uri.substring(idx + 1) : uri;
  }

  /** 记忆迁移半模态：标题 + 副题 + 导出/导入两选项行（图标 + 标题 + 说明，整行可点） */
  @Builder
  private portSheetBuilder() {
    Column({ space: 16 }) {
      Column({ space: 6 }) {
        Text('记忆迁移')
          .fontSize(17)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .width('100%')
        Text('导出或导入 .hmpkg 记忆包')
          .fontSize(12)
          .fontColor($r('app.color.text_tertiary'))
          .width('100%')
      }
      .width('100%')

      Row({ space: 12 }) {
        Column() {
          SymbolGlyph($r('sys.symbol.doc_text_badge_arrow_up'))
            .fontSize(20)
            .fontColor([$r('app.color.brand')])
        }
        .width(44)
        .height(44)
        .borderRadius(14)
        .backgroundColor($r('app.color.brand_light'))
        .justifyContent(FlexAlign.Center)

        Column({ space: 3 }) {
          Text('导出记忆包')
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary'))
          Text('将当前专家的记忆打包保存为 .hmpkg 文件')
            .fontSize(12)
            .fontColor($r('app.color.text_tertiary'))
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
      }
      .width('100%')
      .padding(14)
      .borderRadius(16)
      .backgroundColor($r('app.color.bg_card'))
      .border({ width: 1, color: $r('app.color.card_stroke') })
      .onClick((): void => {
        this.portSheetOpen = false;
        this.exportPackage();
      })

      Row({ space: 12 }) {
        Column() {
          SymbolGlyph($r('sys.symbol.square_and_arrow_down'))
            .fontSize(20)
            .fontColor([$r('app.color.brand')])
        }
        .width(44)
        .height(44)
        .borderRadius(14)
        .backgroundColor($r('app.color.brand_light'))
        .justifyContent(FlexAlign.Center)

        Column({ space: 3 }) {
          Text('导入记忆包')
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary'))
          Text('选取 .hmpkg 文件，合并写入当前专家记忆')
            .fontSize(12)
            .fontColor($r('app.color.text_tertiary'))
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
      }
      .width('100%')
      .padding(14)
      .borderRadius(16)
      .backgroundColor($r('app.color.bg_card'))
      .border({ width: 1, color: $r('app.color.card_stroke') })
      .onClick((): void => {
        this.portSheetOpen = false;
        this.importPackage();
      })
    }
    .padding({ left: 20, right: 20, top: 20, bottom: 30 })
    .width('100%')
  }

  private prefsLocaleLabel(prefs: UserPreferencesModel): string {
    return prefs.locale === 'en' ? 'English' : '中文';
  }

  private prefsTimezoneLabel(prefs: UserPreferencesModel): string {
    return prefs.timezone === '' ? '跟随服务器' : prefs.timezone;
  }

  private prefsModelLabel(prefs: UserPreferencesModel): string {
    return prefs.preferredModel === '' ? '跟随全局' : prefs.preferredModel;
  }

  build() {
    NavDestination() {
      Stack({ alignContent: Alignment.BottomEnd }) {
        Column() {
          PageHeader({ title: '记忆与偏好' })

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
          } else {
            Column() {
              Scroll() {
                Row({ space: 8 }) {
                  ForEach(MEMORY_SCOPES, (s: string) => {
                    Text(memoryScopeLabel(s))
                      .fontSize(13)
                      .fontWeight(this.scope === s ? FontWeight.Medium : FontWeight.Normal)
                      .fontColor(this.scope === s ? $r('app.color.brand') : $r('app.color.text_secondary'))
                      .backgroundColor(this.scope === s ? $r('app.color.brand_light') : $r('app.color.bg_input'))
                      .borderRadius(16)
                      .padding({ left: 14, right: 14, top: 6, bottom: 6 })
                      .onClick((): void => {
                        this.setScope(s);
                      })
                  }, (s: string) => s)
                }
                .width('100%')
              }
              .scrollable(ScrollDirection.Horizontal)
              .scrollBar(BarState.Off)
              .width('100%')

              if (this.scope === 'atoms') {
              Row({ space: 10 }) {
                TextInput({
                  text: this.searchText,
                  placeholder: '搜索记忆内容'
                })
                  .layoutWeight(1)
                  .fontSize(14)
                  .height(40)
                  .backgroundColor($r('app.color.bg_input'))
                  .borderRadius(12)
                  .onChange((value: string): void => {
                    this.onSearchChange(value);
                  })

                Button({ type: ButtonType.Circle, stateEffect: true }) {
                  SymbolGlyph($r('sys.symbol.doc_text'))
                    .fontSize(17)
                    .fontWeight(FontWeight.Medium)
                    .fontColor([$r('app.color.text_primary')])
                }
                .width(40)
                .height(40)
                .backgroundColor($r('app.color.bg_card'))
                .border({ width: 1, color: $r('app.color.divider') })
                .onClick((): void => {
                  this.showPortMenu();
                })
                .bindSheet($$this.portSheetOpen, this.portSheetBuilder, {
                  detents: [SheetSize.FIT_CONTENT],
                  showClose: true,
                  systemMaterial: UiMaterialKit.sheet()
                })
              }
              .width('100%')

              Scroll() {
                Row({ space: 8 }) {
                  ForEach(this.kindFilters, (filter: MemoryKindFilterItem) => {
                    Text(filter.label)
                      .fontSize(13)
                      .fontWeight(this.kindFilter === filter.kind ? FontWeight.Medium : FontWeight.Normal)
                      .fontColor(this.kindFilter === filter.kind ? $r('app.color.brand') : $r('app.color.text_secondary'))
                      .backgroundColor(this.kindFilter === filter.kind ? $r('app.color.brand_light') : $r('app.color.bg_input'))
                      .borderRadius(16)
                      .padding({ left: 14, right: 14, top: 6, bottom: 6 })
                      .onClick((): void => {
                        this.setKindFilter(filter.kind);
                      })
                  }, (filter: MemoryKindFilterItem) => filter.kind)
                }
                .width('100%')
              }
              .scrollable(ScrollDirection.Horizontal)
              .scrollBar(BarState.Off)
              .width('100%')
              .margin({ top: 10, bottom: 4 })

              Refresh({ refreshing: $$this.refreshing }) {
                List({ space: 12 }) {
                  if (this.prefs !== null) {
                    ListItem() {
                      Column({ space: 12 }) {
                        Row({ space: 8 }) {
                          SymbolGlyph($r('sys.symbol.gearshape'))
                            .fontSize(16)
                            .fontColor([$r('app.color.brand')])
                          Text('用户偏好')
                            .fontSize(15)
                            .fontWeight(FontWeight.Medium)
                            .fontColor($r('app.color.text_primary'))
                            .layoutWeight(1)
                          SymbolGlyph($r('sys.symbol.chevron_right'))
                            .fontSize(13)
                            .fontColor([$r('app.color.icon_secondary')])
                        }
                        .width('100%')

                        Row() {
                          Text('语言')
                            .fontSize(13)
                            .fontColor($r('app.color.text_secondary'))
                            .layoutWeight(1)
                          Text(this.prefsLocaleLabel(this.prefs))
                            .fontSize(13)
                            .fontColor($r('app.color.text_primary'))
                        }
                        .width('100%')

                        Row() {
                          Text('时区')
                            .fontSize(13)
                            .fontColor($r('app.color.text_secondary'))
                            .layoutWeight(1)
                          Text(this.prefsTimezoneLabel(this.prefs))
                            .fontSize(13)
                            .fontColor($r('app.color.text_primary'))
                        }
                        .width('100%')

                        Row() {
                          Text('首选模型')
                            .fontSize(13)
                            .fontColor($r('app.color.text_secondary'))
                            .layoutWeight(1)
                          Text(this.prefsModelLabel(this.prefs))
                            .fontSize(13)
                            .fontColor($r('app.color.text_primary'))
                            .maxLines(1)
                            .textOverflow({ overflow: TextOverflow.Ellipsis })
                            .constraintSize({ maxWidth: 180 })
                        }
                        .width('100%')
                      }
                      .width('100%')
                      .padding({ left: 14, right: 14, top: 14, bottom: 14 })
                      .borderRadius(16)
                      .backgroundColor($r('app.color.bg_card'))
                      .onClick((): void => {
                        this.showPrefsDialog();
                      })
                    }
                  }

                  if (this.stats !== null) {
                    ListItem() {
                      Row({ space: 8 }) {
                        Column({ space: 3 }) {
                          Text(`${this.stats.atoms}`)
                            .fontSize(17)
                            .fontWeight(FontWeight.Bold)
                            .fontColor($r('app.color.brand'))
                          Text('记忆')
                            .fontSize(11)
                            .fontColor($r('app.color.text_tertiary'))
                        }
                        .layoutWeight(1)
                        .alignItems(HorizontalAlign.Center)

                        Column({ space: 3 }) {
                          Text(`${this.stats.entities}`)
                            .fontSize(17)
                            .fontWeight(FontWeight.Bold)
                            .fontColor($r('app.color.text_primary'))
                          Text('实体')
                            .fontSize(11)
                            .fontColor($r('app.color.text_tertiary'))
                        }
                        .layoutWeight(1)
                        .alignItems(HorizontalAlign.Center)

                        Column({ space: 3 }) {
                          Text(`${this.stats.episodes}`)
                            .fontSize(17)
                            .fontWeight(FontWeight.Bold)
                            .fontColor($r('app.color.text_primary'))
                          Text('片段')
                            .fontSize(11)
                            .fontColor($r('app.color.text_tertiary'))
                        }
                        .layoutWeight(1)
                        .alignItems(HorizontalAlign.Center)

                        Column({ space: 3 }) {
                          Text(`${this.stats.candidatesPending}`)
                            .fontSize(17)
                            .fontWeight(FontWeight.Bold)
                            .fontColor($r('app.color.text_primary'))
                          Text('待定')
                            .fontSize(11)
                            .fontColor($r('app.color.text_tertiary'))
                        }
                        .layoutWeight(1)
                        .alignItems(HorizontalAlign.Center)
                      }
                      .width('100%')
                      .padding({ left: 14, right: 14, top: 14, bottom: 14 })
                      .borderRadius(16)
                      .backgroundColor($r('app.color.bg_card'))
                    }
                  }

                  if (this.atoms.length === 0) {
                    ListItem() {
                      EmptyView({
                        title: '暂无记忆',
                        subtitle: '专家会在对话中自动沉淀记忆\n也可点击右下角按钮手动添加',
                        icon: $r('sys.symbol.lightbulb')
                      })
                    }
                  }

                  ForEach(this.atoms, (atom: MemoryAtomModel) => {
                    ListItem() {
                      Row({ space: 12 }) {
                        Column() {
                          SymbolGlyph($r('sys.symbol.book'))
                            .fontSize(20)
                            .fontColor([$r('app.color.brand')])
                        }
                        .width(42)
                        .height(42)
                        .borderRadius(13)
                        .backgroundColor($r('app.color.brand_light'))
                        .justifyContent(FlexAlign.Center)
                        .opacity(atom.isDeprecated() ? 0.45 : 1)

                        Column({ space: 7 }) {
                          Text(atom.assertion)
                            .fontSize(15)
                            .fontWeight(FontWeight.Medium)
                            .fontColor(atom.isDeprecated() ? $r('app.color.text_tertiary') : $r('app.color.text_primary'))
                            .maxLines(3)
                            .textOverflow({ overflow: TextOverflow.Ellipsis })
                            .width('100%')
                            .lineHeight(22)
                          if (atom.verbatimQuote !== '') {
                            Text(atom.verbatimQuote)
                              .fontSize(12)
                              .fontColor($r('app.color.text_secondary'))
                              .maxLines(2)
                              .textOverflow({ overflow: TextOverflow.Ellipsis })
                              .width('100%')
                              .lineHeight(17)
                          }
                          Row({ space: 8 }) {
                            Text(atom.kindLabel())
                              .fontSize(11)
                              .fontColor($r('app.color.brand'))
                              .backgroundColor($r('app.color.brand_light'))
                              .borderRadius(6)
                              .padding({ left: 8, right: 8, top: 3, bottom: 3 })
                              .maxLines(1)
                            Text(atom.importanceLabel())
                              .fontSize(11)
                              .fontColor($r('app.color.text_secondary'))
                              .backgroundColor($r('app.color.bg_input'))
                              .borderRadius(6)
                              .padding({ left: 8, right: 8, top: 3, bottom: 3 })
                            if (atom.createdAtMs > 0) {
                              Text(TimeFormat.list(atom.createdAtMs))
                                .fontSize(11)
                                .fontColor($r('app.color.text_tertiary'))
                                .maxLines(1)
                            }
                            if (atom.isDeprecated()) {
                              Text('已废弃')
                                .fontSize(11)
                                .fontColor($r('app.color.danger'))
                                .backgroundColor($r('app.color.danger_soft'))
                                .borderRadius(6)
                                .padding({ left: 8, right: 8, top: 3, bottom: 3 })
                            }
                            Blank()
                          }
                          .width('100%')
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
                            this.showAtomMenu(atom);
                          })
                      )
                    }
                  }, (atom: MemoryAtomModel) => atom.id)
                }
                .width('100%')
                .padding({ left: 14, right: 14, top: 4, bottom: 12 })
                .scrollBar(BarState.Off)
              }
              .layoutWeight(1)
              .width('100%')
              .onRefreshing((): void => {
                this.load();
              })
              } else if (this.scope === 'candidates') {
                this.candidatesBody()
              } else if (this.scope === 'daily') {
                this.dailyBody()
              } else if (this.scope === 'docs') {
                this.docsBody()
              } else {
                this.terminalBody()
              }
            }
            .layoutWeight(1)
            .width('100%')
            .padding({ left: 14, right: 14, top: 4 })
          }
        }
        .width('100%')
        .height('100%')

        if (this.scope === 'atoms') {
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
          .border({ width: 1, color: $r('app.color.divider') })
          .margin(22)
          .onClick((): void => {
            this.showCreate();
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
    .bindSheet($$this.dailyViewOpen, this.dailyViewBuilder, {
      detents: [SheetSize.LARGE, SheetSize.FIT_CONTENT],
      showClose: true,
      systemMaterial: UiMaterialKit.sheet()
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

  @Builder
  candidatesBody() {
    Scroll() {
      Row({ space: 8 }) {
        ForEach(CANDIDATE_FILTERS, (f: CandidateFilterItem) => {
          Text(f.label)
            .fontSize(13)
            .fontWeight(this.candFilter === f.status ? FontWeight.Medium : FontWeight.Normal)
            .fontColor(this.candFilter === f.status ? $r('app.color.brand') : $r('app.color.text_secondary'))
            .backgroundColor(this.candFilter === f.status ? $r('app.color.brand_light') : $r('app.color.bg_input'))
            .borderRadius(16)
            .padding({ left: 14, right: 14, top: 6, bottom: 6 })
            .onClick((): void => {
              this.setCandFilter(f.status);
            })
        }, (f: CandidateFilterItem) => f.status)
      }
      .width('100%')
    }
    .scrollable(ScrollDirection.Horizontal)
    .scrollBar(BarState.Off)
    .width('100%')

    Refresh({ refreshing: $$this.refreshing }) {
      List({ space: 12 }) {
        if (this.candidates.length === 0) {
          ListItem() {
            EmptyView({
              title: '暂无候选记忆',
              subtitle: '专家从对话中提取的候选事实会出现在这里',
              icon: $r('sys.symbol.checkmark_circle')
            })
          }
        }
        ForEach(this.candidates, (c: MemoryCandidateModel) => {
          ListItem() {
            Column({ space: 9 }) {
              Row({ space: 8 }) {
                Text(c.kind === '' ? '未分类' : c.kind)
                  .fontSize(11)
                  .fontColor($r('app.color.brand'))
                  .backgroundColor($r('app.color.brand_light'))
                  .borderRadius(6)
                  .padding({ left: 8, right: 8, top: 3, bottom: 3 })
                Text(c.statusLabel())
                  .fontSize(11)
                  .fontColor($r('app.color.text_secondary'))
                  .backgroundColor($r('app.color.bg_input'))
                  .borderRadius(6)
                  .padding({ left: 8, right: 8, top: 3, bottom: 3 })
                if (c.createdAtMs > 0) {
                  Text(TimeFormat.list(c.createdAtMs))
                    .fontSize(11)
                    .fontColor($r('app.color.text_tertiary'))
                }
                Blank()
              }
              .width('100%')

              Text(c.assertion)
                .fontSize(15)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.text_primary'))
                .width('100%')
                .lineHeight(22)
              if (c.verbatimQuote !== '') {
                Text(`“${c.verbatimQuote}”`)
                  .fontSize(12)
                  .fontColor($r('app.color.text_secondary'))
                  .width('100%')
                  .lineHeight(17)
              }
              if (c.promotionReason !== '') {
                Text(c.promotionReason)
                  .fontSize(12)
                  .fontColor($r('app.color.text_tertiary'))
                  .width('100%')
                  .maxLines(2)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
              }
              if (c.status === 'pending' || c.status === 'needs_review' || c.status === 'conflict') {
                Row({ space: 10 }) {
                  Button('采纳')
                    .fontSize(14)
                    .height(36)
                    .layoutWeight(1)
                    .borderRadius(18)
                    .backgroundColor($r('app.color.brand_light'))
                    .fontColor($r('app.color.brand'))
                    .enabled(!this.operating)
                    .onClick((): void => {
                      this.promoteCandidate(c);
                    })
                  Button('拒绝')
                    .fontSize(14)
                    .height(36)
                    .layoutWeight(1)
                    .borderRadius(18)
                    .backgroundColor($r('app.color.bg_input'))
                    .fontColor($r('app.color.text_secondary'))
                    .enabled(!this.operating)
                    .onClick((): void => {
                      this.rejectCandidate(c);
                    })
                }
                .width('100%')
                .margin({ top: 2 })
              }
            }
            .width('100%')
            .padding({ left: 14, right: 14, top: 14, bottom: 14 })
            .borderRadius(16)
            .backgroundColor($r('app.color.bg_card'))
          }
        }, (c: MemoryCandidateModel) => c.id + c.status)
      }
      .width('100%')
      .padding({ left: 14, right: 14, top: 4, bottom: 12 })
      .scrollBar(BarState.Off)
    }
    .layoutWeight(1)
    .width('100%')
    .margin({ top: 10 })
    .onRefreshing((): void => {
      this.loadCandidates();
    })
  }

  @Builder
  dailyBody() {
    Refresh({ refreshing: $$this.refreshing }) {
      List({ space: 12 }) {
        if (this.dailyFiles.length === 0) {
          ListItem() {
            EmptyView({
              title: '暂无日积月累',
              subtitle: '专家每天会把当日的记忆整理成日记',
              icon: $r('sys.symbol.doc_text')
            })
          }
        }
        ForEach(this.dailyFiles, (f: MemoryDailyFileModel) => {
          ListItem() {
            Row({ space: 12 }) {
              Column() {
                SymbolGlyph($r('sys.symbol.doc_text'))
                  .fontSize(20)
                  .fontColor([$r('app.color.brand')])
              }
              .width(42)
              .height(42)
              .borderRadius(13)
              .backgroundColor($r('app.color.brand_light'))
              .justifyContent(FlexAlign.Center)

              Column({ space: 4 }) {
                Text(f.date)
                  .fontSize(15)
                  .fontWeight(FontWeight.Medium)
                  .fontColor($r('app.color.text_primary'))
                if (f.size > 0) {
                  Text(`${Math.max(1, Math.round(f.size / 1024))} KB`)
                    .fontSize(12)
                    .fontColor($r('app.color.text_tertiary'))
                }
              }
              .layoutWeight(1)
              .alignItems(HorizontalAlign.Start)

              SymbolGlyph($r('sys.symbol.chevron_right'))
                .fontSize(13)
                .fontColor([$r('app.color.icon_secondary')])
            }
            .width('100%')
            .padding({ left: 14, right: 14, top: 12, bottom: 12 })
            .borderRadius(16)
            .backgroundColor($r('app.color.bg_card'))
            .onClick((): void => {
              this.openDaily(f);
            })
            .gesture(
              LongPressGesture()
                .onAction((event: GestureEvent): void => {
                  this.deleteDaily(f);
                })
            )
          }
        }, (f: MemoryDailyFileModel) => f.filename)
      }
      .width('100%')
      .padding({ left: 14, right: 14, top: 4, bottom: 12 })
      .scrollBar(BarState.Off)
    }
    .layoutWeight(1)
    .width('100%')
    .margin({ top: 10 })
    .onRefreshing((): void => {
      this.loadDaily();
    })
  }

  @Builder
  docsBody() {
    List({ space: 12 }) {
      ListItem() {
        Column({ space: 10 }) {
          Row({ space: 8 }) {
            SymbolGlyph($r('sys.symbol.lock'))
              .fontSize(16)
              .fontColor([$r('app.color.brand')])
            Text('MEMORY.md · 强记忆')
              .fontSize(15)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.text_primary'))
              .layoutWeight(1)
            SymbolGlyph($r('sys.symbol.chevron_right'))
              .fontSize(13)
              .fontColor([$r('app.color.icon_secondary')])
          }
          .width('100%')
          Text(this.strongDoc === null ? '' :
            (this.strongDoc.exists && this.strongDoc.content !== ''
              ? this.strongDoc.content : '（尚未创建；新建会话会整篇加载给专家）'))
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))
            .maxLines(4)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
            .lineHeight(18)
        }
        .width('100%')
        .padding({ left: 14, right: 14, top: 14, bottom: 14 })
        .borderRadius(16)
        .backgroundColor($r('app.color.bg_card'))
        .onClick((): void => {
          this.editDoc('strong');
        })
      }

      ListItem() {
        Column({ space: 10 }) {
          Row({ space: 8 }) {
            SymbolGlyph($r('sys.symbol.person'))
              .fontSize(16)
              .fontColor([$r('app.color.brand')])
            Text('USER.md · 用户画像')
              .fontSize(15)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.text_primary'))
              .layoutWeight(1)
            SymbolGlyph($r('sys.symbol.chevron_right'))
              .fontSize(13)
              .fontColor([$r('app.color.icon_secondary')])
          }
          .width('100%')
          Text(this.userDoc === null ? '' :
            (this.userDoc.exists && this.userDoc.content !== ''
              ? this.userDoc.content : '（尚未创建；写在这里的关于你的信息，专家每次新会话都会优先读取）'))
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))
            .maxLines(4)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
            .lineHeight(18)
        }
        .width('100%')
        .padding({ left: 14, right: 14, top: 14, bottom: 14 })
        .borderRadius(16)
        .backgroundColor($r('app.color.bg_card'))
        .onClick((): void => {
          this.editDoc('user');
        })
      }

      ListItem() {
        Button(this.operating ? '核对中...' : '与普通记忆核对（冲突生成待审核候选）')
          .fontSize(14)
          .height(44)
          .width('100%')
          .borderRadius(14)
          .backgroundColor($r('app.color.bg_card'))
          .fontColor($r('app.color.brand'))
          .border({ width: 1, color: $r('app.color.divider') })
          .enabled(!this.operating)
          .onClick((): void => {
            this.runManualReview();
          })
      }
    }
    .width('100%')
    .padding({ left: 14, right: 14, top: 10, bottom: 12 })
    .scrollBar(BarState.Off)
    .layoutWeight(1)
  }

  @Builder
  terminalBody() {
    Refresh({ refreshing: $$this.refreshing }) {
      List({ space: 12 }) {
        ListItem() {
          Text('这里是专家记忆的公开视图 —— 专家就是这样理解你的。')
            .fontSize(12)
            .fontColor($r('app.color.text_tertiary'))
            .width('100%')
        }

        this.terminalSection('关于你', this.terminalAbout, $r('sys.symbol.person'))
        this.terminalSection('当前关注', this.terminalFocus, $r('sys.symbol.timer'))
        this.terminalSection('你告诉过我', this.terminalTold, $r('sys.symbol.message'))

        ListItem() {
          Column({ space: 10 }) {
            Row({ space: 8 }) {
              SymbolGlyph($r('sys.symbol.book'))
                .fontSize(16)
                .fontColor([$r('app.color.brand')])
              Text('近期故事')
                .fontSize(15)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.text_primary'))
            }
            .width('100%')
            if (this.terminalStories.length === 0) {
              Text('暂无情景记录')
                .fontSize(13)
                .fontColor($r('app.color.text_tertiary'))
            }
            ForEach(this.terminalStories, (ep: MemoryEpisodeModel) => {
              Column({ space: 5 }) {
                Text(ep.summary)
                  .fontSize(14)
                  .fontColor($r('app.color.text_primary'))
                  .width('100%')
                  .lineHeight(20)
                Row({ space: 8 }) {
                  if (ep.emotion !== '') {
                    Text(ep.emotion)
                      .fontSize(11)
                      .fontColor($r('app.color.text_secondary'))
                      .backgroundColor($r('app.color.bg_input'))
                      .borderRadius(6)
                      .padding({ left: 8, right: 8, top: 3, bottom: 3 })
                  }
                  if (ep.occurredAtMs > 0) {
                    Text(TimeFormat.list(ep.occurredAtMs))
                      .fontSize(11)
                      .fontColor($r('app.color.text_tertiary'))
                  }
                  Blank()
                }
                .width('100%')
              }
              .width('100%')
              .padding(10)
              .borderRadius(12)
              .backgroundColor($r('app.color.bg_input'))
            }, (ep: MemoryEpisodeModel) => ep.id)
          }
          .width('100%')
          .padding({ left: 14, right: 14, top: 14, bottom: 14 })
          .borderRadius(16)
          .backgroundColor($r('app.color.bg_card'))
        }

        ListItem() {
          Column({ space: 10 }) {
            Row({ space: 8 }) {
              SymbolGlyph($r('sys.symbol.book'))
                .fontSize(16)
                .fontColor([$r('app.color.brand')])
              Text('人物与事物')
                .fontSize(15)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.text_primary'))
            }
            .width('100%')
            if (this.terminalEntities.length === 0) {
              Text('暂无实体')
                .fontSize(13)
                .fontColor($r('app.color.text_tertiary'))
            }
            ForEach(this.terminalEntities, (en: MemoryEntityModel) => {
              Row({ space: 8 }) {
                Text(en.canonicalName)
                  .fontSize(14)
                  .fontColor($r('app.color.text_primary'))
                  .layoutWeight(1)
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                Text(`${en.atomCount} 条记忆`)
                  .fontSize(11)
                  .fontColor($r('app.color.text_tertiary'))
              }
              .width('100%')
              .padding({ left: 10, right: 10, top: 8, bottom: 8 })
              .borderRadius(12)
              .backgroundColor($r('app.color.bg_input'))
            }, (en: MemoryEntityModel) => en.id)
          }
          .width('100%')
          .padding({ left: 14, right: 14, top: 14, bottom: 14 })
          .borderRadius(16)
          .backgroundColor($r('app.color.bg_card'))
        }
      }
      .width('100%')
      .padding({ left: 14, right: 14, top: 4, bottom: 12 })
      .scrollBar(BarState.Off)
    }
    .layoutWeight(1)
    .width('100%')
    .onRefreshing((): void => {
      this.loadTerminal();
    })
  }

  @Builder
  terminalSection(title: string, items: Array<MemoryAtomModel>, icon: Resource) {
    ListItem() {
      Column({ space: 10 }) {
        Row({ space: 8 }) {
          SymbolGlyph(icon)
            .fontSize(16)
            .fontColor([$r('app.color.brand')])
          Text(title)
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary'))
        }
        .width('100%')
        if (items.length === 0) {
          Text('暂无')
            .fontSize(13)
            .fontColor($r('app.color.text_tertiary'))
        }
        ForEach(items, (atom: MemoryAtomModel) => {
          Text(atom.assertion)
            .fontSize(14)
            .fontColor($r('app.color.text_primary'))
            .width('100%')
            .lineHeight(20)
            .padding({ left: 10, right: 10, top: 8, bottom: 8 })
            .borderRadius(12)
            .backgroundColor($r('app.color.bg_input'))
        }, (atom: MemoryAtomModel) => atom.id)
      }
      .width('100%')
      .padding({ left: 14, right: 14, top: 14, bottom: 14 })
      .borderRadius(16)
      .backgroundColor($r('app.color.bg_card'))
    }
  }

  @Builder
  dailyViewBuilder() {
    Column({ space: 12 }) {
      Row() {
        Text(this.dailyViewDate === '' ? '日积月累' : this.dailyViewDate)
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)
        Button('删除')
          .fontSize(13)
          .height(32)
          .borderRadius(16)
          .backgroundColor($r('app.color.danger_soft'))
          .fontColor($r('app.color.danger'))
          .onClick((): void => {
            this.dailyViewOpen = false;
            const target: string = this.dailyViewFilename;
            for (const f of this.dailyFiles) {
              if (f.filename === target) {
                this.deleteDaily(f);
                break;
              }
            }
          })
      }
      .width('100%')

      Scroll() {
        Text(this.dailyViewContent === '' ? '（空）' : this.dailyViewContent)
          .fontSize(14)
          .fontColor($r('app.color.text_primary'))
          .width('100%')
          .lineHeight(22)
      }
      .layoutWeight(1)
      .width('100%')
      .scrollBar(BarState.Auto)
    }
    .width('100%')
    .height('70%')
    .padding({ left: 16, right: 16, top: 12, bottom: 16 })
  }
}

/** 新建/编辑记忆对话框（编辑走 replace，仅支持修改内容） */
@CustomDialog
struct MemoryAtomEditDialog {
  controller?: CustomDialogController;
  agentId: string = '';
  atomId: string = '';
  initialAssertion: string = '';
  onSaved: () => void = (): void => {
  };
  @State assertionText: string = '';
  @State entityNameText: string = '';
  @State kindIndex: number = 0;
  @State importanceIndex: number = 1;
  @State submitting: boolean = false;

  aboutToAppear(): void {
    this.assertionText = this.initialAssertion;
  }

  private isCreate(): boolean {
    return this.atomId === '';
  }

  private kindOptions(): Array<SelectOption> {
    const options: Array<SelectOption> = [
      { value: '事实 (Fact)' },
      { value: '决策 (Decision)' },
      { value: '任务 (Task)' },
      { value: '偏好 (Preference)' }
    ];
    return options;
  }

  private kindLabel(): string {
    const labels: Array<string> = ['事实 (Fact)', '决策 (Decision)', '任务 (Task)', '偏好 (Preference)'];
    return labels[this.kindIndex];
  }

  private kindValue(): string {
    const values: Array<string> = ['Fact', 'Decision', 'Task', 'Preference'];
    return values[this.kindIndex];
  }

  private importanceOptions(): Array<SelectOption> {
    const options: Array<SelectOption> = [
      { value: '低' },
      { value: '中' },
      { value: '高' }
    ];
    return options;
  }

  private importanceLabel(): string {
    const labels: Array<string> = ['低', '中', '高'];
    return labels[this.importanceIndex];
  }

  private importanceValue(): string {
    const values: Array<string> = ['low', 'medium', 'high'];
    return values[this.importanceIndex];
  }

  private async submit(): Promise<void> {
    if (this.submitting) {
      return;
    }
    const assertion: string = this.assertionText.trim();
    if (assertion === '') {
      this.getUIContext().getPromptAction().showToast({ message: '请填写记忆内容' });
      return;
    }
    this.submitting = true;
    try {
      if (this.isCreate()) {
        await MemoryService.createAtom(this.agentId, assertion, this.kindValue(),
          this.importanceValue(), this.entityNameText.trim());
        this.controller?.close();
        this.getUIContext().getPromptAction().showToast({ message: '记忆已创建' });
      } else {
        await MemoryService.replaceAtom(this.agentId, this.atomId, assertion);
        this.controller?.close();
        this.getUIContext().getPromptAction().showToast({ message: '记忆已更新' });
      }
      this.onSaved();
    } catch (e) {
      const message: string = e instanceof OctopApiError ?
        e.message : (this.isCreate() ? '创建失败' : '更新失败');
      this.getUIContext().getPromptAction().showToast({ message });
    } finally {
      this.submitting = false;
    }
  }

  build() {
    Column({ space: 14 }) {
      Text(this.isCreate() ? '新增记忆' : '编辑记忆')
        .fontSize(17)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .width('100%')
        .textAlign(TextAlign.Start)

      TextArea({
        text: this.assertionText,
        placeholder: '记忆内容，如：用户偏好简洁的回答风格'
      })
        .fontSize(14)
        .backgroundColor($r('app.color.bg_input'))
        .borderRadius(12)
        .constraintSize({ minHeight: 84 })
        .width('100%')
        .onChange((value: string): void => {
          this.assertionText = value;
        })

      if (this.isCreate()) {
        TextInput({
          text: this.entityNameText,
          placeholder: '关联主题（可选，如：工作习惯）'
        })
          .fontSize(14)
          .height(42)
          .backgroundColor($r('app.color.bg_input'))
          .borderRadius(12)
          .width('100%')
          .onChange((value: string): void => {
            this.entityNameText = value;
          })

        Select(this.kindOptions())
          .selected(this.kindIndex)
          .value(this.kindLabel())
          .fontColor($r('app.color.text_primary'))
          .font({ size: 14 })
          .backgroundColor($r('app.color.bg_input'))
          .borderRadius(12)
          .width('100%')
          .onSelect((index: number): void => {
            this.kindIndex = index;
          })

        Select(this.importanceOptions())
          .selected(this.importanceIndex)
          .value(this.importanceLabel())
          .fontColor($r('app.color.text_primary'))
          .font({ size: 14 })
          .backgroundColor($r('app.color.bg_input'))
          .borderRadius(12)
          .width('100%')
          .onSelect((index: number): void => {
            this.importanceIndex = index;
          })
      }

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
        Button(this.submitting ? '保存中...' : '保存')
          .fontSize(14)
          .height(38)
          .layoutWeight(1)
          .borderRadius(19)
          .backgroundColor($r('app.color.brand'))
          .fontColor($r('app.color.text_on_brand'))
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

/** 用户偏好编辑对话框（语言 / 时区 / 首选模型） */
@CustomDialog
struct MemoryPrefsDialog {
  controller?: CustomDialogController;
  initialLocale: string = 'zh';
  initialTimezone: string = '';
  initialPreferredModel: string = '';
  onSaved: () => void = (): void => {
  };
  @State localeIndex: number = 0;
  @State timezoneText: string = '';
  @State modelText: string = '';
  @State submitting: boolean = false;

  aboutToAppear(): void {
    this.localeIndex = this.initialLocale === 'en' ? 1 : 0;
    this.timezoneText = this.initialTimezone;
    this.modelText = this.initialPreferredModel;
  }

  private localeOptions(): Array<SelectOption> {
    const options: Array<SelectOption> = [
      { value: '中文' },
      { value: 'English' }
    ];
    return options;
  }

  private localeLabel(): string {
    return this.localeIndex === 1 ? 'English' : '中文';
  }

  private localeValue(): string {
    return this.localeIndex === 1 ? 'en' : 'zh';
  }

  private async submit(): Promise<void> {
    if (this.submitting) {
      return;
    }
    const locale: string = this.localeValue();
    const timezone: string = this.timezoneText.trim();
    const model: string = this.modelText.trim();
    if (locale === this.initialLocale && timezone === this.initialTimezone && model === this.initialPreferredModel) {
      this.getUIContext().getPromptAction().showToast({ message: '偏好未变化' });
      return;
    }
    this.submitting = true;
    try {
      await PreferencesService.patch(locale, timezone, model);
      this.controller?.close();
      this.getUIContext().getPromptAction().showToast({ message: '偏好已保存' });
      this.onSaved();
    } catch (e) {
      const message: string = e instanceof OctopApiError ? e.message : '保存失败';
      this.getUIContext().getPromptAction().showToast({ message });
    } finally {
      this.submitting = false;
    }
  }

  build() {
    Column({ space: 14 }) {
      Text('用户偏好')
        .fontSize(17)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .width('100%')
        .textAlign(TextAlign.Start)

      Select(this.localeOptions())
        .selected(this.localeIndex)
        .value(this.localeLabel())
        .fontColor($r('app.color.text_primary'))
        .font({ size: 14 })
        .backgroundColor($r('app.color.bg_input'))
        .borderRadius(12)
        .width('100%')
        .onSelect((index: number): void => {
          this.localeIndex = index;
        })

      TextInput({
        text: this.timezoneText,
        placeholder: 'IANA 时区，如 Asia/Shanghai（留空清除）'
      })
        .fontSize(14)
        .height(42)
        .backgroundColor($r('app.color.bg_input'))
        .borderRadius(12)
        .width('100%')
        .onChange((value: string): void => {
          this.timezoneText = value;
        })

      TextInput({
        text: this.modelText,
        placeholder: '首选模型 provider/model（可选）'
      })
        .fontSize(14)
        .height(42)
        .backgroundColor($r('app.color.bg_input'))
        .borderRadius(12)
        .width('100%')
        .onChange((value: string): void => {
          this.modelText = value;
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
        Button(this.submitting ? '保存中...' : '保存')
          .fontSize(14)
          .height(38)
          .layoutWeight(1)
          .borderRadius(19)
          .backgroundColor($r('app.color.brand'))
          .fontColor($r('app.color.text_on_brand'))
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

/** MEMORY.md / USER.md 编辑对话框（多行 TextArea + 保存回调） */
@CustomDialog
struct MemoryDocEditDialog {
  controller?: CustomDialogController;
  title: string = '';
  initialContent: string = '';
  onSave: (content: string) => Promise<void> = (content: string): Promise<void> => {
    return Promise.resolve();
  };
  onSaved: () => void = (): void => {
  };
  @State contentText: string = '';
  @State submitting: boolean = false;
  @State errorMsg: string = '';

  aboutToAppear(): void {
    this.contentText = this.initialContent;
  }

  private cancel(): void {
    this.controller?.close();
  }

  private async submit(): Promise<void> {
    if (this.submitting) {
      return;
    }
    this.submitting = true;
    this.errorMsg = '';
    try {
      await this.onSave(this.contentText);
      this.controller?.close();
      this.onSaved();
    } catch (e) {
      this.errorMsg = e instanceof OctopApiError ? e.message : '保存失败';
    } finally {
      this.submitting = false;
    }
  }

  build() {
    Column({ space: 14 }) {
      Text(this.title)
        .fontSize(17)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .width('100%')
        .textAlign(TextAlign.Start)

      TextArea({ text: this.contentText, placeholder: '支持 Markdown；保存后对新会话生效' })
        .fontSize(14)
        .height(300)
        .backgroundColor($r('app.color.bg_input'))
        .borderRadius(12)
        .padding(12)
        .onChange((value: string): void => {
          this.contentText = value;
        })

      if (this.errorMsg !== '') {
        Text(this.errorMsg)
          .fontSize(12)
          .fontColor($r('app.color.danger'))
          .width('100%')
      }

      Row({ space: 12 }) {
        Button($r('app.string.common_cancel'))
          .fontSize(14)
          .height(38)
          .layoutWeight(1)
          .borderRadius(19)
          .backgroundColor($r('app.color.bg_input'))
          .fontColor($r('app.color.text_secondary'))
          .onClick((): void => {
            this.cancel();
          })
        Button(this.submitting ? '保存中...' : '保存')
          .fontSize(14)
          .height(38)
          .layoutWeight(1)
          .borderRadius(19)
          .linearGradient({
            angle: 140,
            colors: [[$r('app.color.brand_grad_start'), 0], [$r('app.color.brand_grad_end'), 1]]
          })
          .fontColor($r('app.color.text_on_brand'))
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
