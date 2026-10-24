import { ChatMessageModel, ChatRole } from '../../model/MessageModels';
import { ChatStreamController } from '../../service/ChatStreamController';
import { OctopApiError } from '../../net/HttpClient';
import { SessionStore } from '../../store/SessionStore';
import { ThreadService } from '../../service/ThreadService';
import { AgentService } from '../../service/AgentService';
import { WelcomeCardModel } from '../../model/ExpertModels';
import { MessageBubble } from '../../components/MessageBubble';
import { ErrorRetry } from '../../components/ErrorRetry';
import { WelcomeCard } from '../../components/WelcomeCard';
import { Log } from '../../utils/Logger';
import { util } from '@kit.ArkTS';

/** 路由参数：目标线程 */
export class ChatDetailNavParam {
  readonly threadId: string;
  readonly isNew: boolean;

  constructor(threadId: string, isNew: boolean) {
    this.threadId = threadId;
    this.isNew = isNew;
  }
}

@Component
export struct ChatDetailPage {
  @Consume('navStack') navStack: NavPathStack;
  @State title: string = '对话';
  @State messages: Array<ChatMessageModel> = [];
  @State inputText: string = '';
  @State streaming: boolean = false;
  @State connecting: boolean = false;
  @State loadError: string = '';
  @State historyReady: boolean = false;
  @State wsError: string = '';
  @State welcome: WelcomeCardModel | null = null;
  private param: ChatDetailNavParam | null = null;
  private controller: ChatStreamController | null = null;
  private scroller: Scroller = new Scroller();
  private lastScrollMs: number = 0;
  /** 当前接收增量帧的助手消息（steer 场景下可能不是最后一条） */
  private activeAssistant: ChatMessageModel | null = null;
  /** 本地预插入、等待 ack/drain 的 steer 用户消息 */
  private steerPending: ChatMessageModel | null = null;
  private currentTurnId: string = '';

  private agentId(): string {
    return AppStorage.get<string>(SessionStore.KEY_AGENT_ID) ?? '';
  }

  private onNavReady(ctx: NavDestinationContext): void {
    if (ctx.pathInfo.param instanceof ChatDetailNavParam) {
      this.param = ctx.pathInfo.param;
      this.title = ctx.pathInfo.param.isNew ? '新对话' : '对话';
      if (this.agentId() === '') {
        this.loadError = '未选择专家，请先在专家页选择';
        this.historyReady = true;
        return;
      }
      this.loadHistory();
      this.connectWs();
    } else {
      this.loadError = '页面参数错误';
      this.historyReady = true;
    }
  }

  private async loadHistory(): Promise<void> {
    const p = this.param;
    const agentId = this.agentId();
    if (p === null || agentId === '') {
      this.loadError = '参数错误';
      this.historyReady = true;
      return;
    }
    try {
      const messages = await ThreadService.history(agentId, p.threadId);
      if (messages.length === 0) {
        // 空会话：拉取欢迎卡片（失败静默降级为默认欢迎语）
        try {
          this.welcome = await AgentService.getWelcomeCard(agentId);
        } catch (e) {
          Log.debug('welcome card load failed, fallback');
          const welcomeText: string = AppStorage.get<string>(SessionStore.KEY_AGENT_WELCOME) ?? '';
          this.welcome = new WelcomeCardModel(welcomeText, []);
        }
      }
      this.messages = messages;
      this.loadError = '';
    } catch (e) {
      this.loadError = e instanceof OctopApiError ? e.message : '历史消息加载失败';
    } finally {
      this.historyReady = true;
    }
  }

  private async connectWs(): Promise<void> {
    const p = this.param;
    const agentId = this.agentId();
    if (p === null || agentId === '' || this.connecting) {
      return;
    }
    this.connecting = true;
    this.wsError = '';
    const controller = new ChatStreamController(agentId, p.threadId);
    this.controller = controller;
    this.wireCallbacks(controller);
    try {
      await controller.connect();
    } catch (e) {
      Log.warn(`WS connect failed: ${e instanceof OctopApiError ? e.message : 'unknown'}`);
      this.wsError = '实时通道连接失败，发送消息时将自动重试';
    } finally {
      this.connecting = false;
    }
  }

  private wireCallbacks(controller: ChatStreamController): void {
    controller.callbacks.onTextDelta = (delta: string): void => {
      const m = this.activeAssistant;
      if (m !== null) {
        m.appendText(delta);
        this.scrollToBottom(false);
      }
    };
    controller.callbacks.onReasoningDelta = (delta: string): void => {
      const m = this.activeAssistant;
      if (m !== null) {
        m.appendReasoning(delta);
      }
    };
    controller.callbacks.onToolActivity = (name: string): void => {
      const m = this.activeAssistant;
      if (m !== null) {
        m.addToolName(name);
      }
    };
    controller.callbacks.onTurnStarted = (turnId: string): void => {
      this.currentTurnId = turnId;
      Log.debug(`turn started: ${turnId}`);
    };
    controller.callbacks.onTurnEnded = (failed: boolean): void => {
      const m = this.activeAssistant;
      if (m !== null) {
        m.markEnded(failed, failed ? '回复中断' : '');
      }
      this.activeAssistant = null;
      this.currentTurnId = '';
      this.streaming = false;
      AppStorage.setOrCreate(SessionStore.KEY_THREADS_DIRTY, true);
    };
    controller.callbacks.onStreamError = (message: string): void => {
      const m = this.activeAssistant;
      if (m !== null) {
        m.markEnded(true, message);
      }
      this.activeAssistant = null;
      this.streaming = false;
      AppStorage.setOrCreate(SessionStore.KEY_THREADS_DIRTY, true);
    };
    controller.callbacks.onSteerAck = (status: string, reason: string): void => {
      if (status === 'rejected' || status === 'removed') {
        this.removeSteerPending();
        this.getUIContext().getPromptAction().showToast({
          message: status === 'rejected' && reason !== '' ? `追问被拒绝：${reason}` : '追问未成功'
        });
      }
    };
    controller.callbacks.onUserEcho = (content: string): void => {
      // drain 完成：本地已预插入用户消息则复用，否则按服务端回显补插
      if (this.steerPending !== null) {
        this.steerPending = null;
      } else if (content !== '') {
        this.messages.push(ChatMessageModel.fromUserText(content, Date.now()));
      }
      const m = ChatMessageModel.streamingAssistant();
      this.messages.push(m);
      this.activeAssistant = m;
      this.streaming = true;
      this.scrollToBottom(true);
    };
    controller.callbacks.onSteerDiscarded = (reason: string): void => {
      this.removeSteerPending();
      this.getUIContext().getPromptAction().showToast({ message: '追问已被取消' });
    };
    controller.callbacks.onConnectionClosed = (code: number, reason: string): void => {
      Log.warn(`WS connection closed: ${code} ${reason}`);
      this.wsError = '实时通道已断开，发送消息时将自动重连';
      if (this.streaming) {
        const m = this.activeAssistant;
        if (m !== null) {
          m.markEnded(true, '网络连接中断');
        }
        this.activeAssistant = null;
        this.streaming = false;
      }
    };
  }

  /** 移除本地预插入的 steer 用户消息 */
  private removeSteerPending(): void {
    const pending = this.steerPending;
    if (pending === null) {
      return;
    }
    this.steerPending = null;
    this.messages = this.messages.filter((m: ChatMessageModel): boolean => m !== pending);
  }

  private scrollToBottom(force: boolean): void {
    const now = Date.now();
    if (!force && now - this.lastScrollMs < 150) {
      return;
    }
    this.lastScrollMs = now;
    if (this.messages.length === 0) {
      return;
    }
    this.scroller.scrollToIndex(this.messages.length - 1, false);
  }

  /** 发送：流式进行中走 steer 追问，否则走常规 user_turn */
  private async send(): Promise<void> {
    if (this.connecting) {
      return;
    }
    const text: string = this.inputText.trim();
    if (text === '') {
      return;
    }
    if (this.streaming) {
      await this.sendSteer(text);
      return;
    }
    const c = this.controller;
    if (c === null || !c.connected) {
      await this.connectWs();
    }
    const controller = this.controller;
    if (controller === null || !controller.connected) {
      this.wsError = '连接服务器失败，请检查网络后重试';
      return;
    }
    this.wsError = '';
    this.welcome = null;
    this.inputText = '';
    this.messages.push(ChatMessageModel.fromUserText(text, Date.now()));
    const m = ChatMessageModel.streamingAssistant();
    this.messages.push(m);
    this.activeAssistant = m;
    this.streaming = true;
    this.scrollToBottom(true);
    try {
      await controller.sendUserTurn(text);
    } catch (e) {
      const am = this.activeAssistant;
      if (am !== null) {
        am.markEnded(true, '消息发送失败');
      }
      this.activeAssistant = null;
      this.streaming = false;
    }
  }

  /** Steer 追问：本地先插入用户消息，ack rejected 时移除并提示 */
  private async sendSteer(text: string): Promise<void> {
    const controller = this.controller;
    if (controller === null || !controller.connected) {
      this.wsError = '连接已断开，无法追加消息';
      return;
    }
    if (this.currentTurnId === '') {
      this.getUIContext().getPromptAction().showToast({ message: '正在等待回复开始，请稍候' });
      return;
    }
    this.wsError = '';
    this.inputText = '';
    const pending = ChatMessageModel.fromUserText(text, Date.now());
    this.messages.push(pending);
    this.steerPending = pending;
    this.scrollToBottom(true);
    try {
      await controller.sendSteer(text, this.currentTurnId, util.generateRandomUUID());
    } catch (e) {
      this.removeSteerPending();
      this.getUIContext().getPromptAction().showToast({ message: '追问发送失败' });
    }
  }

  private async cancelTurn(): Promise<void> {
    const c = this.controller;
    if (c === null) {
      return;
    }
    try {
      await c.cancelTurn();
    } catch (e) {
      Log.warn('cancel turn failed');
    }
  }

  aboutToDisappear(): void {
    const c = this.controller;
    if (c !== null) {
      c.close();
      this.controller = null;
    }
    AppStorage.setOrCreate(SessionStore.KEY_THREADS_DIRTY, true);
  }

  build() {
    NavDestination() {
      Column() {
        if (!this.historyReady && this.loadError === '') {
          Column() {
            LoadingProgress()
              .width(36)
              .height(36)
              .color($r('app.color.brand'))
          }
          .layoutWeight(1)
          .width('100%')
          .justifyContent(FlexAlign.Center)
        } else if (this.loadError !== '' && this.messages.length === 0) {
          Column() {
            ErrorRetry({
              message: this.loadError,
              onRetry: (): void => {
                this.historyReady = false;
                this.loadError = '';
                this.loadHistory();
                this.connectWs();
              }
            })
          }
          .layoutWeight(1)
          .width('100%')
          .justifyContent(FlexAlign.Center)
        } else {
          List({ scroller: this.scroller, space: 12 }) {
            if (this.welcome !== null && this.messages.length === 0) {
              ListItem() {
                WelcomeCard({
                  message: this.welcome.message,
                  prompts: this.welcome.quickPrompts,
                  onPromptClick: (prompt: string): void => {
                    this.inputText = prompt;
                  }
                })
              }
            }
            ForEach(this.messages, (msg: ChatMessageModel, index: number) => {
              ListItem() {
                MessageBubble({ msg: msg })
              }
            }, (msg: ChatMessageModel, index: number) => `${index}_${msg.id}`)
          }
          .layoutWeight(1)
          .width('100%')
          .padding({ left: 14, right: 14, top: 10, bottom: 6 })
          .scrollBar(BarState.Off)
        }

        Column({ space: 6 }) {
          if (this.wsError !== '') {
            Text(this.wsError)
              .fontSize(12)
              .fontColor($r('app.color.danger'))
              .padding({ left: 12, right: 12 })
          }
          Row({ space: 10 }) {
            TextInput({
              text: this.inputText,
              placeholder: this.streaming ? '可补充要求，与回复同时生效...' : $r('app.string.chat_input_placeholder')
            })
              .layoutWeight(1)
              .fontSize(15)
              .height(42)
              .backgroundColor($r('app.color.bg_input'))
              .borderRadius(21)
              .padding({ left: 16, right: 16 })
              .onChange((value: string): void => {
                this.inputText = value;
              })
              .enterKeyType(EnterKeyType.Send)
              .onSubmit((enterKey: EnterKeyType): void => {
                this.send();
              })
            if (this.streaming) {
              Row({ space: 8 }) {
                Column() {
                  SymbolGlyph($r('sys.symbol.stop_circle'))
                    .fontSize(22)
                    .fontColor([$r('app.color.danger')])
                }
                .width(40)
                .height(40)
                .borderRadius(20)
                .backgroundColor($r('app.color.bg_input'))
                .justifyContent(FlexAlign.Center)
                .alignItems(HorizontalAlign.Center)
                .onClick((): void => {
                  this.cancelTurn();
                })
                Column() {
                  SymbolGlyph($r('sys.symbol.paperplane_fill'))
                    .fontSize(20)
                    .fontColor([$r('app.color.text_on_brand')])
                }
                .width(40)
                .height(40)
                .borderRadius(20)
                .linearGradient({
                  angle: 140,
                  colors: [[$r('app.color.brand_grad_start'), 0], [$r('app.color.brand_grad_end'), 1]]
                })
                .justifyContent(FlexAlign.Center)
                .alignItems(HorizontalAlign.Center)
                .opacity(this.inputText.trim() === '' ? 0.4 : 1)
                .onClick((): void => {
                  if (this.inputText.trim() !== '') {
                    this.sendSteer(this.inputText.trim());
                  }
                })
              }
            } else {
              Column() {
                SymbolGlyph($r('sys.symbol.paperplane_fill'))
                  .fontSize(20)
                  .fontColor([$r('app.color.text_on_brand')])
              }
              .width(42)
              .height(42)
              .borderRadius(21)
              .linearGradient({
                angle: 140,
                colors: [[$r('app.color.brand_grad_start'), 0], [$r('app.color.brand_grad_end'), 1]]
              })
              .shadow({ radius: 10, color: '#2E0A59F7', offsetX: 0, offsetY: 4 })
              .justifyContent(FlexAlign.Center)
              .alignItems(HorizontalAlign.Center)
              .onClick((): void => {
                this.send();
              })
            }
          }
          .width('100%')
          .padding({ left: 12, right: 12, top: 8, bottom: 10 })
        }
        .width('100%')
        .backgroundColor($r('app.color.bg_card'))
        .border({ width: { top: 1 }, color: $r('app.color.divider') })
      }
      .width('100%')
      .height('100%')
      .backgroundColor($r('app.color.bg_page'))
    }
    .title(this.title)
    .onReady((ctx: NavDestinationContext): void => {
      this.onNavReady(ctx);
    })
    .onBackPressed((): boolean => {
      if (this.streaming) {
        this.cancelTurn();
      }
      return false;
    })
  }
}
