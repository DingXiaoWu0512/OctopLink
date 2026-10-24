import { AgentModel } from '../../model/AgentModels';
import { AgentService } from '../../service/AgentService';
import { OctopApiError } from '../../net/HttpClient';
import { SessionStore } from '../../store/SessionStore';
import { EmptyView } from '../../components/EmptyView';
import { ErrorRetry } from '../../components/ErrorRetry';
import { AgentEditNavParam } from './AgentEditPage';
import { UiMaterialKit } from '../../components/UiMaterialKit';

/** 专家筛选 chips 文案 */
class ExpertFilterOption {
  readonly label: string;
  readonly value: number;

  constructor(label: string, value: number) {
    this.label = label;
    this.value = value;
  }
}

/** 专家一级 Tab（Cube 助手页式布局）：大标题 + 筛选 chips + 全宽卡片（卡片内开始对话） */
@Component
export struct ExpertListPage {
  @Consume('navStack') navStack: NavPathStack;
  @Prop topInset: number = 0;
  @Prop bottomPad: number = 72;
  @StorageProp(SessionStore.KEY_AGENT_ID) currentAgentId: string = '';
  @StorageLink(SessionStore.KEY_AGENTS_DIRTY) @Watch('onDirtyChanged') agentsDirty: boolean = false;
  @State agents: Array<AgentModel> = [];
  @State loading: boolean = false;
  @State refreshing: boolean = false;
  @State errorMsg: string = '';
  @State operating: boolean = false;
  @State filterIndex: number = 0;
  @State searching: boolean = false;
  @State keyword: string = '';

  aboutToAppear(): void {
    this.load();
  }

  onDirtyChanged(): void {
    if (this.agentsDirty) {
      this.agentsDirty = false;
      this.load();
    }
  }

  private async load(): Promise<void> {
    this.loading = true;
    this.errorMsg = '';
    try {
      this.agents = await AgentService.listMine();
      if (this.currentAgentId === '' && this.agents.length > 0) {
        SessionStore.setCurrentAgent(this.agents[0]);
      }
    } catch (e) {
      this.errorMsg = e instanceof OctopApiError ? e.message : '专家列表加载失败';
    } finally {
      this.loading = false;
    }
  }

  private goCreate(): void {
    this.navStack.pushPath(new NavPathInfo('expertCreate', null));
  }

  /** 筛选 + 搜索后的可见列表 */
  private visibleAgents(): Array<AgentModel> {
    const result: Array<AgentModel> = [];
    const kw: string = this.keyword.trim().toLowerCase();
    for (const agent of this.agents) {
      if (this.filterIndex === 1 && agent.state !== 'running') {
        continue;
      }
      if (this.filterIndex === 2 && agent.state === 'running') {
        continue;
      }
      if (kw !== '' && agent.name.toLowerCase().indexOf(kw) < 0 &&
        agent.description.toLowerCase().indexOf(kw) < 0) {
        continue;
      }
      result.push(agent);
    }
    return result;
  }

  private filterOptions(): Array<ExpertFilterOption> {
    return [
      new ExpertFilterOption('全部', 0),
      new ExpertFilterOption('运行中', 1),
      new ExpertFilterOption('未运行', 2)
    ];
  }

  /** 卡片内「开始对话」：切换专家 → 新对话 → 跳聊天 Tab */
  private startChat(agent: AgentModel): void {
    if (agent.agentId !== this.currentAgentId) {
      SessionStore.setCurrentAgent(agent);
    }
    AppStorage.setOrCreate(SessionStore.KEY_ACTIVE_THREAD_ID, '');
    AppStorage.setOrCreate(SessionStore.KEY_MAIN_TAB, 1);
  }

  /** 长按专家：操作菜单（owner 可编辑/删除） */
  private showAgentMenu(agent: AgentModel): void {
    const sheets: Array<SheetInfo> = [];
    if (agent.isOwner) {
      sheets.push({
        title: '编辑专家',
        action: (): void => {
          this.navStack.pushPath(new NavPathInfo('agentEdit', new AgentEditNavParam(agent.agentId)));
        }
      });
      sheets.push({
        title: '删除专家',
        action: (): void => {
          this.confirmDeleteAgent(agent);
        }
      });
    } else {
      sheets.push({
        title: `由 @${agent.ownerUsername === '' ? '他人' : agent.ownerUsername} 共享`,
        action: (): void => {
        }
      });
    }
    this.getUIContext().showActionSheet({
      title: agent.name,
      message: '选择要执行的操作',
      sheets: sheets
    });
  }

  private confirmDeleteAgent(agent: AgentModel): void {
    this.getUIContext().showAlertDialog({
      title: '删除专家',
      message: `删除「${agent.name}」后不可恢复，确定删除吗？`,
      primaryButton: {
        value: $r('app.string.common_cancel'),
        action: (): void => {
        }
      },
      secondaryButton: {
        value: $r('app.string.common_confirm'),
        action: (): void => {
          this.deleteAgent(agent);
        }
      },
      alignment: DialogAlignment.Bottom
    });
  }

  private async deleteAgent(agent: AgentModel): Promise<void> {
    if (this.operating) {
      return;
    }
    this.operating = true;
    try {
      await AgentService.remove(agent.agentId);
      if (agent.agentId === this.currentAgentId) {
        AppStorage.setOrCreate(SessionStore.KEY_AGENT_ID, '');
        AppStorage.setOrCreate(SessionStore.KEY_AGENT_NAME, '');
        AppStorage.setOrCreate(SessionStore.KEY_AGENT_WELCOME, '');
        AppStorage.setOrCreate(SessionStore.KEY_AGENT_MODEL, '');
      }
      this.getUIContext().getPromptAction().showToast({ message: '已删除' });
      await this.load();
    } catch (e) {
      this.getUIContext().getPromptAction().showToast({
        message: e instanceof OctopApiError ? e.message : '删除失败'
      });
    } finally {
      this.operating = false;
    }
  }

  @Builder
  chipBuilder(option: ExpertFilterOption) {
    Text(option.label)
      .fontSize(13)
      .fontWeight(option.value === this.filterIndex ? FontWeight.Medium : FontWeight.Normal)
      .fontColor(option.value === this.filterIndex ? $r('app.color.brand') : $r('app.color.text_secondary'))
      .padding({ left: 14, right: 14, top: 7, bottom: 7 })
      .borderRadius(16)
      .backgroundColor(option.value === this.filterIndex ?
        $r('app.color.brand_light') : $r('app.color.bg_input'))
      .onClick((): void => {
        this.filterIndex = option.value;
      })
  }

  @Builder
  agentCard(agent: AgentModel) {
    Column({ space: 10 }) {
      Row({ space: 12 }) {
        Image($r('app.media.octop_logo'))
          .width(42)
          .height(42)
          .borderRadius(21)
          .backgroundColor($r('app.color.brand_light'))
        Column({ space: 4 }) {
          Row({ space: 6 }) {
            Text(agent.name)
              .fontSize(16)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.text_primary'))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
            if (agent.personaMbti !== '') {
              Text(agent.personaMbti)
                .fontSize(10)
                .fontColor($r('app.color.brand'))
                .backgroundColor($r('app.color.brand_light'))
                .borderRadius(5)
                .padding({ left: 6, right: 6, top: 2, bottom: 2 })
            }
            if (agent.isShared) {
              Text('共享')
                .fontSize(10)
                .fontColor($r('app.color.text_secondary'))
                .backgroundColor($r('app.color.bg_input'))
                .borderRadius(5)
                .padding({ left: 6, right: 6, top: 2, bottom: 2 })
            }
          }
          Row({ space: 5 }) {
            if (agent.state === 'running') {
              Circle()
                .width(6)
                .height(6)
                .fill($r('app.color.success'))
              Text('运行中')
                .fontSize(11)
                .fontColor($r('app.color.text_tertiary'))
            } else if (agent.state !== '') {
              Circle()
                .width(6)
                .height(6)
                .fill($r('app.color.text_tertiary'))
              Text('未运行')
                .fontSize(11)
                .fontColor($r('app.color.text_tertiary'))
            }
            if (agent.agentId === this.currentAgentId) {
              Text($r('app.string.expert_current'))
                .fontSize(11)
                .fontColor($r('app.color.brand'))
                .backgroundColor($r('app.color.brand_light'))
                .borderRadius(9)
                .padding({ left: 8, right: 8, top: 2, bottom: 2 })
            }
          }
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        if (agent.agentId !== this.currentAgentId && agent.unreadCount > 0) {
          Text(`${agent.unreadCount}`)
            .fontSize(12)
            .fontColor($r('app.color.text_on_brand'))
            .backgroundColor($r('app.color.brand'))
            .borderRadius(10)
            .constraintSize({ minWidth: 20 })
            .textAlign(TextAlign.Center)
            .padding({ left: 6, right: 6, top: 2, bottom: 2 })
        }
      }
      .width('100%')

      if (agent.description !== '') {
        Text(agent.description)
          .fontSize(13)
          .fontColor($r('app.color.text_secondary'))
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
      }

      Row() {
        Blank()
        Button({ type: ButtonType.Normal, stateEffect: true }) {
          Row({ space: 5 }) {
            SymbolGlyph($r('sys.symbol.paperplane'))
              .fontSize(13)
              .fontColor([$r('app.color.brand')])
            Text('开始对话')
              .fontSize(13)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.brand'))
          }
        }
        .height(32)
        .borderRadius(16)
        .backgroundColor($r('app.color.brand_light'))
        .systemMaterial(UiMaterialKit.button())
        .padding({ left: 14, right: 14 })
        .onClick((): void => {
          this.startChat(agent);
        })
      }
      .width('100%')
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding(14)
    .borderRadius(16)
    .backgroundColor($r('app.color.bg_card'))
    .border({ width: 1, color: $r('app.color.card_stroke') })
    .onClick((): void => {
      if (agent.agentId !== this.currentAgentId) {
        SessionStore.setCurrentAgent(agent);
        this.getUIContext().getPromptAction().showToast({ message: `已切换到 ${agent.name}` });
      }
    })
    .gesture(
      LongPressGesture()
        .onAction((event: GestureEvent): void => {
          this.showAgentMenu(agent);
        })
    )
  }

  build() {
    Column() {
      Row() {
        Column({ space: 4 }) {
          Text($r('app.string.tab_expert'))
            .fontSize(26)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.text_primary'))
          Text(this.agents.length > 0 ? `${this.agents.length} 位专家` : '管理你的专属专家')
            .fontSize(13)
            .fontColor($r('app.color.text_tertiary'))
        }
        .alignItems(HorizontalAlign.Start)

        Blank()

        Button({ type: ButtonType.Circle, stateEffect: true }) {
          SymbolGlyph(this.searching ? $r('sys.symbol.xmark') : $r('sys.symbol.magnifyingglass'))
            .fontSize(18)
            .fontColor([$r('app.color.icon_secondary')])
        }
        .width(38)
        .height(38)
        .backgroundColor($r('app.color.bg_card'))
        .systemMaterial(UiMaterialKit.button())
        .onClick((): void => {
          if (this.searching) {
            this.keyword = '';
          }
          this.searching = !this.searching;
        })

        Button({ type: ButtonType.Circle, stateEffect: true }) {
          SymbolGlyph($r('sys.symbol.plus'))
            .fontSize(20)
            .fontColor([$r('app.color.icon_secondary')])
        }
        .width(38)
        .height(38)
        .backgroundColor($r('app.color.bg_card'))
        .systemMaterial(UiMaterialKit.button())
        .margin({ left: 8 })
        .onClick((): void => {
          this.goCreate();
        })
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: this.topInset + 10, bottom: 10 })

      if (this.searching) {
        TextInput({
          text: this.keyword,
          placeholder: '搜索专家名称或描述'
        })
          .fontSize(14)
          .height(38)
          .borderRadius(19)
          .backgroundColor($r('app.color.bg_input'))
          .padding({ left: 14, right: 14 })
          .margin({ left: 16, right: 16, bottom: 8 })
          .onChange((value: string): void => {
            this.keyword = value;
          })
      }

      Row({ space: 8 }) {
        ForEach(this.filterOptions(), (option: ExpertFilterOption) => {
          this.chipBuilder(option)
        }, (option: ExpertFilterOption) => `${option.value}_${this.filterIndex === option.value}`)
      }
      .width('100%')
      .padding({ left: 16, right: 16, bottom: 10 })

      if (this.loading && this.agents.length === 0) {
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
      } else if (this.agents.length === 0) {
        Column({ space: 12 }) {
          EmptyView({ title: '暂无可用专家', subtitle: '点击右上角按钮，从模板创建你的第一个专家' })
          Button('创建专家')
            .height(42)
            .fontSize(15)
            .borderRadius(21)
            .backgroundColor($r('app.color.brand'))
            .fontColor($r('app.color.text_on_brand'))
            .padding({ left: 28, right: 28 })
            .onClick((): void => {
              this.goCreate();
            })
        }
        .layoutWeight(1)
        .width('100%')
        .justifyContent(FlexAlign.Center)
      } else {
        Refresh({ refreshing: $$this.refreshing }) {
          List({ space: 10 }) {
            if (this.visibleAgents().length === 0) {
              ListItem() {
                Column() {
                  Text('没有符合筛选条件的专家')
                    .fontSize(13)
                    .fontColor($r('app.color.text_tertiary'))
                }
                .width('100%')
                .padding({ top: 40 })
                .justifyContent(FlexAlign.Center)
              }
            }
            ForEach(this.visibleAgents(), (agent: AgentModel) => {
              ListItem() {
                this.agentCard(agent)
              }
            }, (agent: AgentModel) =>
              `${agent.agentId}_${agent.state}_${agent.unreadCount}_${agent.agentId === this.currentAgentId}`)
          }
          .width('100%')
          .height('100%')
          .padding({ left: 16, right: 16, bottom: this.bottomPad + 12 })
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
    .backgroundColor($r('app.color.bg_page'))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }
}
