import { ChatAttachmentModel, ChatMessageModel, ChatRole, MsgAttachmentModel } from '../../model/MessageModels';
import { ChatStreamController } from '../../service/ChatStreamController';
import { OctopApiError } from '../../net/HttpClient';
import { SessionStore } from '../../store/SessionStore';
import { ThreadService } from '../../service/ThreadService';
import { AgentService } from '../../service/AgentService';
import { WelcomeCardModel } from '../../model/ExpertModels';
import { AgentModel } from '../../model/AgentModels';
import { ContextUsageModel, HistoryResult, ThreadModel } from '../../model/ThreadModels';
import { HitlRequestModel } from '../../model/HitlModels';
import { MessageBubble } from '../../components/MessageBubble';
import { StreamingOrbit } from '../../components/StreamingOrbit';
import { WelcomeCard } from '../../components/WelcomeCard';
import { ErrorRetry } from '../../components/ErrorRetry';
import { CommandPalette } from '../../components/CommandPalette';
import { ModelPickerSheet } from '../../components/ModelPickerSheet';
import { UiMaterialKit } from '../../components/UiMaterialKit';
import { TimeFormat } from '../../utils/TimeFormat';
import { Log } from '../../utils/Logger';
import { ThreadDigestCache } from '../../utils/ThreadDigestCache';
import { util } from '@kit.ArkTS';
import { fileIo, picker } from '@kit.CoreFileKit';

/** HITL 动作展示视图（Builder ForEach 用稳定对象） */
class HitlActionView {
  readonly name: string;
  readonly description: string;
  readonly argsPreview: string;

  constructor(name: string, description: string, argsPreview: string) {
    this.name = name;
    this.description = description;
    this.argsPreview = argsPreview;
  }
}

/** 首页聊天 Tab：消息流内嵌 + 空态欢迎 + 命令面板 + 专家切换（流式逻辑迁移自 ChatDetailPage） */
@Component
export struct ChatHomeTab {
  @Consume('navStack') navStack: NavPathStack;
  @Prop topInset: number = 0;
  @Prop bottomPad: number = 72;
  @StorageLink(SessionStore.KEY_ACTIVE_THREAD_ID) @Watch('onThreadChanged') activeThreadId: string = '';
  @StorageProp(SessionStore.KEY_AGENT_ID) @Watch('onAgentChanged') agentId: string = '';
  @StorageProp(SessionStore.KEY_AGENT_NAME) agentName: string = '';
  @StorageProp(SessionStore.KEY_AGENT_MODEL) agentModel: string = '';
  @State messages: Array<ChatMessageModel> = [];
  @State inputText: string = '';
  @State streaming: boolean = false;
  @State streamPhase: string = '';
  @State connecting: boolean = false;
  @State wsError: string = '';
  @State loadError: string = '';
  @State historyReady: boolean = true;
  @State welcome: WelcomeCardModel | null = null;
  @State recentThread: ThreadModel | null = null;
  @State dotBreath: number = 1;
  @State paletteOpen: boolean = false;
  @State agentSheetOpen: boolean = false;
  @State agents: Array<AgentModel> = [];
  @State agentsLoading: boolean = false;
  @State attachments: Array<ChatAttachmentModel> = [];
  @State uploading: boolean = false;
  @State polishing: boolean = false;
  @State attachSheetOpen: boolean = false;
  @State contextUsage: ContextUsageModel | null = null;
  @State hitlPending: HitlRequestModel | null = null;
  @State hitlSubmitting: boolean = false;
  @State turnModel: string = '';
  @State turnModelLabel: string = '';
  @State modelSheetOpen: boolean = false;
  @State historyHasMore: boolean = false;
  @State loadingEarlier: boolean = false;
  @State hitlEditOpen: boolean = false;
  @State hitlEditArgs: string = '';
  private controller: ChatStreamController | null = null;
  private connectingPromise: Promise<boolean> | null = null;
  private scroller: Scroller = new Scroller();
  private lastScrollMs: number = 0;
  private activeAssistant: ChatMessageModel | null = null;
  private steerPending: ChatMessageModel | null = null;
  private currentTurnId: string = '';
  private lastConnectedId: string = '';
  private threadCreating: boolean = false;
  private steerClientPendingId: string = '';
  private steerServerPendingId: string = '';

  aboutToAppear(): void {
    this.startBreathing();
    if (this.agentId === '') {
      this.pickDefaultAgent();
      return;
    }
    if (this.activeThreadId !== '') {
      this.loadHistory();
      this.connectWs();
    } else {
      this.loadWelcome();
    }
  }

  aboutToDisappear(): void {
    this.teardownStream();
  }

  private async pickDefaultAgent(): Promise<void> {
    try {
      const agents = await AgentService.listMine();
      if (agents.length > 0) {
        SessionStore.setCurrentAgent(agents[0]);
      }
    } catch (e) {
      Log.warn('default agent load failed');
    }
  }

  /** 专家变化：断开旧连接、清空界面、重置会话并拉取新欢迎态 */
  private onAgentChanged(): void {
    this.teardownStream();
    this.streaming = false;
    this.activeAssistant = null;
    this.steerPending = null;
    this.currentTurnId = '';
    this.messages = [];
    this.welcome = null;
    this.recentThread = null;
    this.attachments = [];
    this.contextUsage = null;
    this.hitlPending = null;
    this.hitlSubmitting = false;
    this.historyHasMore = false;
    this.loadingEarlier = false;
    this.steerClientPendingId = '';
    this.steerServerPendingId = '';
    if (this.agentId === '') {
      return;
    }
    if ((AppStorage.get<string>(SessionStore.KEY_ACTIVE_THREAD_ID) ?? '') !== '') {
      AppStorage.setOrCreate(SessionStore.KEY_ACTIVE_THREAD_ID, '');
    } else {
      this.loadWelcome();
    }
  }

  /** 会话变化：断开旧连接，非空则加载历史并连接 WS，空则回欢迎态 */
  private onThreadChanged(): void {
    this.teardownStream();
    this.streaming = false;
    this.activeAssistant = null;
    this.steerPending = null;
    this.currentTurnId = '';
    this.welcome = null;
    this.recentThread = null;
    this.attachments = [];
    this.contextUsage = null;
    this.hitlPending = null;
    this.hitlSubmitting = false;
    this.historyHasMore = false;
    this.loadingEarlier = false;
    this.steerClientPendingId = '';
    this.steerServerPendingId = '';
    if (this.activeThreadId === '') {
      this.messages = [];
      this.historyReady = true;
      this.loadWelcome();
      return;
    }
    if (this.agentId === '') {
      this.loadError = '未选择专家，请先在专家页选择';
      this.historyReady = true;
      return;
    }
    this.loadHistory();
    this.connectWs();
  }

  /** 摘要文本：从消息数组末尾取第一条非空文本 */
  private digestTextFromMessages(msgs: Array<ChatMessageModel>): string {
    for (let i = msgs.length - 1; i >= 0; i--) {
      const text: string = msgs[i].text.trim();
      if (text !== '') {
        return text;
      }
    }
    return '';
  }

  /** 同步会话摘要缓存（供会话列表副标题展示） */
  private syncDigest(preferred: string): void {
    const threadId: string = AppStorage.get<string>(SessionStore.KEY_ACTIVE_THREAD_ID) ?? '';
    if (threadId === '') {
      return;
    }
    let text: string = preferred;
    if (text.trim() === '') {
      text = this.digestTextFromMessages(this.messages);
    }
    if (text.trim() === '') {
      return;
    }
    ThreadDigestCache.put(threadId, text, this.messages.length);
  }

  /** 重试：取最后一条用户消息文本重新发送（新 turn 语义，不删服务端记录） */
  private async retryLastTurn(): Promise<void> {
    if (this.streaming) {
      return;
    }
    for (let i = this.messages.length - 1; i >= 0; i--) {
      const m = this.messages[i];
      if (m.role === ChatRole.USER) {
        const text: string = m.text.trim();
        if (text === '') {
          return;
        }
        this.inputText = text;
        await this.send();
        return;
      }
    }
  }

  private async loadHistory(): Promise<void> {
    const threadId: string = this.activeThreadId;
    const agentId: string = AppStorage.get<string>(SessionStore.KEY_AGENT_ID) ?? '';
    if (threadId === '' || agentId === '') {
      return;
    }
    this.historyReady = false;
    try {
      const result: HistoryResult = await ThreadService.historyFull(agentId, threadId);
      if (threadId !== (AppStorage.get<string>(SessionStore.KEY_ACTIVE_THREAD_ID) ?? '')) {
        return;
      }
      this.messages = result.messages;
      this.historyHasMore = result.hasMore;
      this.hitlPending = result.hitlPending;
      this.hitlSubmitting = false;
      this.loadError = '';
      this.historyReady = true;
      this.syncDigest('');
      this.markThreadRead(agentId, threadId);
      this.refreshContextUsage();
      if (result.messages.length === 0) {
        this.loadWelcome();
      } else {
        this.scrollToBottom(true);
      }
    } catch (e) {
      this.loadError = e instanceof OctopApiError ? e.message : '历史消息加载失败';
      this.historyReady = true;
    }
  }

  /** 向前翻页加载更早的历史消息（offset=当前已加载数） */
  private async loadEarlierMessages(): Promise<void> {
    const threadId: string = this.activeThreadId;
    const agentId: string = AppStorage.get<string>(SessionStore.KEY_AGENT_ID) ?? '';
    if (threadId === '' || agentId === '' || this.loadingEarlier) {
      return;
    }
    this.loadingEarlier = true;
    try {
      const result: HistoryResult = await ThreadService.historyFull(agentId, threadId, this.messages.length);
      if (threadId !== (AppStorage.get<string>(SessionStore.KEY_ACTIVE_THREAD_ID) ?? '')) {
        return;
      }
      this.messages = result.messages.concat(this.messages);
      this.historyHasMore = result.hasMore;
    } catch (e) {
      this.getUIContext().getPromptAction().showToast({
        message: e instanceof OctopApiError ? e.message : '加载更早消息失败'
      });
    }
    this.loadingEarlier = false;
  }

  /** 清除线程未读（fire-and-forget），成功后触发专家列表徽章刷新 */
  private markThreadRead(agentId: string, threadId: string): void {
    ThreadService.markRead(agentId, threadId).then((): void => {
      AppStorage.setOrCreate(SessionStore.KEY_AGENTS_DIRTY, true);
    }).catch((): void => {
      Log.debug('mark read failed, ignore');
    });
  }

  /** 拉取当前线程上下文窗口用量（turn 结束/历史加载后刷新） */
  private refreshContextUsage(): void {
    const threadId: string = AppStorage.get<string>(SessionStore.KEY_ACTIVE_THREAD_ID) ?? '';
    const agentId: string = AppStorage.get<string>(SessionStore.KEY_AGENT_ID) ?? '';
    if (threadId === '' || agentId === '') {
      this.contextUsage = null;
      return;
    }
    ThreadService.contextUsage(agentId, threadId).then((usage: ContextUsageModel): void => {
      if (threadId === (AppStorage.get<string>(SessionStore.KEY_ACTIVE_THREAD_ID) ?? '')) {
        this.contextUsage = usage;
      }
    }).catch((): void => {
      // 静默失败：上下文条为辅助信息
    });
  }

  private async loadWelcome(): Promise<void> {
    const agentId: string = AppStorage.get<string>(SessionStore.KEY_AGENT_ID) ?? '';
    if (agentId === '') {
      return;
    }
    try {
      this.welcome = await AgentService.getWelcomeCard(agentId);
    } catch (e) {
      Log.debug('welcome card load failed, fallback');
      const welcomeText: string = AppStorage.get<string>(SessionStore.KEY_AGENT_WELCOME) ?? '';
      this.welcome = new WelcomeCardModel(welcomeText, []);
    }
    this.refreshRecent();
  }

  /** 欢迎态"继续上次对话"卡片数据：无活跃会话时拉最近一条 */
  private async refreshRecent(): Promise<void> {
    const agentId: string = AppStorage.get<string>(SessionStore.KEY_AGENT_ID) ?? '';
    if (agentId === '' || (AppStorage.get<string>(SessionStore.KEY_ACTIVE_THREAD_ID) ?? '') !== '') {
      this.recentThread = null;
      return;
    }
    try {
      const threads = await ThreadService.list(agentId, 1);
      if ((AppStorage.get<string>(SessionStore.KEY_ACTIVE_THREAD_ID) ?? '') !== '') {
        return;
      }
      this.recentThread = threads.length > 0 ? threads[0] : null;
    } catch (e) {
      this.recentThread = null;
    }
  }

  /** 建立/复用 WS 连接；并发调用共享同一个连接 Promise */
  private connectWs(): Promise<boolean> {
    const existing = this.connectingPromise;
    if (existing !== null) {
      return existing;
    }
    const threadId: string = AppStorage.get<string>(SessionStore.KEY_ACTIVE_THREAD_ID) ?? '';
    const agentId: string = AppStorage.get<string>(SessionStore.KEY_AGENT_ID) ?? '';
    if (threadId === '' || agentId === '') {
      return Promise.resolve(false);
    }
    const c = this.controller;
    if (c !== null && c.connected && this.lastConnectedId === threadId) {
      return Promise.resolve(true);
    }
    this.teardownStream();
    this.connecting = true;
    this.wsError = '';
    const promise: Promise<boolean> = new Promise<boolean>((resolve: (ok: boolean) => void) => {
      const controller = new ChatStreamController(agentId, threadId);
      this.wireCallbacks(controller);
      controller.connect().then((): void => {
        if (threadId !== (AppStorage.get<string>(SessionStore.KEY_ACTIVE_THREAD_ID) ?? '')) {
          controller.close();
          this.connecting = false;
          this.connectingPromise = null;
          resolve(false);
          return;
        }
        this.controller = controller;
        this.lastConnectedId = threadId;
        this.connecting = false;
        this.connectingPromise = null;
        resolve(true);
      }).catch((): void => {
        Log.warn('WS connect failed');
        this.wsError = '实时通道连接失败，发送消息时将自动重试';
        this.connecting = false;
        this.connectingPromise = null;
        resolve(false);
      });
    });
    this.connectingPromise = promise;
    return promise;
  }

  private teardownStream(): void {
    const c = this.controller;
    if (c !== null) {
      c.close();
      this.controller = null;
    }
    this.lastConnectedId = '';
    this.connectingPromise = null;
  }

  private wireCallbacks(controller: ChatStreamController): void {
    controller.callbacks.onTextDelta = (delta: string): void => {
      const m = this.activeAssistant;
      if (m !== null) {
        m.appendText(delta);
        if (this.streamPhase !== '正在生成…') {
          this.streamPhase = '正在生成…';
        }
        this.scrollToBottom(false);
      }
    };
    controller.callbacks.onReasoningDelta = (delta: string): void => {
      const m = this.activeAssistant;
      if (m !== null) {
        m.appendReasoning(delta);
        if (this.streamPhase !== '深度推理中…') {
          this.streamPhase = '深度推理中…';
        }
      }
    };
    controller.callbacks.onSpeaker = (agentId: string): void => {
      const m = this.activeAssistant;
      if (m !== null && m.speakerId === '') {
        m.speakerId = agentId;
      }
    };
    controller.callbacks.onToolActivity = (name: string): void => {
      const m = this.activeAssistant;
      if (m !== null) {
        m.addToolName(name);
        this.streamPhase = this.toolPhaseText(name);
      }
    };
    controller.callbacks.onToolCall = (id: string, name: string, argsDelta: string): void => {
      const m = this.activeAssistant;
      if (m !== null) {
        m.upsertToolCall(id, name, argsDelta);
        this.scrollToBottom(false);
      }
    };
    controller.callbacks.onToolResult = (output: string): void => {
      const m = this.activeAssistant;
      if (m !== null) {
        m.setToolResult('', output);
      }
    };
    controller.callbacks.onUsage = (inputTokens: number, outputTokens: number): void => {
      const m = this.activeAssistant;
      if (m !== null) {
        m.setUsage(inputTokens, outputTokens);
      }
    };
    controller.callbacks.onAttachment = (att: MsgAttachmentModel): void => {
      const m = this.activeAssistant;
      if (m !== null) {
        m.addAttachment(att);
        this.scrollToBottom(false);
      }
    };
    controller.callbacks.onTurnStarted = (turnId: string): void => {
      this.currentTurnId = turnId;
      this.streamPhase = '正在思考…';
    };
    controller.callbacks.onTurnEnded = (failed: boolean): void => {
      const m = this.activeAssistant;
      if (m !== null) {
        m.markEnded(failed, failed ? '回复中断' : '');
        this.syncDigest(m.text);
      }
      this.activeAssistant = null;
      this.currentTurnId = '';
      this.streaming = false;
      this.streamPhase = '';
      AppStorage.setOrCreate(SessionStore.KEY_THREADS_DIRTY, true);
      this.refreshContextUsage();
    };
    controller.callbacks.onStreamError = (message: string): void => {
      const m = this.activeAssistant;
      if (m !== null) {
        m.markEnded(true, message);
        this.syncDigest(m.text);
      }
      this.activeAssistant = null;
      this.streaming = false;
      this.streamPhase = '';
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
    controller.callbacks.onSteerQueued = (clientPendingId: string, pendingId: string, turnId: string): void => {
      this.steerServerPendingId = pendingId;
      const pending = this.steerPending;
      if (pending !== null && pending.clientPendingId === clientPendingId) {
        pending.isSteerQueued = true;
      }
    };
    controller.callbacks.onSteerRemoved = (clientPendingId: string): void => {
      const pending = this.steerPending;
      if (pending !== null && pending.clientPendingId === clientPendingId) {
        this.removeSteerPending();
        this.getUIContext().getPromptAction().showToast({ message: '追问已撤回' });
      }
    };
    controller.callbacks.onSteerRejected = (clientPendingId: string, reason: string): void => {
      const pending = this.steerPending;
      if (pending === null || pending.clientPendingId !== clientPendingId) {
        return;
      }
      this.removeSteerPending();
      this.getUIContext().getPromptAction().showToast({
        message: reason !== '' ? `追问被拒绝：${reason}` : '追问未成功'
      });
    };
    controller.callbacks.onUserEcho = (content: string): void => {
      if (this.steerPending !== null) {
        this.steerPending = null;
      } else if (content !== '') {
        this.messages.push(ChatMessageModel.fromUserText(content, Date.now()));
      }
      const m = ChatMessageModel.streamingAssistant();
      this.messages.push(m);
      this.activeAssistant = m;
      this.streaming = true;
      this.streamPhase = '正在思考…';
      this.scrollToBottom(true);
    };
    controller.callbacks.onSteerDiscarded = (reason: string): void => {
      this.removeSteerPending();
      this.getUIContext().getPromptAction().showToast({ message: '追问已被取消' });
    };
    controller.callbacks.onHitlRequired = (request: HitlRequestModel): void => {
      const m = this.activeAssistant;
      if (m !== null) {
        m.markEnded(false, '');
      }
      this.activeAssistant = null;
      this.streaming = false;
      this.streamPhase = '';
      this.hitlPending = request;
      this.hitlSubmitting = false;
      this.scrollToBottom(true);
    };
    controller.callbacks.onResumeStreamEnd = (failed: boolean): void => {
      const m = this.activeAssistant;
      if (m !== null) {
        m.markEnded(failed, failed ? '回复中断' : '');
        this.syncDigest(m.text);
      }
      this.activeAssistant = null;
      this.streaming = false;
      this.streamPhase = '';
      this.hitlSubmitting = false;
      AppStorage.setOrCreate(SessionStore.KEY_THREADS_DIRTY, true);
      this.refreshContextUsage();
    };
    controller.callbacks.onTurnStatus = (active: boolean): void => {
      // 订阅应答：active=true 服务端仍在输出（弱流恢复续流）；false 且本地在等待恢复则中断
      if (!active && this.streaming && this.streamPhase === '恢复续流中…') {
        const m = this.activeAssistant;
        if (m !== null) {
          m.markEnded(true, '回复中断');
          this.syncDigest(m.text);
        }
        this.activeAssistant = null;
        this.streaming = false;
        this.streamPhase = '';
      } else if (active && this.streaming) {
        this.streamPhase = '正在生成…';
      }
    };
    controller.callbacks.onConnectionClosed = (code: number, reason: string): void => {
      Log.warn(`WS connection closed: ${code} ${reason}`);
      this.wsError = '实时通道已断开，发送消息时将自动重连';
      if (this.streaming) {
        // 弱流恢复：保持消息与流状态，稍后重连（subscribe 回放追赶帧 + turn_status）
        this.streamPhase = '恢复续流中…';
        setTimeout((): void => {
          this.recoverConnection();
        }, 1500);
      }
    };
  }

  /** 弱流恢复重连：成功后由 turn_status/回放帧继续续流 */
  private async recoverConnection(): Promise<void> {
    if (!this.streaming) {
      return;
    }
    const ok: boolean = await this.connectWs();
    if (!ok && this.streaming) {
      const m = this.activeAssistant;
      if (m !== null) {
        m.markEnded(true, '网络连接中断');
        this.syncDigest(m.text);
      }
      this.activeAssistant = null;
      this.streaming = false;
      this.streamPhase = '';
    }
  }

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

  /** 首次发送前确保会话存在：无活跃会话则创建并写入全局状态 */
  private async ensureThread(): Promise<string> {
    const current: string = AppStorage.get<string>(SessionStore.KEY_ACTIVE_THREAD_ID) ?? '';
    if (current !== '') {
      return current;
    }
    if ((AppStorage.get<string>(SessionStore.KEY_AGENT_ID) ?? '') === '') {
      await this.pickDefaultAgent();
    }
    const agentId: string = AppStorage.get<string>(SessionStore.KEY_AGENT_ID) ?? '';
    if (agentId === '') {
      return '';
    }
    if (this.threadCreating) {
      return '';
    }
    this.threadCreating = true;
    try {
      const created = await ThreadService.create(agentId);
      AppStorage.setOrCreate(SessionStore.KEY_ACTIVE_THREAD_ID, created.threadId);
      AppStorage.setOrCreate(SessionStore.KEY_THREADS_DIRTY, true);
      this.threadCreating = false;
      return created.threadId;
    } catch (e) {
      this.threadCreating = false;
      this.getUIContext().getPromptAction().showToast({
        message: e instanceof OctopApiError ? e.message : '创建会话失败'
      });
      return '';
    }
  }

  /** 发送：流式进行中走 steer 追问，否则确保会话后走常规 user_turn */
  private async send(): Promise<void> {
    const text: string = this.inputText.trim();
    if (text === '') {
      return;
    }
    if (this.streaming) {
      await this.sendSteer(text);
      return;
    }
    const threadId: string = await this.ensureThread();
    if (threadId === '') {
      if ((AppStorage.get<string>(SessionStore.KEY_AGENT_ID) ?? '') === '') {
        this.getUIContext().getPromptAction().showToast({ message: '暂无可用专家，请先在专家页添加' });
      }
      return;
    }
    const connected: boolean = await this.connectWs();
    if (!connected) {
      this.wsError = '连接服务器失败，请检查网络后重试';
      return;
    }
    const controller = this.controller;
    if (controller === null) {
      return;
    }
    this.wsError = '';
    this.welcome = null;
    this.recentThread = null;
    this.inputText = '';
    const atts: Array<ChatAttachmentModel> = this.attachments;
    this.attachments = [];
    const userMsg = ChatMessageModel.fromUserText(text, Date.now());
    for (const att of atts) {
      userMsg.attachmentNames.push(att.filename);
    }
    userMsg.fresh = true;
    this.messages.push(userMsg);
    const m = ChatMessageModel.streamingAssistant();
    this.messages.push(m);
    this.activeAssistant = m;
    this.streaming = true;
    this.streamPhase = '正在思考…';
    this.scrollToBottom(true);
    try {
      await controller.sendUserTurn(text, atts, this.turnModel);
      AppStorage.setOrCreate(SessionStore.KEY_THREADS_DIRTY, true);
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
    pending.fresh = true;
    this.messages.push(pending);
    this.steerPending = pending;
    this.scrollToBottom(true);
    const clientPendingId: string = util.generateRandomUUID();
    pending.clientPendingId = clientPendingId;
    this.steerClientPendingId = clientPendingId;
    this.steerServerPendingId = '';
    try {
      await controller.sendSteer(text, this.currentTurnId, clientPendingId);
    } catch (e) {
      this.removeSteerPending();
      this.getUIContext().getPromptAction().showToast({ message: '追问发送失败' });
    }
  }

  /** 撤回已排队的 steer */
  private async withdrawSteer(): Promise<void> {
    const controller = this.controller;
    if (controller === null) {
      return;
    }
    try {
      await controller.sendSteerRemove(this.currentTurnId, this.steerClientPendingId, this.steerServerPendingId);
    } catch (e) {
      this.getUIContext().getPromptAction().showToast({ message: '撤回失败，请重试' });
    }
  }

  private async cancelTurn(): Promise<void> {
    // HITL 审批恢复流进行中：中止 SSE 即停止生成
    if (this.hitlSubmitting) {
      this.abortHitlResume();
      return;
    }
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

  /** 中止进行中的 HITL 审批恢复（"停止生成"） */
  private abortHitlResume(): void {
    const c = this.controller;
    if (c !== null) {
      c.abortResume();
    }
    const m = this.activeAssistant;
    if (m !== null) {
      m.markEnded(false, '已停止生成');
    }
    this.activeAssistant = null;
    this.streaming = false;
    this.hitlSubmitting = false;
    this.streamPhase = '';
  }

  /** HITL 决策提交：approve/reject/respond/edit，走 SSE resume 恢复流 */
  private submitHitl(decisionType: string, message: string, editedActionStr: string = ''): void {
    const controller = this.controller;
    const pending = this.hitlPending;
    if (controller === null || pending === null || this.hitlSubmitting) {
      return;
    }
    this.hitlSubmitting = true;
    this.hitlPending = null;
    const m = ChatMessageModel.streamingAssistant();
    this.messages.push(m);
    this.activeAssistant = m;
    this.streaming = true;
    this.streamPhase = '正在生成…';
    this.scrollToBottom(true);
    controller.resumeHitl(decisionType, message, pending.pendingId, editedActionStr);
  }

  /** 人工回复：使用输入框内容作为 respond 决策消息 */
  private submitHitlRespond(): void {
    const text: string = this.inputText.trim();
    if (text === '') {
      this.getUIContext().getPromptAction().showToast({ message: '请先在输入框填写回复内容' });
      return;
    }
    this.inputText = '';
    this.submitHitl('respond', text);
  }

  /** 打开 HITL edit 编辑面板：装载首个动作的原始参数 JSON */
  private startHitlEdit(): void {
    const pending = this.hitlPending;
    if (pending === null) {
      return;
    }
    this.hitlEditArgs = pending.editableArgsJson();
    this.hitlEditOpen = true;
  }

  /** 提交 edit 决策：校验 JSON 合法后走 resume */
  private submitHitlEdit(): void {
    const raw: string = this.hitlEditArgs.trim();
    if (raw === '') {
      this.getUIContext().getPromptAction().showToast({ message: '参数不能为空' });
      return;
    }
    try {
      const parsed: object = JSON.parse(raw) as object;
      if (parsed === null || typeof parsed !== 'object') {
        this.getUIContext().getPromptAction().showToast({ message: '参数必须是合法 JSON 对象' });
        return;
      }
    } catch (e) {
      this.getUIContext().getPromptAction().showToast({ message: '参数必须是合法 JSON 对象' });
      return;
    }
    this.hitlEditOpen = false;
    this.submitHitl('edit', '', raw);
  }

  /** 从相册选择图片并上传为附件 */
  private async pickImage(): Promise<void> {
    this.attachSheetOpen = false;
    const photoPicker = new picker.PhotoViewPicker();
    const options = new picker.PhotoSelectOptions();
    options.MIMEType = picker.PhotoViewMIMETypes.IMAGE_TYPE;
    options.maxSelectNumber = 1;
    try {
      const result = await photoPicker.select(options);
      if (result.photoUris.length > 0) {
        await this.uploadByUri(result.photoUris[0]);
      }
    } catch (e) {
      Log.debug('photo pick cancelled');
    }
  }

  /** 从文件选择器选文档并上传为附件 */
  private async pickDocument(): Promise<void> {
    this.attachSheetOpen = false;
    const docPicker = new picker.DocumentViewPicker();
    const options = new picker.DocumentSelectOptions();
    options.maxSelectNumber = 1;
    try {
      const result = await docPicker.select(options);
      if (result.length > 0) {
        await this.uploadByUri(result[0]);
      }
    } catch (e) {
      Log.debug('document pick cancelled');
    }
  }

  private async uploadByUri(uri: string): Promise<void> {
    const agentId: string = AppStorage.get<string>(SessionStore.KEY_AGENT_ID) ?? '';
    if (agentId === '') {
      this.getUIContext().getPromptAction().showToast({ message: '请先选择专家' });
      return;
    }
    this.uploading = true;
    try {
      const file = fileIo.openSync(uri, fileIo.OpenMode.READ_ONLY);
      let data: ArrayBuffer;
      try {
        const stat = fileIo.statSync(file.fd);
        data = new ArrayBuffer(stat.size);
        fileIo.readSync(file.fd, data);
      } finally {
        fileIo.closeSync(file);
      }
      const fileName: string = this.fileNameFromUri(uri);
      const att = await AgentService.uploadAttachment(agentId, fileName, this.guessContentType(fileName), data);
      this.attachments = this.attachments.concat([att]);
    } catch (e) {
      this.getUIContext().getPromptAction().showToast({
        message: e instanceof OctopApiError ? e.message : '附件上传失败'
      });
    }
    this.uploading = false;
  }

  private fileNameFromUri(uri: string): string {
    const idx: number = uri.lastIndexOf('/');
    const name: string = idx >= 0 ? uri.substring(idx + 1) : uri;
    if (name === '') {
      return 'attachment';
    }
    try {
      return decodeURIComponent(name);
    } catch (e) {
      return name;
    }
  }

  private guessContentType(fileName: string): string {
    const lower: string = fileName.toLowerCase();
    if (lower.endsWith('.png')) {
      return 'image/png';
    }
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) {
      return 'image/jpeg';
    }
    if (lower.endsWith('.gif')) {
      return 'image/gif';
    }
    if (lower.endsWith('.webp')) {
      return 'image/webp';
    }
    if (lower.endsWith('.pdf')) {
      return 'application/pdf';
    }
    if (lower.endsWith('.txt') || lower.endsWith('.md')) {
      return 'text/plain';
    }
    if (lower.endsWith('.json')) {
      return 'application/json';
    }
    return 'application/octet-stream';
  }

  private removeAttachment(att: ChatAttachmentModel): void {
    this.attachments = this.attachments.filter((item: ChatAttachmentModel): boolean => item !== att);
  }

  /** 润色输入框提示词 */
  private async polishInput(): Promise<void> {
    const text: string = this.inputText.trim();
    const agentId: string = AppStorage.get<string>(SessionStore.KEY_AGENT_ID) ?? '';
    if (text === '' || agentId === '' || this.polishing) {
      return;
    }
    this.polishing = true;
    try {
      const polished: string = await AgentService.polishPrompt(agentId, text);
      if (polished !== '') {
        this.inputText = polished;
      }
    } catch (e) {
      this.getUIContext().getPromptAction().showToast({
        message: e instanceof OctopApiError ? e.message : '润色失败'
      });
    }
    this.polishing = false;
  }

  /** 新对话：中断当前回复并回到欢迎态 */
  private startNewConversation(): void {
    if (this.streaming) {
      this.cancelTurn();
    }
    AppStorage.setOrCreate(SessionStore.KEY_ACTIVE_THREAD_ID, '');
  }

  private async openAgentSheet(): Promise<void> {
    this.agentSheetOpen = true;
    this.agentsLoading = true;
    try {
      this.agents = await AgentService.listMine();
    } catch (e) {
      this.agents = [];
    }
    this.agentsLoading = false;
  }

  private selectAgent(agent: AgentModel): void {
    this.agentSheetOpen = false;
    SessionStore.setCurrentAgent(agent);
  }

  /** 状态点呼吸动画（无限往返） */
  private startBreathing(): void {
    this.getUIContext().animateTo({
      duration: 1200,
      curve: Curve.EaseInOut,
      iterations: -1,
      playMode: PlayMode.Alternate
    }, (): void => {
      this.dotBreath = 0.35;
    });
  }

  private contextBarColor(): Resource {
    const usage = this.contextUsage;
    if (usage === null) {
      return $r('app.color.brand');
    }
    const pct: number = usage.percent();
    if (pct >= 90) {
      return $r('app.color.danger');
    }
    if (pct >= 70) {
      return $r('app.color.warning');
    }
    return $r('app.color.success');
  }

  private contextPct(): number {
    return this.contextUsage === null ? 0 : this.contextUsage.percent();
  }

  /** 工具活动 → 状态行文案映射 */
  private toolPhaseText(name: string): string {
    if (name.indexOf('web_search') >= 0) {
      return '正在搜索网络';
    }
    if (name.indexOf('knowledge') >= 0) {
      return '正在检索知识库';
    }
    if (name !== '') {
      return `正在调用 ${name}`;
    }
    return '正在调用工具';
  }

  private statusColor(): Resource {
    if (this.wsError !== '' || this.loadError !== '') {
      return $r('app.color.danger');
    }
    if (this.connecting) {
      return $r('app.color.warning');
    }
    return $r('app.color.success');
  }

  private statusText(): string {
    if (this.wsError !== '') {
      return '连接异常';
    }
    if (this.streaming) {
      return '回复中';
    }
    if (this.connecting) {
      return '连接中';
    }
    if (this.agentId === '') {
      return '未选择专家';
    }
    return '在线';
  }

  @Builder
  recentThreadCard(thread: ThreadModel) {
    Row({ space: 12 }) {
      Column() {
        SymbolGlyph($r('sys.symbol.clock'))
          .fontSize(15)
          .fontColor([$r('app.color.brand')])
      }
      .width(32)
      .height(32)
      .borderRadius(10)
      .backgroundColor($r('app.color.brand_light'))
      .justifyContent(FlexAlign.Center)
      Column({ space: 2 }) {
        Text('继续上次对话')
          .fontSize(11)
          .fontColor($r('app.color.text_tertiary'))
        Text(thread.title === '' ? '新对话' : thread.title)
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      Text(TimeFormat.list(thread.lastActiveMs))
        .fontSize(11)
        .fontColor($r('app.color.text_tertiary'))
      SymbolGlyph($r('sys.symbol.chevron_right'))
        .fontSize(13)
        .fontColor([$r('app.color.text_tertiary')])
    }
    .width('100%')
    .padding({ left: 14, right: 14, top: 12, bottom: 12 })
    .borderRadius(14)
    .backgroundColor($r('app.color.bg_card'))
    .onClick((): void => {
      AppStorage.setOrCreate(SessionStore.KEY_ACTIVE_THREAD_ID, thread.threadId);
    })
  }

  @Builder
  emptyStateBuilder() {
    Column({ space: 14 }) {
      if (this.welcome !== null) {
        WelcomeCard({
          message: this.welcome.message,
          prompts: this.welcome.quickPrompts,
          onPromptClick: (prompt: string): void => {
            this.inputText = prompt;
          }
        })
      }
      if (this.recentThread !== null && this.activeThreadId === '') {
        this.recentThreadCard(this.recentThread)
      }
    }
    .width('100%')
    .padding({ top: 12 })
  }

  @Builder
  agentSheetBuilder() {
    Column() {
      Text('选择专家')
        .fontSize(17)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .padding({ top: 18, bottom: 10 })
      if (this.agentsLoading) {
        Column() {
          LoadingProgress()
            .width(28)
            .height(28)
            .color($r('app.color.brand'))
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else if (this.agents.length === 0) {
        Column() {
          Text('暂无可用专家')
            .fontSize(14)
            .fontColor($r('app.color.text_tertiary'))
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else {
        List({ space: 8 }) {
          ForEach(this.agents, (agent: AgentModel) => {
            ListItem() {
              Row({ space: 12 }) {
                Image($r('app.media.octop_logo'))
                  .width(40)
                  .height(40)
                  .borderRadius(20)
                  .backgroundColor($r('app.color.brand_light'))
                Column({ space: 2 }) {
                  Text(agent.name)
                    .fontSize(15)
                    .fontWeight(FontWeight.Medium)
                    .fontColor($r('app.color.text_primary'))
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                  if (agent.description !== '') {
                    Text(agent.description)
                      .fontSize(12)
                      .fontColor($r('app.color.text_tertiary'))
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                  }
                }
                .layoutWeight(1)
                .alignItems(HorizontalAlign.Start)
                if (agent.agentId === this.agentId) {
                  SymbolGlyph($r('sys.symbol.checkmark'))
                    .fontSize(16)
                    .fontColor([$r('app.color.brand')])
                }
              }
              .width('100%')
              .padding({ left: 14, right: 14, top: 10, bottom: 10 })
              .borderRadius(14)
              .backgroundColor(agent.agentId === this.agentId ?
                $r('app.color.brand_light') : $r('app.color.bg_card'))
              .onClick((): void => {
                this.selectAgent(agent);
              })
            }
          }, (agent: AgentModel) => agent.agentId)
        }
        .width('100%')
        .padding({ left: 12, right: 12, bottom: 24 })
        .scrollBar(BarState.Off)
      }
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  hitlCardBuilder() {
    Column({ space: 10 }) {
      Row({ space: 8 }) {
        SymbolGlyph($r('sys.symbol.exclamationmark_circle'))
          .fontSize(17)
          .fontColor([$r('app.color.warning')])
        Text('操作需要审批')
          .fontSize(15)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)
        if (this.hitlSubmitting) {
          LoadingProgress()
            .width(16)
            .height(16)
            .color($r('app.color.brand'))
        }
      }
      .width('100%')
      ForEach(this.hitlPendingActions(), (action: HitlActionView) => {
        Column({ space: 5 }) {
          Row({ space: 6 }) {
            SymbolGlyph($r('sys.symbol.paperclip'))
              .fontSize(13)
              .fontColor([$r('app.color.brand')])
            Text(action.name === '' ? '受控操作' : action.name)
              .fontSize(14)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.text_primary'))
              .layoutWeight(1)
          }
          .width('100%')
          if (action.description !== '') {
            Text(action.description)
              .fontSize(12)
              .fontColor($r('app.color.text_secondary'))
              .width('100%')
          }
          if (action.argsPreview !== '') {
            Text(action.argsPreview)
              .fontSize(11)
              .fontColor($r('app.color.text_tertiary'))
              .fontFamily('monospace')
              .maxLines(5)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .width('100%')
              .padding(8)
              .borderRadius(8)
              .backgroundColor($r('app.color.bg_input'))
          }
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
      }, (action: HitlActionView) => action.name)
      Row({ space: 8 }) {
        Button('拒绝')
          .fontSize(14)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.danger'))
          .backgroundColor($r('app.color.danger_soft'))
          .borderRadius(14)
          .height(36)
          .layoutWeight(1)
          .systemMaterial(UiMaterialKit.button())
          .onClick((): void => {
            this.submitHitl('reject', '');
          })
        Button('修改后执行')
          .fontSize(14)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
          .backgroundColor($r('app.color.bg_input'))
          .borderRadius(14)
          .height(36)
          .layoutWeight(1)
          .systemMaterial(UiMaterialKit.button())
          .onClick((): void => {
            this.startHitlEdit();
          })
        Button('批准')
          .fontSize(14)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.brand'))
          .backgroundColor($r('app.color.brand_light'))
          .borderRadius(14)
          .height(36)
          .layoutWeight(1)
          .systemMaterial(UiMaterialKit.button())
          .onClick((): void => {
            this.submitHitl('approve', '');
          })
      }
      .width('100%')
      .bindSheet($$this.hitlEditOpen, this.hitlEditSheetBuilder, {
        height: 420,
        showClose: true,
        onDisappear: (): void => {
          this.hitlEditOpen = false;
        }
      })
      Divider().color($r('app.color.card_stroke'))
      Text('也可以直接在下方输入框填写意见后点「人工回复」')
        .fontSize(11)
        .fontColor($r('app.color.text_tertiary'))
        .width('100%')
      if (this.inputText.trim() !== '') {
        Button('人工回复')
          .fontSize(14)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.brand'))
          .backgroundColor($r('app.color.brand_light'))
          .borderRadius(14)
          .height(36)
          .width('100%')
          .systemMaterial(UiMaterialKit.button())
          .onClick((): void => {
            this.submitHitlRespond();
          })
      }
    }
    .width('100%')
    .padding(14)
    .borderRadius(16)
    .backgroundColor($r('app.color.bg_card'))
    .border({ width: 1, color: $r('app.color.card_stroke') })
    .shadow({ radius: 12, color: '#1405243F', offsetX: 0, offsetY: 4 })
    .alignItems(HorizontalAlign.Start)
  }

  /** HITL 动作视图（@Builder ForEach 需要稳定对象） */
  private hitlPendingActions(): Array<HitlActionView> {
    const pending = this.hitlPending;
    if (pending === null) {
      return [];
    }
    const views: Array<HitlActionView> = [];
    for (const action of pending.actions) {
      views.push(new HitlActionView(action.name, action.description, action.argsPreview));
    }
    if (views.length === 0) {
      views.push(new HitlActionView('', '专家请求执行一个受控操作，请确认。', ''));
    }
    return views;
  }

  /** 本轮模型选择 sheet */
  @Builder
  private modelSheetBuilder() {
    ModelPickerSheet({
      allowAuto: true,
      onPick: (ref: string, label: string): void => {
        this.turnModel = ref;
        this.turnModelLabel = ref === '' ? '' : label;
        this.modelSheetOpen = false;
      }
    })
  }

  /** HITL edit 决策面板：编辑动作参数 JSON 后提交 */
  @Builder
  private hitlEditSheetBuilder() {
    Column({ space: 10 }) {
      Text('修改操作参数')
        .fontSize(17)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .width('100%')
        .padding({ top: 18, bottom: 4 })
      Text('以 JSON 格式调整参数，提交后专家将按修改后的参数执行')
        .fontSize(12)
        .fontColor($r('app.color.text_secondary'))
        .width('100%')
      TextArea({ text: this.hitlEditArgs })
        .fontSize(12)
        .fontFamily('monospace')
        .fontColor($r('app.color.text_primary'))
        .backgroundColor($r('app.color.bg_input'))
        .borderRadius(12)
        .constraintSize({ minHeight: 140 })
        .width('100%')
        .onChange((value: string): void => {
          this.hitlEditArgs = value;
        })
      Button('按修改后参数执行')
        .fontSize(15)
        .fontWeight(FontWeight.Bold)
        .fontColor(Color.White)
        .backgroundColor($r('app.color.brand'))
        .borderRadius(16)
        .height(44)
        .width('100%')
        .margin({ top: 4 })
        .onClick((): void => {
          this.submitHitlEdit();
        })
    }
    .width('100%')
    .padding({ left: 16, right: 16, bottom: 30 })
  }

  @Builder
  attachSheetBuilder() {
    Column({ space: 4 }) {
      Text('添加附件')
        .fontSize(17)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .padding({ top: 18, bottom: 10 })
      Row({ space: 12 }) {
        Column({ space: 6 }) {
          Column() {
            SymbolGlyph($r('sys.symbol.paperclip'))
              .fontSize(22)
              .fontColor([$r('app.color.brand')])
          }
          .width(46)
          .height(46)
          .borderRadius(23)
          .backgroundColor($r('app.color.brand_light'))
          .justifyContent(FlexAlign.Center)
          Text('选择图片')
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))
        }
        .layoutWeight(1)
        .onClick((): void => {
          this.pickImage();
        })

        Column({ space: 6 }) {
          Column() {
            SymbolGlyph($r('sys.symbol.book'))
              .fontSize(22)
              .fontColor([$r('app.color.brand')])
          }
          .width(46)
          .height(46)
          .borderRadius(23)
          .backgroundColor($r('app.color.brand_light'))
          .justifyContent(FlexAlign.Center)
          Text('选择文件')
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))
        }
        .layoutWeight(1)
        .onClick((): void => {
          this.pickDocument();
        })
      }
      .width('100%')
      .padding({ left: 16, right: 16, bottom: 28 })
    }
    .width('100%')
  }

  @Builder
  paletteBuilder() {
    CommandPalette({
      agentId: this.agentId,
      onClose: (): void => {
        this.paletteOpen = false;
      },
      onOpenSettings: (): void => {
        this.navStack.pushPath(new NavPathInfo('settings', null));
      }
    })
  }

  build() {
    Column() {
      Row({ space: 10 }) {
        Button({ type: ButtonType.Normal, stateEffect: true }) {
          Row({ space: 8 }) {
            Image($r('app.media.octop_logo'))
              .width(32)
              .height(32)
              .borderRadius(16)
            Text(this.agentName === '' ? '选择专家' : this.agentName)
              .fontSize(15)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.text_primary'))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .constraintSize({ maxWidth: 110 })
            SymbolGlyph($r('sys.symbol.chevron_down'))
              .fontSize(12)
              .fontColor([$r('app.color.text_tertiary')])
          }
        }
        .padding({ left: 6, right: 12, top: 5, bottom: 5 })
        .borderRadius(21)
        .backgroundColor($r('app.color.bg_card'))
        .systemMaterial(UiMaterialKit.button())
        .onClick((): void => {
          this.openAgentSheet();
        })
        .bindSheet($$this.agentSheetOpen, this.agentSheetBuilder, {
          detents: [SheetSize.MEDIUM],
          systemMaterial: UiMaterialKit.sheet()
        })

        Column({ space: 3 }) {
          Text(this.activeThreadId === '' ? '新对话' : '对话')
            .fontSize(13)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_secondary'))
          Row({ space: 5 }) {
            Column()
              .width(7)
              .height(7)
              .borderRadius(4)
              .backgroundColor(this.statusColor())
              .opacity(this.dotBreath)
            Text(this.statusText())
              .fontSize(11)
              .fontColor($r('app.color.text_tertiary'))
          }
          if (this.agentModel !== '') {
            Text(this.agentModel)
              .fontSize(11)
              .fontColor($r('app.color.text_tertiary'))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .constraintSize({ maxWidth: 130 })
          }
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        Button({ type: ButtonType.Circle, stateEffect: true }) {
          SymbolGlyph($r('sys.symbol.magnifyingglass'))
            .fontSize(18)
            .fontColor([$r('app.color.icon_secondary')])
        }
        .width(38)
        .height(38)
        .backgroundColor($r('app.color.bg_card'))
        .systemMaterial(UiMaterialKit.button())
        .onClick((): void => {
          this.paletteOpen = true;
        })
        .bindSheet($$this.paletteOpen, this.paletteBuilder, {
          detents: [SheetSize.MEDIUM, SheetSize.LARGE],
          systemMaterial: UiMaterialKit.sheet()
        })

        Button({ type: ButtonType.Circle, stateEffect: true }) {
          SymbolGlyph($r('sys.symbol.square_and_pencil'))
            .fontSize(18)
            .fontColor([$r('app.color.icon_secondary')])
        }
        .width(38)
        .height(38)
        .backgroundColor($r('app.color.bg_card'))
        .systemMaterial(UiMaterialKit.button())
        .onClick((): void => {
          this.startNewConversation();
        })
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: this.topInset + 10, bottom: 8 })

      if (this.wsError !== '') {
        Row({ space: 6 }) {
          SymbolGlyph($r('sys.symbol.wifi'))
            .fontSize(13)
            .fontColor([$r('app.color.warning')])
          Text(this.wsError)
            .fontSize(12)
            .fontColor($r('app.color.warning'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
        }
        .width('100%')
        .padding({ left: 12, right: 12, top: 7, bottom: 7 })
        .borderRadius(10)
        .backgroundColor($r('app.color.warning_soft'))
        .margin({ left: 16, right: 16, bottom: 4 })
      }

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
        Stack({ alignContent: Alignment.Bottom }) {
          List({ scroller: this.scroller, space: 12 }) {
            if (this.historyHasMore) {
              ListItem() {
                Row({ space: 6 }) {
                  if (this.loadingEarlier) {
                    LoadingProgress()
                      .width(14)
                      .height(14)
                      .color($r('app.color.brand'))
                  }
                  Text(this.loadingEarlier ? '正在加载…' : '加载更早的消息')
                    .fontSize(12)
                    .fontColor($r('app.color.text_secondary'))
                }
                .width('100%')
                .justifyContent(FlexAlign.Center)
                .padding({ top: 6, bottom: 6 })
                .onClick((): void => {
                  this.loadEarlierMessages();
                })
              }
            }
            if (this.messages.length === 0) {
              ListItem() {
                this.emptyStateBuilder()
              }
            }
            ForEach(this.messages, (msg: ChatMessageModel, index: number) => {
              ListItem() {
                MessageBubble({
                  msg: msg,
                  onRetry: (): void => {
                    this.retryLastTurn();
                  },
                  onSteerRemove: (): void => {
                    this.withdrawSteer();
                  }
                })
              }
            }, (msg: ChatMessageModel, index: number) => `${index}_${msg.id}`)
            if (this.hitlPending !== null) {
              ListItem() {
                this.hitlCardBuilder()
              }
            }
          }
          .width('100%')
          .height('100%')
          .padding({ left: 14, right: 14, top: 6, bottom: 6 })
          .scrollBar(BarState.Off)

          if (this.messages.length > 0) {
            Column()
              .width('100%')
              .height(30)
              .linearGradient({
                angle: 180,
                colors: [['#00000000', 0], [$r('app.color.bg_page'), 1]]
              })
              .hitTestBehavior(HitTestMode.None)
          }
        }
        .layoutWeight(1)
        .width('100%')
      }

      if (this.streaming && this.streamPhase !== '') {
        Row({ space: 7 }) {
          StreamingOrbit({ orbitSize: 14 })
          Text(this.streamPhase)
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 3, bottom: 2 })
        .alignItems(VerticalAlign.Center)
      }

      if (this.uploading || this.attachments.length > 0) {
        Scroll() {
          Row({ space: 8 }) {
            if (this.uploading) {
              Row({ space: 6 }) {
                LoadingProgress()
                  .width(14)
                  .height(14)
                  .color($r('app.color.brand'))
                Text('上传中...')
                  .fontSize(12)
                  .fontColor($r('app.color.text_secondary'))
              }
              .padding({ left: 10, right: 10, top: 6, bottom: 6 })
              .borderRadius(12)
              .backgroundColor($r('app.color.bg_input'))
            }
            ForEach(this.attachments, (att: ChatAttachmentModel) => {
              Row({ space: 6 }) {
                SymbolGlyph($r('sys.symbol.paperclip'))
                  .fontSize(12)
                  .fontColor([$r('app.color.brand')])
                Text(att.filename === '' ? '附件' : att.filename)
                  .fontSize(12)
                  .fontColor($r('app.color.text_secondary'))
                  .maxLines(1)
                  .constraintSize({ maxWidth: 140 })
                SymbolGlyph($r('sys.symbol.xmark'))
                  .fontSize(11)
                  .fontColor([$r('app.color.text_tertiary')])
                  .onClick((): void => {
                    this.removeAttachment(att);
                  })
              }
              .padding({ left: 10, right: 10, top: 6, bottom: 6 })
              .borderRadius(12)
              .backgroundColor($r('app.color.bg_input'))
            }, (att: ChatAttachmentModel) => att.workspacePath)
          }
        }
        .scrollable(ScrollDirection.Horizontal)
        .scrollBar(BarState.Off)
        .width('100%')
        .padding({ left: 12, right: 12, top: 2, bottom: 2 })
        .align(Alignment.Start)
      }

      Column({ space: 4 }) {
        TextArea({
          text: this.inputText,
          placeholder: this.streaming ? '可补充要求，与回复同时生效...' : $r('app.string.chat_input_placeholder')
        })
          .fontSize(15)
          .maxLines(5)
          .constraintSize({ minHeight: 46, maxHeight: 128 })
          .backgroundColor(Color.Transparent)
          .padding({ left: 16, right: 16, top: 10, bottom: 0 })
          .onChange((value: string): void => {
            if (value === '/') {
              this.inputText = '';
              this.paletteOpen = true;
              return;
            }
            this.inputText = value;
          })

        Row({ space: 10 }) {
          Button({ type: ButtonType.Circle, stateEffect: true }) {
            SymbolGlyph($r('sys.symbol.plus'))
              .fontSize(19)
              .fontColor([$r('app.color.icon_secondary')])
          }
          .width(34)
          .height(34)
          .backgroundColor($r('app.color.bg_input'))
          .systemMaterial(UiMaterialKit.button())
          .onClick((): void => {
            this.attachSheetOpen = true;
          })
          .bindSheet($$this.attachSheetOpen, this.attachSheetBuilder, {
            detents: [SheetSize.MEDIUM],
            systemMaterial: UiMaterialKit.sheet()
          })

          Button({ type: ButtonType.Circle, stateEffect: true }) {
            if (this.polishing) {
              LoadingProgress()
                .width(18)
                .height(18)
                .color($r('app.color.brand'))
            } else {
              SymbolGlyph($r('sys.symbol.wand_and_stars'))
                .fontSize(19)
                .fontColor([$r('app.color.icon_secondary')])
            }
          }
          .width(34)
          .height(34)
          .backgroundColor($r('app.color.bg_input'))
          .systemMaterial(UiMaterialKit.button())
          .onClick((): void => {
            this.polishInput();
          })

          Button({ stateEffect: true }) {
            Row({ space: 4 }) {
              Text(this.turnModelLabel === '' ? '自动' : this.turnModelLabel)
                .fontSize(11)
                .fontColor(this.turnModelLabel === '' ?
                  $r('app.color.text_secondary') : $r('app.color.brand'))
                .maxLines(1)
                .constraintSize({ maxWidth: 90 })
              SymbolGlyph($r('sys.symbol.chevron_down'))
                .fontSize(9)
                .fontColor([$r('app.color.text_tertiary')])
            }
          }
          .height(30)
          .padding({ left: 10, right: 8 })
          .borderRadius(15)
          .backgroundColor($r('app.color.bg_input'))
          .systemMaterial(UiMaterialKit.button())
          .onClick((): void => {
            this.modelSheetOpen = true;
          })
          .bindSheet($$this.modelSheetOpen, this.modelSheetBuilder, {
            detents: [SheetSize.MEDIUM, SheetSize.LARGE],
            systemMaterial: UiMaterialKit.sheet()
          })

          Blank()

          if (this.contextUsage !== null) {
            Stack() {
              Progress({ value: this.contextPct(), total: 100, type: ProgressType.Ring })
                .width(30)
                .height(30)
                .color(this.contextBarColor())
                .style({ strokeWidth: 2.5 })
              Text(`${this.contextPct()}%`)
                .fontSize(8)
                .fontWeight(FontWeight.Medium)
                .fontColor(this.contextBarColor())
            }
          }

          if (this.streaming) {
            Button({ type: ButtonType.Circle, stateEffect: true }) {
              SymbolGlyph($r('sys.symbol.stop_circle'))
                .fontSize(21)
                .fontColor([$r('app.color.danger')])
            }
            .width(34)
            .height(34)
            .backgroundColor($r('app.color.bg_input'))
            .systemMaterial(UiMaterialKit.button())
            .onClick((): void => {
              this.cancelTurn();
            })

            Button({ type: ButtonType.Circle, stateEffect: true }) {
              SymbolGlyph($r('sys.symbol.paperplane_fill'))
                .fontSize(18)
                .fontColor([$r('app.color.text_on_brand')])
            }
            .width(34)
            .height(34)
            .backgroundColor($r('app.color.brand'))
            .opacity(this.inputText.trim() === '' ? 0.4 : 1)
            .onClick((): void => {
              if (this.inputText.trim() !== '') {
                this.sendSteer(this.inputText.trim());
              }
            })
          } else {
            Button({ type: ButtonType.Circle, stateEffect: true }) {
              SymbolGlyph($r('sys.symbol.paperplane_fill'))
                .fontSize(18)
                .fontColor([$r('app.color.text_on_brand')])
            }
            .width(34)
            .height(34)
            .backgroundColor($r('app.color.brand'))
            .onClick((): void => {
              this.send();
            })
          }
        }
        .width('100%')
        .padding({ left: 10, right: 10, bottom: 10 })
      }
      .width('100%')
      .borderRadius(24)
      .backgroundColor($r('app.color.bg_card'))
      .border({ width: 1, color: $r('app.color.card_stroke') })
      .shadow({ radius: 12, color: '#1205243F', offsetX: 0, offsetY: 4 })
      .margin({ left: 12, right: 12, top: 6, bottom: this.bottomPad + 10 })
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.bg_page'))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }
}
