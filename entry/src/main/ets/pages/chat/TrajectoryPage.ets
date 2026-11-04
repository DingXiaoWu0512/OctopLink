import { TrajectoryEventModel, TrajectoryHistoryModel, TrajectoryMetricsModel } from '../../model/TrajectoryModels';
import { TrajectoryService } from '../../service/TrajectoryService';
import { OctopApiError } from '../../net/HttpClient';
import { PageHeader } from '../../components/PageHeader';
import { EmptyView } from '../../components/EmptyView';
import { ErrorRetry } from '../../components/ErrorRetry';
import { TimeFormat } from '../../utils/TimeFormat';
import { Log } from '../../utils/Logger';
import { picker, fileIo } from '@kit.CoreFileKit';
import { MenuSheetContent, MenuSheetOption } from '../../components/MenuSheet';
import { UiMaterialKit } from '../../components/UiMaterialKit';

/** 路由参数：目标会话 */
export class TrajectoryNavParam {
  readonly agentId: string;
  readonly threadId: string;

  constructor(agentId: string, threadId: string) {
    this.agentId = agentId;
    this.threadId = threadId;
  }
}

/** kind 过滤 chips 选项（kind 为空串表示全部） */
class TrajectoryKindChip {
  readonly label: string;
  readonly kind: string;

  constructor(label: string, kind: string) {
    this.label = label;
    this.kind = kind;
  }
}

/** 指标卡单元格（ForEach 用稳定对象） */
class TrajectoryMetricCell {
  readonly label: string;
  readonly text: string;

  constructor(label: string, text: string) {
    this.label = label;
    this.text = text;
  }
}

/** 对话轨迹：指标卡 + kind 过滤 + 事件时间线 + 加载更多/下拉刷新/导出 */
@Component
export struct TrajectoryPage {
  @State loading: boolean = true;
  @State refreshing: boolean = false;
  @State errorMsg: string = '';
  @State events: Array<TrajectoryEventModel> = [];
  @State metrics: TrajectoryMetricsModel | null = null;
  @State kindFilter: string = '';
  @State hasMore: boolean = false;
  @State loadingMore: boolean = false;
  @State exporting: boolean = false;
  @State menuOpen: boolean = false;
  @State menuTitle: string = '';
  @State menuMessage: string = '';
  @State menuOptions: Array<MenuSheetOption> = [];
  private menuActions: Array<() => void> = [];

  private agentId: string = '';
  private threadId: string = '';
  private nextBeforeSeq: number | null = null;

  private readonly kindChips: Array<TrajectoryKindChip> = [
    new TrajectoryKindChip('全部', ''),
    new TrajectoryKindChip('用户', 'user'),
    new TrajectoryKindChip('助手', 'assistant'),
    new TrajectoryKindChip('工具', 'tool'),
    new TrajectoryKindChip('系统', 'system'),
    new TrajectoryKindChip('上下文', 'context'),
    new TrajectoryKindChip('压缩', 'compacted')
  ];

  private onNavReady(ctx: NavDestinationContext): void {
    if (ctx.pathInfo.param instanceof TrajectoryNavParam) {
      this.agentId = ctx.pathInfo.param.agentId;
      this.threadId = ctx.pathInfo.param.threadId;
      this.load();
    } else {
      this.loading = false;
      this.errorMsg = '页面参数错误';
    }
  }

  private selectedKinds(): Array<string> {
    const kinds: Array<string> = [];
    if (this.kindFilter !== '') {
      kinds.push(this.kindFilter);
    }
    return kinds;
  }

  private async load(): Promise<void> {
    this.loading = this.events.length === 0;
    this.errorMsg = '';
    try {
      const history: TrajectoryHistoryModel = await TrajectoryService.history(
        this.agentId, this.threadId, 50, null, this.selectedKinds());
      this.events = history.events;
      this.hasMore = history.hasMore;
      this.nextBeforeSeq = history.nextBeforeSeq;
    } catch (e) {
      this.errorMsg = e instanceof OctopApiError ? e.message : '轨迹加载失败';
    } finally {
      this.loading = false;
    }
    this.loadMetrics();
  }

  private async loadMetrics(): Promise<void> {
    try {
      this.metrics = await TrajectoryService.metrics(this.agentId, this.threadId);
    } catch (e) {
      this.metrics = null;
      Log.warn('trajectory metrics load failed');
    }
  }

  private async loadMore(): Promise<void> {
    if (this.loadingMore || !this.hasMore || this.nextBeforeSeq === null) {
      return;
    }
    this.loadingMore = true;
    try {
      const history: TrajectoryHistoryModel = await TrajectoryService.history(
        this.agentId, this.threadId, 50, this.nextBeforeSeq, this.selectedKinds());
      this.events = this.events.concat(history.events);
      this.hasMore = history.hasMore;
      this.nextBeforeSeq = history.nextBeforeSeq;
    } catch (e) {
      const message: string = e instanceof OctopApiError ? e.message : '加载更多失败';
      this.getUIContext().getPromptAction().showToast({ message });
    } finally {
      this.loadingMore = false;
    }
  }

  private applyKindFilter(kind: string): void {
    if (this.kindFilter === kind) {
      return;
    }
    this.kindFilter = kind;
    this.events = [];
    this.hasMore = false;
    this.nextBeforeSeq = null;
    this.load();
  }

  private kindLabel(kind: string): string {
    if (kind === 'user') {
      return '用户';
    }
    if (kind === 'assistant') {
      return '助手';
    }
    if (kind === 'tool') {
      return '工具';
    }
    if (kind === 'system') {
      return '系统';
    }
    if (kind === 'context') {
      return '上下文';
    }
    if (kind === 'compacted') {
      return '压缩';
    }
    return kind === '' ? '未知' : kind;
  }

  private kindBadgeText(kind: string): Resource {
    if (kind === 'user') {
      return $r('app.color.brand');
    }
    if (kind === 'assistant') {
      return $r('app.color.success');
    }
    if (kind === 'tool' || kind === 'compacted') {
      return $r('app.color.warning');
    }
    return $r('app.color.text_secondary');
  }

  private kindBadgeBg(kind: string): Resource {
    if (kind === 'user') {
      return $r('app.color.brand_light');
    }
    if (kind === 'assistant') {
      return $r('app.color.success_soft');
    }
    if (kind === 'tool' || kind === 'compacted') {
      return $r('app.color.warning_soft');
    }
    return $r('app.color.bg_input');
  }

  private metricCells(): Array<TrajectoryMetricCell> {
    const m: TrajectoryMetricsModel | null = this.metrics;
    const turns: string = m === null ? '—' : m.turns.toLocaleString();
    const steps: string = m === null ? '—' : m.steps.toLocaleString();
    const ttft: string = m === null || m.ttftAvgMs === null ? '—' : `${Math.round(m.ttftAvgMs)} ms`;
    const tokPerS: string = m === null || m.tokPerS === null ? '—' : `${m.tokPerS.toFixed(1)} tok/s`;
    const llmMs: string = m === null || m.llmDurationMs === null ? '—' : `${Math.round(m.llmDurationMs)} ms`;
    const toolMs: string = m === null || m.toolDurationMs === null ? '—' : `${Math.round(m.toolDurationMs)} ms`;
    const inputTok: string = m === null || m.inputTokens === null ? '—' : m.inputTokens.toLocaleString();
    const outputTok: string = m === null || m.outputTokens === null ? '—' : m.outputTokens.toLocaleString();
    const cacheRead: string = m === null || m.cacheReadTokens === null ? '—' : m.cacheReadTokens.toLocaleString();
    const cacheHit: string = m === null || m.cacheHitRatio === null ? '—' : `${Math.round(m.cacheHitRatio * 100)}%`;
    return [
      new TrajectoryMetricCell('回合', turns),
      new TrajectoryMetricCell('步数', steps),
      new TrajectoryMetricCell('平均首字', ttft),
      new TrajectoryMetricCell('生成速度', tokPerS),
      new TrajectoryMetricCell('LLM 耗时', llmMs),
      new TrajectoryMetricCell('工具耗时', toolMs),
      new TrajectoryMetricCell('输入 token', inputTok),
      new TrajectoryMetricCell('输出 token', outputTok),
      new TrajectoryMetricCell('缓存读取', cacheRead),
      new TrajectoryMetricCell('缓存命中', cacheHit)
    ];
  }

  private exportLabel(): string {
    if (this.exporting) {
      return '导出中...';
    }
    return '导出';
  }

  private showExportSheet(): void {
    this.menuTitle = '导出轨迹';
    this.menuMessage = '选择导出格式';
    this.menuOptions = [
      new MenuSheetOption($r('sys.symbol.doc_plaintext'), 'JSONL（逐行事件）', '每行一个 JSON 事件', false),
      new MenuSheetOption($r('sys.symbol.doc_text'), 'JSON（事件数组）', '单个 JSON 数组文件', false)
    ];
    this.menuActions = [
      (): void => {
        this.exportTrajectory('jsonl');
      },
      (): void => {
        this.exportTrajectory('json');
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

  private async exportTrajectory(format: string): Promise<void> {
    if (this.exporting) {
      return;
    }
    this.exporting = true;
    try {
      const buffer: ArrayBuffer =
        await TrajectoryService.exportBlob(this.agentId, this.threadId, format);
      this.saveExport(format, buffer);
    } catch (e) {
      const message: string = e instanceof OctopApiError ? e.message : '导出失败';
      this.getUIContext().getPromptAction().showToast({ message });
    } finally {
      this.exporting = false;
    }
  }

  private saveExport(format: string, buffer: ArrayBuffer): void {
    const docPicker = new picker.DocumentViewPicker();
    const saveOptions = new picker.DocumentSaveOptions();
    saveOptions.newFileNames = [`trajectory_${this.threadId}.${format}`];
    docPicker.save(saveOptions).then(async (uris: Array<string>): Promise<void> => {
      if (uris.length > 0) {
        const file = fileIo.openSync(uris[0], fileIo.OpenMode.READ_WRITE);
        try {
          fileIo.writeSync(file.fd, buffer);
        } finally {
          fileIo.closeSync(file);
        }
        this.getUIContext().getPromptAction().showToast({ message: '已保存' });
      }
    }).catch((): void => {
      Log.warn('trajectory export save canceled or failed');
    });
  }

  build() {
    NavDestination() {
      Column() {
        PageHeader({ title: '对话轨迹' })

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
            Column() {
              Flex({ wrap: FlexWrap.Wrap }) {
                ForEach(this.metricCells(), (cell: TrajectoryMetricCell) => {
                  Column({ space: 4 }) {
                    Text(cell.label)
                      .fontSize(11)
                      .fontColor($r('app.color.text_tertiary'))
                    Text(cell.text)
                      .fontSize(15)
                      .fontWeight(FontWeight.Medium)
                      .fontColor($r('app.color.text_primary'))
                      .maxLines(1)
                  }
                  .width('50%')
                  .alignItems(HorizontalAlign.Start)
                  .padding({ top: 10, bottom: 2 })
                }, (cell: TrajectoryMetricCell) => `${cell.label}_${cell.text}`)
              }
              .width('100%')
            }
            .width('100%')
            .padding({ left: 16, right: 16, top: 6, bottom: 8 })
            .borderRadius(16)
            .backgroundColor($r('app.color.bg_card'))
            .border({ width: 1, color: $r('app.color.divider') })

            Row({ space: 10 }) {
              Scroll() {
                Row({ space: 8 }) {
                  ForEach(this.kindChips, (chip: TrajectoryKindChip) => {
                    Text(chip.label)
                      .fontSize(12)
                      .fontWeight(this.kindFilter === chip.kind ? FontWeight.Medium : FontWeight.Normal)
                      .fontColor(this.kindFilter === chip.kind ?
                        $r('app.color.text_on_brand') : $r('app.color.text_secondary'))
                      .backgroundColor(this.kindFilter === chip.kind ?
                        $r('app.color.brand') : $r('app.color.bg_input'))
                      .height(30)
                      .padding({ left: 12, right: 12 })
                      .borderRadius(15)
                      .maxLines(1)
                      .onClick((): void => {
                        this.applyKindFilter(chip.kind);
                      })
                  }, (chip: TrajectoryKindChip) => chip.kind)
                }
              }
              .scrollable(ScrollDirection.Horizontal)
              .scrollBar(BarState.Off)
              .layoutWeight(1)

              Button(this.exportLabel())
                .fontSize(12)
                .height(30)
                .borderRadius(15)
                .backgroundColor($r('app.color.bg_input'))
                .fontColor($r('app.color.brand'))
                .enabled(!this.exporting)
                .onClick((): void => {
                  this.showExportSheet();
                })
            }
            .width('100%')
            .margin({ top: 12 })

            Refresh({ refreshing: $$this.refreshing }) {
              List({ space: 10 }) {
                if (this.events.length === 0) {
                  ListItem() {
                    EmptyView({
                      title: '暂无轨迹事件',
                      subtitle: '发送消息后这里会展示对话轨迹',
                      icon: $r('sys.symbol.clock')
                    })
                  }
                } else {
                  ForEach(this.events, (event: TrajectoryEventModel) => {
                    ListItem() {
                      Column({ space: 8 }) {
                        Row({ space: 8 }) {
                          Text(this.kindLabel(event.kind))
                            .fontSize(11)
                            .fontWeight(FontWeight.Medium)
                            .fontColor(this.kindBadgeText(event.kind))
                            .backgroundColor(this.kindBadgeBg(event.kind))
                            .borderRadius(6)
                            .padding({ left: 8, right: 8, top: 3, bottom: 3 })
                            .maxLines(1)
                          Text(`#${event.seq}`)
                            .fontSize(11)
                            .fontColor($r('app.color.text_tertiary'))
                            .maxLines(1)
                          if (event.isError) {
                            Text('错误')
                              .fontSize(11)
                              .fontWeight(FontWeight.Medium)
                              .fontColor($r('app.color.danger'))
                              .backgroundColor($r('app.color.danger_soft'))
                              .borderRadius(6)
                              .padding({ left: 8, right: 8, top: 3, bottom: 3 })
                              .maxLines(1)
                          }
                          Blank()
                          Text(TimeFormat.full(event.tsMs))
                            .fontSize(11)
                            .fontColor($r('app.color.text_tertiary'))
                            .maxLines(1)
                        }
                        .width('100%')

                        Text(event.summary === '' ? '（无摘要）' : event.summary)
                          .fontSize(13)
                          .fontColor(event.isError ?
                            $r('app.color.danger') : $r('app.color.text_secondary'))
                          .maxLines(2)
                          .textOverflow({ overflow: TextOverflow.Ellipsis })
                          .width('100%')
                          .lineHeight(19)
                      }
                      .width('100%')
                      .padding(14)
                      .borderRadius(16)
                      .backgroundColor($r('app.color.bg_card'))
                      .border({ width: 1, color: $r('app.color.divider') })
                    }
                  }, (event: TrajectoryEventModel) => event.eventId)

                  if (this.hasMore) {
                    ListItem() {
                      Button(this.loadingMore ? '加载中...' : '加载更多')
                        .fontSize(13)
                        .height(34)
                        .borderRadius(17)
                        .padding({ left: 24, right: 24 })
                        .backgroundColor($r('app.color.bg_input'))
                        .fontColor($r('app.color.brand'))
                        .enabled(!this.loadingMore)
                        .onClick((): void => {
                          this.loadMore();
                        })
                    }
                    .width('100%')
                    .margin({ top: 4 })
                  }
                }
              }
              .width('100%')
              .height('100%')
              .scrollBar(BarState.Off)
            }
            .layoutWeight(1)
            .width('100%')
            .margin({ top: 12 })
            .onRefreshing((): void => {
              this.load();
            })
          }
          .width('100%')
          .height('100%')
          .padding({ left: 14, right: 14, top: 4, bottom: 12 })
          .alignItems(HorizontalAlign.Start)
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
