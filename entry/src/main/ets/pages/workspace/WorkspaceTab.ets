import { LengthMetrics } from '@kit.ArkUI';
import { HdsNavigation, HdsNavigationTitleMode, ScrollEffectType, hdsMaterial } from '@kit.UIDesignKit';
import { SessionStore } from '../../store/SessionStore';
import { ChannelService, ConnectorService, CronService, KnowledgeService, PluginService } from '../../service/WorkspaceService';
import { SkillService } from '../../service/SkillService';
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

/** statCard @Builder 按引用传参选项（@Builder 值传参不随 @State 刷新，曾导致统计卡恒显「—」） */
interface WsStatCardOptions {
  icon: Resource;
  count: number;
  label: string;
  color: Resource;
  softColor: Resource;
  route: string;
  needsAgent: boolean;
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
    new WorkspaceRow('工作区文件', '浏览与管理工作区目录', 'workspaceFiles',
      $r('sys.symbol.folder_fill'), $r('app.color.success'), $r('app.color.success_soft'), true),
    new WorkspaceRow('连接器', '外部工具与 MCP 服务', 'connectors',
      $r('sys.symbol.link'), $r('app.color.warning'), $r('app.color.warning_soft'), false)
  ]),
  new WorkspaceSection('专家配置', [
    new WorkspaceRow('技能', '提示词技能与市场安装', 'skills',
      $r('sys.symbol.wand_and_stars'), $r('app.color.brand'), $r('app.color.brand_light'), true),
    new WorkspaceRow('技能包', '技能合集的打包与挂载', 'skillPackages',
      $r('sys.symbol.square_grid_2x2'), $r('app.color.brand'), $r('app.color.brand_light'), true),
    new WorkspaceRow('子代理', '安装子代理协同专家工作', 'subagents',
      $r('sys.symbol.robot'), $r('app.color.success'), $r('app.color.success_soft'), true),
    new WorkspaceRow('工具开关', '按专家启停内置与插件工具', 'toolSettings',
      $r('sys.symbol.wrench_and_screwdriver'), $r('app.color.warning'), $r('app.color.warning_soft'), true),
    new WorkspaceRow('插件', '按专家启用能力扩展', 'plugins',
      $r('sys.symbol.puzzle'), $r('app.color.brand'), $r('app.color.brand_light'), true),
    new WorkspaceRow('MBTI 人格', '为专家设定性格底色', 'mbti',
      $r('sys.symbol.face_smiling'), $r('app.color.danger'), $r('app.color.danger_soft'), true),
    new WorkspaceRow('记忆', '专家的长期记忆管理', 'memory',
      $r('sys.symbol.lightbulb'), $r('app.color.warning'), $r('app.color.warning_soft'), true)
  ]),
  new WorkspaceSection('运营管理', [
    new WorkspaceRow('用量统计', 'Token 消耗与模型调用', 'usage',
      $r('sys.symbol.bolt'), $r('app.color.brand'), $r('app.color.brand_light'), false),
    new WorkspaceRow('用户组', '分组管理与批量授权', 'userGroups',
      $r('sys.symbol.person_2'), $r('app.color.warning'), $r('app.color.warning_soft'), false),
    new WorkspaceRow('邀请码', '注册邀请码创建与吊销', 'invites',
      $r('sys.symbol.paperplane'), $r('app.color.brand'), $r('app.color.brand_light'), false),
    new WorkspaceRow('桥接设备', '跨实例 Bridge 连接管理', 'bridge',
      $r('sys.symbol.wifi'), $r('app.color.success'), $r('app.color.success_soft'), false)
  ])
];

/** 工作台：专家自动化中心（概览 + 分组入口） */
@Component
export struct WorkspaceTab {
  @Consume('navStack') navStack: NavPathStack;
  @StorageProp(SessionStore.KEY_AGENT_ID) @Watch('onAgentChanged') agentId: string = '';
  @StorageLink('immersive.light.on') immersiveOn: boolean = true;
  @State refreshing: boolean = false;
  @State cronCount: number = -1;
  @State channelCount: number = -1;
  @State kbCount: number = -1;
  @State connectorCount: number = -1;
  @State pluginCount: number = -1;
  @State skillCount: number = -1;
  @Prop topInset: number = 0;
  @Prop bottomPad: number = 72;
  private scroller: Scroller = new Scroller();

  aboutToAppear(): void {
    this.refreshAll();
  }

  private onAgentChanged(): void {
    this.cronCount = -1;
    this.channelCount = -1;
    this.pluginCount = -1;
    this.skillCount = -1;
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
      tasks.push(this.fetchSkills());
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

  private async fetchSkills(): Promise<void> {
    if (this.agentId === '') {
      this.skillCount = -1;
      return;
    }
    try {
      this.skillCount = (await SkillService.list(this.agentId)).length;
    } catch (e) {
      this.skillCount = -1;
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
    if (route === 'skills') {
      return this.skillCount;
    }
    return -2;
  }

  private openRoute(route: string, needsAgent: boolean): void {
    if (needsAgent && this.agentId === '') {
      this.getUIContext().getPromptAction().showToast({ message: '请先在专家页选择专家' });
      return;
    }
    this.navStack.pushPath(new NavPathInfo(route, null));
  }

  @Builder
  statCard($$: WsStatCardOptions) {
    Column({ space: 7 }) {
      Row() {
        SymbolGlyph($$.icon)
          .fontSize(15)
          .fontColor([$$.color])
      }
      .width(28)
      .height(28)
      .justifyContent(FlexAlign.Center)
      .backgroundColor($$.softColor)
      .borderRadius(9)

      // 数字槽：已加载显示真实数字；需选专家且未选显示「—」；其余（加载中/失败）显示加载圈，不显示横杠
      Column() {
        if ($$.count >= 0) {
          Text(`${$$.count}`)
            .fontSize(19)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.text_primary'))
        } else if ($$.needsAgent && this.agentId === '') {
          Text('—')
            .fontSize(19)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.text_tertiary'))
        } else {
          LoadingProgress()
            .width(18)
            .height(18)
            .color($r('app.color.text_tertiary'))
        }
      }
      .constraintSize({ minHeight: 26 })
      .justifyContent(FlexAlign.Center)

      Text($$.label)
        .fontSize(11)
        .fontColor($r('app.color.text_tertiary'))
    }
    .layoutWeight(1)
    .padding({ top: 13, bottom: 13, left: 6, right: 6 })
    .borderRadius(15)
    .backgroundColor($r('app.color.card_glass'))
    .backgroundBlurStyle(BlurStyle.COMPONENT_THIN)
    .systemMaterial(UiMaterialKit.card())
    .border({ width: 1, color: $r('app.color.card_stroke') })
    .alignItems(HorizontalAlign.Center)
    .onClick((): void => {
      this.openRoute($$.route, $$.needsAgent);
    })
  }

  @Builder
  statsBuilder() {
    Row({ space: 10 }) {
      this.statCard({
        icon: $r('sys.symbol.clock'), count: this.cronCount, label: '定时任务',
        color: $r('app.color.brand'), softColor: $r('app.color.brand_light'),
        route: 'cron', needsAgent: true
      })
      this.statCard({
        icon: $r('sys.symbol.book'), count: this.kbCount, label: '知识库',
        color: $r('app.color.success'), softColor: $r('app.color.success_soft'),
        route: 'knowledge', needsAgent: false
      })
      this.statCard({
        icon: $r('sys.symbol.link'), count: this.connectorCount, label: '连接器',
        color: $r('app.color.warning'), softColor: $r('app.color.warning_soft'),
        route: 'connectors', needsAgent: false
      })
      this.statCard({
        icon: $r('sys.symbol.puzzle'), count: this.pluginCount, label: '插件',
        color: $r('app.color.brand'), softColor: $r('app.color.brand_light'),
        route: 'plugins', needsAgent: true
      })
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
    .backgroundColor($r('app.color.card_glass'))
    .backgroundBlurStyle(BlurStyle.COMPONENT_THIN)
    .systemMaterial(UiMaterialKit.card())
    .border({ width: 1, color: $r('app.color.card_stroke') })
    .shadow({ radius: 10, color: '#0A000000', offsetY: 3 })
  }

  build() {
    HdsNavigation() {
      Refresh({ refreshing: $$this.refreshing }) {
        List({ scroller: this.scroller }) {
          // 头部占位项：静止时避开标题栏区域（contentStartOffset 滚动回顶后会失效，真机实测）。
          // 高度 = 状态栏避让（topInset）+ MINI 标题行 56vp + 8vp 间隙；固定 60vp 时 hero 卡与
          // 标题文字重叠（实测 bounds：卡顶 245px < 标题底 287px），随设备避让区自适应
          ListItem()
            .height(this.topInset + 64)
            .width('100%')
            .hitTestBehavior(HitTestMode.None)
          ListItem() {
          Column({ space: 14 }) {
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
        }
        .width('100%')
        .clip(false)
        .cachedCount(3, true)
        .scrollBar(BarState.Off)
      }
      .width('100%')
      .height('100%')
      .onRefreshing((): void => {
        this.refreshAll();
      })
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
        title: { mainTitle: $r('app.string.workspace_title') }
      }
    })
    .titleMode(HdsNavigationTitleMode.MINI)
    .hideBackButton(true)
    .bindToScrollable([this.scroller])
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.bg_page'))
  }
}
