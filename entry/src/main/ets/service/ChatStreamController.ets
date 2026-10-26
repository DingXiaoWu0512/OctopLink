import { OctopWsClient } from '../net/WsClient';
import { SseClient } from '../net/SseClient';
import { HttpClient } from '../net/HttpClient';
import { JsonHelper } from '../utils/JsonHelper';
import { UrlUtil } from '../utils/UrlUtil';
import { Log } from '../utils/Logger';
import { ChatAttachmentModel, MsgAttachmentModel } from '../model/MessageModels';
import { HitlRequestModel } from '../model/HitlModels';

/** 流式回调集合（由聊天页注入） */
export class StreamCallbacks {
  onTextDelta: (delta: string) => void = (delta: string) => {
  };
  onReasoningDelta: (delta: string) => void = (delta: string) => {
  };
  onToolActivity: (name: string) => void = (name: string) => {
  };
  onTurnStarted: (turnId: string) => void = (turnId: string) => {
  };
  onTurnEnded: (failed: boolean) => void = (failed: boolean) => {
  };
  onStreamError: (message: string) => void = (message: string) => {
  };
  onConnectionClosed: (code: number, reason: string) => void = (code: number, reason: string) => {
  };
  /** steer 应答（仅发送方收到）：status queued/rejected/removed */
  onSteerAck: (status: string, reason: string) => void = (status: string, reason: string) => {
  };
  /** drain 后服务端合成的正式用户气泡（meta.steer=true） */
  onUserEcho: (content: string) => void = (content: string) => {
  };
  /** 排队的 steer 被丢弃（取消/过期等） */
  onSteerDiscarded: (reason: string) => void = (reason: string) => {
  };
  /** HITL 审批请求到达（流终止，等待审批恢复） */
  onHitlRequired: (request: HitlRequestModel) => void = (request: HitlRequestModel) => {
  };
  /** HITL 恢复 SSE 流结束（done/error/再次 hitl_required） */
  onResumeStreamEnd: (failed: boolean) => void = (failed: boolean) => {
  };
  /** 团队成员发言者（token 帧 agent_id） */
  onSpeaker: (agentId: string) => void = (agentId: string) => {
  };
  /** 回合 token 用量（usage 帧，字段名双兼容） */
  onUsage: (inputTokens: number, outputTokens: number) => void =
    (inputTokens: number, outputTokens: number) => {
    };
  /** 消息内媒体附件（attachment 帧） */
  onAttachment: (att: MsgAttachmentModel) => void = (att: MsgAttachmentModel) => {
  };
  /** 工具调用流式分片（tool_call_chunk：id/name/args 增量） */
  onToolCall: (id: string, name: string, argsDelta: string) => void =
    (id: string, name: string, argsDelta: string) => {
    };
  /** 工具执行结果文本（tool_result 帧，按到达顺序附加） */
  onToolResult: (output: string) => void = (output: string) => {
  };
  /** 订阅状态应答（active=true 服务端仍在流式输出，弱流恢复判定） */
  onTurnStatus: (active: boolean) => void = (active: boolean) => {
  };
  /** steer 排队成功（steer.queued，服务端分配 pending_id） */
  onSteerQueued: (clientPendingId: string, pendingId: string, turnId: string) => void =
    (clientPendingId: string, pendingId: string, turnId: string) => {
    };
  /** steer 撤回成功（steer.removed） */
  onSteerRemoved: (clientPendingId: string) => void = (clientPendingId: string) => {
  };
  /** steer 排队被拒（steer.rejected；注意拒绝不发 error 帧） */
  onSteerRejected: (clientPendingId: string, reason: string) => void =
    (clientPendingId: string, reason: string) => {
    };
}

/**
 * 单线程流式聊天控制器：
 * - 建立 WS 连接并 subscribe 线程
 * - 解析服务端帧（token、reasoning、turn 系列、error 等）分发给回调
 * - 帧过滤：带 thread_id 且与当前线程不符的帧丢弃
 * - 流终止判定：turn.ended、error、hitl_required（与官方 Dashboard 一致）
 */
export class ChatStreamController {
  private ws: OctopWsClient = new OctopWsClient();
  private agentId: string;
  private threadId: string;
  private activeSse: SseClient | null = null;
  private pendingHitl: HitlRequestModel | null = null;
  readonly callbacks: StreamCallbacks = new StreamCallbacks();

  constructor(agentId: string, threadId: string) {
    this.agentId = agentId;
    this.threadId = threadId;
  }

  get connected(): boolean {
    return this.ws.isConnected();
  }

  async connect(): Promise<void> {
    this.ws.setTextMessageHandler((text: string): void => {
      this.handleFrame(text);
    });
    this.ws.setClosedHandler((code: number, reason: string): void => {
      this.callbacks.onConnectionClosed(code, reason);
    });
    const baseUrl: string = HttpClient.getInstance().getBaseUrl();
    const token: string = HttpClient.getInstance().getToken();
    const url: string =
      `${UrlUtil.httpToWs(baseUrl)}/api/agents/${this.agentId}/chat/ws?token=${encodeURIComponent(token)}`;
    await this.ws.connect(url);
    const subscribe: Record<string, Object> = {
      'type': 'subscribe',
      'thread_id': this.threadId
    };
    await this.ws.send(JSON.stringify(subscribe));
  }

  async sendUserTurn(text: string, attachments?: Array<ChatAttachmentModel>,
    model?: string): Promise<void> {
    const frame: Record<string, Object> = {
      'type': 'user_turn',
      'text': text,
      'thread_id': this.threadId
    };
    if (model !== undefined && model !== '') {
      frame['model'] = model;
    }
    if (attachments !== undefined && attachments.length > 0) {
      const items: Array<Record<string, Object>> = [];
      for (const att of attachments) {
        items.push(att.toFrameItem());
      }
      frame['attachments'] = items;
    }
    await this.ws.send(JSON.stringify(frame));
  }

  /**
   * HITL 审批恢复：POST SSE /api/agents/{id}/chat/hitl/resume。
   * SSE 帧与 WS 帧同构（token/reasoning/tool/turn/done/error/hitl_required），
   * 复用同一套 handleFrame 路由；done/error 时回调 onResumeStreamEnd。
   * editedActionStr 非空时为 edit 决策（edited_action JSON 对象文本）。
   */
  async resumeHitl(decisionType: string, message: string, pendingId: string,
    editedActionStr: string = ''): Promise<void> {
    const baseUrl: string = HttpClient.getInstance().getBaseUrl();
    const token: string = HttpClient.getInstance().getToken();
    const headers: Record<string, string> = {
      'Authorization': `Bearer ${token}`,
      'Accept': 'text/event-stream',
      'Content-Type': 'application/json'
    };
    const decision: Record<string, Object> = { 'type': decisionType };
    if (message !== '') {
      decision['message'] = message;
    }
    if (editedActionStr !== '') {
      const edited: Record<string, Object> | null = JsonHelper.parse(editedActionStr);
      if (edited !== null) {
        decision['edited_action'] = edited;
      }
    }
    const decisions: Array<Record<string, Object>> = [decision];
    const hitlPolicy: Record<string, Object> = { 'mode': 'ask' };
    const body: Record<string, Object> = {
      'thread_id': this.threadId,
      'decisions': decisions,
      'hitl_policy': hitlPolicy
    };
    if (pendingId !== '') {
      body['pending_id'] = pendingId;
    }
    const sse: SseClient = new SseClient();
    this.activeSse = sse;
    let sseEnded: boolean = false;
    const finish = (failed: boolean): void => {
      if (sseEnded) {
        return;
      }
      sseEnded = true;
      this.activeSse = null;
      this.callbacks.onResumeStreamEnd(failed);
    };
    const url: string = `${baseUrl}/api/agents/${this.agentId}/chat/hitl/resume`;
    try {
      await sse.post(url, headers, JSON.stringify(body), (data: string): void => {
        const rec = JsonHelper.parse(data);
        if (rec === null) {
          return;
        }
        const type: string = JsonHelper.getString(rec, 'type', '');
        const frameThread: string = JsonHelper.getString(rec, 'thread_id', '');
        if (frameThread !== '' && frameThread !== this.threadId) {
          return;
        }
        switch (type) {
          case 'hitl_required':
            // 嵌套审批：再次弹卡，流终止
            this.pendingHitl = HitlRequestModel.fromFrameRecord(rec);
            finish(true);
            if (this.pendingHitl !== null) {
              this.callbacks.onHitlRequired(this.pendingHitl);
            }
            break;
          case 'done':
            finish(false);
            break;
          case 'error':
            this.callbacks.onStreamError(JsonHelper.getString(rec, 'message', '审批恢复失败'));
            finish(true);
            break;
          default:
            this.handleFrame(data);
            break;
        }
      });
      // 流正常读完但未收到 done 帧：按成功收尾
      finish(false);
    } catch (e) {
      const err = e as BusinessError;
      Log.error(`HITL resume SSE failed: ${err.code} ${err.message}`);
      this.callbacks.onStreamError('审批恢复连接失败');
      finish(true);
    }
  }

  /** 取消进行中的 HITL 恢复流 */
  abortResume(): void {
    const sse: SseClient | null = this.activeSse;
    if (sse !== null) {
      sse.abort();
      this.activeSse = null;
    }
  }

  /**
   * Steer 追问：turn 进行中追加消息。
   * expectedTurnId 为 turn.started/turn.resumed 返回的 turn_id；
   * clientPendingId 由调用方生成（util.generateRandomUUID），用于关联 ack/discard。
   */
  async sendSteer(text: string, expectedTurnId: string, clientPendingId: string): Promise<void> {
    const frame: Record<string, Object> = {
      'type': 'user_turn',
      'text': text,
      'thread_id': this.threadId,
      'delivery': 'auto',
      'client_pending_id': clientPendingId,
      'expected_turn_id': expectedTurnId
    };
    await this.ws.send(JSON.stringify(frame));
  }

  /** 撤回已排队的 steer（服务端 steer.removed 广播确认） */
  async sendSteerRemove(turnId: string, clientPendingId: string, pendingId: string): Promise<void> {
    const frame: Record<string, Object> = {
      'type': 'steer_remove',
      'thread_id': this.threadId,
      'turn_id': turnId,
      'client_pending_id': clientPendingId,
      'pending_id': pendingId
    };
    await this.ws.send(JSON.stringify(frame));
  }

  async cancelTurn(): Promise<void> {
    const frame: Record<string, Object> = {
      'type': 'cancel',
      'thread_id': this.threadId
    };
    await this.ws.send(JSON.stringify(frame));
  }

  close(): void {
    this.ws.close();
  }

  private handleFrame(text: string): void {
    const rec = JsonHelper.parse(text);
    if (rec === null) {
      return;
    }
    const type: string = JsonHelper.getString(rec, 'type', '');
    // 帧过滤：携带 thread_id 且与当前线程不符时丢弃
    const frameThread: string = JsonHelper.getString(rec, 'thread_id', '');
    if (frameThread !== '' && frameThread !== this.threadId) {
      return;
    }
    switch (type) {
      case 'token': {
        const speaker: string = JsonHelper.getString(rec, 'agent_id', '');
        if (speaker !== '') {
          this.callbacks.onSpeaker(speaker);
        }
        this.callbacks.onTextDelta(JsonHelper.getString(rec, 'content', ''));
        break;
      }
      case 'reasoning':
        this.callbacks.onReasoningDelta(JsonHelper.getString(rec, 'content', ''));
        break;
      case 'tool_call_chunk': {
        // name/args 均为分片累积；display_name 优先做活动提示
        const id: string = JsonHelper.getString(rec, 'id', '');
        const name: string = JsonHelper.getString(rec, 'name', '');
        const argsDelta: string = JsonHelper.getString(rec, 'args', '');
        this.callbacks.onToolCall(id, name, argsDelta);
        const display: string = JsonHelper.getString(rec, 'display_name', name);
        this.callbacks.onToolActivity(display);
        break;
      }
      case 'tool_result': {
        // messages 数组提取文本结果（按到达顺序附加到最近一次调用）
        const msgRecs: Array<Record<string, Object>> = JsonHelper.getRecordArray(rec, 'messages');
        let output: string = '';
        for (const msgRec of msgRecs) {
          const c: Object | undefined = msgRec['content'];
          if (typeof c === 'string') {
            output += c;
          } else {
            const blocks: Array<Record<string, Object>> = JsonHelper.getRecordArray(msgRec, 'content');
            for (const block of blocks) {
              output += JsonHelper.getString(block, 'text', '');
            }
          }
        }
        if (output.length > 500) {
          output = `${output.substring(0, 500)}…`;
        }
        if (output !== '') {
          this.callbacks.onToolResult(output);
        }
        break;
      }
      case 'usage': {
        // token 字段名契约未明示，双兼容解析
        const inputTokens: number = JsonHelper.getNumber(rec, 'input_tokens',
          JsonHelper.getNumber(rec, 'prompt_tokens', 0));
        const outputTokens: number = JsonHelper.getNumber(rec, 'output_tokens',
          JsonHelper.getNumber(rec, 'completion_tokens', 0));
        this.callbacks.onUsage(inputTokens, outputTokens);
        break;
      }
      case 'attachment':
        this.callbacks.onAttachment(MsgAttachmentModel.fromFrameRecord(rec));
        break;
      case 'turn_status':
        this.callbacks.onTurnStatus(JsonHelper.getBool(rec, 'active', false));
        break;
      case 'turn.started':
      case 'turn.resumed':
        this.callbacks.onTurnStarted(JsonHelper.getString(rec, 'turn_id', ''));
        break;
      case 'turn.ended':
        this.callbacks.onTurnEnded(JsonHelper.getBool(rec, 'failed', false));
        break;
      case 'steer.ack':
        this.callbacks.onSteerAck(
          JsonHelper.getString(rec, 'status', ''), JsonHelper.getString(rec, 'reason', ''));
        break;
      case 'steer.queued':
        this.callbacks.onSteerQueued(
          JsonHelper.getString(rec, 'client_pending_id', ''),
          JsonHelper.getString(rec, 'pending_id', ''),
          JsonHelper.getString(rec, 'turn_id', ''));
        break;
      case 'steer.removed':
        this.callbacks.onSteerRemoved(JsonHelper.getString(rec, 'client_pending_id', ''));
        break;
      case 'steer.rejected':
        this.callbacks.onSteerRejected(
          JsonHelper.getString(rec, 'client_pending_id', ''),
          JsonHelper.getString(rec, 'reason', ''));
        break;
      case 'user': {
        // drain 后服务端合成的正式用户气泡（meta.steer=true 时）
        const metaRec: Record<string, Object> | null = JsonHelper.getRecord(rec, 'meta');
        const isSteer: boolean = metaRec !== null && JsonHelper.getBool(metaRec, 'steer', false);
        if (isSteer) {
          let content: string = JsonHelper.getString(rec, 'content', '');
          if (content === '') {
            // content 可能为内容块数组
            const blocks = JsonHelper.getRecordArray(rec, 'content');
            for (const block of blocks) {
              content += JsonHelper.getString(block, 'text', '');
            }
          }
          this.callbacks.onUserEcho(content);
        }
        break;
      }
      case 'steer.discarded':
        this.callbacks.onSteerDiscarded(JsonHelper.getString(rec, 'reason', ''));
        break;
      case 'error': {
        const message: string = JsonHelper.getString(rec, 'message', '');
        this.callbacks.onStreamError(message === '' ? '服务处理出错' : message);
        break;
      }
      case 'hitl_required':
        // 流终止帧：转审批卡等待用户决策后 resume
        this.pendingHitl = HitlRequestModel.fromFrameRecord(rec);
        if (this.pendingHitl !== null) {
          this.callbacks.onHitlRequired(this.pendingHitl);
        }
        break;
      case 'pong':
      case 'done':
      case 'state_update':
      case 'state_snapshot':
      case 'slash_action':
      case 'custom':
        // 心跳应答/harness 结束（turn.ended 为准）等静默处理
        break;
      default:
        // steer.drained/steer.queue_snapshot 等帧 MVP 不处理
        Log.debug(`WS frame ignored: ${type}`);
        break;
    }
  }
}
