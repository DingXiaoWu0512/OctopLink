import { ChatAttachmentModel, ChatMessageModel, ChatRole, MsgAttachmentModel } from '../../model/MessageModels';
import { ChatStreamController } from '../../service/ChatStreamController';
import { OctopApiError } from '../../net/HttpClient';
import { SessionStore } from '../../store/SessionStore';
import { ThreadService } from '../../service/ThreadService';
import { AgentService } from '../../service/AgentService';
import { WelcomeCardModel } from '../../model/ExpertModels';
import { AgentModel } from '../../model/AgentModels';
import { ContextUsageModel, HistoryResult, ThreadModel } from '../../model/ThreadModels';
import { ResolvedModelEntry } from '../../model/WorkspaceModels';
import { ProviderService } from '../../service/ProviderService';
import { SlashCategory, SlashCommandSpec, SlashGroup } from '../../model/SlashModels';
import { HitlRequestModel } from '../../model/HitlModels';
import { MessageBubble } from '../../components/MessageBubble';
import { InputFlowBorder } from '../../components/OctopThinkingIndicator';
import { WelcomeCard } from '../../components/WelcomeCard';
import { ErrorRetry } from '../../components/ErrorRetry';
import { CommandPalette } from '../../components/CommandPalette';
import { ModelPickerSheet } from '../../components/ModelPickerSheet';
import { UiMaterialKit } from '../../components/UiMaterialKit';
import { AgentAvatar } from '../../components/AgentAvatar';
import { LocalTtsService } from '../../service/LocalTtsService';
import { TimeFormat } from '../../utils/TimeFormat';
import { Log } from '../../utils/Logger';
import { ThreadDigestCache } from '../../utils/ThreadDigestCache';
import { TextPacer } from '../../utils/TextPacer';
import { util } from '@kit.ArkTS';
import { fileIo, picker } from '@kit.CoreFileKit';
import { LengthMetrics, window } from '@kit.ArkUI';
import { HdsNavigation, HdsNavigationTitleMode, ScrollEffectType, hdsMaterial } from '@kit.UIDesignKit';
import { MenuSheetContent, MenuSheetOption } from '../../components/MenuSheet';
import { PetAvatar } from '../../pet/PetAvatar';
import { AppPrefs } from '../../store/AppPrefs';

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
  /** US4 键盘期间距收缩：软键盘高度（vp，MainPage 传导）；>0 时输入卡底边距收缩至 10；
   *  US2 键盘重锚：高度变化（弹出/收起）时贴底状态下双段延迟重锚列表（@Watch onKbHeightChange） */
  @Prop @Watch('onKbHeightChange') kbHeight: number = 0;
  @StorageLink(SessionStore.KEY_ACTIVE_THREAD_ID) @Watch('onThreadChanged') activeThreadId: string = '';
  @StorageProp(SessionStore.KEY_AGENT_ID) @Watch('onAgentChanged') agentId: string = '';
  @StorageProp(SessionStore.KEY_AGENT_NAME) agentName: string = '';
  @State messages: Array<ChatMessageModel> = [];
  @State inputText: string = '';
  /** US4：输入框聚焦态（输入卡边框 1vp/2vp 切换） */
  @State inputFocused: boolean = false;
  @StorageLink('immersive.light.on') immersiveOn: boolean = true;
  /** 聊天页头部宠物显隐（我的 → 外观 开关，默认开；AppPrefs 持久化，aboutToAppear 恢复） */
  @StorageLink('pet.visible') petVisible: boolean = true;
  @State streaming: boolean = false;
  @State streamPhase: string = '';
  /** US1 流式滚动自由：用户是否愿意贴底（手势向历史方向滚动置 false 暂停自动滚底；
   *  回到最新入口/onReachEnd/force 调用点恢复 true，状态转换见 spec FR-001~FR-004） */
  @State stickBottom: boolean = true;
  @State connecting: boolean = false;
  @State wsError: string = '';
  @State loadError: string = '';
  @State historyReady: boolean = true;
  @State welcome: WelcomeCardModel | null = null;
  @State recentThread: ThreadModel | null = null;
  @State paletteOpen: boolean = false;
  @State agentSheetOpen: boolean = false;
  @State agents: Array<AgentModel> = [];
  @State agentsLoading: boolean = false;
  @State attachments: Array<ChatAttachmentModel> = [];
  @State uploading: boolean = false;
  @State attachSheetOpen: boolean = false;
  @State contextUsage: ContextUsageModel | null = null;
  @State hitlPending: HitlRequestModel | null = null;
  @State hitlSubmitting: boolean = false;
  @State turnModel: string = '';
  @State turnModelLabel: string = '';
  @State modelSheetOpen: boolean = false;
  @State contextSheetOpen: boolean = false;
  /** 当前会话模型（thread model_ref，'' 或 'auto/auto' 表示自动） */
  @State threadModelRef: string = '';
  /** 当前模型的思考强度档位（reasoning_config.efforts，仅固定模型可解析） */
  @State modelEfforts: Array<string> = [];
  @State modelDefaultEffort: string = '';
  @State threadReasoningMode: string = '';
  @State threadReasoningEffort: string = '';
  @State effortSheetOpen: boolean = false;
  @State effortIdx: number = 0;
  @State historyHasMore: boolean = false;
  @State loadingEarlier: boolean = false;
  @State hitlEditOpen: boolean = false;
  @State hitlEditArgs: string = '';
  @State inputMaxWidth: number = 460;
  /** 输入卡量得宽/高（vp）：流光 overlay 几何用（overlay 内 '100%' 高度不按宿主解析）；
   *  flowH 初值 105（输入卡单行预估高）防首帧塌陷，onAreaChange 首帧即校正实测值 */
  @State flowW: number = 0;
  @State flowH: number = 105;
  @State slashPanelMaxHeight: number = 280;
  @State slashSpecs: Array<SlashCommandSpec> = SlashCommandSpec.fallbackList();
  private controller: ChatStreamController | null = null;
  private connectingPromise: Promise<boolean> | null = null;
  private wsReconnectTimer: number = -1;
  private wsReconnectAttempts: number = 0;
  /** 组件销毁标记：置位后停止一切自动重连 */
  private wsTeardown: boolean = false;
  private scroller: Scroller = new Scroller();
  /** US4：输入框控制器（发送成功路径收起软键盘） */
  private textAreaController: TextAreaController = new TextAreaController();
  private lastScrollMs: number = 0;
  /** 切专家清空活跃线程时置位：onThreadChanged 转 loadRecentThread 而非欢迎态 */
  private pendingRecentLoad: boolean = false;
  private activeAssistant: ChatMessageModel | null = null;
  private steerPending: ChatMessageModel | null = null;
  private currentTurnId: string = '';
  /** 服务端权威消息层：仅整体替换（loadHistory/endTurnReconciled）或翻页前插（loadEarlierMessages） */
  private serverMsgs: Array<ChatMessageModel> = [];
  /** 本地进行中 overlay：fresh 用户消息、流式占位、steer 排队消息、中断标记气泡；reconcile 成功后清空 */
  private liveMsgs: Array<ChatMessageModel> = [];
  /** 发送防重入守卫：连接握手等待期阻止二次进入 send */
  private turnSending: boolean = false;
  /** 上次已处理线程 id：onThreadChanged 同值守卫（@StorageLink 同值 setOrCreate 亦触发 @Watch） */
  private lastHandledThreadId: string = '';
  private lastConnectedId: string = '';
  private threadCreating: boolean = false;
  private steerClientPendingId: string = '';
  private steerServerPendingId: string = '';
  /** US2：回合代际计数——beginTurn 仅在创建新占位时自增（复用占位不++）；reconcile 据此识别过期拉取 */
  private turnGen: number = 0;
  /** US1：文本打字机缓冲——delta 入缓冲，40ms tick 小步落盘（自适应追赶，收尾 finish 全量零丢失） */
  private textPacer: TextPacer = new TextPacer(40, (chunk: string): void => {
    const m = this.activeAssistant;
    if (m !== null) {
      m.appendText(chunk);
      if (this.streamPhase !== '正在生成…') {
        this.streamPhase = '正在生成…';
      }
      this.scrollToBottom(false);
    }
  });
  /** US1：推理打字机缓冲——思考增量小步落盘（"深度推理中…"相位由 onReasoningDelta 帧到达时更新） */
  private reasoningPacer: TextPacer = new TextPacer(40, (chunk: string): void => {
    const m = this.activeAssistant;
    if (m !== null) {
      m.appendReasoning(chunk);
    }
  });

  aboutToAppear(): void {
    this.loadSlashCommands();
    AppPrefs.getInstance().getPetVisible().then((v: boolean): void => {
      this.petVisible = v;
    }).catch((): void => {
    });
    window.getLastWindow(getContext(this)).then((win: window.Window): void => {
      const wv: number = this.getUIContext().px2vp(win.getWindowProperties().windowRect.width);
      this.inputMaxWidth = wv < 600 ? 320 : (wv < 840 ? 380 : 460);
    }).catch((): void => {
      Log.debug('window width load failed, keep default bar width');
    });
    if (this.agentId === '') {
      this.pickDefaultAgent();
      return;
    }
    // 专家记忆：restore 只恢复了 agentId（名称为空）→ 拉取详情回填；失败回退默认链
    if (this.agentName === '') {
      this.backfillCurrentAgent();
    }
    if (this.activeThreadId !== '') {
      // 初始线程未经 @Watch 处理，同步记录已处理 id（首次同值点击即命中守卫）
      this.lastHandledThreadId = this.activeThreadId;
      this.loadHistory();
      this.connectWs();
    } else {
      this.loadRecentThread();
    }
  }

  aboutToDisappear(): void {
    this.wsTeardown = true;
    this.cancelWsReconnect();
    this.teardownStream();
    // US1：页面销毁取消打字缓冲（teardownStream 不触碰 pacer——断线重连续流期间缓冲保留；此处才是取消点）
    this.textPacer.cancel();
    this.reasoningPacer.cancel();
    this.stopTtsPlayback();
  }

  /** 停止本机引擎朗读：离页/切会话兜底，不持有引擎引用 */
  private stopTtsPlayback(): void {
    LocalTtsService.stop();
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

  /** 专家记忆：冷启动恢复了 agentId 但名称未回填 → 拉取详情经 setCurrentAgent 回填四键（并触发 onAgentChanged 重载）；
   *  详情拉取失败（专家已删除/失效）→ 清 agentId 回退 pickDefaultAgent 默认链（现状行为保留为兜底） */
  private async backfillCurrentAgent(): Promise<void> {
    const wantedId: string = this.agentId;
    try {
      const agent: AgentModel = await AgentService.get(wantedId);
      // 拉取期间用户已手动切换专家：丢弃过期回填，不覆盖新选择
      if (this.agentId !== wantedId) {
        return;
      }
      SessionStore.setCurrentAgent(agent);
    } catch (e) {
      Log.warn('backfill current agent failed, fallback to default');
      if (this.agentId !== wantedId) {
        return;
      }
      AppStorage.setOrCreate(SessionStore.KEY_AGENT_ID, '');
      this.pickDefaultAgent();
    }
  }

  /** 专家变化：断开旧连接、清空界面、重置会话并拉取新欢迎态 */
  private onAgentChanged(): void {
    this.teardownStream();
    this.stopTtsPlayback();
    // US1：切专家取消打字缓冲（定时器零泄漏，缓冲文字不串写到新专家会话）
    this.textPacer.cancel();
    this.reasoningPacer.cancel();
    this.streaming = false;
    this.activeAssistant = null;
    this.steerPending = null;
    this.currentTurnId = '';
    this.serverMsgs = [];
    this.liveMsgs = [];
    this.recompose();
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
    this.threadModelRef = '';
    if (this.agentId === '') {
      return;
    }
    if ((AppStorage.get<string>(SessionStore.KEY_ACTIVE_THREAD_ID) ?? '') !== '') {
      this.pendingRecentLoad = true;
      AppStorage.setOrCreate(SessionStore.KEY_ACTIVE_THREAD_ID, '');
    } else {
      this.loadRecentThread();
    }
  }

  /** 会话变化：同值守卫（不拆流不重载）；异值断开旧连接，非空则加载历史并连接 WS，空则回欢迎态 */
  private onThreadChanged(): void {
    if (this.activeThreadId === this.lastHandledThreadId) {
      // 同值守卫：@StorageLink 上同值 setOrCreate 亦触发 @Watch，
      // 流式中点击会话列表当前会话不拆流、不重载、光晕动画保持
      return;
    }
    this.lastHandledThreadId = this.activeThreadId;
    this.teardownStream();
    this.stopTtsPlayback();
    // US1：切会话（异值重置分支）取消打字缓冲（同值守卫提前 return，流式中点当前会话不拆流不清缓冲）
    this.textPacer.cancel();
    this.reasoningPacer.cancel();
    this.streaming = false;
    this.activeAssistant = null;
    this.steerPending = null;
    this.currentTurnId = '';
    this.serverMsgs = [];
    this.liveMsgs = [];
    this.recompose();
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
    this.threadModelRef = '';
    if (this.activeThreadId === '') {
      this.historyReady = true;
      if (this.pendingRecentLoad) {
        this.pendingRecentLoad = false;
        this.loadRecentThread();
        return;
      }
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
    this.loadThreadModelRef();
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

  // ============ 双层消息架构：serverMsgs（服务端权威层）+ liveMsgs（本地 overlay 层） ============

  /** 渲染数组统一重赋值：@State messages 恒等于 serverMsgs.concat(liveMsgs) */
  private recompose(): void {
    this.messages = this.serverMsgs.concat(this.liveMsgs);
  }

  /** 服务端权威层整体替换（loadHistory/endTurnReconciled），不触碰 liveMsgs，不做任何文本判重 */
  private setServerMsgs(list: Array<ChatMessageModel>): void {
    this.serverMsgs = list;
    this.recompose();
  }

  /** 本地 overlay 层追加（fresh 用户消息 / 流式占位 / steer 排队消息） */
  private pushLive(m: ChatMessageModel): void {
    this.liveMsgs.push(m);
    this.recompose();
  }

  /** 本地 overlay 层移除（发送失败移除本轮占位 / steer 撤回移除排队消息） */
  private removeLive(m: ChatMessageModel): void {
    this.liveMsgs = this.liveMsgs.filter((x: ChatMessageModel): boolean => x !== m);
    this.recompose();
  }

  /** turn 生命周期-开始：幂等创建/复用流式占位（activeAssistant 已存在则复用，不重复 push） */
  private beginTurn(phase: string): void {
    let m: ChatMessageModel | null = this.activeAssistant;
    if (m === null) {
      // US1：新占位创建——取消上一回合残留打字缓冲（防陈旧文字写入新占位）
      this.textPacer.cancel();
      this.reasoningPacer.cancel();
      // US2：回合代际自增（仅创建新占位时；复用占位不++），过期 reconcile 完成时据此中止
      this.turnGen++;
      m = ChatMessageModel.streamingAssistant();
      this.pushLive(m);
      this.activeAssistant = m;
    }
    this.streaming = true;
    this.streamPhase = phase;
  }

  /** turn 生命周期-纯本地标记收尾：占位 markEnded 后保留在 liveMsgs（中断/审批暂停兜底），不拉历史 */
  private endTurnMarked(failed: boolean, message: string): void {
    // US1：收尾前先全量落盘打字缓冲（顺序保证：finish 先于占位引用变更，最终内容完整写入，零丢失）
    this.textPacer.finish();
    this.reasoningPacer.finish();
    const m = this.activeAssistant;
    if (m !== null) {
      m.markEnded(failed, message);
      this.syncDigest(m.text);
    }
    this.activeAssistant = null;
    this.currentTurnId = '';
    this.streaming = false;
    this.streamPhase = '';
  }

  /** turn 生命周期-权威 reconcile 收尾（唯一常规收尾）：入口同步收敛（①finish pacer ②捕获代际/占位
    *  ③收敛回合状态——任何 await 之前）→ ④拉全量历史 → 同 tick 替换 serverMsgs 并清空 liveMsgs
    *  → 刷新 hitlPending/hasMore/摘要/上下文/线程列表；线程切换或代际变化（新回合已开始）时中止不覆盖；
    *  失败对入口捕获的占位回退本地标记 */
  private async endTurnReconciled(): Promise<void> {
    // ① US1：收尾前先全量落盘打字缓冲（缓冲写入尚在显示的占位，收尾内容零丢失）
    this.textPacer.finish();
    this.reasoningPacer.finish();
    // ② US2：捕获回合代际与占位引用（供拉取完成后的代际守卫与失败回退使用）
    const gen: number = this.turnGen;
    const turnAssistant: ChatMessageModel | null = this.activeAssistant;
    const threadId: string = AppStorage.get<string>(SessionStore.KEY_ACTIVE_THREAD_ID) ?? '';
    const agentId: string = AppStorage.get<string>(SessionStore.KEY_AGENT_ID) ?? '';
    if (threadId === '' || agentId === '') {
      this.endTurnMarked(true, '回复中断');
      return;
    }
    // ③ US2 同步收敛回合状态（任何 await 之前）：竞态窗口（await 拉历史期间）内 streaming 已为 false，
    //    窗口内点击发送命中 send() 常规分支（turnSending 守卫 + 同步清输入），不再误路由进无守卫的 steer；
    //    已完成的占位气泡保留在 liveMsgs 显示，直到权威历史替换
    this.streaming = false;
    this.streamPhase = '';
    this.currentTurnId = '';
    this.activeAssistant = null;
    // ④ US2：await 拉全量历史（竞态窗口自此打开，回合状态已收敛）
    let result: HistoryResult | null = null;
    try {
      result = await ThreadService.historyFull(agentId, threadId);
    } catch (e) {
      Log.warn('turn reconcile history fetch failed, fallback to local marked end');
    }
    if (threadId !== (AppStorage.get<string>(SessionStore.KEY_ACTIVE_THREAD_ID) ?? '')) {
      // 线程已切换：过期 reconcile 中止（新线程的全量重置自会接管界面）
      return;
    }
    if (gen !== this.turnGen) {
      // US2 代际守卫：拉取期间已有新回合开始（新占位创建时 turnGen 自增），过期 reconcile 中止不覆盖，
      // 不清空 liveMsgs（其中已含新回合的 fresh 消息与流式占位）
      return;
    }
    if (result === null) {
      // US2 拉取失败回退：对入口捕获的占位 markEnded（null 安全），中断气泡保留在 liveMsgs 直至下次
      // reconcile/切会话清空；代际已变则上面已提前 return（跳过标记，新回合自会 reconcile 收尾）
      if (turnAssistant !== null) {
        turnAssistant.markEnded(true, '回复中断');
        this.syncDigest(turnAssistant.text);
      }
      return;
    }
    // 同 tick 原子切换：先清空本地 overlay，再以服务端权威整体替换，recompose 一次生效无闪烁
    this.liveMsgs = [];
    this.setServerMsgs(result.messages);
    // US2：liveMsgs 已清空，同步清理 dangling steerPending（引用消息已不在 overlay 则置 null，防后续 echo 被误吞）
    const danglingSteer: ChatMessageModel | null = this.steerPending;
    if (danglingSteer !== null && this.liveMsgs.indexOf(danglingSteer) < 0) {
      this.steerPending = null;
    }
    this.historyHasMore = result.hasMore;
    this.hitlPending = result.hitlPending;
    this.hitlSubmitting = false;
    // 回合状态（activeAssistant/currentTurnId/streaming/streamPhase）已在入口③同步收敛，此处无需重复
    this.syncDigest('');
    AppStorage.setOrCreate(SessionStore.KEY_THREADS_DIRTY, true);
    this.refreshContextUsage();
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
      // 双层架构：历史拉取只整体替换服务端权威层，本地进行中 overlay（liveMsgs）不动，不做文本判重
      this.setServerMsgs(result.messages);
      this.historyHasMore = result.hasMore;
      this.hitlPending = result.hitlPending;
      this.hitlSubmitting = false;
      this.loadError = '';
      this.historyReady = true;
      this.syncDigest('');
      this.markThreadRead(agentId, threadId);
      this.refreshContextUsage();
      if (this.messages.length === 0) {
        this.loadWelcome();
      } else {
        // 打开时用一次滚动到底：产生真实滚动帧，让标题栏 GRADUAL_BLUR 初始态求值
        // （纯程序化静默定位后效果不求值，首次手势才出现）
        // US3：改 scrollEdge 锚定真实底端，消除标题栏占位/加载更早项的索引偏移
        setTimeout((): void => {
          if (this.messages.length > 0) {
            // US1：打开会话强制贴底并恢复跟随
            this.stickBottom = true;
            this.scroller.scrollEdge(Edge.Bottom);
          }
        }, 120);
      }
    } catch (e) {
      this.loadError = e instanceof OctopApiError ? e.message : '历史消息加载失败';
      this.historyReady = true;
    }
  }

  /** 向前翻页加载更早的历史消息（offset 只数服务端权威层） */
  private async loadEarlierMessages(): Promise<void> {
    const threadId: string = this.activeThreadId;
    const agentId: string = AppStorage.get<string>(SessionStore.KEY_AGENT_ID) ?? '';
    if (threadId === '' || agentId === '' || this.loadingEarlier) {
      return;
    }
    this.loadingEarlier = true;
    try {
      // offset 只数服务端权威层：本地 liveMsgs（流式占位/刚发消息）不计入，避免窗口偏高返回重叠重复
      const result: HistoryResult = await ThreadService.historyFull(agentId, threadId, this.serverMsgs.length);
      if (threadId !== (AppStorage.get<string>(SessionStore.KEY_ACTIVE_THREAD_ID) ?? '')) {
        return;
      }
      // 翻页前插：结果消息接在 serverMsgs 之前整体替换权威层，liveMsgs 不动
      this.setServerMsgs(result.messages.concat(this.serverMsgs));
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

  /** 无活跃线程时自动进入最近一条会话，无会话/失败回退欢迎态 */
  private async loadRecentThread(): Promise<void> {
    const agentId: string = AppStorage.get<string>(SessionStore.KEY_AGENT_ID) ?? '';
    if (agentId === '') {
      return;
    }
    try {
      const threads: Array<ThreadModel> = await ThreadService.list(agentId, 1);
      if (threads.length > 0) {
        AppStorage.setOrCreate(SessionStore.KEY_ACTIVE_THREAD_ID, threads[0].threadId);
        return;
      }
    } catch (e) {
      Log.debug('recent thread load failed, fallback to welcome');
    }
    this.loadWelcome();
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
    this.cancelWsReconnect();
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
      // US1：delta 入打字机缓冲，由 40ms tick 小步落盘（帧按网络批次到达不再整批跳出）
      this.textPacer.push(delta);
    };
    controller.callbacks.onReasoningDelta = (delta: string): void => {
      const m = this.activeAssistant;
      // US3：推理首帧记录时间戳（折叠行"深度思考中… Ns"计时基准，仅首帧写一次）
      if (m !== null && m.reasoningStartAt === undefined) {
        m.reasoningStartAt = Date.now();
      }
      // US1：推理增量入缓冲小步落盘；"深度推理中…"相位在帧到达时同步更新
      if (this.activeAssistant !== null && this.streamPhase !== '深度推理中…') {
        this.streamPhase = '深度推理中…';
      }
      this.reasoningPacer.push(delta);
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
        // US3：工具名 badge/状态行变化时滚到真实底部，"正在调用 xx"出现即可见最新内容
        this.scrollToBottom(false);
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
      if (this.streamPhase === '恢复续流中…') {
        // 断线/重启续流的 turn.resumed：保留续流相位语义（回合结束仍以权威 reconcile 补齐缺口）
        this.streamPhase = '正在生成…';
      } else {
        this.streamPhase = '正在思考…';
      }
    };
    controller.callbacks.onTurnEnded = (failed: boolean): void => {
      // 回合结束一律以服务端权威历史 reconcile 收尾（唯一常规收尾路径）：
      // 服务端历史自带 failed/error 状态，本地不再做 gap 缺口追踪
      this.endTurnReconciled();
    };
    controller.callbacks.onStreamError = (message: string): void => {
      // 流错误：纯本地标记收尾（中断气泡保留在 liveMsgs，待下次 reconcile/切会话清空）
      this.endTurnMarked(true, message);
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
        // steer echo：清除排队引用，消息本体保留在 liveMsgs（由回合结束 reconcile 统一清空）
        this.steerPending = null;
      } else if (content !== '') {
        // 仅当本地 overlay 尾部不存在同文本用户消息时补推（send() 先行 push 的消息不重复）
        let tailDup: boolean = false;
        for (let i = this.liveMsgs.length - 1; i >= 0; i--) {
          if (this.liveMsgs[i].role === ChatRole.USER) {
            tailDup = this.liveMsgs[i].text === content;
            break;
          }
        }
        if (!tailDup) {
          this.pushLive(ChatMessageModel.fromUserText(content, Date.now()));
        }
      }
      this.beginTurn('正在思考…');
      // US1：用户主动行为（echo 补推）强制贴底并恢复跟随
      this.stickBottom = true;
      this.scrollToBottom(true);
    };
    controller.callbacks.onSteerDiscarded = (reason: string): void => {
      this.removeSteerPending();
      this.getUIContext().getPromptAction().showToast({ message: '追问已被取消' });
    };
    controller.callbacks.onHitlRequired = (request: HitlRequestModel): void => {
      // 审批暂停：纯本地标记收尾（占位气泡保留在 liveMsgs），弹审批卡等待决策
      this.endTurnMarked(false, '');
      this.hitlPending = request;
      this.hitlSubmitting = false;
      // US1：审批卡出现强制贴底并恢复跟随
      this.stickBottom = true;
      this.scrollToBottom(true);
    };
    controller.callbacks.onResumeStreamEnd = (failed: boolean): void => {
      // 审批恢复 SSE 流结束（done/error/嵌套审批）：本地标记收尾占位气泡
      this.endTurnMarked(failed, failed ? '回复中断' : '');
      this.hitlSubmitting = false;
      AppStorage.setOrCreate(SessionStore.KEY_THREADS_DIRTY, true);
      this.refreshContextUsage();
    };
    controller.callbacks.onTurnStatus = (active: boolean): void => {
      // 订阅应答：active=true 服务端仍在输出（弱流恢复续流）；false 且本地在等待恢复则以权威历史收尾
      if (!active && this.streaming && this.streamPhase === '恢复续流中…') {
        // 服务端回合已结束：完整回复已在服务端线程消息里，reconcile 拉回替换，不误标"回复中断"
        this.endTurnReconciled();
      } else if (active && this.streaming) {
        this.streamPhase = '正在生成…';
      } else if (active && !this.streaming && this.activeAssistant === null &&
        this.hitlPending === null && !this.hitlSubmitting) {
        // 重启续流：订阅应答表明回合仍活跃但本地无流式气泡（App 重启/重进会话后订阅）。
        // 重建流式占位接续后续实时帧；回合结束以权威 reconcile 补齐全量内容
        this.beginTurn('恢复续流中…');
        this.scrollToBottom(true);
      }
    };
    controller.callbacks.onConnectionClosed = (code: number, reason: string): void => {
      Log.warn(`WS connection closed: ${code} ${reason}`);
      if (this.wsTeardown) {
        return;
      }
      this.wsError = '实时通道已断开，正在自动重连…';
      if (this.streaming) {
        // 弱流恢复：保持消息与流状态，重连后由 turn_status/实时帧续流，回合结束以权威 reconcile 补齐
        this.streamPhase = '恢复续流中…';
      }
      this.scheduleWsReconnect();
    };
  }

  /** 断线自动重连：指数退避 2s 起步、30s 封顶，成功后清零计数 */
  private scheduleWsReconnect(): void {
    if (this.wsTeardown) {
      return;
    }
    this.cancelWsReconnect();
    const threadId: string = AppStorage.get<string>(SessionStore.KEY_ACTIVE_THREAD_ID) ?? '';
    const agentId: string = AppStorage.get<string>(SessionStore.KEY_AGENT_ID) ?? '';
    if (threadId === '' || agentId === '') {
      return;
    }
    const delayMs: number = Math.min(2000 * Math.pow(2, this.wsReconnectAttempts), 30000);
    this.wsReconnectAttempts++;
    this.wsReconnectTimer = setTimeout((): void => {
      this.wsReconnectTimer = -1;
      this.reconnectWs();
    }, delayMs);
  }

  private cancelWsReconnect(): void {
    if (this.wsReconnectTimer !== -1) {
      clearTimeout(this.wsReconnectTimer);
      this.wsReconnectTimer = -1;
    }
  }

  private async reconnectWs(): Promise<void> {
    if (this.wsTeardown) {
      return;
    }
    const ok: boolean = await this.connectWs();
    if (this.wsTeardown) {
      return;
    }
    if (ok) {
      this.wsReconnectAttempts = 0;
      this.wsError = '';
      return;
    }
    // 流式中的弱流恢复连续失败：本地标记中断，不再无限等待（气泡保留在 liveMsgs 待下次 reconcile）
    if (this.streaming && this.wsReconnectAttempts >= 4) {
      this.endTurnMarked(true, '网络连接中断');
      return;
    }
    this.scheduleWsReconnect();
  }

  private removeSteerPending(): void {
    const pending = this.steerPending;
    if (pending === null) {
      return;
    }
    this.steerPending = null;
    this.removeLive(pending);
  }

  /** US4 键盘期间距收缩统一入口：输入卡底边距——
   *  键盘弹出（kbHeight>0，悬浮 TabBar 已隐藏）收缩至 10（约 35px，缩减 ≥2/3）；
   *  收起恢复 bottomPad+10 现状（FR-014 收起态视觉零变化）。
   *  输入卡 margin.bottom 与列表 contentEndOffset 同用此入口，卡片与气泡停止位永远一致 */
  private inputBottomInset(): number {
    return this.kbHeight > 0 ? 10 : this.bottomPad + 10;
  }

  /** US2 键盘收起重锚：键盘收起瞬间 List 视口扩展而 contentEndOffset 尚未随 kbHeight 更新完成，
   *  stackFromEnd 把内容末端锚到新视口底，最新消息沉入输入卡后方；布局稳定后补 scrollEdge
   *  使收起态 contentEndOffset（bottomPad+10）生效，消息回到输入卡上方正常间隙位。
   *  双段延迟（120/320ms）覆盖窗口 RESIZE 动画前后两帧时序不确定；延迟回调内重查最新
   *  stickBottom 尊重用户滚动自由；不调 scrollToBottom(force)（避免强制置位覆盖阅读位置）；幂等可重入 */
  private onKbHeightChange(): void {
    if (this.stickBottom && this.messages.length > 0) {
      setTimeout((): void => {
        if (this.stickBottom) {
          this.scroller.scrollEdge(Edge.Bottom);
        }
      }, 120);
      setTimeout((): void => {
        if (this.stickBottom) {
          this.scroller.scrollEdge(Edge.Bottom);
        }
      }, 320);
    }
  }

  private scrollToBottom(force: boolean): void {
    // US1 贴底门禁：非 force 且用户已滚离底部（stickBottom=false）时直接返回，
    // 置于 150ms 节流之前——未贴底时零滚动调用，流式期间 textPacer 每 delta 的
    // 滚底调用不再把视口拉回，用户可自由上滑阅读历史
    if (!force && !this.stickBottom) {
      return;
    }
    // US1：force 强制贴底视为用户/系统主动回底，恢复自动跟随
    // （集中兜底 submitHitl/续流重建等未逐一枚举的 force 调用点）
    if (force) {
      this.stickBottom = true;
    }
    const now = Date.now();
    if (!force && now - this.lastScrollMs < 150) {
      return;
    }
    this.lastScrollMs = now;
    if (this.messages.length === 0) {
      return;
    }
    // US3 滚动修复：scrollToIndex 受标题栏占位/加载更早/审批卡等附加项索引偏移影响，
    // 实际落在倒数第 1+offset 条消息上（"工具调用时跳到最近上一条"根因）；scrollEdge 直接锚定列表真实底端
    this.scroller.scrollEdge(Edge.Bottom);
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

  /** 发送：流式进行中走 steer 追问，否则确保会话后走常规 user_turn（turnSending 防重入） */
  private async send(): Promise<void> {
    if (this.turnSending) {
      // 防重入守卫：上次发送仍在握手/推送等待期，忽略本次点击（慢网双击不双重推送）
      return;
    }
    const text: string = this.inputText.trim();
    if (text === '') {
      return;
    }
    // 客户端动作命令（/new、/stop 等）本地执行，不发送到服务端
    const actionSpec = this.matchActionCommand(text);
    if (actionSpec !== null) {
      this.inputText = '';
      this.runSlashCommand(actionSpec);
      return;
    }
    if (this.streaming) {
      // US2：steer 分支对齐常规分支——turnSending 防重入守卫（回复收尾窗口快速双击只进一次，
      // 修复：双击均进无守卫 sendSteer → 服务端各记一条 user_turn → 出两条相同消息）
      this.turnSending = true;
      // 任何 await 之前同步清空输入框：即时反馈 + 二次点击命中守卫/空输入直接返回
      this.inputText = '';
      try {
        await this.sendSteer(text);
      } finally {
        this.turnSending = false;
      }
      return;
    }
    this.turnSending = true;
    const originalInput: string = this.inputText;
    // 任何 await 之前同步清空输入框：即时反馈 + 二次点击因空输入直接返回
    this.inputText = '';
    try {
      const threadId: string = await this.ensureThread();
      if (threadId === '') {
        if ((AppStorage.get<string>(SessionStore.KEY_AGENT_ID) ?? '') === '') {
          this.getUIContext().getPromptAction().showToast({ message: '暂无可用专家，请先在专家页添加' });
        }
        this.inputText = originalInput;
        return;
      }
      const connected: boolean = await this.connectWs();
      if (!connected) {
        this.wsError = '连接服务器失败，请检查网络后重试';
        this.inputText = originalInput;
        this.getUIContext().getPromptAction().showToast({ message: '消息发送失败，请检查网络' });
        return;
      }
      if (this.streaming) {
        // 连接等待期间订阅应答已重建续流占位（US2 竞态）：改走 steer 追问，避免重复推送流式占位
        await this.sendSteer(text);
        return;
      }
      const controller = this.controller;
      if (controller === null) {
        this.inputText = originalInput;
        return;
      }
      this.wsError = '';
      this.welcome = null;
      this.recentThread = null;
      const atts: Array<ChatAttachmentModel> = this.attachments;
      this.attachments = [];
      const userMsg = ChatMessageModel.fromUserText(text, Date.now());
      for (const att of atts) {
        userMsg.attachmentNames.push(att.filename);
      }
      userMsg.fresh = true;
      this.pushLive(userMsg);
      this.beginTurn('正在思考…');
      // US1：用户主动发送强制贴底并恢复跟随
      this.stickBottom = true;
      this.scrollToBottom(true);
      try {
        await controller.sendUserTurn(text, atts, this.turnModel);
        // US4：常规发送成功后收起软键盘
        this.textAreaController.stopEditing();
        AppStorage.setOrCreate(SessionStore.KEY_THREADS_DIRTY, true);
      } catch (e) {
        // 发送失败：恢复输入原文、移除本轮用户消息与流式占位（不留本地残迹）、toast 提示
        const am = this.activeAssistant;
        if (am !== null) {
          this.removeLive(am);
        }
        this.removeLive(userMsg);
        this.activeAssistant = null;
        this.currentTurnId = '';
        this.streaming = false;
        this.streamPhase = '';
        this.inputText = originalInput;
        this.getUIContext().getPromptAction().showToast({ message: '消息发送失败' });
      }
    } finally {
      this.turnSending = false;
    }
  }

  /** Steer 追问：本地先插入用户消息（liveMsgs），ack rejected 时移除并提示 */
  private async sendSteer(text: string): Promise<void> {
    let controller = this.controller;
    if (controller === null || !controller.connected) {
      // 断线追问：await（重连）前同步清空输入（即时反馈），重连失败恢复输入
      const originalInput: string = this.inputText;
      this.inputText = '';
      const reconnected: boolean = await this.connectWs();
      if (!reconnected) {
        this.wsError = '连接已断开，无法追加消息';
        this.inputText = originalInput !== '' ? originalInput : text;
        return;
      }
      controller = this.controller;
      if (controller === null) {
        this.inputText = originalInput !== '' ? originalInput : text;
        return;
      }
    }
    if (this.currentTurnId === '') {
      this.getUIContext().getPromptAction().showToast({ message: '正在等待回复开始，请稍候' });
      // US2：未发送成功，恢复原文（调用方已在 await 前清空输入，此处回填避免输入丢失）
      this.inputText = text;
      return;
    }
    this.wsError = '';
    this.inputText = '';
    const pending = ChatMessageModel.fromUserText(text, Date.now());
    pending.fresh = true;
    this.pushLive(pending);
    this.steerPending = pending;
    // US1：steer 追问推送强制贴底并恢复跟随
    this.stickBottom = true;
    this.scrollToBottom(true);
    const clientPendingId: string = util.generateRandomUUID();
    pending.clientPendingId = clientPendingId;
    this.steerClientPendingId = clientPendingId;
    this.steerServerPendingId = '';
    try {
      await controller.sendSteer(text, this.currentTurnId, clientPendingId);
      // US4：追问发送成功后收起软键盘
      this.textAreaController.stopEditing();
    } catch (e) {
      this.removeSteerPending();
      // US2：发送失败恢复原文（与常规发送分支失败恢复输入对齐），排队消息已移除不留残迹
      this.inputText = text;
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

  /** 中止进行中的 HITL 审批恢复（"停止生成"）：本地标记收尾，气泡保留在 liveMsgs */
  private abortHitlResume(): void {
    const c = this.controller;
    if (c !== null) {
      c.abortResume();
    }
    this.endTurnMarked(false, '已停止生成');
    this.hitlSubmitting = false;
  }

  /** HITL 决策提交：approve/reject/respond/edit，走 SSE resume 恢复流（beginTurn 幂等复用/创建占位） */
  private submitHitl(decisionType: string, message: string, editedActionStr: string = ''): void {
    const controller = this.controller;
    const pending = this.hitlPending;
    if (controller === null || pending === null || this.hitlSubmitting) {
      return;
    }
    this.hitlSubmitting = true;
    this.hitlPending = null;
    this.beginTurn('正在生成…');
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
    // US4：人工回复提交成功路径，收起软键盘
    this.textAreaController.stopEditing();
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

  /** 斜杠查询：输入以 "/" 开头时返回命令词（空格前的部分，支持 "/命令 参数"），否则 null */
  private slashQuery(): string | null {
    const text: string = this.inputText;
    if (!text.startsWith('/')) {
      return null;
    }
    let head: string = text.substring(1);
    const spIdx: number = head.indexOf(' ');
    if (spIdx >= 0) {
      head = head.substring(0, spIdx);
    }
    return head.trim().toLowerCase();
  }

  /** 拉取服务端原生斜杠命令（失败保持内置回退） */
  private loadSlashCommands(): void {
    AgentService.listSlashCommands().then((specs: Array<SlashCommandSpec>): void => {
      if (specs.length > 0) {
        this.slashSpecs = specs;
      }
    }).catch((): void => {
      Log.debug('slash commands load failed, keep fallback');
    });
  }

  /** 当前过滤词命中的斜杠分组（按 core/skills/session/media/system/debug 排序） */
  private matchingSlashGroups(): Array<SlashGroup> {
    const query: string | null = this.slashQuery();
    if (query === null) {
      return [];
    }
    const groups: Array<SlashGroup> = [];
    const order: Array<string> = SlashCategory.order();
    const rest: Array<SlashCommandSpec> = [];
    for (const category of order) {
      const items: Array<SlashCommandSpec> = [];
      for (const spec of this.slashSpecs) {
        if (spec.category === category && spec.matches(query)) {
          items.push(spec);
        }
      }
      if (items.length > 0) {
        groups.push(new SlashGroup(category, SlashCategory.label(category), items));
      }
    }
    for (const spec of this.slashSpecs) {
      if (order.indexOf(spec.category) < 0 && spec.matches(query)) {
        rest.push(spec);
      }
    }
    if (rest.length > 0) {
      groups.push(new SlashGroup('other', SlashCategory.label('other'), rest));
    }
    return groups;
  }

  /** Lucide 图标名 → 系统 Symbol 映射 */
  private slashIcon(icon: string): Resource {
    if (icon === 'Activity') {
      return $r('sys.symbol.dot_radiowaves_left_and_right');
    }
    if (icon === 'Cpu') {
      return $r('sys.symbol.robot');
    }
    if (icon === 'MessagesSquare') {
      return $r('sys.symbol.message_fill');
    }
    if (icon === 'RefreshCw') {
      return $r('sys.symbol.arrow_clockwise');
    }
    if (icon === 'Archive') {
      return $r('sys.symbol.square_grid_2x2');
    }
    if (icon === 'Database') {
      return $r('sys.symbol.folder_fill');
    }
    if (icon === 'Square') {
      return $r('sys.symbol.stop_circle');
    }
    if (icon === 'BarChart3') {
      return $r('sys.symbol.doc_text');
    }
    if (icon === 'Coins') {
      return $r('sys.symbol.timer');
    }
    if (icon === 'List') {
      return $r('sys.symbol.message');
    }
    if (icon === 'ArrowLeftRight') {
      return $r('sys.symbol.arrow_left');
    }
    if (icon === 'Undo2') {
      return $r('sys.symbol.play');
    }
    if (icon === 'Type') {
      return $r('sys.symbol.character_textbox');
    }
    if (icon === 'Trash2') {
      return $r('sys.symbol.trash');
    }
    if (icon === 'Pin') {
      return $r('sys.symbol.pin');
    }
    if (icon === 'Clock') {
      return $r('sys.symbol.clock');
    }
    if (icon === 'Bot') {
      return $r('sys.symbol.robot');
    }
    if (icon === 'Sparkles') {
      return $r('sys.symbol.wand_and_stars');
    }
    if (icon === 'Plug') {
      return $r('sys.symbol.link');
    }
    if (icon === 'CircleHelp') {
      return $r('sys.symbol.lightbulb');
    }
    return $r('sys.symbol.wand_and_stars');
  }

  /** tone → 主色 */
  private slashToneColor(tone: string): Resource {
    if (tone === 'emerald') {
      return $r('app.color.success');
    }
    if (tone === 'rose') {
      return $r('app.color.danger');
    }
    if (tone === 'amber' || tone === 'orange') {
      return $r('app.color.warning');
    }
    if (tone === 'slate') {
      return $r('app.color.text_secondary');
    }
    return $r('app.color.brand');
  }

  /** 选中命令：客户端动作本地执行；需参数预填；其余直接发送（与 Web 端 runSlashCommand 对齐） */
  private runSlashCommand(spec: SlashCommandSpec): void {
    if (spec.clientAction === 'new_chat') {
      this.inputText = '';
      // US4：斜杠命令本地执行成功路径，收起软键盘
      this.textAreaController.stopEditing();
      this.startNewConversation();
      return;
    }
    if (spec.clientAction === 'cancel_stream') {
      this.inputText = '';
      // US4：斜杠命令本地执行成功路径，收起软键盘
      this.textAreaController.stopEditing();
      this.cancelTurn();
      return;
    }
    if (spec.needsInput()) {
      this.inputText = spec.prefillText();
      return;
    }
    this.inputText = spec.commandToken();
    this.send();
  }

  /** 精确匹配带客户端动作的斜杠命令（/new、/stop 及其别名），供 send 拦截 */
  private matchActionCommand(text: string): SlashCommandSpec | null {
    for (const spec of this.slashSpecs) {
      if (spec.clientAction === 'none') {
        continue;
      }
      if (text === spec.commandToken() || text === `/${spec.name}`) {
        return spec;
      }
      for (const alias of spec.aliases) {
        if (text === `/${alias}`) {
          return spec;
        }
      }
    }
    return null;
  }
  /** 斜杠命令候选面板（输入 "/" 时展示在输入框上方：紧凑双列网格，与 Web 端 slashMenu 同构） */
  @Builder
  private slashPanelBuilder() {
    Scroll() {
      Column() {
        ForEach(this.matchingSlashGroups(), (group: SlashGroup) => {
          Text(group.label)
            .fontSize(10)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_tertiary'))
            .width('100%')
            .textAlign(TextAlign.Start)
            .padding({ left: 8, top: 6, bottom: 3 })
          Grid() {
            ForEach(group.items, (spec: SlashCommandSpec) => {
              GridItem() {
                Column({ space: 4 }) {
                  Row({ space: 6 }) {
                    SymbolGlyph(this.slashIcon(spec.icon))
                      .fontSize(14)
                      .fontColor([this.slashToneColor(spec.tone)])
                    Text(spec.label())
                      .fontSize(12)
                      .fontWeight(FontWeight.Medium)
                      .fontColor($r('app.color.text_primary'))
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                      .layoutWeight(1)
                  }
                  .width('100%')
                  Text(spec.commandToken())
                    .fontSize(10)
                    .fontColor($r('app.color.text_tertiary'))
                    .fontFamily('monospace')
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                    .padding({ left: 5, right: 5, top: 1, bottom: 1 })
                    .borderRadius(4)
                    .backgroundColor($r('app.color.bg_input'))
                }
                .alignItems(HorizontalAlign.Start)
                .width('100%')
                .padding({ left: 8, right: 8, top: 6, bottom: 6 })
                .borderRadius(10)
                .onClick((): void => {
                  this.runSlashCommand(spec);
                })
              }
            }, (spec: SlashCommandSpec) => spec.name)
          }
          .columnsTemplate('1fr 1fr')
          .columnsGap(6)
          .rowsGap(4)
          .width('100%')
        }, (group: SlashGroup) => group.category)
      }
      .width('100%')
    }
    .scrollBar(BarState.Off)
    .width('100%')
    .padding({ left: 6, right: 6, top: 2, bottom: 6 })
    .borderRadius(14)
    .backgroundColor($r('app.color.bg_card'))
    .border({ width: 1, color: $r('app.color.card_stroke') })
    .shadow({ radius: 12, color: '#1205243F', offsetX: 0, offsetY: 4 })
    // 注意：constraintSize 只能调用一次，二次调用会整体覆盖前者（maxHeight 必须与 maxWidth 合并声明）
    .constraintSize({ maxHeight: this.slashPanelMaxHeight, maxWidth: this.inputMaxWidth })
    .margin({ left: 12, right: 12, bottom: 4 })
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

  /** 标题胶囊头像：优先从已加载专家列表取 iconUrl（未加载时 AgentAvatar 走 agentId 头像接口回退） */
  private currentAgentIconUrl(): string {
    for (const agent of this.agents) {
      if (agent.agentId === this.agentId) {
        return agent.iconUrl;
      }
    }
    return '';
  }

  /** 拉取当前会话的 model_ref 与思考强度设置，并解析固定模型的思考档位 */
  private async loadThreadModelRef(): Promise<void> {
    const threadId: string = this.activeThreadId;
    const agentId: string = this.agentId;
    if (threadId === '' || agentId === '') {
      this.threadModelRef = '';
      this.modelEfforts = [];
      this.modelDefaultEffort = '';
      return;
    }
    try {
      const threads: Array<ThreadModel> = await ThreadService.list(agentId, 200);
      if (threadId !== this.activeThreadId || agentId !== this.agentId) {
        return;
      }
      let found: ThreadModel | null = null;
      for (const thread of threads) {
        if (thread.threadId === threadId) {
          found = thread;
          break;
        }
      }
      this.threadModelRef = found === null ? '' : found.modelRef;
      this.threadReasoningMode = found === null ? '' : found.reasoningMode;
      this.threadReasoningEffort = found === null ? '' : found.reasoningEffort;
      await this.loadReasoningEfforts();
    } catch (e) {
      Log.debug('thread model_ref load failed, keep auto');
    }
  }

  /** 解析当前固定模型的思考强度档位（auto 模型无法预知，不显示开关） */
  private async loadReasoningEfforts(): Promise<void> {
    const ref: string = this.threadModelRef;
    this.modelEfforts = [];
    this.modelDefaultEffort = '';
    if (ref === '' || ref === 'auto/auto') {
      return;
    }
    try {
      const models: Array<ResolvedModelEntry> = await ProviderService.resolvedModels();
      if (ref !== this.threadModelRef) {
        return;
      }
      for (const entry of models) {
        if (entry.ref() === ref) {
          this.modelEfforts = entry.reasoningEfforts;
          this.modelDefaultEffort = entry.reasoningDefaultEffort;
          break;
        }
      }
    } catch (e) {
      Log.debug('resolved models load failed, hide effort pill');
    }
  }

  /** 档位显示名：常见枚举中文映射，token budget 等数值档位原样显示 */
  private effortLabel(v: string): string {
    if (v === 'low') {
      return '低';
    }
    if (v === 'medium') {
      return '中';
    }
    if (v === 'high') {
      return '高';
    }
    if (v === 'minimal') {
      return '极低';
    }
    if (v === 'max') {
      return '最高';
    }
    if (v === 'none') {
      return '无';
    }
    return v;
  }

  /** 当前生效档位（线程设置 > 模型默认），空表示跟随模型默认行为 */
  private currentEffort(): string {
    if (this.threadReasoningEffort !== '') {
      return this.threadReasoningEffort;
    }
    return this.modelDefaultEffort;
  }

  /** 当前档位在 efforts 中的索引（未命中回退首档） */
  private currentEffortIdx(): number {
    const cur: string = this.currentEffort();
    for (let i = 0; i < this.modelEfforts.length; i++) {
      if (this.modelEfforts[i] === cur) {
        return i;
      }
    }
    return 0;
  }

  /** 思考强度开关可见：固定模型且提供 2 档以上强度 */
  private effortPillVisible(): boolean {
    return this.activeThreadId !== '' && this.modelEfforts.length > 1;
  }

  /** 保存思考强度（原模式为关闭/未设置时显式开启，保证档位生效；其余保持原模式） */
  private async saveReasoningEffort(effort: string): Promise<void> {
    const threadId: string = this.activeThreadId;
    if (threadId === '') {
      return;
    }
    const body: Record<string, Object> = { 'reasoning_effort': effort };
    if (this.threadReasoningMode === '' || this.threadReasoningMode === 'disabled') {
      body['reasoning_mode'] = 'enabled';
      this.threadReasoningMode = 'enabled';
    }
    try {
      await ThreadService.updateThreadSettings(this.agentId, threadId, JSON.stringify(body));
      this.threadReasoningEffort = effort;
    } catch (e) {
      this.getUIContext().getPromptAction().showToast({ message: '思考强度保存失败' });
    }
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
                AgentAvatar({ agentId: agent.agentId, iconUrl: agent.iconUrl, avatarSize: 40 })
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

  /** 上下文用量详情 sheet */
  @Builder
  private contextSheetBuilder() {
    Column({ space: 12 }) {
      Text('上下文用量')
        .fontSize(17)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .width('100%')
        .padding({ top: 18, bottom: 4 })
      if (this.contextUsage !== null) {
        Progress({ value: this.contextPct(), total: 100, type: ProgressType.Linear })
          .width('100%')
          .color(this.contextBarColor())
          .style({ strokeWidth: 8 })
        Row({ space: 12 }) {
          Column({ space: 2 }) {
            Text(`${this.contextUsage.usedTokens}`)
              .fontSize(16)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.text_primary'))
            Text('已用 tokens')
              .fontSize(11)
              .fontColor($r('app.color.text_secondary'))
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)
          Column({ space: 2 }) {
            Text(`${this.contextUsage.maxTokens}`)
              .fontSize(16)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.text_primary'))
            Text('上限 tokens')
              .fontSize(11)
              .fontColor($r('app.color.text_secondary'))
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)
          Column({ space: 2 }) {
            Text(`${this.contextPct()}%`)
              .fontSize(16)
              .fontWeight(FontWeight.Bold)
              .fontColor(this.contextBarColor())
            Text('占用比例')
              .fontSize(11)
              .fontColor($r('app.color.text_secondary'))
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)
        }
        .width('100%')
        Text('上下文接近上限时，早期消息可能被截断。可开启新会话以获得完整上下文空间。')
          .fontSize(12)
          .fontColor($r('app.color.text_tertiary'))
          .width('100%')
          .lineHeight(18)
      }
    }
    .width('100%')
    .padding({ left: 20, right: 20, bottom: 28 })
    .alignItems(HorizontalAlign.Start)
  }

  /** 思考强度滑块面板（当前会话固定模型的 reasoning 档位） */
  @Builder
  private effortSheetBuilder() {
    Column({ space: 14 }) {
      Text('思考强度')
        .fontSize(17)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .width('100%')
        .padding({ top: 18, bottom: 2 })
      Text('控制回复前的思考深度：强度越高回答越细致，耗时与消耗也越多')
        .fontSize(12)
        .fontColor($r('app.color.text_secondary'))
        .width('100%')
        .lineHeight(18)
      Slider({ value: this.effortIdx, min: 0, max: this.modelEfforts.length - 1, step: 1, style: SliderStyle.OutSet })
        .width('100%')
        .blockColor($r('app.color.brand'))
        .selectedColor($r('app.color.brand'))
        .trackColor($r('app.color.bg_input'))
        .showSteps(true)
        .showTips(true, this.effortLabel(this.modelEfforts[this.effortIdx]))
        .onChange((value: number, mode: SliderChangeMode) => {
          const idx: number = Math.round(value);
          this.effortIdx = idx;
          if (mode === SliderChangeMode.End && idx < this.modelEfforts.length) {
            this.saveReasoningEffort(this.modelEfforts[idx]);
          }
        })
      Row() {
        ForEach(this.modelEfforts, (effort: string, idx: number) => {
          Text(this.effortLabel(effort))
            .fontSize(11)
            .fontWeight(idx === this.effortIdx ? FontWeight.Bold : FontWeight.Normal)
            .fontColor(idx === this.effortIdx ? $r('app.color.brand') : $r('app.color.text_tertiary'))
            .layoutWeight(1)
            .textAlign(idx === 0 ? TextAlign.Start :
              (idx === this.modelEfforts.length - 1 ? TextAlign.End : TextAlign.Center))
        }, (effort: string, idx: number) => `${idx}_${effort}`)
      }
      .width('100%')
    }
    .width('100%')
    .padding({ left: 20, right: 20, bottom: 28 })
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
    MenuSheetContent({
      title: '添加附件',
      message: '选择附件类型',
      options: [
        new MenuSheetOption($r('sys.symbol.picture'), '选择图片', '从相册选择图片上传', false),
        new MenuSheetOption($r('sys.symbol.paperclip'), '选择文件', '从文件选择器选文档', false)
      ],
      onSelect: (index: number): void => {
        if (index === 0) {
          this.pickImage();
        } else if (index === 1) {
          this.pickDocument();
        }
      }
    })
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
      },
      onOpenSessions: (): void => {
        this.paletteOpen = false;
        this.navStack.pushPath(new NavPathInfo('sessions', null));
      }
    })
  }

  /** US4 空闲发送按钮投影：空输入置灰态无浮起投影，有内容保持品牌浮起 */
  private idleSendBtnShadow(): ShadowOptions {
    if (this.inputText.trim() === '') {
      return { radius: 0, color: Color.Transparent, offsetX: 0, offsetY: 0 };
    }
    return { radius: 8, color: '#33E85D75', offsetX: 0, offsetY: 2 };
  }

  /** 列表头部占位高度：标题栏为滚动沉浸模式（无 bottomBuilder 固定模式），
   * 静止时把首条压到标题栏玻璃之下（断线胶囊悬浮于标题栏玻璃之上，不额外占行） */
  chatTitleHeight(): number {
    return this.topInset + 60;
  }

  /** 标题区胶囊：专家选择，小尺寸沉浸按钮（材质与标题栏右侧按钮同族，无投影浮起）
   *  挂在 titleBar bottomBuilder（subTitleBuilder 在 HdsNavigation 内部作用域无法渲染，实测仅 bottomBuilder 槽位可用） */
  @Builder
  titleCapsuleBuilder() {
    Row({ space: 10 }) {
      Row({ space: 7 }) {
        AgentAvatar({ agentId: this.agentId, iconUrl: this.currentAgentIconUrl(), avatarSize: 26 })
        Text(this.agentName === '' ? '选择专家' : this.agentName)
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .maxLines(1)
          .constraintSize({ maxWidth: 220 })
        SymbolGlyph($r('sys.symbol.chevron_down'))
          .fontSize(11)
          .fontColor([$r('app.color.text_tertiary')])
      }
      .height(38)
      .padding({ left: 7, right: 12 })
      .borderRadius(19)
      .backgroundColor(UiMaterialKit.glassBg($r('app.color.bg_input')))
      .systemMaterial(UiMaterialKit.button())
      .border({ width: 1, color: $r('app.color.card_stroke') })
      .onClick((): void => {
        this.openAgentSheet();
      })

      Blank()
    }
    .width('100%')
    .padding({ left: 28, right: 28 })
  }

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      HdsNavigation() {
        if (!this.historyReady && this.loadError === '') {
        Column() {
          LoadingProgress()
            .width(36)
            .height(36)
            .color($r('app.color.brand'))
        }
        .height('100%')
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
        .height('100%')
        .width('100%')
        .justifyContent(FlexAlign.Center)
      } else {
          List({ scroller: this.scroller, space: 12 }) {
            // 头部占位项：静止（回顶）时把首条内容压到 FREE 标题栏之下。
            // contentStartOffset 滚动回顶后会失效（真机实测），改用占位项随数据重建保留位置；
            // 滚动时占位随内容上移，历史消息仍从标题栏玻璃后穿过（GRADUAL_BLUR 沉浸设计不变）
            ListItem()
              .height(this.chatTitleHeight())
              .width('100%')
              .hitTestBehavior(HitTestMode.None)
            // AIGC 显式标识：AI 生成内容提示（《人工智能生成合成内容标识办法》）
            ListItem() {
              Text('内容由 AI 生成，请注意甄别')
                .fontSize(10)
                .fontColor($r('app.color.text_tertiary'))
                .opacity(0.5)
                .width('100%')
                .textAlign(TextAlign.Center)
                .hitTestBehavior(HitTestMode.None)
            }
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
            ForEach(this.messages, (msg: ChatMessageModel) => {
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
            }, (msg: ChatMessageModel) => msg.id)
            if (this.hitlPending !== null) {
              ListItem() {
                this.hitlCardBuilder()
              }
            }
          }
          .width('100%')
          .height('100%')
          .padding({ left: 14, right: 14 })
          // 内容末尾与输入卡顶边保持 22vp 对称间隙（= 输入卡底边与悬浮 TabBar 顶边间距）：
          // inputBottomInset 输入卡底边距（US4 键盘期收缩至 10，收起恢复 bottomPad+10）
          // + flowH 输入卡实测高（多行撑高动态跟随） + 22 对称间隙
          .contentEndOffset(this.inputBottomInset() + this.flowH + 22)
          .clip(false)
          .cachedCount(3, true)
          .scrollBar(BarState.Off)
          // US1 手势感知：仅处理手指拖拽（Scroll）与惯性（Fling）帧；
          // 程序化 scrollEdge 为 Idle 态，直接返回过滤自反馈（自动滚动不洗掉 stickBottom）
          .onScroll((scrollOffset: number, scrollState: ScrollState): void => {
            if (scrollState === ScrollState.Idle) {
              return;
            }
            // 方向符号【待实测校准，验收轮允许翻转一次】：scrollOffset 为相对上一帧偏移——
            // 内容上移为正（视口向底部/最新）、内容下移为负（视口向顶部/历史）；
            // 用户向历史方向滚动即视为"离开底部"，暂停自动贴底
            if (scrollOffset < 0) {
              this.stickBottom = false;
            }
          })
          // US1：滑回底端自动恢复贴底跟随（无需点"回到最新"）
          .onReachEnd((): void => {
            this.stickBottom = true;
          })
          // 从底部开始布局：打开会话直接显示最新消息（无延迟滚动闪烁），键盘弹出压缩视口时消息仍锚定底部
          // US1 修复：内容增长（流式生成）时 stackFromEnd 会把视口重新锚定到内容末端，
          // 洗掉用户已滚离底部的历史位（不触发 onScroll/onReachEnd，胶囊与跟随状态脱节）；
          // 用户滚离底部（stickBottom=false）期间关闭末端锚定，回底（点"最新"/滑回底）后自动恢复
          .stackFromEnd(this.stickBottom && this.messages.length > 0)
          .bindSheet($$this.paletteOpen, this.paletteBuilder, {
            detents: [SheetSize.MEDIUM, SheetSize.LARGE],
            systemMaterial: UiMaterialKit.sheet()
          })
      }
      }
      .titleBar({
        avoidLayoutSafeArea: true,
        enableComponentSafeArea: true,
        style: {
            scrollEffectOpts: {
              enableScrollEffect: this.immersiveOn,
              scrollEffectType: ScrollEffectType.IMMERSIVE_GRADIENT_BLUR,
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
          title: {
            mainTitle: ''
          },
          menu: {
            value: [{
              content: {
                label: '搜索',
                icon: $r('sys.symbol.magnifyingglass'),
                isEnabled: true,
                action: (): void => {
                  this.paletteOpen = true;
                }
              }
            }, {
              content: {
                label: '历史',
                icon: $r('sys.symbol.timer'),
                isEnabled: true,
                action: (): void => {
                  this.navStack.pushPath(new NavPathInfo('sessions', null));
                }
              }
            }]
          }
        }
      })
      .titleMode(HdsNavigationTitleMode.MINI)
      .hideBackButton(true)
      .bindToScrollable([this.scroller])
      .bindSheet($$this.agentSheetOpen, this.agentSheetBuilder, {
        detents: [SheetSize.MEDIUM],
        systemMaterial: UiMaterialKit.sheet()
      })
      .width('100%')
      .height('100%')

      // 聊天宠物：Muse 式——顶部正中悬浮（状态栏下沿）、覆盖在标题栏玻璃之上，
      // 正下方挂当前专家名名牌；心情派生自会话状态，心情气泡临时顶替名牌。
      // 显隐开关（我的 → 外观，默认开）。放在根 Stack 里保证响应式——
      // HDS 的 stackBuilder 对组件状态变化不响应（实测），不能用作挂载点
      if (this.petVisible) {
        Column() {
          PetAvatar({
            streaming: this.streaming,
            wsError: this.wsError,
            hitlPending: this.hitlPending !== null
            // 名牌（petName）暂不传：头部标题已是专家名，重复展示；需要时传 petName 即可
          })
        }
        .width('100%')
        .height('100%')
        .alignItems(HorizontalAlign.Center)
        .justifyContent(FlexAlign.Start)
        .padding({ top: this.topInset + 66 })
        .hitTestBehavior(HitTestMode.None)
      }

      // 底部沉浸层：输入区（内容末尾已由 contentEndOffset 停在面板上边，无需渐变过渡）
      Column() {

      // US1 回到最新：用户上滑离开底部且仍在流式时显示于输入卡上方（小巧胶囊），
      // 点击强制回底并恢复自动跟随；贴底（stickBottom=true）或非流式时隐藏
      if (!this.stickBottom && this.streaming) {
        Row() {
          Row({ space: 4 }) {
            SymbolGlyph($r('sys.symbol.arrow_down'))
              .fontSize(12)
              .fontColor([$r('app.color.text_secondary')])
            Text('最新')
              .fontSize(12)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.text_secondary'))
          }
          .height(28)
          .padding({ left: 12, right: 12 })
          .borderRadius(14)
          .backgroundColor(UiMaterialKit.glassBg($r('app.color.fab_glass')))
          .backgroundBlurStyle(BlurStyle.COMPONENT_THICK)
          .border({ width: 1, color: $r('app.color.card_stroke') })
          .shadow({ radius: 8, color: '#1205243F', offsetX: 0, offsetY: 2 })
          .onClick((): void => {
            this.stickBottom = true;
            this.scrollToBottom(true);
          })
        }
        .width('100%')
        .justifyContent(FlexAlign.End)
        // 右侧 76vp 实测校准：避让右上新对话圆钮（36vp，TopEnd offset(-29,-64)，左缘实测 294vp），
        // 胶囊右缘 = 屏宽 365.7 - 76 ≈ 289.7vp，与圆钮左缘留 ~4vp 间隙并排；否则"最"字被圆钮遮挡、
        // 胶囊中心点击区与圆钮包围盒重叠会误触新对话
        .padding({ left: 16, right: 76, top: 2, bottom: 2 })
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
              .backgroundColor('#B3FFFFFF')
              .border({ width: 1, color: $r('app.color.card_stroke') })
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
              .backgroundColor('#B3FFFFFF')
              .border({ width: 1, color: $r('app.color.card_stroke') })
            }, (att: ChatAttachmentModel) => att.workspacePath)
          }
        }
        .scrollable(ScrollDirection.Horizontal)
        .scrollBar(BarState.Off)
        .width('100%')
        .padding({ left: 12, right: 12, top: 2, bottom: 2 })
        .align(Alignment.Start)
      }

      if (this.slashQuery() !== null && this.matchingSlashGroups().length > 0) {
        this.slashPanelBuilder()
      }

      if (this.effortPillVisible()) {
        Row({ space: 5 }) {
          SymbolGlyph($r('sys.symbol.lightbulb'))
            .fontSize(14)
            .fontColor([$r('app.color.brand')])
          Text(this.currentEffort() === '' ?
            '深度思考' : `深度思考·${this.effortLabel(this.currentEffort())}`)
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))
          SymbolGlyph($r('sys.symbol.chevron_down'))
            .fontSize(9)
            .fontColor([$r('app.color.text_tertiary')])
        }
        .height(28)
        .padding({ left: 12, right: 10 })
        .borderRadius(14)
        .backgroundColor(UiMaterialKit.glassBg($r('app.color.bg_input')))
        .systemMaterial(UiMaterialKit.button())
        .border({ width: 1, color: $r('app.color.card_stroke') })
        .margin({ left: 16, bottom: 6 })
        .onClick((): void => {
          this.effortIdx = this.currentEffortIdx();
          this.effortSheetOpen = true;
        })
        .bindSheet($$this.effortSheetOpen, this.effortSheetBuilder, {
          detents: [SheetSize.FIT_CONTENT],
          systemMaterial: UiMaterialKit.sheet()
        })
      }

      Stack({ alignContent: Alignment.TopEnd }) {
        // 流光垫底（z 序修复）：流光为包裹 Stack 第一子节点（内容下方），命中测试自上而下先命中内容，确定性根治流式触摸拦截
        Stack() {
          if (this.streaming) {
            InputFlowBorder({ w: this.flowW, h: this.flowH })
          }
        Column({ space: 4 }) {
        TextArea({
          text: this.inputText,
          placeholder: this.streaming ? '可补充要求，与回复同时生效...' :
            $r('app.string.chat_input_placeholder'),
          controller: this.textAreaController
        })
          .fontSize(15)
          // US4 去 maxLines 截断（截断不滚动是原 Bug 根因）：不限字数，高度 6 行封顶，超出后内容框内滚动，
          // 右侧滑动条溢出出现/不溢出隐藏（barState(BarState.Auto)，SDK 中 TextArea 的滚动条模式属性）。
          // maxHeight 校准（验证轮实测，模拟器 1280x2832/3.5px-per-vp/字体缩放1）：fontSize 15 实际行距 62px=17.7vp（中英文一致），
          // 6 行完整可见 = padding-top 35px + 5x62 + 行墨迹 48px + 底部行距 13px = 406px ≈ 116vp；
          // 原 146 初始值按 22.7vp/行 估算，实测可见 7.7 行偏 高，故按"恰好 6 行完整可见"校准为 116。
          .constraintSize({ minHeight: 46, maxHeight: 116 })
          .barState(BarState.Auto)
          .backgroundColor(Color.Transparent)
          .padding({ left: 16, right: 16, top: 10, bottom: 0 })
          .onChange((value: string): void => {
            this.inputText = value;
          })
          .onFocus((): void => {
            this.inputFocused = true;
          })
          .onBlur((): void => {
            this.inputFocused = false;
          })

        Row({ space: 6 }) {
          Button({ type: ButtonType.Circle, stateEffect: true }) {
            SymbolGlyph($r('sys.symbol.plus'))
              .fontSize(20)
              .fontColor([$r('app.color.icon_secondary')])
          }
          .width(34)
          .height(34)
          .backgroundColor(UiMaterialKit.glassBg($r('app.color.bg_input')))
          .systemMaterial(UiMaterialKit.pill())
          .border({ width: 1, color: $r('app.color.card_stroke') })
          .onClick((): void => {
            this.attachSheetOpen = true;
          })
          .bindSheet($$this.attachSheetOpen, this.attachSheetBuilder, {
            detents: [SheetSize.FIT_CONTENT],
            systemMaterial: UiMaterialKit.sheet()
          })

          Button({ stateEffect: true }) {
            Row({ space: 4 }) {
              Text(this.turnModelLabel === '' ? '自动' : this.turnModelLabel)
                .fontSize(11)
                .fontColor(this.turnModelLabel === '' ?
                  $r('app.color.text_secondary') : $r('app.color.brand'))
                .maxLines(1)
                .constraintSize({ maxWidth: 72 })
              SymbolGlyph($r('sys.symbol.chevron_down'))
                .fontSize(9)
                .fontColor([$r('app.color.text_tertiary')])
            }
          }
          .height(30)
          .padding({ left: 10, right: 8 })
          .borderRadius(15)
          .backgroundColor(UiMaterialKit.glassBg($r('app.color.bg_input')))
          .systemMaterial(UiMaterialKit.pill())
          .border({ width: 1, color: $r('app.color.card_stroke') })
          .onClick((): void => {
            this.modelSheetOpen = true;
          })
          .bindSheet($$this.modelSheetOpen, this.modelSheetBuilder, {
            detents: [SheetSize.MEDIUM, SheetSize.LARGE],
            systemMaterial: UiMaterialKit.sheet()
          })

          Blank()

          if (this.contextUsage !== null) {
            Text(`${this.contextPct()}%`)
              .fontSize(11)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.contextBarColor())
              .height(28)
              .padding({ left: 10, right: 10 })
              .textAlign(TextAlign.Center)
              .constraintSize({ minWidth: 44 })
              .borderRadius(14)
              .backgroundColor(UiMaterialKit.glassBg($r('app.color.bg_input')))
              .systemMaterial(UiMaterialKit.pill())
              .border({ width: 1, color: $r('app.color.card_stroke') })
              .onClick((): void => {
                this.contextSheetOpen = true;
              })
              .bindSheet($$this.contextSheetOpen, this.contextSheetBuilder, {
                detents: [SheetSize.FIT_CONTENT],
                systemMaterial: UiMaterialKit.sheet()
              })
          }

          // 发送/停止合并为单按钮：流式中空输入→停止；有输入→发送追问（steer）；空闲→发送
          if (this.streaming && this.inputText.trim() === '') {
            Button({ type: ButtonType.Circle, stateEffect: true }) {
              SymbolGlyph($r('sys.symbol.stop_circle'))
                .fontSize(24)
                .fontColor([$r('app.color.danger')])
            }
            .width(40)
            .height(40)
            .backgroundColor(UiMaterialKit.glassBg($r('app.color.bg_input')))
            .systemMaterial(UiMaterialKit.pill())
            .border({ width: 1, color: $r('app.color.danger') })
            .onClick((): void => {
              this.cancelTurn();
            })
          } else if (this.streaming) {
            Button({ type: ButtonType.Circle, stateEffect: true }) {
              SymbolGlyph($r('sys.symbol.paperplane_fill'))
                .fontSize(20)
                .fontColor([$r('app.color.text_on_brand')])
            }
            .width(40)
            .height(40)
            .backgroundColor($r('app.color.bg_bubble_user'))
            .border({ width: 1, color: '#26E85D75' })
            .shadow({ radius: 8, color: '#33E85D75', offsetX: 0, offsetY: 2 })
            .onClick((): void => {
              this.sendSteer(this.inputText.trim());
            })
          } else {
            // US4：空闲态空输入发送按钮置灰禁用（enabled(false)+降低前景/背景对比），有内容恢复品牌态
            Button({ type: ButtonType.Circle, stateEffect: true }) {
              SymbolGlyph($r('sys.symbol.paperplane_fill'))
                .fontSize(20)
                .fontColor([this.inputText.trim() === '' ?
                  $r('app.color.text_tertiary') : $r('app.color.text_on_brand')])
            }
            .width(40)
            .height(40)
            .backgroundColor(this.inputText.trim() === '' ?
              $r('app.color.bg_input') : $r('app.color.bg_bubble_user'))
            .border({ width: 1, color: this.inputText.trim() === '' ?
              $r('app.color.card_stroke') : '#26E85D75' })
            .shadow(this.idleSendBtnShadow())
            .enabled(this.inputText.trim() !== '')
            .onClick((): void => {
              this.send();
            })
          }
        }
        .width('100%')
        .padding({ left: 10, right: 10, bottom: 10 })
      }
      .width('100%')
        }
        .width('100%')
        .borderRadius(24)
        .backgroundColor(UiMaterialKit.glassBg($r('app.color.panel_glass')))
        .backgroundBlurStyle(BlurStyle.COMPONENT_REGULAR)
        .systemMaterial(UiMaterialKit.card())
        // US4：输入框聚焦时边框加粗（1vp→2vp），失焦恢复；颜色沿用 card_stroke
        .border({ width: this.inputFocused ? 2 : 1, color: $r('app.color.card_stroke') })
        .shadow({ radius: 12, color: '#1205243F', offsetX: 0, offsetY: 4 })
        .constraintSize({ maxWidth: this.inputMaxWidth })
        .margin({ left: 16, right: 16, top: 6, bottom: this.inputBottomInset() })
        .onAreaChange((_oldArea: Area, newArea: Area) => {
          this.flowW = Number(newArea.width);
          this.flowH = Number(newArea.height);
        })

        if (this.slashQuery() === null) {
          Button({ type: ButtonType.Circle, stateEffect: true }) {
            SymbolGlyph($r('sys.symbol.square_and_pencil'))
              .fontSize(16)
              .fontWeight(FontWeight.Medium)
              .fontColor([$r('app.color.text_primary')])
          }
          .width(36)
          .height(36)
          .backgroundColor($r('app.color.fab_glass'))
          .backgroundBlurStyle(BlurStyle.COMPONENT_THICK)
          .border({ width: 1, color: $r('app.color.card_stroke') })
          .offset({ x: -29, y: -64 })
          .onClick((): void => {
            this.startNewConversation();
          })
        }
      }
      }
      .width('100%')
      .alignItems(HorizontalAlign.Center)

      // 标题区胶囊覆盖层：与 MINI 标题栏右侧搜索/历史按钮垂直居中对齐
      // （菜单按钮中心 ≈ topInset+28，胶囊高 38 → y = topInset+28-19）
      Column() {
        this.titleCapsuleBuilder()
      }
      .width('100%')
      .position({ x: 0, y: this.topInset + 9 })
      .hitTestBehavior(HitTestMode.Transparent)
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.bg_page'))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    .onAreaChange((_oldArea: Area, newArea: Area) => {
      // 斜杠面板高度上限 = 半屏（用户要求），避免大面积遮挡
      this.slashPanelMaxHeight = Math.max(200, Number(newArea.height) / 2);
    })
  }
}
