import { fileIo, picker } from '@kit.CoreFileKit';
import {
  HubRankingSectionModel,
  HubSkillModel,
  SkillSummaryModel
} from '../../model/SkillModels';
import { SkillService } from '../../service/SkillService';
import { OctopApiError } from '../../net/HttpClient';
import { SessionStore } from '../../store/SessionStore';
import { EmptyView } from '../../components/EmptyView';
import { ErrorRetry } from '../../components/ErrorRetry';
import { PageHeader } from '../../components/PageHeader';
import { UiMaterialKit } from '../../components/UiMaterialKit';
import { MenuSheetContent, MenuSheetOption } from '../../components/MenuSheet';

/** 新建技能对话框 */
@CustomDialog
struct SkillCreateDialog {
  controller?: CustomDialogController;
  agentId: string = '';
  onSaved: () => void = (): void => {
  };

  @State nameText: string = '';
  @State contentText: string = '';
  @State overwrite: boolean = false;
  @State submitting: boolean = false;

  private async submit(): Promise<void> {
    if (this.submitting) {
      return;
    }
    const name: string = this.nameText.trim();
    const content: string = this.contentText.trim();
    if (name === '' || content === '') {
      this.getUIContext().getPromptAction().showToast({ message: '请填写技能名与内容' });
      return;
    }
    this.submitting = true;
    try {
      await SkillService.create(this.agentId, name, content, null, this.overwrite);
      this.controller?.close();
      this.getUIContext().getPromptAction().showToast({ message: '技能已创建' });
      this.onSaved();
    } catch (e) {
      const message: string = e instanceof OctopApiError ? e.message : '创建失败';
      this.getUIContext().getPromptAction().showToast({ message });
    } finally {
      this.submitting = false;
    }
  }

  build() {
    Column({ space: 14 }) {
      Text('新建技能')
        .fontSize(17)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .width('100%')
        .textAlign(TextAlign.Start)

      Scroll() {
        Column({ space: 12 }) {
          TextInput({
            text: this.nameText,
            placeholder: '技能名，如 pdf-reader'
          })
            .fontSize(14)
            .height(42)
            .backgroundColor($r('app.color.bg_input'))
            .borderRadius(12)
            .onChange((value: string): void => {
              this.nameText = value;
            })

          TextArea({
            text: this.contentText,
            placeholder: 'SKILL.md 内容（Markdown，支持 frontmatter）'
          })
            .fontSize(13)
            .constraintSize({ minHeight: 96, maxHeight: 200 })
            .backgroundColor($r('app.color.bg_input'))
            .borderRadius(12)
            .onChange((value: string): void => {
              this.contentText = value;
            })

          Row() {
            Column({ space: 3 }) {
              Text('覆盖同名技能')
                .fontSize(14)
                .fontColor($r('app.color.text_primary'))
              Text('工作区已存在同名技能时直接替换')
                .fontSize(11)
                .fontColor($r('app.color.text_tertiary'))
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)

            Toggle({ type: ToggleType.Switch, isOn: this.overwrite })
              .onChange((isOn: boolean): void => {
                this.overwrite = isOn;
              })
          }
          .constraintSize({ minHeight: 44 })
          .width('100%')
        }
        .width('100%')
      }
      .constraintSize({ maxHeight: 420 })
      .width('100%')
      .align(Alignment.TopStart)

      Row({ space: 12 }) {
        Button($r('app.string.common_cancel'))
          .fontSize(14)
          .height(40)
          .padding({ left: 18, right: 18 })
          .borderRadius(20)
          .backgroundColor(Color.Transparent)
          .fontColor($r('app.color.text_secondary'))
          .onClick((): void => {
            this.controller?.close();
          })
        Button(this.submitting ? '创建中...' : '创建')
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .height(40)
          .padding({ left: 24, right: 24 })
          .borderRadius(20)
          .linearGradient({
            angle: 140,
            colors: [[$r('app.color.brand_grad_start'), 0], [$r('app.color.brand_grad_end'), 1]]
          })
          .shadow({ radius: 10, color: '#260A59F7', offsetY: 4 })
          .fontColor($r('app.color.text_on_brand'))
          .enabled(!this.submitting)
          .onClick((): void => {
            this.submit();
          })
      }
      .width('100%')
      .justifyContent(FlexAlign.End)
    }
    .padding(22)
    .width('100%')
  }
}

/** 编辑技能对话框（仅 workspace 技能） */
@CustomDialog
struct SkillEditDialog {
  controller?: CustomDialogController;
  agentId: string = '';
  slug: string = '';
  initialContent: string = '';
  onSaved: () => void = (): void => {
  };

  @State contentText: string = '';
  @State submitting: boolean = false;

  aboutToAppear(): void {
    this.contentText = this.initialContent;
  }

  private async submit(): Promise<void> {
    if (this.submitting) {
      return;
    }
    this.submitting = true;
    try {
      await SkillService.update(this.agentId, this.slug, this.contentText, null);
      this.controller?.close();
      this.getUIContext().getPromptAction().showToast({ message: '技能已保存' });
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
      Text(`编辑技能 · ${this.slug}`)
        .fontSize(17)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .width('100%')
        .textAlign(TextAlign.Start)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })

      Scroll() {
        Column() {
          TextArea({ text: this.contentText })
            .fontSize(13)
            .constraintSize({ minHeight: 160 })
            .backgroundColor($r('app.color.bg_input'))
            .borderRadius(12)
            .onChange((value: string): void => {
              this.contentText = value;
            })
        }
        .width('100%')
      }
      .constraintSize({ maxHeight: 420 })
      .width('100%')
      .align(Alignment.TopStart)

      Row({ space: 12 }) {
        Button($r('app.string.common_cancel'))
          .fontSize(14)
          .height(40)
          .padding({ left: 18, right: 18 })
          .borderRadius(20)
          .backgroundColor(Color.Transparent)
          .fontColor($r('app.color.text_secondary'))
          .onClick((): void => {
            this.controller?.close();
          })
        Button(this.submitting ? '保存中...' : '保存')
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .height(40)
          .padding({ left: 24, right: 24 })
          .borderRadius(20)
          .linearGradient({
            angle: 140,
            colors: [[$r('app.color.brand_grad_start'), 0], [$r('app.color.brand_grad_end'), 1]]
          })
          .shadow({ radius: 10, color: '#260A59F7', offsetY: 4 })
          .fontColor($r('app.color.text_on_brand'))
          .enabled(!this.submitting)
          .onClick((): void => {
            this.submit();
          })
      }
      .width('100%')
      .justifyContent(FlexAlign.End)
    }
    .padding(22)
    .width('100%')
  }
}

/** 从 URL 导入技能对话框 */
@CustomDialog
struct SkillImportDialog {
  controller?: CustomDialogController;
  agentId: string = '';
  onSaved: () => void = (): void => {
  };

  @State urlText: string = '';
  @State enableAfter: boolean = true;
  @State overwrite: boolean = false;
  @State submitting: boolean = false;

  private async submit(): Promise<void> {
    if (this.submitting) {
      return;
    }
    const url: string = this.urlText.trim();
    if (url === '') {
      this.getUIContext().getPromptAction().showToast({ message: '请填写技能包 URL' });
      return;
    }
    this.submitting = true;
    try {
      await SkillService.importSkill(this.agentId, url, '', this.enableAfter, this.overwrite);
      this.controller?.close();
      this.getUIContext().getPromptAction().showToast({ message: '导入成功' });
      this.onSaved();
    } catch (e) {
      const message: string = e instanceof OctopApiError ? e.message : '导入失败';
      this.getUIContext().getPromptAction().showToast({ message });
    } finally {
      this.submitting = false;
    }
  }

  build() {
    Column({ space: 14 }) {
      Text('从 URL 导入技能')
        .fontSize(17)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .width('100%')
        .textAlign(TextAlign.Start)

      Scroll() {
        Column({ space: 12 }) {
          TextInput({
            text: this.urlText,
            placeholder: '技能包 bundle URL（.zip）'
          })
            .fontSize(14)
            .height(42)
            .backgroundColor($r('app.color.bg_input'))
            .borderRadius(12)
            .onChange((value: string): void => {
              this.urlText = value;
            })

          Row() {
            Text('导入后启用')
              .fontSize(14)
              .fontColor($r('app.color.text_primary'))
              .layoutWeight(1)
            Toggle({ type: ToggleType.Switch, isOn: this.enableAfter })
              .onChange((isOn: boolean): void => {
                this.enableAfter = isOn;
              })
          }
          .constraintSize({ minHeight: 44 })
          .width('100%')

          Row() {
            Text('覆盖同名技能')
              .fontSize(14)
              .fontColor($r('app.color.text_primary'))
              .layoutWeight(1)
            Toggle({ type: ToggleType.Switch, isOn: this.overwrite })
              .onChange((isOn: boolean): void => {
                this.overwrite = isOn;
              })
          }
          .constraintSize({ minHeight: 44 })
          .width('100%')
        }
        .width('100%')
      }
      .constraintSize({ maxHeight: 420 })
      .width('100%')
      .align(Alignment.TopStart)

      Row({ space: 12 }) {
        Button($r('app.string.common_cancel'))
          .fontSize(14)
          .height(40)
          .padding({ left: 18, right: 18 })
          .borderRadius(20)
          .backgroundColor(Color.Transparent)
          .fontColor($r('app.color.text_secondary'))
          .onClick((): void => {
            this.controller?.close();
          })
        Button(this.submitting ? '导入中...' : '导入')
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .height(40)
          .padding({ left: 24, right: 24 })
          .borderRadius(20)
          .linearGradient({
            angle: 140,
            colors: [[$r('app.color.brand_grad_start'), 0], [$r('app.color.brand_grad_end'), 1]]
          })
          .shadow({ radius: 10, color: '#260A59F7', offsetY: 4 })
          .fontColor($r('app.color.text_on_brand'))
          .enabled(!this.submitting)
          .onClick((): void => {
            this.submit();
          })
      }
      .width('100%')
      .justifyContent(FlexAlign.End)
    }
    .padding(22)
    .width('100%')
  }
}

/** 市场技能头像：优先渲染 SkillHub CDN 网络图（iconUrl），加载失败或为空回退通用魔法棒徽章 */
@Component
struct HubSkillIcon {
  @Prop iconUrl: string;
  @State loadFailed: boolean = false;

  build() {
    if (this.iconUrl !== '' && !this.loadFailed) {
      Image(this.iconUrl)
        .width(42)
        .height(42)
        .borderRadius(13)
        .objectFit(ImageFit.Cover)
        .onError((): void => {
          this.loadFailed = true;
        })
    } else {
      Column() {
        SymbolGlyph($r('sys.symbol.wand_and_stars'))
          .fontSize(20)
          .fontColor([$r('app.color.brand')])
      }
      .width(42)
      .height(42)
      .borderRadius(13)
      .backgroundColor($r('app.color.brand_light'))
      .justifyContent(FlexAlign.Center)
    }
  }
}

/** 技能管理：我的技能 + 技能市场（当前专家） */
@Component
export struct SkillsPage {
  @State skills: Array<SkillSummaryModel> = [];
  @State hubResults: Array<HubSkillModel> = [];
  @State loading: boolean = true;
  @State refreshing: boolean = false;
  @State errorMsg: string = '';
  @State operating: boolean = false;
  @State segIndex: number = 0;
  @State hubQuery: string = '';
  @State hubSearching: boolean = false;
  @State hubSearched: boolean = false;
  // 市场推荐榜单（进入市场标签自动加载，搜索后以搜索结果为准）
  @State hubRankLoading: boolean = false;
  @State hubRankError: string = '';
  @State hubRankLoaded: boolean = false;
  @State menuOpen: boolean = false;
  @State menuTitle: string = '';
  @State menuMessage: string = '';
  @State menuOptions: Array<MenuSheetOption> = [];
  private menuActions: Array<() => void> = [];
  private agentId: string = '';
  private pathStack: NavPathStack | null = null;
  private dialogController: CustomDialogController | null = null;

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
      this.skills = await SkillService.list(this.agentId);
    } catch (e) {
      this.errorMsg = e instanceof OctopApiError ? e.message : '技能加载失败';
    } finally {
      this.loading = false;
    }
  }

  private kindLabel(kind: string): string {
    if (kind === 'builtin') {
      return '内置';
    }
    if (kind === 'package') {
      return '技能包';
    }
    return '自定义';
  }

  private kindColor(kind: string): Resource {
    if (kind === 'builtin') {
      return $r('app.color.brand');
    }
    if (kind === 'package') {
      return $r('app.color.warning');
    }
    return $r('app.color.success');
  }

  private kindBgColor(kind: string): Resource {
    if (kind === 'builtin') {
      return $r('app.color.brand_light');
    }
    if (kind === 'package') {
      return $r('app.color.warning_soft');
    }
    return $r('app.color.success_soft');
  }

  private async toggleSkill(skill: SkillSummaryModel, on: boolean): Promise<void> {
    if (this.operating) {
      return;
    }
    this.operating = true;
    try {
      await SkillService.setEnabled(this.agentId, skill.slug, on);
      await this.load();
    } catch (e) {
      const message: string = e instanceof OctopApiError ? e.message : '操作失败';
      this.getUIContext().getPromptAction().showToast({ message });
      await this.load();
    } finally {
      this.operating = false;
    }
  }

  private showSkillMenu(skill: SkillSummaryModel): void {
    const options: Array<MenuSheetOption> = [];
    const actions: Array<() => void> = [];
    if (skill.kind === 'workspace') {
      options.push(new MenuSheetOption($r('sys.symbol.square_and_pencil'), '编辑', '修改技能内容', false));
      actions.push((): void => {
        this.showEdit(skill);
      });
    }
    options.push(new MenuSheetOption($r('sys.symbol.square_and_arrow_down'), '导出 ZIP', '', false));
    actions.push((): void => {
      this.exportSkill(skill);
    });
    if (skill.kind === 'workspace') {
      options.push(new MenuSheetOption($r('sys.symbol.trash'), '删除', '', true));
      actions.push((): void => {
        this.confirmDelete(skill);
      });
    }
    this.menuTitle = skill.displayTitle();
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

  private async showEdit(skill: SkillSummaryModel): Promise<void> {
    try {
      const detail = await SkillService.get(this.agentId, skill.slug);
      this.dialogController = new CustomDialogController({
        builder: SkillEditDialog({
          agentId: this.agentId,
          slug: skill.slug,
          initialContent: detail.raw,
          onSaved: (): void => {
            this.load();
          }
        }),
        autoCancel: true,
        systemMaterial: UiMaterialKit.sheet()
      });
      this.dialogController.open();
    } catch (e) {
      const message: string = e instanceof OctopApiError ? e.message : '加载技能详情失败';
      this.getUIContext().getPromptAction().showToast({ message });
    }
  }

  private async exportSkill(skill: SkillSummaryModel): Promise<void> {
    if (this.operating) {
      return;
    }
    this.operating = true;
    try {
      const data: ArrayBuffer = await SkillService.exportOne(this.agentId, skill.slug);
      await this.saveZipFile(`${skill.slug}.zip`, data);
    } catch (e) {
      const message: string = e instanceof OctopApiError ? e.message : '导出失败';
      this.getUIContext().getPromptAction().showToast({ message });
    } finally {
      this.operating = false;
    }
  }

  private async saveZipFile(fileName: string, data: ArrayBuffer): Promise<void> {
    const docPicker = new picker.DocumentViewPicker();
    const saveOptions = new picker.DocumentSaveOptions();
    saveOptions.newFileNames = [fileName];
    let uris: Array<string> = [];
    try {
      uris = await docPicker.save(saveOptions);
    } catch (e) {
      return;
    }
    if (uris.length === 0) {
      return;
    }
    const file = fileIo.openSync(uris[0], fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.TRUNC);
    try {
      fileIo.writeSync(file.fd, data);
    } finally {
      fileIo.closeSync(file);
    }
    this.getUIContext().getPromptAction().showToast({ message: '已保存' });
  }

  private confirmDelete(skill: SkillSummaryModel): void {
    this.getUIContext().showAlertDialog({
      title: '删除技能',
      message: `确定删除「${skill.displayTitle()}」吗？`,
      primaryButton: {
        value: $r('app.string.common_cancel'),
        action: (): void => {
        }
      },
      secondaryButton: {
        value: $r('app.string.common_confirm'),
        action: (): void => {
          this.deleteSkill(skill);
        }
      },
      alignment: DialogAlignment.Bottom
    });
  }

  private async deleteSkill(skill: SkillSummaryModel): Promise<void> {
    if (this.operating) {
      return;
    }
    this.operating = true;
    try {
      await SkillService.remove(this.agentId, skill.slug);
      this.getUIContext().getPromptAction().showToast({ message: '已删除' });
      await this.load();
    } catch (e) {
      const message: string = e instanceof OctopApiError ? e.message : '删除失败';
      this.getUIContext().getPromptAction().showToast({ message });
    } finally {
      this.operating = false;
    }
  }

  private showAddMenu(): void {
    this.menuTitle = '添加技能';
    this.menuMessage = '选择添加方式';
    this.menuOptions = [
      new MenuSheetOption($r('sys.symbol.pencil_line'), '新建技能', '在线编写技能内容', false),
      new MenuSheetOption($r('sys.symbol.link'), '从 URL 导入', '从技能包地址导入', false)
    ];
    this.menuActions = [
      (): void => {
        this.showCreate();
      },
      (): void => {
        this.showImport();
      }
    ];
    this.menuOpen = true;
  }

  private showCreate(): void {
    this.dialogController = new CustomDialogController({
      builder: SkillCreateDialog({
        agentId: this.agentId,
        onSaved: (): void => {
          this.load();
        }
      }),
      autoCancel: true,
      systemMaterial: UiMaterialKit.sheet()
    });
    this.dialogController.open();
  }

  private showImport(): void {
    this.dialogController = new CustomDialogController({
      builder: SkillImportDialog({
        agentId: this.agentId,
        onSaved: (): void => {
          this.load();
        }
      }),
      autoCancel: true,
      systemMaterial: UiMaterialKit.sheet()
    });
    this.dialogController.open();
  }

  private async searchHub(): Promise<void> {
    if (this.hubSearching) {
      return;
    }
    this.hubSearching = true;
    try {
      this.hubResults = await SkillService.hubSearch(this.agentId, this.hubQuery.trim());
      this.hubSearched = true;
    } catch (e) {
      const message: string = e instanceof OctopApiError ? e.message : '搜索失败';
      this.getUIContext().getPromptAction().showToast({ message });
    } finally {
      this.hubSearching = false;
    }
  }

  /** 加载市场推荐榜单（rankings type=recommended，单分区）；已有内容时失败仅 toast 不清列表 */
  private async loadHubRankings(): Promise<void> {
    if (this.hubRankLoading || this.agentId === '') {
      return;
    }
    this.hubRankLoading = true;
    this.hubRankError = '';
    try {
      const sections: Array<HubRankingSectionModel> =
        await SkillService.hubRankings(this.agentId, 'recommended');
      if (sections.length > 0) {
        this.hubResults = sections[0].skills;
      }
      this.hubRankLoaded = true;
    } catch (e) {
      const message: string = e instanceof OctopApiError ? e.message : '推荐榜单加载失败';
      if (this.hubResults.length === 0) {
        this.hubRankError = message;
      } else {
        this.getUIContext().getPromptAction().showToast({ message });
      }
    } finally {
      this.hubRankLoading = false;
    }
  }

  /** 进入市场标签时确保默认榜单已加载（未搜索过、未加载成功过时触发一次） */
  private ensureHubRankings(): void {
    if (this.hubSearched || this.hubRankLoaded || this.hubRankLoading) {
      return;
    }
    this.loadHubRankings();
  }

  /** 市场下拉刷新：重载当前视图（搜索结果 → 重新搜索；榜单 → 重新拉取） */
  private async refreshHubView(): Promise<void> {
    if (this.hubSearched) {
      await this.searchHub();
    } else {
      await this.loadHubRankings();
    }
    this.refreshing = false;
  }

  private async installHubSkill(skill: HubSkillModel): Promise<void> {
    if (this.operating) {
      return;
    }
    this.operating = true;
    try {
      const skillName: string = skill.name !== '' ? skill.name : skill.slug;
      await SkillService.hubInstall(this.agentId, skillName, true);
      this.getUIContext().getPromptAction().showToast({ message: '已安装' });
    } catch (e) {
      const message: string = e instanceof OctopApiError ? e.message : '安装失败';
      this.getUIContext().getPromptAction().showToast({ message });
    } finally {
      this.operating = false;
    }
  }

  @Builder
  segmentBar() {
    Row({ space: 6 }) {
      Text(`我的技能${this.skills.length > 0 ? ` (${this.skills.length})` : ''}`)
        .fontSize(13)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.segIndex === 0 ? $r('app.color.text_on_brand') : $r('app.color.text_secondary'))
        .height(32)
        .padding({ left: 14, right: 14 })
        .borderRadius(16)
        .backgroundColor(this.segIndex === 0 ? $r('app.color.brand') : $r('app.color.bg_input'))
        .onClick((): void => {
          this.segIndex = 0;
        })
      Text('技能市场')
        .fontSize(13)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.segIndex === 1 ? $r('app.color.text_on_brand') : $r('app.color.text_secondary'))
        .height(32)
        .padding({ left: 14, right: 14 })
        .borderRadius(16)
        .backgroundColor(this.segIndex === 1 ? $r('app.color.brand') : $r('app.color.bg_input'))
        .onClick((): void => {
          this.segIndex = 1;
          this.ensureHubRankings();
        })
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 10 })
  }

  @Builder
  hubSearchBar() {
    Row({ space: 8 }) {
      TextInput({
        text: this.hubQuery,
        placeholder: '搜索技能市场'
      })
        .fontSize(13)
        .height(38)
        .backgroundColor($r('app.color.bg_input'))
        .borderRadius(19)
        .padding({ left: 14, right: 14 })
        .layoutWeight(1)
        .onChange((value: string): void => {
          this.hubQuery = value;
        })
        .onSubmit((enterKey: EnterKeyType): void => {
          this.searchHub();
        })
      Button(this.hubSearching ? '搜索中' : '搜索')
        .fontSize(13)
        .height(38)
        .padding({ left: 16, right: 16 })
        .borderRadius(19)
        .backgroundColor($r('app.color.brand'))
        .fontColor($r('app.color.text_on_brand'))
        .enabled(!this.hubSearching)
        .onClick((): void => {
          this.searchHub();
        })
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 10 })
  }

  @Builder
  skillIcon(skill: SkillSummaryModel) {
    if (skill.emoji !== '') {
      Text(skill.emoji)
        .fontSize(20)
        .width(42)
        .height(42)
        .textAlign(TextAlign.Center)
    } else {
      Column() {
        SymbolGlyph($r('sys.symbol.wand_and_stars'))
          .fontSize(20)
          .fontColor([$r('app.color.brand')])
      }
      .width(42)
      .height(42)
      .borderRadius(13)
      .backgroundColor($r('app.color.brand_light'))
      .justifyContent(FlexAlign.Center)
    }
  }

  @Builder
  mineList() {
    if (this.skills.length === 0) {
      Column() {
        EmptyView({
          title: '暂无技能',
          subtitle: '点击右下角按钮添加，或到技能市场安装',
          icon: $r('sys.symbol.wand_and_stars')
        })
      }
      .layoutWeight(1)
      .width('100%')
      .justifyContent(FlexAlign.Center)
    } else {
      Refresh({ refreshing: $$this.refreshing }) {
        List({ space: 12 }) {
          ForEach(this.skills, (skill: SkillSummaryModel) => {
            ListItem() {
              Row({ space: 12 }) {
                this.skillIcon(skill)
                Column({ space: 7 }) {
                  Row() {
                    Text(skill.displayTitle())
                      .fontSize(16)
                      .fontWeight(FontWeight.Medium)
                      .fontColor(skill.enabled ? $r('app.color.text_primary') : $r('app.color.text_tertiary'))
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                      .layoutWeight(1)
                    Toggle({ type: ToggleType.Switch, isOn: skill.enabled })
                      .onChange((isOn: boolean): void => {
                        this.toggleSkill(skill, isOn);
                      })
                  }
                  .width('100%')
                  if (skill.displaySummary() !== '') {
                    Text(skill.displaySummary())
                      .fontSize(13)
                      .fontColor($r('app.color.text_secondary'))
                      .maxLines(2)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                      .width('100%')
                      .lineHeight(19)
                  }
                  Row({ space: 8 }) {
                    Text(this.kindLabel(skill.kind))
                      .fontSize(11)
                      .fontColor(this.kindColor(skill.kind))
                      .backgroundColor(this.kindBgColor(skill.kind))
                      .borderRadius(6)
                      .padding({ left: 8, right: 8, top: 3, bottom: 3 })
                    Text(skill.slug)
                      .fontSize(11)
                      .fontColor($r('app.color.text_tertiary'))
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                      .constraintSize({ maxWidth: 180 })
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
              .opacity(skill.enabled ? 1 : 0.6)
              .gesture(
                LongPressGesture()
                  .onAction((event: GestureEvent): void => {
                    this.showSkillMenu(skill);
                  })
              )
            }
          }, (skill: SkillSummaryModel) => `${skill.kind}:${skill.slug}`)
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

  @Builder
  hubList() {
    if (this.hubRankLoading && !this.hubSearched && this.hubResults.length === 0) {
      // 默认榜单首次加载
      Column() {
        LoadingProgress()
          .width(36)
          .height(36)
          .color($r('app.color.brand'))
      }
      .layoutWeight(1)
      .width('100%')
      .justifyContent(FlexAlign.Center)
    } else if (this.hubRankError !== '' && !this.hubSearched && this.hubResults.length === 0) {
      // 默认榜单加载失败：错误重试（不退回"搜索技能市场"空态）
      Column() {
        ErrorRetry({
          message: this.hubRankError,
          onRetry: (): void => {
            this.loadHubRankings();
          }
        })
      }
      .layoutWeight(1)
      .width('100%')
      .justifyContent(FlexAlign.Center)
    } else if (this.hubResults.length === 0) {
      Column() {
        EmptyView({
          title: this.hubSearched ? '没有找到匹配的技能' : '搜索技能市场',
          subtitle: this.hubSearched ? '换个关键词试试' : '输入关键词，安装社区技能',
          icon: $r('sys.symbol.magnifyingglass')
        })
      }
      .layoutWeight(1)
      .width('100%')
      .justifyContent(FlexAlign.Center)
    } else {
      Refresh({ refreshing: $$this.refreshing }) {
        List({ space: 12 }) {
          ForEach(this.hubResults, (skill: HubSkillModel) => {
            ListItem() {
              Row({ space: 12 }) {
                HubSkillIcon({ iconUrl: skill.iconUrl })
                Column({ space: 6 }) {
                  Text(skill.name !== '' ? skill.name : skill.slug)
                    .fontSize(15)
                    .fontWeight(FontWeight.Medium)
                    .fontColor($r('app.color.text_primary'))
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                    .width('100%')
                  if (skill.description !== '') {
                    Text(skill.description)
                      .fontSize(12)
                      .fontColor($r('app.color.text_secondary'))
                      .maxLines(2)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                      .width('100%')
                      .lineHeight(17)
                  }
                }
                .layoutWeight(1)
                .alignItems(HorizontalAlign.Start)
                Button('安装')
                  .fontSize(12)
                  .height(30)
                  .padding({ left: 14, right: 14 })
                  .borderRadius(15)
                  .backgroundColor($r('app.color.brand_light'))
                  .fontColor($r('app.color.brand'))
                  .onClick((): void => {
                    this.installHubSkill(skill);
                  })
              }
              .width('100%')
              .padding({ left: 14, right: 14, top: 12, bottom: 12 })
              .borderRadius(16)
              .backgroundColor($r('app.color.bg_card'))
            }
          }, (skill: HubSkillModel) => `${skill.slug}_${skill.iconUrl}`)
        }
        .width('100%')
        .height('100%')
        .padding({ left: 14, right: 14, top: 10 })
        .scrollBar(BarState.Off)
      }
      .layoutWeight(1)
      .width('100%')
      .onRefreshing((): void => {
        this.refreshHubView();
      })
    }
  }

  build() {
    NavDestination() {
      Stack({ alignContent: Alignment.BottomEnd }) {
        Column() {
          PageHeader({ title: '技能' })
          this.segmentBar()

          if (this.segIndex === 1) {
            this.hubSearchBar()
          }

          if (this.loading && this.segIndex === 0) {
            Column() {
              LoadingProgress()
                .width(36)
                .height(36)
                .color($r('app.color.brand'))
            }
            .layoutWeight(1)
            .width('100%')
            .justifyContent(FlexAlign.Center)
          } else if (this.errorMsg !== '' && this.segIndex === 0) {
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
          } else if (this.segIndex === 0) {
            this.mineList()
          } else {
            this.hubList()
          }
        }
        .width('100%')
        .height('100%')

        if (this.segIndex === 0) {
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
            this.showAddMenu();
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
