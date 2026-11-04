import { LengthMetrics } from '@kit.ArkUI';
import { HdsNavigation, HdsNavigationTitleMode, ScrollEffectType, hdsMaterial, TextStyleMode } from '@kit.UIDesignKit';
import { AgentModel } from '../../model/AgentModels';
import { AgentService } from '../../service/AgentService';
import { OctopApiError } from '../../net/HttpClient';
import { SessionStore } from '../../store/SessionStore';
import { AppPrefs } from '../../store/AppPrefs';
import { EmptyView } from '../../components/EmptyView';
import { ErrorRetry } from '../../components/ErrorRetry';
import { AgentEditNavParam } from './AgentEditPage';
import { UiMaterialKit } from '../../components/UiMaterialKit';
import { AgentAvatar } from '../../components/AgentAvatar';
import { CapsuleSegmentBar, SegmentBarOption } from '../../components/CapsuleSegmentBar';
import { MenuSheetContent, MenuSheetOption } from '../../components/MenuSheet';

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
  @StorageProp(SessionStore.KEY_ROLE) role: string = '';
  @StorageLink(SessionStore.KEY_AGENTS_DIRTY) @Watch('onDirtyChanged') agentsDirty: boolean = false;
  @State agents: Array<AgentModel> = [];
  @State loading: boolean = false;
  @State refreshing: boolean = false;
  @State errorMsg: string = '';
  @State operating: boolean = false;
  @State filterIndex: number = 0;
  @StorageLink('immersive.light.on') immersiveOn: boolean = true;
  @State searching: boolean = false;
  @State keyword: string = '';
  @State menuOpen: boolean = false;
  @State menuTitle: string = '';
  @State menuMessage: string = '';
  @State menuOptions: Array<MenuSheetOption> = [];
  private menuActions: Array<() => void> = [];
  private scroller: Scroller = new Scroller();

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
      if (this.filterIndex === 3) {
        this.agents = await AgentService.listAll();
      } else {
        this.agents = await AgentService.listMine();
      }
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
    const options: Array<ExpertFilterOption> = [
      new ExpertFilterOption('全部', 0),
      new ExpertFilterOption('运行中', 1),
      new ExpertFilterOption('未运行', 2)
    ];
    if (this.role === 'admin') {
      options.push(new ExpertFilterOption('全部用户', 3));
    }
    return options;
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
    this.menuTitle = agent.name;
    this.menuMessage = '选择要执行的操作';
    if (agent.isOwner) {
      this.menuOptions = [
        new MenuSheetOption($r('sys.symbol.square_and_pencil'), '编辑专家', '修改资料、人设与模型', false),
        new MenuSheetOption($r('sys.symbol.trash'), '删除专家', '', true)
      ];
      this.menuActions = [
        (): void => {
          this.navStack.pushPath(new NavPathInfo('agentEdit', new AgentEditNavParam(agent.agentId)));
        },
        (): void => {
          this.confirmDeleteAgent(agent);
        }
      ];
    } else {
      this.menuOptions = [
        new MenuSheetOption($r('sys.symbol.person_2'),
          `由 @${agent.ownerUsername === '' ? '他人' : agent.ownerUsername} 共享`, '', false)
      ];
      this.menuActions = [];
    }
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
        // 专家记忆：删除的是当前专家，同步清持久化（防下次启动恢复已删 id）
        AppPrefs.getInstance().setLastAgentId('');
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

  /** 滑动胶囊分段选项（由 ExpertFilterOption 映射，value 与 filterIndex 一致） */
  private segmentOptions(): Array<SegmentBarOption> {
    return this.filterOptions().map((option: ExpertFilterOption): SegmentBarOption =>
      new SegmentBarOption(option.label, `${option.value}`));
  }

  /** 滑动胶囊选中回调：复用既有 filterIndex 切换 + load() */
  private onSegmentSelect(index: number): void {
    const options: Array<ExpertFilterOption> = this.filterOptions();
    if (index < 0 || index >= options.length) {
      return;
    }
    const value: number = options[index].value;
    if (this.filterIndex !== value) {
      this.filterIndex = value;
      this.load();
    }
  }

  @Builder
  agentCard(agent: AgentModel) {
    Column({ space: 10 }) {
      Row({ space: 12 }) {
        AgentAvatar({ agentId: agent.agentId, iconUrl: agent.iconUrl })
        Column({ space: 4 }) {
          Row({ space: 6 }) {
            Text(agent.name)
              .fontSize(16)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.text_primary'))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
            if (agent.kind === 'team') {
              Text('团队')
                .fontSize(10)
                .fontColor($r('app.color.brand'))
                .backgroundColor($r('app.color.brand_light'))
                .borderRadius(5)
                .padding({ left: 6, right: 6, top: 2, bottom: 2 })
            }
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

  /** HdsNavigation 标题栏底部自定义区：搜索框 / 滑动胶囊筛选（列表从玻璃下方滚过） */
  @Builder
  searchFilterBuilder() {
    if (this.searching) {
      TextInput({
        text: this.keyword,
        placeholder: '搜索专家名称或描述'
      })
        .fontSize(14)
        .height(38)
        .borderRadius(19)
        .backgroundColor(Color.Transparent)
        .systemMaterial(UiMaterialKit.button())
        .padding({ left: 14, right: 14 })
        .margin({ left: 16, right: 16, bottom: 6 })
        .onChange((value: string): void => {
          this.keyword = value;
        })
    } else {
      CapsuleSegmentBar({
        options: this.segmentOptions(),
        selectedIndex: this.filterIndex,
        onSelect: (index: number): void => {
          this.onSegmentSelect(index);
        }
      })
      .width('100%')
      .padding({ left: 16, right: 16, bottom: 8 })
    }
  }

  build() {
    HdsNavigation() {
      Column() {
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
          List({ space: 10, scroller: this.scroller }) {
            // 头部占位项：静止时避开标题栏区域。不用 contentStartOffset——它滚动回顶后
            // 会失效（真机实测），内容项占位随数据重建保留，位置不会丢。
            // 固定常量：MINI 标题栏（单行标题 + chips 行）≈ 145vp + 间距
            ListItem()
              .height(150)
              .width('100%')
              .hitTestBehavior(HitTestMode.None)
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
            // 尾部占位项：最后一张卡片完整停在悬浮导航栏上方（与顶部 150 占位同构，
            // 不用 contentEndOffset——滚动回顶后会失效（真机实测））
            ListItem()
              .height(this.bottomPad)
              .width('100%')
              .hitTestBehavior(HitTestMode.None)
          }
          .width('100%')
          .height('100%')
          .padding({ left: 16, right: 16, bottom: 0 })
          .clip(false)
          .cachedCount(3, true)
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
      // 内容延伸进状态栏区（与聊天页一致）：滚动正文从标题栏/状态栏下穿过，由 GRADUAL_BLUR 提供光感
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])

    }
    .titleBar({
      avoidLayoutSafeArea: true,
      style: {
        scrollEffectOpts: {
          enableScrollEffect: this.immersiveOn,
          scrollEffectType: ScrollEffectType.IMMERSIVE_GRADIENT_BLUR,
          enableRefreshOffsetChange: false,
          blurEffectiveStartOffset: LengthMetrics.vp(0),
          blurEffectiveEndOffset: LengthMetrics.vp(20)
        },
        systemMaterialEffect: {
          materialType: this.immersiveOn ? hdsMaterial.MaterialType.IMMERSIVE : hdsMaterial.MaterialType.NONE,
          materialLevel: hdsMaterial.MaterialLevel.ADAPTIVE
        },
        originalStyle: {
          contentStyle: {
            titleStyle: {
              mainTitleColor: $r('app.color.text_primary'),
              subTitleColor: $r('app.color.text_secondary')
            },
            menuStyle: {
              iconColor: $r('app.color.icon_secondary'),
              textColor: $r('app.color.text_primary')
            }
          }
        },
        scrollEffectStyle: {
          contentStyle: {
            titleStyle: {
              mainTitleColor: $r('app.color.text_primary'),
              subTitleColor: $r('app.color.text_secondary')
            },
            menuStyle: {
              iconColor: $r('app.color.icon_secondary'),
              textColor: $r('app.color.text_primary')
            }
          }
        }
      },
      content: {
        title: { mainTitle: $r('app.string.tab_expert') },
        menu: {
          value: [{
            content: {
              label: '团队',
              type: TextStyleMode.NORMAL,
              isEnabled: true,
              action: (): void => {
                this.navStack.pushPath(new NavPathInfo('teams', null));
              }
            }
          }, {
            content: {
              label: '搜索',
              icon: this.searching ? $r('sys.symbol.xmark') : $r('sys.symbol.magnifyingglass'),
              isEnabled: true,
              action: (): void => {
                if (this.searching) {
                  this.keyword = '';
                }
                this.searching = !this.searching;
              }
            }
          }, {
            content: {
              label: '新建',
              icon: $r('sys.symbol.plus'),
              isEnabled: true,
              action: (): void => {
                this.goCreate();
              }
            }
          }]
        },
        bottomBuilder: {
          builder: (): void => this.searchFilterBuilder(),
          height: 50
        }
      }
    })
    .titleMode(HdsNavigationTitleMode.MINI)
    .hideBackButton(true)
    .bindToScrollable([this.scroller])
    .width('100%')
    .height('100%')
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
