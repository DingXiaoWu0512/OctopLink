import { JsonHelper } from '../utils/JsonHelper';
import { OctopApiError } from '../net/HttpClient';

export enum ChatRole {
  USER = 'user',
  ASSISTANT = 'assistant'
}

/** 工具调用（流式 tool_call_chunk 累积 / 历史 tool_use 块）：不可变模型，更新时整体替换数组元素 */
export class ToolCallModel {
  readonly id: string;
  readonly name: string;
  readonly argsText: string;
  readonly resultText: string;

  constructor(id: string, name: string, argsText: string, resultText: string) {
    this.id = id;
    this.name = name;
    this.argsText = argsText;
    this.resultText = resultText;
  }
}

/** 消息内媒体附件（WS attachment 帧 / 历史 inbound_attachments） */
export class MsgAttachmentModel {
  readonly kind: string;
  readonly mimeType: string;
  readonly url: string;
  readonly previewUrl: string;
  readonly dataBase64: string;
  readonly filename: string;
  readonly altText: string;

  constructor(kind: string, mimeType: string, url: string, previewUrl: string,
    dataBase64: string, filename: string, altText: string) {
    this.kind = kind;
    this.mimeType = mimeType;
    this.url = url;
    this.previewUrl = previewUrl;
    this.dataBase64 = dataBase64;
    this.filename = filename;
    this.altText = altText;
  }

  /** WS attachment 帧解析：kind/mime_type/data 或 url/preview_url/filename/alt_text */
  static fromFrameRecord(rec: Record<string, Object>): MsgAttachmentModel {
    return new MsgAttachmentModel(
      JsonHelper.getString(rec, 'kind', ''),
      JsonHelper.getString(rec, 'mime_type', ''),
      JsonHelper.getString(rec, 'url', ''),
      JsonHelper.getString(rec, 'preview_url', ''),
      JsonHelper.getString(rec, 'data', ''),
      JsonHelper.getString(rec, 'filename', ''),
      JsonHelper.getString(rec, 'alt_text', '')
    );
  }

  /** 展示地址：url > previewUrl > base64 data URL */
  displayUrl(): string {
    if (this.url !== '') {
      return this.url;
    }
    if (this.previewUrl !== '') {
      return this.previewUrl;
    }
    if (this.dataBase64 !== '') {
      return `data:${this.mimeType};base64,${this.dataBase64}`;
    }
    return '';
  }

  isImage(): boolean {
    return this.kind === 'image' || this.mimeType.startsWith('image/');
  }
}

/** 聊天附件（POST /api/agents/{id}/upload 响应） */
export class ChatAttachmentModel {
  readonly workspacePath: string;
  readonly filename: string;
  readonly mediaType: string;
  readonly accessUrl: string;

  constructor(workspacePath: string, filename: string, mediaType: string, accessUrl: string) {
    this.workspacePath = workspacePath;
    this.filename = filename;
    this.mediaType = mediaType;
    this.accessUrl = accessUrl;
  }

  static fromResponse(text: string): ChatAttachmentModel {
    const rec = JsonHelper.parse(text);
    if (rec === null) {
      throw new OctopApiError('附件上传响应格式错误', 0, 'BAD_RESPONSE');
    }
    let path: string = JsonHelper.getString(rec, 'workspace_path', '');
    if (path === '') {
      path = JsonHelper.getString(rec, 'path', '');
    }
    if (path === '') {
      throw new OctopApiError('附件上传响应缺少路径', 0, 'BAD_RESPONSE');
    }
    return new ChatAttachmentModel(
      path,
      JsonHelper.getString(rec, 'filename', ''),
      JsonHelper.getString(rec, 'media_type', ''),
      JsonHelper.getString(rec, 'access_url', JsonHelper.getString(rec, 'url', ''))
    );
  }

  isImageMedia(): boolean {
    return this.mediaType.startsWith('image/');
  }

  /**
   * 用户消息 content 块（与官方 dashboard buildUserMessageContent 对齐）：
   * 图片 → image 视觉块（后端转 image_url base64），其余 → file 工作区路径提示块。
   * 服务器 UserTurnWsFrame 不识别顶层 attachments 字段，附件必须嵌入 messages content。
   */
  toContentBlock(): Record<string, Object> {
    if (this.isImageMedia() && this.accessUrl !== '') {
      const source: Record<string, Object> = { 'type': 'url', 'url': this.accessUrl };
      if (this.mediaType !== '') {
        source['media_type'] = this.mediaType;
      }
      const block: Record<string, Object> = {
        'type': 'image',
        'source': source,
        'preview_url': this.accessUrl,
        'workspace_path': this.workspacePath
      };
      if (this.filename !== '') {
        block['filename'] = this.filename;
      }
      return block;
    }
    const block: Record<string, Object> = {
      'type': 'file',
      'filename': this.filename !== '' ? this.filename : 'attachment',
      'workspace_path': this.workspacePath
    };
    if (this.mediaType !== '') {
      block['media_type'] = this.mediaType;
    }
    return block;
  }
}

let localIdSeed = 0;

function nextLocalId(): string {
  localIdSeed += 1;
  return `local_${localIdSeed}`;
}

/**
 * 聊天消息模型（V1 @Observed，配合 @ObjectLink 实现流式增量渲染）。
 * 注意：数组字段变更必须整体重新赋值才能被观察到。
 */
@Observed
export class ChatMessageModel {
  id: string;
  role: ChatRole;
  text: string;
  reasoning: string;
  toolNames: Array<string>;
  streaming: boolean;
  failed: boolean;
  errorMessage: string;
  timestampMs: number;
  usageIn: number;
  usageOut: number;
  attachmentNames: Array<string>;
  fresh: boolean;
  toolCalls: Array<ToolCallModel>;
  attachments: Array<MsgAttachmentModel>;
  speakerId: string;
  speakerName: string;
  isSteerQueued: boolean;
  clientPendingId: string;
  /** US3 思考态精修：推理首帧时间戳（onReasoningDelta 首帧记录，供折叠行可选计时"深度思考中… Ns"展示） */
  reasoningStartAt?: number;

  constructor(role: ChatRole, text: string) {
    this.id = nextLocalId();
    this.role = role;
    this.text = text;
    this.reasoning = '';
    this.toolNames = [];
    this.streaming = false;
    this.failed = false;
    this.errorMessage = '';
    this.timestampMs = 0;
    this.usageIn = 0;
    this.usageOut = 0;
    this.attachmentNames = [];
    this.fresh = false;
    this.toolCalls = [];
    this.attachments = [];
    this.speakerId = '';
    this.speakerName = '';
    this.isSteerQueued = false;
    this.clientPendingId = '';
  }

  /** 构造用户消息 */
  static fromUserText(text: string, timestampMs: number): ChatMessageModel {
    const msg = new ChatMessageModel(ChatRole.USER, text);
    msg.timestampMs = timestampMs;
    return msg;
  }

  /** 构造等待流式输出的助手占位消息 */
  static streamingAssistant(): ChatMessageModel {
    const msg = new ChatMessageModel(ChatRole.ASSISTANT, '');
    msg.streaming = true;
    msg.timestampMs = Date.now();
    return msg;
  }

  /** 构造专家欢迎语消息 */
  static assistantWelcome(text: string): ChatMessageModel {
    const msg = new ChatMessageModel(ChatRole.ASSISTANT, text);
    msg.timestampMs = 0;
    return msg;
  }

  appendText(delta: string): void {
    this.text += delta;
  }

  appendReasoning(delta: string): void {
    this.reasoning += delta;
  }

  addToolName(name: string): void {
    if (name !== '' && this.toolNames.indexOf(name) < 0) {
      // @Observed 数组需整体赋值才能触发 UI 更新
      this.toolNames = this.toolNames.concat([name]);
    }
  }

  setUsage(inputTokens: number, outputTokens: number): void {
    this.usageIn = inputTokens;
    this.usageOut = outputTokens;
  }

  addAttachment(att: MsgAttachmentModel): void {
    this.attachments = this.attachments.concat([att]);
  }

  /** 工具调用分片合并：按 id 累积 name/args（不可变替换以触发观察刷新） */
  upsertToolCall(id: string, name: string, argsDelta: string): void {
    let found: boolean = false;
    const next: Array<ToolCallModel> = [];
    for (const call of this.toolCalls) {
      if (call.id === id && id !== '') {
        found = true;
        next.push(new ToolCallModel(call.id, name !== '' ? name : call.name,
          call.argsText + argsDelta, call.resultText));
      } else {
        next.push(call);
      }
    }
    if (!found) {
      next.push(new ToolCallModel(id, name, argsDelta, ''));
      if (name !== '') {
        this.addToolName(name);
      }
    }
    this.toolCalls = next;
  }

  /** 回填工具结果（按调用 id）；id 为空时附加到最后一个无结果的调用 */
  setToolResult(id: string, resultText: string): void {
    const next: Array<ToolCallModel> = [];
    let attached: boolean = false;
    for (const call of this.toolCalls) {
      if (id !== '' && call.id === id) {
        next.push(new ToolCallModel(call.id, call.name, call.argsText,
          call.resultText === '' ? resultText : call.resultText));
        attached = true;
      } else {
        next.push(call);
      }
    }
    if (!attached && id === '') {
      for (let i = next.length - 1; i >= 0; i--) {
        if (next[i].resultText === '') {
          next[i] = new ToolCallModel(next[i].id, next[i].name, next[i].argsText, resultText);
          attached = true;
          break;
        }
      }
    }
    this.toolCalls = next;
  }

  markEnded(failed: boolean, errorMessage: string): void {
    this.streaming = false;
    this.failed = failed;
    this.errorMessage = errorMessage;
  }

  /** 解析单条历史消息；system 消息返回 null（tool 消息由 parseHistory 单独回填） */
  static fromHistoryRecord(rec: Record<string, Object>): ChatMessageModel | null {
    const role: string = JsonHelper.getString(rec, 'role', '');
    if (role !== 'user' && role !== 'assistant' && role !== 'tool') {
      return null;
    }
    const msg = new ChatMessageModel(role === 'user' ? ChatRole.USER : ChatRole.ASSISTANT, '');
    msg.id = JsonHelper.getString(rec, 'id', '');
    msg.timestampMs = JsonHelper.toMs(rec['timestamp']);
    // 团队发言者
    msg.speakerId = JsonHelper.getString(rec, 'agent_id', '');
    // content 可能为纯字符串或内容块数组
    const content = rec['content'];
    if (typeof content === 'string') {
      msg.text = content;
    } else {
      const blocks = JsonHelper.getRecordArray(rec, 'content');
      for (const block of blocks) {
        const type: string = JsonHelper.getString(block, 'type', '');
        if (type === 'text') {
          msg.text += JsonHelper.getString(block, 'text', '');
        } else if (type === 'thinking') {
          msg.reasoning += JsonHelper.getString(block, 'thinking', '');
        } else if (type === 'tool_use') {
          const callId: string = JsonHelper.getString(block, 'id', '');
          const callName: string = JsonHelper.getString(block, 'name', '');
          const inputVal: Object | undefined = block['input'];
          const argsJson: string = inputVal === undefined || inputVal === null ? '' : JSON.stringify(inputVal);
          msg.upsertToolCall(callId, callName, argsJson);
        }
      }
    }
    const usageRec: Record<string, Object> | null = JsonHelper.getRecord(rec, 'usage');
    if (usageRec !== null) {
      msg.usageIn = JsonHelper.getNumber(usageRec, 'input_tokens', 0);
      msg.usageOut = JsonHelper.getNumber(usageRec, 'output_tokens', 0);
    }
    const inboundRecs: Array<Record<string, Object>> = JsonHelper.getRecordArray(rec, 'inbound_attachments');
    for (const inbound of inboundRecs) {
      const name: string = JsonHelper.getString(inbound, 'filename', '');
      if (name !== '') {
        msg.attachmentNames.push(name);
      }
    }
    const status: string = JsonHelper.getString(rec, 'status', '');
    if (status === 'error') {
      msg.failed = true;
      msg.errorMessage = JsonHelper.getString(rec, 'error_code', '回复失败');
    }
    return msg;
  }

  /** 将 role=tool 历史消息中的 tool_result 块回填到之前最后一条助手消息的工具调用上 */
  private static attachToolResults(msgs: Array<ChatMessageModel>, rec: Record<string, Object>): void {
    let target: ChatMessageModel | null = null;
    for (let i = msgs.length - 1; i >= 0; i--) {
      if (msgs[i].role === ChatRole.ASSISTANT) {
        target = msgs[i];
        break;
      }
    }
    if (target === null) {
      return;
    }
    const blocks: Array<Record<string, Object>> = JsonHelper.getRecordArray(rec, 'content');
    for (const block of blocks) {
      const type: string = JsonHelper.getString(block, 'type', '');
      if (type !== 'tool_result') {
        continue;
      }
      const callId: string = JsonHelper.getString(block, 'id', '');
      let output: string = JsonHelper.getString(block, 'output', '');
      if (output === '') {
        const c: Object | undefined = block['content'];
        if (typeof c === 'string') {
          output = c;
        } else {
          const inner: Array<Record<string, Object>> = JsonHelper.getRecordArray(block, 'content');
          for (const b of inner) {
            const t: string = JsonHelper.getString(b, 'text', '');
            output += t !== '' ? t : JsonHelper.getString(b, 'output', '');
          }
        }
      }
      if (output.length > 500) {
        output = `${output.substring(0, 500)}…`;
      }
      target.setToolResult(callId, output);
    }
  }

  /** 解析 GET .../history 响应中的 messages 数组（含 tool 消息结果回填） */
  static parseHistory(text: string): Array<ChatMessageModel> {
    const result: Array<ChatMessageModel> = [];
    const rec = JsonHelper.parse(text);
    if (rec === null) {
      return result;
    }
    const messages = JsonHelper.getRecordArray(rec, 'messages');
    for (const msgRec of messages) {
      const role: string = JsonHelper.getString(msgRec, 'role', '');
      if (role === 'tool') {
        ChatMessageModel.attachToolResults(result, msgRec);
        continue;
      }
      const msg = ChatMessageModel.fromHistoryRecord(msgRec);
      if (msg !== null) {
        result.push(msg);
      }
    }
    return result;
  }
}
