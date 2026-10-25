import { AgentService } from '../service/AgentService';
import { ThreadService } from '../service/ThreadService';
import { ThreadModel } from '../model/ThreadModels';
import { AgentModel } from '../model/AgentModels';
import { SessionStore } from '../store/SessionStore';
import { TimeFormat } from '../utils/TimeFormat';
import { Log } from '../utils/Logger';

/**
 * 命令面板（"/"或头部搜索触发）：
 * - 快速操作：新对话 / 查看会话 / 打开工作台 / 设置
 * - 会话搜索：客户端过滤标题，点击切换会话
 * - 专家搜索：客户端过滤名称，点击切换专家
 */
@Component
export struct CommandPalette {
  @Prop agentId: string = '';
  onClose: () => void = (): void => {
  };
  onOpenSettings: () => void = (): void => {
  };
  onOpenSessions: () => void = (): void => {
  };
  @State query: string = '';
  @State threads: Array<ThreadModel> = [];
  @State agents: Array<AgentModel> = [];
  @State loading: boolean = false;
  @State loaded: boolean = false;

  aboutToAppear(): void {
    this.loadData();
  }

  private async loadData(): Promise<void> {
    this.loading = true;
    try {
      this.agents = await AgentService.listMine();
    } catch (e) {
      Log.warn('palette agents load failed');
    }
    const agentId: string = AppStorage.get<string>(SessionStore.KEY_AGENT_ID) ?? this.agentId;
    if (agentId !== '') {
      try {
        this.threads = await ThreadService.list(agentId, 50);
      } catch (e) {
        Log.warn('palette threads load failed');
      }
    }
    this.loading = false;
    this.loaded = true;
  }

  private normalizedQuery(): string {
    return this.query.trim().toLowerCase();
  }

  private filteredThreads(): Array<ThreadModel> {
    const q: string = this.normalizedQuery();
    if (q === '') {
      return this.threads.slice(0, 5);
    }
    const result: Array<ThreadModel> = [];
    for (const thread of this.threads) {
      if (thread.title.toLowerCase().indexOf(q) >= 0) {
        result.push(thread);
        if (result.length >= 20) {
          break;
        }
      }
    }
    return result;
  }

  private filteredAgents(): Array<AgentModel> {
    const q: string = this.normalizedQuery();
    if (q === '') {
      return this.agents;
    }
    const result: Array<AgentModel> = [];
    for (const agent of this.agents) {
      if (agent.name.toLowerCase().indexOf(q) >= 0 ||
        agent.description.toLowerCase().indexOf(q) >= 0) {
        result.push(agent);
      }
    }
    return result;
  }

  private startNewChat(): void {
    AppStorage.setOrCreate(SessionStore.KEY_ACTIVE_THREAD_ID, '');
    AppStorage.setOrCreate(SessionStore.KEY_MAIN_TAB, 1);
    this.onClose();
  }

  private openThread(threadId: string): void {
    AppStorage.setOrCreate(SessionStore.KEY_ACTIVE_THREAD_ID, threadId);
    AppStorage.setOrCreate(SessionStore.KEY_MAIN_TAB, 1);
    this.onClose();
  }

  private switchAgent(agent: AgentModel): void {
    SessionStore.setCurrentAgent(agent);
    this.onClose();
  }

  private gotoSessions(): void {
    this.onOpenSessions();
    this.onClose();
  }

  private gotoWorkspace(): void {
    AppStorage.setOrCreate(SessionStore.KEY_MAIN_TAB, 2);
    this.onClose();
  }

  @Builder
  sectionHeader(title: string) {
    Text(title)
      .fontSize(12)
      .fontWeight(FontWeight.Medium)
      .fontColor($r('app.color.text_tertiary'))
      .width('100%')
      .padding({ left: 20, right: 20, top: 16, bottom: 8 })
  }

  @Builder
  quickActionRow(icon: Resource, title: string, handler: () => void) {
    Row({ space: 12 }) {
      Column() {
        SymbolGlyph(icon)
          .fontSize(16)
          .fontColor([$r('app.color.brand')])
      }
      .width(32)
      .height(32)
      .borderRadius(10)
      .backgroundColor($r('app.color.brand_light'))
      .justifyContent(FlexAlign.Center)
      Text(title)
        .fontSize(15)
        .fontColor($r('app.color.text_primary'))
        .layoutWeight(1)
      SymbolGlyph($r('sys.symbol.chevron_right'))
        .fontSize(13)
        .fontColor([$r('app.color.text_tertiary')])
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 8, bottom: 8 })
    .onClick((): void => {
      handler();
    })
  }

  @Builder
  threadRow(thread: ThreadModel) {
    Row({ space: 12 }) {
      Column() {
        SymbolGlyph($r('sys.symbol.message_fill'))
          .fontSize(15)
          .fontColor([$r('app.color.brand')])
      }
      .width(32)
      .height(32)
      .borderRadius(10)
      .backgroundColor($r('app.color.brand_light'))
      .justifyContent(FlexAlign.Center)
      Column({ space: 2 }) {
        Text(thread.title === '' ? '新对话' : thread.title)
          .fontSize(15)
          .fontColor($r('app.color.text_primary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(TimeFormat.list(thread.lastActiveMs))
          .fontSize(11)
          .fontColor($r('app.color.text_tertiary'))
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      SymbolGlyph($r('sys.symbol.arrow_up_right'))
        .fontSize(14)
        .fontColor([$r('app.color.text_tertiary')])
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 8, bottom: 8 })
    .onClick((): void => {
      this.openThread(thread.threadId);
    })
  }

  @Builder
  agentRow(agent: AgentModel) {
    Row({ space: 12 }) {
      Image($r('app.media.octop_logo'))
        .width(32)
        .height(32)
        .borderRadius(16)
        .backgroundColor($r('app.color.brand_light'))
      Column({ space: 2 }) {
        Text(agent.name)
          .fontSize(15)
          .fontColor($r('app.color.text_primary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        if (agent.description !== '') {
          Text(agent.description)
            .fontSize(11)
            .fontColor($r('app.color.text_tertiary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      SymbolGlyph($r('sys.symbol.arrow_up_right'))
        .fontSize(14)
        .fontColor([$r('app.color.text_tertiary')])
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 8, bottom: 8 })
    .onClick((): void => {
      this.switchAgent(agent);
    })
  }

  build() {
    Column() {
      Search({ value: this.query, placeholder: '搜索会话与专家' })
        .width('100%')
        .height(40)
        .textFont({ size: 14 })
        .borderRadius(20)
        .backgroundColor($r('app.color.bg_input'))
        .padding({ left: 16, right: 16 })
        .margin({ left: 16, right: 16, top: 12 })
        .onChange((value: string): void => {
          this.query = value;
        })

      if (this.loading) {
        Column() {
          LoadingProgress()
            .width(28)
            .height(28)
            .color($r('app.color.brand'))
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else {
        List({ space: 0 }) {
          if (this.normalizedQuery() === '') {
            ListItem() {
              Column() {
                this.sectionHeader('快速操作')
                Column() {
                  this.quickActionRow($r('sys.symbol.square_and_pencil'), '新对话', (): void => {
                    this.startNewChat();
                  })
                  this.quickActionRow($r('sys.symbol.timer'), '查看全部会话', (): void => {
                    this.gotoSessions();
                  })
                  this.quickActionRow($r('sys.symbol.square_grid_2x2'), '打开工作台', (): void => {
                    this.gotoWorkspace();
                  })
                  this.quickActionRow($r('sys.symbol.gearshape'), '设置', (): void => {
                    this.onOpenSettings();
                    this.onClose();
                  })
                }
                .width('100%')
              }
              .width('100%')
            }

            if (this.filteredThreads().length > 0) {
              ListItem() {
                Column() {
                  this.sectionHeader('最近会话')
                  ForEach(this.filteredThreads(), (thread: ThreadModel) => {
                    this.threadRow(thread)
                  }, (thread: ThreadModel) => thread.threadId)
                }
                .width('100%')
              }
            }
          } else {
            ListItem() {
              Column() {
                this.sectionHeader('会话')
                if (this.filteredThreads().length === 0) {
                  Text('无匹配会话')
                    .fontSize(13)
                    .fontColor($r('app.color.text_tertiary'))
                    .padding({ left: 20, bottom: 8 })
                }
                ForEach(this.filteredThreads(), (thread: ThreadModel) => {
                  this.threadRow(thread)
                }, (thread: ThreadModel) => thread.threadId)
              }
              .width('100%')
            }
          }

          if (this.filteredAgents().length > 0) {
            ListItem() {
              Column() {
                this.sectionHeader(this.normalizedQuery() === '' ? '专家' : '匹配专家')
                ForEach(this.filteredAgents(), (agent: AgentModel) => {
                  this.agentRow(agent)
                }, (agent: AgentModel) => agent.agentId)
              }
              .width('100%')
            }
          }
        }
        .layoutWeight(1)
        .width('100%')
        .scrollBar(BarState.Off)
        .padding({ bottom: 24 })
      }
    }
    .width('100%')
    .height('100%')
  }
}
