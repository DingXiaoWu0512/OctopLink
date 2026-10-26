import { SessionStore } from '../../store/SessionStore';
import { ChannelService, ConnectorService, CronService, KnowledgeService, PluginService } from '../../service/WorkspaceService';
import { UiMaterialKit } from '../../components/UiMaterialKit';

class WorkspaceRow {
  readonly name: string;
  readonly hint: string;
  readonly route: string;
  readonly icon: Resource;
  readonly color: Resource;
  readonly softColor: Resource;
  readonly needsAgent: boolean;

  constructor(name: string, hint: string, route: string, icon: Resource, color: Resource,
    softColor: Resource, needsAgent: boolean) {
    this.name = name;
    this.hint = hint;
    this.route = route;
    this.icon = icon;
    this.color = color;
    this.softColor = softColor;
    this.needsAgent = needsAgent;
  }
}

class WorkspaceSection {
  readonly title: string;
  readonly rows: Array<WorkspaceRow>;

  constructor(title: string, rows: Array<WorkspaceRow>) {
    this.title = title;
    this.rows = rows;
  }
}

const SECTION_LIST: Array<WorkspaceSection> = [
  new WorkspaceSection('自动化', [
    new WorkspaceRow('定时任务', '让专家按计划自动执行', 'cron',
      $r('sys.symbol.clock'), $r('app.color.brand'), $r('app.color.brand_light'), true),
    new WorkspaceRow('渠道接入', 'IM 平台消息接入专家', 'channels',
      $r('sys.symbol.dot_radiowaves_left_and_right'), $r('app.color.brand'), $r('app.color.brand_light'), true)
  ]),
  new WorkspaceSection('知识与数据', [
    new WorkspaceRow('知识库', '管理文档与数据源', 'knowledge',
      $r('sys.symbol.book'), $r('app.color.success'), $r('app.color.success_soft'), false),
    new WorkspaceRow('连接器', '外部工具与 MCP 服务', 'connectors',
      $r('sys.symbol.link'), $r('app.color.warning'), $r('app.color.warning_soft'), false)
  ]),
  new WorkspaceSection('专家配置', [
    new WorkspaceRow('插件', '按专家启用能力扩展', 'plugins',
      $r('sys.symbol.puzzle'), $r('app.color.brand'), $r('app.color.brand_light'), true),
    new WorkspaceRow('MBTI 人格', '为专家设定性格底色', 'mbti',
      $r('sys.symbol.face_smiling'), $r('app.color.danger'), $r('app.color.danger_soft'), true)
  ])
];

/** 工作台：专家自动化中心（概览 + 分组入口） */
@Component
export struct WorkspaceTab {
  @Consume('navStack') navStack: NavPathStack;
  @StorageProp(SessionStore.KEY_AGENT_ID) @Watch('onAgentChanged') agentId: string = '';
  @StorageProp(SessionStore.KEY_AGENT_NAME) agentName: string = '';
  @State refreshing: boolean = false;
  @State cronCount: number = -1;
  @State channelCount: number = -1;
  @State kbCount: number = -1;
  @State connectorCount: number = -1;
  @State pluginCount: number = -1;
  @Prop topInset: number = 0;
  @Prop bottomPad: number = 72;

  aboutToAppear(): void {
    this.refreshAll();
  }

  private onAgentChanged(): void {
    this.cronCount = -1;
    this.channelCount = -1;
    this.pluginCount = -1;
    this.refreshAll();
  }

  private async refreshAll(): Promise<void> {
    const tasks: Array<Promise<void>> = [];
    tasks.push(this.fetchKb());
    tasks.push(this.fetchConnectors());
    if (this.agentId !== '') {
      tasks.push(this.fetchCron());
      tasks.push(this.fetchChannels());
      tasks.push(this.fetchPlugins());
    }
    await Promise.all(tasks);
    this.refreshing = false;
  }

  private async fetchCron(): Promise<void> {
    if (this.agentId === '') {
      this.cronCount = -1;
      return;
    }
    try {
      this.cronCount = (await CronService.list(this.agentId)).length;
    } catch (e) {
      this.cronCount = -1;
    }
  }

  private async fetchChannels(): Promise<void> {
    if (this.agentId === '') {
      this.channelCount = -1;
      return;
    }
    try {
      this.channelCount = (await ChannelService.list(this.agentId)).length;
    } catch (e) {
      this.channelCount = -1;
    }
  }

  private async fetchKb(): Promise<void> {
    try {
      this.kbCount = (await KnowledgeService.listBases()).length;
    } catch (e) {
      this.kbCount = -1;
    }
  }

  private async fetchConnectors(): Promise<void> {
    try {
      this.connectorCount = (await ConnectorService.list()).length;
    } catch (e) {
      this.connectorCount = -1;
    }
  }

  private async fetchPlugins(): Promise<void> {
    if (this.agentId === '') {
      this.pluginCount = -1;
      return;
    }
    try {
      this.pluginCount = (await PluginService.listForAgent(this.agentId)).length;
    } catch (e) {
      this.pluginCount = -1;
    }
  }

  private countFor(route: string): number {
    if (route === 'cron') {
      return this.cronCount;
    }
    if (route === 'channels') {
      return this.channelCount;
    }
    if (route === 'knowledge') {
      return this.kbCount;
    }
    if (route === 'connectors') {
      return this.connectorCount;
    }
    if (route === 'plugins') {
      return this.pluginCount;
    }
    return -2;
  }

  private countText(count: number): string {
    return count < 0 ? '—' : `${count}`;
  }

  private openRoute(route: string, needsAgent: boolean): void {
    if (needsAgent && this.agentId === '') {
      this.getUIContext().getPromptAction().showToast({ message: '请先在专家页选择专家' });
      return;
    }
    this.navStack.pushPath(new NavPathInfo(route, null));
  }

  private goExpert(): void {
    AppStorage.setOrCreate(SessionStore.KEY_MAIN_TAB, 0);
  }

  @Builder
  heroBuilder() {
    Button({ type: ButtonType.Normal, stateEffect: true }) {
      Row({ space: 12 }) {
        Column() {
          Image($r('app.media.octop_logo'))
            .width(24)
            .height(24)
            .borderRadius(12)
        }
        .width(38)
        .height(38)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
        .backgroundColor($r('app.color.bg_input'))
        .borderRadius(12)

        Column({ space: 2 }) {
          Text(this.agentId === '' ? '未选择专家' : '当前专家')
            .fontSize(10)
            .fontColor($r('app.color.text_tertiary'))
          Text(this.agentId === '' ? '点击前往专家页选择' : this.agentName)
            .fontSize(15)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.text_primary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        SymbolGlyph($r('sys.symbol.chevron_right'))
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor([$r('app.color.text_tertiary')])
      }
      .width('100%')
      .padding({ left: 14, right: 14, top: 10, bottom: 10 })
    }
    .width('100%')
    .borderRadius(18)
    .backgroundColor($r('app.color.bg_card'))
    .systemMaterial(UiMaterialKit.card())
    .onClick((): void => {
      this.goExpert();
    })
  }

  @Builder
  statCard(icon: Resource, count: number, label: string, color: Resource, softColor: Resource,
    route: string, needsAgent: boolean) {
    Column({ space: 7 }) {
      Row() {
        SymbolGlyph(icon)
          .fontSize(15)
          .fontColor([color])
      }
      .width(28)
      .height(28)
      .justifyContent(FlexAlign.Center)
      .backgroundColor(softColor)
      .borderRadius(9)

      Text(this.countText(count))
        .fontSize(19)
        .fontWeight(FontWeight.Bold)
        .fontColor(count < 0 ? $r('app.color.text_tertiary') : $r('app.color.text_primary'))

      Text(label)
        .fontSize(11)
        .fontColor($r('app.color.text_tertiary'))
    }
    .layoutWeight(1)
    .padding({ top: 13, bottom: 13, left: 6, right: 6 })
    .borderRadius(15)
    .backgroundColor($r('app.color.bg_card'))
    .border({ width: 1, color: $r('app.color.card_stroke') })
    .alignItems(HorizontalAlign.Center)
    .onClick((): void => {
      this.openRoute(route, needsAgent);
    })
  }

  @Builder
  statsBuilder() {
    Row({ space: 10 }) {
      this.statCard($r('sys.symbol.clock'), this.cronCount, '定时任务',
        $r('app.color.brand'), $r('app.color.brand_light'), 'cron', true)
      this.statCard($r('sys.symbol.book'), this.kbCount, '知识库',
        $r('app.color.success'), $r('app.color.success_soft'), 'knowledge', false)
      this.statCard($r('sys.symbol.link'), this.connectorCount, '连接器',
        $r('app.color.warning'), $r('app.color.warning_soft'), 'connectors', false)
      this.statCard($r('sys.symbol.puzzle'), this.pluginCount, '插件',
        $r('app.color.brand'), $r('app.color.brand_light'), 'plugins', true)
    }
    .width('100%')
  }

  @Builder
  sectionHeader(title: string) {
    Text(title)
      .fontSize(13)
      .fontWeight(FontWeight.Medium)
      .fontColor($r('app.color.text_tertiary'))
      .margin({ left: 4, bottom: 8 })
  }

  @Builder
  sectionCard(section: WorkspaceSection) {
    Column() {
      ForEach(section.rows, (row: WorkspaceRow, index: number) => {
        Column() {
          if (index > 0) {
            Divider()
              .color($r('app.color.divider'))
              .margin({ left: 62 })
          }
          Row({ space: 12 }) {
            Column() {
              SymbolGlyph(row.icon)
                .fontSize(18)
                .fontColor([row.color])
            }
            .width(36)
            .height(36)
            .justifyContent(FlexAlign.Center)
            .backgroundColor(row.softColor)
            .borderRadius(11)

            Column({ space: 3 }) {
              Text(row.name)
                .fontSize(15)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.text_primary'))
              Text(row.hint)
                .fontSize(12)
                .fontColor($r('app.color.text_tertiary'))
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
            }
            .layoutWeight(1)
            .alignItems(HorizontalAlign.Start)

            if (row.needsAgent && this.agentId === '') {
              Text('需选专家')
                .fontSize(11)
                .fontColor($r('app.color.text_tertiary'))
                .backgroundColor($r('app.color.bg_input'))
                .borderRadius(7)
                .padding({ left: 8, right: 8, top: 3, bottom: 3 })
            } else {
              if (this.countFor(row.route) >= 0) {
                Text(`${this.countFor(row.route)} 项`)
                  .fontSize(12)
                  .fontColor($r('app.color.text_tertiary'))
              }
              SymbolGlyph($r('sys.symbol.chevron_right'))
                .fontSize(13)
                .fontColor([$r('app.color.icon_secondary')])
            }
          }
          .width('100%')
          .padding({ left: 14, right: 14, top: 13, bottom: 13 })
        }
        .onClick((): void => {
          this.openRoute(row.route, row.needsAgent);
        })
      }, (row: WorkspaceRow) => `${row.route}_${this.countFor(row.route)}`)
    }
    .width('100%')
    .borderRadius(16)
    .backgroundColor($r('app.color.bg_card'))
    .border({ width: 1, color: $r('app.color.card_stroke') })
    .shadow({ radius: 10, color: '#0A000000', offsetY: 3 })
  }

  /** 沉浸光感标题栏：静止透底无边条，滚动时系统 GRADUAL_BLUR 渐变模糊 */
  @Builder
  titleBarBuilder() {
    Column() {
      Text($r('app.string.workspace_title'))
        .fontSize(26)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .width('100%')
        .textAlign(TextAlign.Start)
        .padding({ left: 16, right: 16, top: this.topInset + 10, bottom: 8 })
    }
    .width('100%')
    .expandSafeArea([SafeAreaType.SYSTEM])
  }

  build() {
    Navigation() {
      Refresh({ refreshing: $$this.refreshing }) {
        Scroll() {
          Column({ space: 14 }) {
            this.heroBuilder()
            this.statsBuilder()

            Column({ space: 22 }) {
              ForEach(SECTION_LIST, (section: WorkspaceSection) => {
                Column() {
                  this.sectionHeader(section.title)
                  this.sectionCard(section)
                }
                .width('100%')
                .alignItems(HorizontalAlign.Start)
              }, (section: WorkspaceSection) => section.title)
            }
            .width('100%')
          }
          .width('100%')
          .padding({ left: 16, right: 16, bottom: this.bottomPad + 20 })
          .alignItems(HorizontalAlign.Start)
        }
        .width('100%')
        .contentStartOffset(this.topInset + 54)
        .scrollBar(BarState.Off)
      }
      .width('100%')
      .height('100%')
      .onRefreshing((): void => {
        this.refreshAll();
      })
    }
    .title({
      builder: this.titleBarBuilder,
      height: this.topInset + 54
    }, {
      barStyle: BarStyle.STACK,
      scrollEffectOptions: { scrollEffectType: ScrollEffectType.GRADUAL_BLUR }
    })
    .hideBackButton(true)
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.bg_page'))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }
}
