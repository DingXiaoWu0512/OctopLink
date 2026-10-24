import { SessionStore } from '../../store/SessionStore';
import { AgentService } from '../../service/AgentService';
import { ThreadService } from '../../service/ThreadService';
import { OctopApiError } from '../../net/HttpClient';
import { ThreadModel } from '../../model/ThreadModels';
import { EmptyView } from '../../components/EmptyView';
import { ErrorRetry } from '../../components/ErrorRetry';
import { ThreadRenameDialog } from '../../components/ThreadRenameDialog';
import { ThreadSettingsNavParam } from './ThreadSettingsPage';
import { TimeFormat } from '../../utils/TimeFormat';
import { UiMaterialKit } from '../../components/UiMaterialKit';
import { ThreadDigestCache } from '../../utils/ThreadDigestCache';

/** 会话分组（置顶无表头 / 今天 / 昨天 / 7天内 / 更早） */
class SessionsThreadGroup {
  readonly header: string;
  readonly items: Array<ThreadModel>;

  constructor(header: string, items: Array<ThreadModel>) {
    this.header = header;
    this.items = items;
  }
}

/** 会话列表 Tab：日期分组 + 左滑快捷操作（置顶/重命名/删除），点击切回聊天 Tab */
@Component
export struct SessionsTab {
  @Consume('navStack') navStack: NavPathStack;
  @StorageProp(SessionStore.KEY_AGENT_NAME) agentName: string = '';
  @StorageLink(SessionStore.KEY_THREADS_DIRTY) @Watch('onDirtyChanged') threadsDirty: boolean = false;
  @State groups: Array<SessionsThreadGroup> = [];
  @State threadCount: number = 0;
  @State loading: boolean = false;
  @State refreshing: boolean = false;
  @State errorMsg: string = '';
  @State operating: boolean = false;
  @Prop topInset: number = 0;
  @Prop bottomPad: number = 72;
  private renameController: CustomDialogController | null = null;

  aboutToAppear(): void {
    this.reload();
  }

  onDirtyChanged(): void {
    if (this.threadsDirty) {
      this.threadsDirty = false;
      this.reload();
    }
  }

  private agentId(): string {
    return AppStorage.get<string>(SessionStore.KEY_AGENT_ID) ?? '';
  }

  /** 会话摘要副标题（本地缓存，无则空串） */
  private digestSummary(thread: ThreadModel): string {
    const digest = ThreadDigestCache.get(thread.threadId);
    return digest === null ? '' : digest.lastText;
  }

  /** 会话消息数文案（本地缓存） */
  private digestCountText(thread: ThreadModel): string {
    const digest = ThreadDigestCache.get(thread.threadId);
    return digest === null ? '' : `${digest.count} 条`;
  }

  /** 刷新：确保已选择专家，然后按日期分组拉取线程列表 */
  private async reload(): Promise<void> {
    if (this.agentId() === '') {
      try {
        const agents = await AgentService.listMine();
        if (agents.length > 0) {
          SessionStore.setCurrentAgent(agents[0]);
        }
      } catch (e) {
        this.errorMsg = e instanceof OctopApiError ? e.message : '专家列表加载失败';
        this.loading = false;
        this.refreshing = false;
        return;
      }
    }
    this.loading = true;
    try {
      const id: string = this.agentId();
      if (id === '') {
        this.groups = [];
        this.threadCount = 0;
        this.errorMsg = '';
        return;
      }
      const threads = await ThreadService.list(id, 50);
      this.errorMsg = '';
      this.rebuildGroups(threads);
    } catch (e) {
      this.errorMsg = e instanceof OctopApiError ? e.message : '会话列表加载失败';
    } finally {
      this.loading = false;
      this.refreshing = false;
    }
  }

  private rebuildGroups(threads: Array<ThreadModel>): void {
    const pinned: Array<ThreadModel> = [];
    const today: Array<ThreadModel> = [];
    const yesterday: Array<ThreadModel> = [];
    const week: Array<ThreadModel> = [];
    const older: Array<ThreadModel> = [];
    const now = new Date();
    const dayMs: number = 86400000;
    const todayStart: number = new Date(now.getFullYear(), now.getMonth(), now.getDate()).getTime();
    const yesterdayStart: number = todayStart - dayMs;
    const weekStart: number = todayStart - dayMs * 7;
    for (const thread of threads) {
      if (thread.pinned) {
        pinned.push(thread);
      } else if (thread.lastActiveMs >= todayStart) {
        today.push(thread);
      } else if (thread.lastActiveMs >= yesterdayStart) {
        yesterday.push(thread);
      } else if (thread.lastActiveMs >= weekStart) {
        week.push(thread);
      } else {
        older.push(thread);
      }
    }
    const groups: Array<SessionsThreadGroup> = [];
    if (pinned.length > 0) {
      groups.push(new SessionsThreadGroup('', pinned));
    }
    if (today.length > 0) {
      groups.push(new SessionsThreadGroup('今天', today));
    }
    if (yesterday.length > 0) {
      groups.push(new SessionsThreadGroup('昨天', yesterday));
    }
    if (week.length > 0) {
      groups.push(new SessionsThreadGroup('7天内', week));
    }
    if (older.length > 0) {
      groups.push(new SessionsThreadGroup('更早', older));
    }
    this.groups = groups;
    this.threadCount = threads.length;
  }

  /** 点击会话：设为活跃会话并切回聊天 Tab */
  private openThread(thread: ThreadModel): void {
    AppStorage.setOrCreate(SessionStore.KEY_ACTIVE_THREAD_ID, thread.threadId);
    AppStorage.setOrCreate(SessionStore.KEY_MAIN_TAB, 1);
  }

  /** 新对话：回到聊天 Tab 欢迎态 */
  private startNewChat(): void {
    AppStorage.setOrCreate(SessionStore.KEY_ACTIVE_THREAD_ID, '');
    AppStorage.setOrCreate(SessionStore.KEY_MAIN_TAB, 1);
  }

  /** 长按会话：操作菜单（置顶/重命名/删除） */
  private showThreadMenu(thread: ThreadModel): void {
    const sheets: Array<SheetInfo> = [];
    sheets.push({
      title: thread.pinned ? '取消置顶' : '置顶该会话',
      action: (): void => {
        this.togglePinned(thread);
      }
    });
    sheets.push({
      title: '重命名会话',
      action: (): void => {
        this.showRenameDialog(thread);
      }
    });
    sheets.push({
      title: '从最后回复分叉',
      action: (): void => {
        this.forkFromLast(thread);
      }
    });
    sheets.push({
      title: '会话设置',
      action: (): void => {
        this.openThreadSettings(thread);
      }
    });
    sheets.push({
      title: '删除会话',
      action: (): void => {
        this.confirmDeleteThread(thread);
      }
    });
    this.getUIContext().showActionSheet({
      title: thread.title === '' ? '新对话' : thread.title,
      message: '选择要执行的操作',
      sheets: sheets
    });
  }

  private async togglePinned(thread: ThreadModel): Promise<void> {
    if (this.operating) {
      return;
    }
    this.operating = true;
    try {
      await ThreadService.setPinned(this.agentId(), thread.threadId, !thread.pinned);
      await this.reload();
    } catch (e) {
      this.getUIContext().getPromptAction().showToast({
        message: e instanceof OctopApiError ? e.message : '操作失败'
      });
    } finally {
      this.operating = false;
    }
  }

  private showRenameDialog(thread: ThreadModel): void {
    this.renameController = new CustomDialogController({
      builder: ThreadRenameDialog({
        initialName: thread.title,
        onConfirm: (name: string): void => {
          this.renameThread(thread.threadId, name);
        }
      }),
      autoCancel: true
    });
    this.renameController.open();
  }

  private async renameThread(threadId: string, name: string): Promise<void> {
    try {
      await ThreadService.rename(this.agentId(), threadId, name);
      await this.reload();
    } catch (e) {
      this.getUIContext().getPromptAction().showToast({
        message: e instanceof OctopApiError ? e.message : '重命名失败'
      });
    }
  }

  /** 从最后一条助手回复分叉新会话，成功后切到新会话聊天页 */
  private async forkFromLast(thread: ThreadModel): Promise<void> {
    if (this.operating) {
      return;
    }
    this.operating = true;
    try {
      const newThreadId: string = await ThreadService.forkFromLast(this.agentId(), thread.threadId);
      if (newThreadId === '') {
        this.getUIContext().getPromptAction().showToast({ message: '分叉失败：响应缺少会话 ID' });
        return;
      }
      AppStorage.setOrCreate(SessionStore.KEY_ACTIVE_THREAD_ID, newThreadId);
      AppStorage.setOrCreate(SessionStore.KEY_THREADS_DIRTY, true);
      AppStorage.setOrCreate(SessionStore.KEY_MAIN_TAB, 1);
      this.getUIContext().getPromptAction().showToast({ message: '已从最后回复分叉新会话' });
    } catch (e) {
      this.getUIContext().getPromptAction().showToast({
        message: e instanceof OctopApiError ? e.message : '分叉失败'
      });
    } finally {
      this.operating = false;
    }
  }

  /** 打开会话设置页（模型/推理/对话模式/审批策略） */
  private openThreadSettings(thread: ThreadModel): void {
    this.navStack.pushPath(new NavPathInfo('threadSettings',
      new ThreadSettingsNavParam(this.agentId(), thread.threadId)));
  }

  private confirmDeleteThread(thread: ThreadModel): void {
    this.getUIContext().showAlertDialog({
      title: '删除会话',
      message: '删除后聊天记录不可恢复，确定删除该会话吗？',
      primaryButton: {
        value: $r('app.string.common_cancel'),
        action: (): void => {
        }
      },
      secondaryButton: {
        value: $r('app.string.common_confirm'),
        action: (): void => {
          this.deleteThread(thread.threadId);
        }
      },
      alignment: DialogAlignment.Bottom
    });
  }

  private async deleteThread(threadId: string): Promise<void> {
    if (this.operating) {
      return;
    }
    this.operating = true;
    try {
      await ThreadService.remove(this.agentId(), threadId);
      if (threadId === (AppStorage.get<string>(SessionStore.KEY_ACTIVE_THREAD_ID) ?? '')) {
        AppStorage.setOrCreate(SessionStore.KEY_ACTIVE_THREAD_ID, '');
      }
      await this.reload();
    } catch (e) {
      this.getUIContext().getPromptAction().showToast({
        message: e instanceof OctopApiError ? e.message : '删除失败'
      });
    } finally {
      this.operating = false;
    }
  }

  @Builder
  groupHeader(title: string) {
    if (title === '') {
      Row()
        .height(2)
    } else {
      Text(title)
        .fontSize(12)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_tertiary'))
        .padding({ left: 2, top: 10, bottom: 6 })
    }
  }

  @Builder
  swipeActions(thread: ThreadModel) {
    Row({ space: 8 }) {
      Column({ space: 3 }) {
        SymbolGlyph($r('sys.symbol.pin'))
          .fontSize(17)
          .fontColor([$r('app.color.warning')])
        Text(thread.pinned ? '取消置顶' : '置顶')
          .fontSize(10)
          .fontColor($r('app.color.text_secondary'))
      }
      .width(56)
      .height(52)
      .borderRadius(12)
      .backgroundColor($r('app.color.swipe_pin'))
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
      .onClick((): void => {
        this.togglePinned(thread);
      })

      Column({ space: 3 }) {
        SymbolGlyph($r('sys.symbol.character_textbox'))
          .fontSize(17)
          .fontColor([$r('app.color.brand')])
        Text('重命名')
          .fontSize(10)
          .fontColor($r('app.color.text_secondary'))
      }
      .width(56)
      .height(52)
      .borderRadius(12)
      .backgroundColor($r('app.color.swipe_rename'))
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
      .onClick((): void => {
        this.showRenameDialog(thread);
      })

      Column({ space: 3 }) {
        SymbolGlyph($r('sys.symbol.trash'))
          .fontSize(17)
          .fontColor([$r('app.color.danger')])
        Text('删除')
          .fontSize(10)
          .fontColor($r('app.color.text_secondary'))
      }
      .width(56)
      .height(52)
      .borderRadius(12)
      .backgroundColor($r('app.color.swipe_delete'))
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
      .onClick((): void => {
        this.confirmDeleteThread(thread);
      })
    }
    .padding({ left: 4, right: 4 })
  }

  @Builder
  threadCard(thread: ThreadModel) {
    Row({ space: 12 }) {
      Column() {
        SymbolGlyph($r('sys.symbol.message'))
          .fontSize(18)
          .fontColor([$r('app.color.brand')])
      }
      .width(38)
      .height(38)
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
      .backgroundColor($r('app.color.brand_light'))
      .borderRadius(12)

      Column({ space: 6 }) {
        Row({ space: 8 }) {
          Text(thread.title === '' ? '新对话' : thread.title)
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
          if (thread.pinned) {
            SymbolGlyph($r('sys.symbol.star_fill'))
              .fontSize(13)
              .fontColor([$r('app.color.warning')])
          }
          if (thread.modelRef !== '' && thread.modelRef !== 'auto/auto') {
            Text(thread.modelRef)
              .fontSize(10)
              .fontColor($r('app.color.text_tertiary'))
              .maxLines(1)
              .constraintSize({ maxWidth: 90 })
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .padding({ left: 6, right: 6, top: 2, bottom: 2 })
              .borderRadius(8)
              .backgroundColor($r('app.color.bg_input'))
          }
          Text(TimeFormat.list(thread.lastActiveMs))
            .fontSize(12)
            .fontColor($r('app.color.text_tertiary'))
        }
        .width('100%')

        if (thread.turnActive) {
          Row({ space: 5 }) {
            LoadingProgress()
              .width(12)
              .height(12)
              .color($r('app.color.brand'))
            Text('专家正在回复…')
              .fontSize(12)
              .fontColor($r('app.color.brand'))
          }
        } else if (thread.awaitingUser) {
          Row({ space: 5 }) {
            SymbolGlyph($r('sys.symbol.paperplane'))
              .fontSize(12)
              .fontColor([$r('app.color.warning')])
            Text('待你回复')
              .fontSize(12)
              .fontColor($r('app.color.warning'))
          }
        } else if (this.digestSummary(thread) !== '') {
          Row({ space: 8 }) {
            Text(this.digestSummary(thread))
              .fontSize(13)
              .fontColor($r('app.color.text_tertiary'))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .layoutWeight(1)
            Text(this.digestCountText(thread))
              .fontSize(11)
              .fontColor($r('app.color.text_tertiary'))
          }
          .width('100%')
        } else if (!thread.hasMessages) {
          Text('还没有消息，去说第一句吧')
            .fontSize(12)
            .fontColor($r('app.color.text_tertiary'))
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      SymbolGlyph($r('sys.symbol.chevron_right'))
        .fontSize(14)
        .fontColor([$r('app.color.text_tertiary')])
    }
    .width('100%')
    .padding({ left: 12, right: 12, top: 12, bottom: 12 })
    .borderRadius(16)
    .backgroundColor($r('app.color.bg_card'))
    .border({ width: 1, color: $r('app.color.card_stroke') })
    .shadow({ radius: 10, color: '#0A000000', offsetY: 3 })
    .onClick((): void => {
      this.openThread(thread);
    })
    .gesture(
      LongPressGesture()
        .onAction((event: GestureEvent): void => {
          this.showThreadMenu(thread);
        })
    )
  }

  build() {
    Stack({ alignContent: Alignment.BottomEnd }) {
      Column() {
        Row() {
          Column({ space: 4 }) {
            Text($r('app.string.tab_sessions'))
              .fontSize(26)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.text_primary'))
            Row({ space: 5 }) {
              if (this.agentName !== '') {
                SymbolGlyph($r('sys.symbol.robot'))
                  .fontSize(13)
                  .fontColor([$r('app.color.brand')])
                Text(this.agentName)
                  .fontSize(13)
                  .fontColor($r('app.color.text_secondary'))
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .constraintSize({ maxWidth: 160 })
              }
              Text(this.agentName !== '' ? `· ${this.threadCount} 个会话` : `${this.threadCount} 个会话`)
                .fontSize(13)
                .fontColor($r('app.color.text_tertiary'))
            }
            .width('100%')
          }
          .alignItems(HorizontalAlign.Start)
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 16, bottom: 10 })

        if (this.loading && this.threadCount === 0) {
          Column() {
            LoadingProgress()
              .width(36)
              .height(36)
              .color($r('app.color.brand'))
          }
          .layoutWeight(1)
          .width('100%')
          .justifyContent(FlexAlign.Center)
        } else if (this.errorMsg !== '' && this.threadCount === 0) {
          Column() {
            ErrorRetry({
              message: this.errorMsg,
              onRetry: (): void => {
                this.reload();
              }
            })
          }
          .layoutWeight(1)
          .width('100%')
          .justifyContent(FlexAlign.Center)
        } else {
          Refresh({ refreshing: $$this.refreshing }) {
            if (this.threadCount === 0) {
              Column() {
                EmptyView({
                  title: '还没有对话',
                  subtitle: '点击右下角按钮，开始与专家交流'
                })
                Button('开始新对话')
                  .height(42)
                  .fontSize(15)
                  .borderRadius(21)
                  .backgroundColor($r('app.color.brand'))
                  .fontColor($r('app.color.text_on_brand'))
                  .padding({ left: 28, right: 28 })
                  .margin({ top: 8 })
                  .onClick((): void => {
                    this.startNewChat();
                  })
              }
              .width('100%')
              .height('100%')
              .justifyContent(FlexAlign.Center)
            } else {
              List({ space: 10 }) {
                ForEach(this.groups, (group: SessionsThreadGroup) => {
                  ListItemGroup({ header: this.groupHeader(group.header) }) {
                    ForEach(group.items, (thread: ThreadModel) => {
                      ListItem() {
                        this.threadCard(thread)
                      }
                      .swipeAction({
                        end: (): void => {
                          this.swipeActions(thread);
                        }
                      })
                    }, (thread: ThreadModel) =>
                      `${thread.threadId}_${thread.title}_${thread.pinned}_${thread.turnActive}_${this.digestSummary(thread)}`)
                  }
                }, (group: SessionsThreadGroup) =>
                  `${group.header}_${group.items.length > 0 ? group.items[0].threadId : 'none'}`)
              }
              .width('100%')
              .height('100%')
              .padding({ left: 16, right: 16, top: 2, bottom: this.bottomPad + 12 })
              .scrollBar(BarState.Off)
            }
          }
          .layoutWeight(1)
          .width('100%')
          .onRefreshing((): void => {
            this.reload();
          })
        }
      }
      .width('100%')
      .height('100%')
      .padding({ top: this.topInset })

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
      .margin({ left: 22, right: 22, bottom: this.bottomPad })
      .onClick((): void => {
        this.startNewChat();
      })
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.bg_page'))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }
}
