import { JsonHelper } from '../utils/JsonHelper';
import { OctopApiError } from '../net/HttpClient';

export enum ChatRole {
  USER = 'user',
  ASSISTANT = 'assistant'
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

  /** user_turn 帧 attachments 数组项 */
  toFrameItem(): Record<string, Object> {
    const item: Record<string, Object> = {
      'workspace_path': this.workspacePath,
      'filename': this.filename,
      'media_type': this.mediaType
    };
    return item;
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

  markEnded(failed: boolean, errorMessage: string): void {
    this.streaming = false;
    this.failed = failed;
    this.errorMessage = errorMessage;
  }

  /** 解析单条历史消息；tool/system 消息返回 null（MVP 不展示） */
  static fromHistoryRecord(rec: Record<string, Object>): ChatMessageModel | null {
    const role: string = JsonHelper.getString(rec, 'role', '');
    if (role !== 'user' && role !== 'assistant') {
      return null;
    }
    const msg = new ChatMessageModel(role === 'user' ? ChatRole.USER : ChatRole.ASSISTANT, '');
    msg.id = JsonHelper.getString(rec, 'id', '');
    msg.timestampMs = JsonHelper.toMs(rec['timestamp']);
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
          msg.addToolName(JsonHelper.getString(block, 'name', ''));
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

  /** 解析 GET .../history 响应中的 messages 数组 */
  static parseHistory(text: string): Array<ChatMessageModel> {
    const result: Array<ChatMessageModel> = [];
    const rec = JsonHelper.parse(text);
    if (rec === null) {
      return result;
    }
    const messages = JsonHelper.getRecordArray(rec, 'messages');
    for (const msgRec of messages) {
      const msg = ChatMessageModel.fromHistoryRecord(msgRec);
      if (msg !== null) {
        result.push(msg);
      }
    }
    return result;
  }
}
