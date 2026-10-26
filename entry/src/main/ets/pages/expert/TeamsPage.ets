import { AgentModel } from '../../model/AgentModels';
import { TeamModel } from '../../model/WorkspaceModels';
import { AgentService } from '../../service/AgentService';
import { TeamService } from '../../service/WorkspaceService';
import { OctopApiError } from '../../net/HttpClient';
import { EmptyView } from '../../components/EmptyView';
import { ErrorRetry } from '../../components/ErrorRetry';
import { ModelPickerSheet } from '../../components/ModelPickerSheet';
import { PageHeader } from '../../components/PageHeader';
import { UiMaterialKit } from '../../components/UiMaterialKit';

/** 我的团队：列表 / 创建 / 编辑 / 删除（成员至少 2 位专家） */
@Component
export struct TeamsPage {
  @State teams: Array<TeamModel> = [];
  @State loading: boolean = true;
  @State refreshing: boolean = false;
  @State errorMsg: string = '';
  @State operating: boolean = false;
  @State sheetOpen: boolean = false;
  @State saving: boolean = false;
  @State nameText: string = '';
  @State descText: string = '';
  @State modelText: string = '';
  @State candidates: Array<AgentModel> = [];
  @State selectedIds: Array<string> = [];
  @State candidatesLoading: boolean = false;
  @State modelSheetOpen: boolean = false;
  private pathStack: NavPathStack | null = null;
  private editingTeam: TeamModel | null = null;

  private onNavReady(ctx: NavDestinationContext): void {
    this.pathStack = ctx.pathStack;
    this.load();
  }

  private async load(): Promise<void> {
    this.loading = this.teams.length === 0;
    this.errorMsg = '';
    try {
      this.teams = await TeamService.list();
    } catch (e) {
      this.errorMsg = e instanceof OctopApiError ? e.message : '团队列表加载失败';
    } finally {
      this.loading = false;
      this.refreshing = false;
    }
  }

  /** 候选成员：自己的 + 共享的专家（排除团队） */
  private async loadCandidates(): Promise<void> {
    this.candidatesLoading = true;
    try {
      const all: Array<AgentModel> = await AgentService.listMine();
      const result: Array<AgentModel> = [];
      for (const agent of all) {
        if (agent.kind !== 'team') {
          result.push(agent);
        }
      }
      this.candidates = result;
    } catch (e) {
      this.candidates = [];
    }
    this.candidatesLoading = false;
  }

  private openCreateSheet(): void {
    this.editingTeam = null;
    this.nameText = '';
    this.descText = '';
    this.modelText = '';
    this.selectedIds = [];
    this.sheetOpen = true;
    this.loadCandidates();
  }

  private openEditSheet(team: TeamModel): void {
    this.editingTeam = team;
    this.nameText = team.name;
    this.descText = team.description;
    this.modelText = team.defaultModel;
    this.selectedIds = team.memberIds.slice(0);
    this.sheetOpen = true;
    this.loadCandidates();
  }

  private toggleMember(agentId: string): void {
    const idx: number = this.selectedIds.indexOf(agentId);
    if (idx >= 0) {
      this.selectedIds.splice(idx, 1);
    } else {
      this.selectedIds.push(agentId);
    }
  }

  private async saveTeam(): Promise<void> {
    if (this.saving) {
      return;
    }
    const name: string = this.nameText.trim();
    if (name === '') {
      this.getUIContext().getPromptAction().showToast({ message: '请填写团队名称' });
      return;
    }
    if (this.selectedIds.length < 2) {
      this.getUIContext().getPromptAction().showToast({ message: '团队至少需要 2 位成员' });
      return;
    }
    this.saving = true;
    try {
      const body: Record<string, Object> = {
        'name': name,
        'member_ids': this.selectedIds.slice(0)
      };
      if (this.descText.trim() !== '') {
        body['description'] = this.descText.trim();
      }
      if (this.modelText !== '') {
        body['default_model'] = this.modelText;
      }
      if (this.editingTeam === null) {
        await TeamService.create(JSON.stringify(body));
      } else {
        await TeamService.patch(this.editingTeam.teamId, JSON.stringify(body));
      }
      this.sheetOpen = false;
      this.getUIContext().getPromptAction().showToast({
        message: this.editingTeam === null ? '团队已创建' : '团队已更新'
      });
      this.load();
    } catch (e) {
      const message: string = e instanceof OctopApiError ? e.message : '保存失败';
      this.getUIContext().getPromptAction().showToast({ message });
    }
    this.saving = false;
  }

  private showTeamMenu(team: TeamModel): void {
    this.getUIContext().showActionSheet({
      title: team.name,
      message: '选择要执行的操作',
      sheets: [
        {
          title: '编辑团队',
          action: (): void => {
            this.openEditSheet(team);
          }
        },
        {
          title: '删除团队',
          action: (): void => {
            this.confirmDelete(team);
          }
        }
      ]
    });
  }

  private confirmDelete(team: TeamModel): void {
    this.getUIContext().showAlertDialog({
      title: '删除团队',
      message: `删除「${team.name}」后不可恢复，确定删除吗？`,
      primaryButton: {
        value: $r('app.string.common_cancel'),
        action: (): void => {
        }
      },
      secondaryButton: {
        value: $r('app.string.common_confirm'),
        action: (): void => {
          this.deleteTeam(team);
        }
      },
      alignment: DialogAlignment.Bottom
    });
  }

  private async deleteTeam(team: TeamModel): Promise<void> {
    if (this.operating) {
      return;
    }
    this.operating = true;
    try {
      await TeamService.remove(team.teamId);
      await this.load();
    } catch (e) {
      const message: string = e instanceof OctopApiError ? e.message : '删除失败';
      this.getUIContext().getPromptAction().showToast({ message });
    } finally {
      this.operating = false;
    }
  }

  @Builder
  private teamSheetBuilder() {
    Column({ space: 12 }) {
      Text(this.editingTeam === null ? '创建团队' : '编辑团队')
        .fontSize(17)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .width('100%')
      TextInput({ text: this.nameText, placeholder: '团队名称' })
        .fontSize(14)
        .height(42)
        .backgroundColor($r('app.color.bg_input'))
        .borderRadius(12)
        .onChange((value: string): void => {
          this.nameText = value;
        })
      TextArea({ text: this.descText, placeholder: '团队描述（可选）' })
        .fontSize(14)
        .height(60)
        .backgroundColor($r('app.color.bg_input'))
        .borderRadius(12)
        .onChange((value: string): void => {
          this.descText = value;
        })
      Row({ space: 8 }) {
        Text('默认模型')
          .fontSize(13)
          .fontColor($r('app.color.text_secondary'))
        Blank()
        Text(this.modelText === '' ? '自动' : this.modelText)
          .fontSize(13)
          .fontColor(this.modelText === '' ? $r('app.color.text_tertiary') : $r('app.color.text_primary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .constraintSize({ maxWidth: '60%' })
        SymbolGlyph($r('sys.symbol.chevron_right'))
          .fontSize(13)
          .fontColor([$r('app.color.text_tertiary')])
      }
      .width('100%')
      .height(42)
      .padding({ left: 12, right: 12 })
      .backgroundColor($r('app.color.bg_input'))
      .borderRadius(12)
      .onClick((): void => {
        this.modelSheetOpen = true;
      })
      .bindSheet($$this.modelSheetOpen, this.modelSheetBuilder, {
        detents: [SheetSize.MEDIUM, SheetSize.LARGE],
        showClose: true
      })

      Column({ space: 6 }) {
        Row() {
          Text(`选择成员（已选 ${this.selectedIds.length} 位，至少 2 位）`)
            .fontSize(13)
            .fontColor($r('app.color.text_secondary'))
          Blank()
          if (this.candidatesLoading) {
            LoadingProgress()
              .width(16)
              .height(16)
              .color($r('app.color.text_tertiary'))
          }
        }
        .width('100%')
        Scroll() {
          Column({ space: 6 }) {
            ForEach(this.candidates, (agent: AgentModel) => {
              Row({ space: 10 }) {
                if (this.selectedIds.indexOf(agent.agentId) >= 0) {
                  SymbolGlyph($r('sys.symbol.checkmark'))
                    .fontSize(18)
                    .fontColor([$r('app.color.brand')])
                } else {
                  Circle()
                    .width(16)
                    .height(16)
                    .fill(Color.Transparent)
                    .stroke($r('app.color.text_tertiary'))
                    .strokeWidth(1.5)
                }
                Text(agent.name)
                  .fontSize(14)
                  .fontColor($r('app.color.text_primary'))
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .layoutWeight(1)
                if (agent.state === 'running') {
                  Circle()
                    .width(6)
                    .height(6)
                    .fill($r('app.color.success'))
                }
              }
              .width('100%')
              .padding({ left: 12, right: 12, top: 10, bottom: 10 })
              .borderRadius(12)
              .backgroundColor($r('app.color.bg_input'))
              .onClick((): void => {
                this.toggleMember(agent.agentId);
              })
            }, (agent: AgentModel) => `${agent.agentId}_${this.selectedIds.indexOf(agent.agentId) >= 0}`)
          }
          .width('100%')
        }
        .align(Alignment.Top)
        .constraintSize({ maxHeight: 260 })
        .scrollBar(BarState.Auto)
      }
      .width('100%')

      Button(this.saving ? '保存中…' : '保存')
        .fontSize(15)
        .fontWeight(FontWeight.Bold)
        .height(44)
        .width('100%')
        .borderRadius(22)
        .backgroundColor($r('app.color.brand'))
        .fontColor($r('app.color.text_on_brand'))
        .enabled(!this.saving)
        .onClick((): void => {
          this.saveTeam();
        })
    }
    .padding({ left: 18, right: 18, top: 18, bottom: 30 })
    .width('100%')
  }

  @Builder
  private modelSheetBuilder() {
    ModelPickerSheet({
      allowAuto: true,
      onPick: (ref: string, label: string): void => {
        this.modelText = ref;
        this.modelSheetOpen = false;
      }
    })
  }

  build() {
    NavDestination() {
      Stack({ alignContent: Alignment.BottomEnd }) {
        Column() {
          PageHeader({ title: '我的团队' })

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
          } else if (this.teams.length === 0) {
            Column() {
              EmptyView({
                title: '暂无团队',
                subtitle: '点击右下角按钮，组合多位专家创建团队',
                icon: $r('sys.symbol.person')
              })
            }
            .layoutWeight(1)
            .width('100%')
            .justifyContent(FlexAlign.Center)
          } else {
            Refresh({ refreshing: $$this.refreshing }) {
              List({ space: 10 }) {
                ForEach(this.teams, (team: TeamModel) => {
                  ListItem() {
                    Column({ space: 6 }) {
                      Row({ space: 8 }) {
                        Text(team.name)
                          .fontSize(16)
                          .fontWeight(FontWeight.Medium)
                          .fontColor($r('app.color.text_primary'))
                          .maxLines(1)
                          .textOverflow({ overflow: TextOverflow.Ellipsis })
                        if (team.state === 'running') {
                          Circle()
                            .width(7)
                            .height(7)
                            .fill($r('app.color.success'))
                        }
                        Blank()
                        Text(`${team.members.length} 位成员`)
                          .fontSize(12)
                          .fontColor($r('app.color.text_tertiary'))
                      }
                      .width('100%')
                      if (team.description !== '') {
                        Text(team.description)
                          .fontSize(13)
                          .fontColor($r('app.color.text_secondary'))
                          .maxLines(1)
                          .textOverflow({ overflow: TextOverflow.Ellipsis })
                          .width('100%')
                      }
                      if (team.memberNames() !== '') {
                        Text(team.memberNames())
                          .fontSize(12)
                          .fontColor($r('app.color.text_tertiary'))
                          .maxLines(1)
                          .textOverflow({ overflow: TextOverflow.Ellipsis })
                          .width('100%')
                      }
                    }
                    .width('100%')
                    .alignItems(HorizontalAlign.Start)
                    .padding(14)
                    .borderRadius(16)
                    .backgroundColor($r('app.color.bg_card'))
                    .border({ width: 1, color: $r('app.color.card_stroke') })
                    .shadow({ radius: 10, color: '#0A000000', offsetY: 3 })
                    .gesture(
                      LongPressGesture()
                        .onAction((event: GestureEvent): void => {
                          this.showTeamMenu(team);
                        })
                    )
                  }
                }, (team: TeamModel) => `${team.teamId}_${team.members.length}_${team.state}`)
              }
              .width('100%')
              .height('100%')
              .padding({ left: 12, right: 12, top: 4, bottom: 90 })
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
        .bindSheet($$this.sheetOpen, this.teamSheetBuilder, {
          detents: [SheetSize.MEDIUM, SheetSize.LARGE],
          showClose: true
        })

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
          this.openCreateSheet();
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
