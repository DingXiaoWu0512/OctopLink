import { ChatMessageModel, ChatRole, ToolCallModel, MsgAttachmentModel } from '../model/MessageModels';
import { MarkdownText } from './MarkdownText';
import { BusyOctop } from './StreamingOrbit';
import { LocalTtsService, LocalTtsCallbacks } from '../service/LocalTtsService';
import { I18nService } from '../service/I18nService';
import { UiMaterialKit } from './UiMaterialKit';
import { TodoProgressPanel } from './TodoProgressPanel';
import {
  TodoListItem,
  isWriteTodosToolName,
  collectTodoItems,
  parsePartialTodoItems,
  mergeTodoItems
} from '../utils/ParseWriteTodos';
import { pasteboard } from '@kit.BasicServicesKit';

/** MessageBubble 专用本机朗读回调：命名类实现（避免 struct 方法内对象字面量），驱动按钮三态与错误 toast */
class BubbleTtsCallbacks implements LocalTtsCallbacks {
  private readonly owner: MessageBubble;

  constructor(owner: MessageBubble) {
    this.owner = owner;
  }

  onStart(): void {
    this.owner.speakingBusy = false;
    this.owner.speaking = true;
  }

  onComplete(): void {
    this.owner.speakingBusy = false;
    this.owner.speaking = false;
  }

  onStop(): void {
    this.owner.speakingBusy = false;
    this.owner.speaking = false;
  }

  onError(message: string): void {
    this.owner.speakingBusy = false;
    this.owner.speaking = false;
    this.owner.getUIContext().getPromptAction().showToast({ message: message === '' ? '朗读失败' : message });
  }
}

/** 单条消息气泡：用户右对齐渐变蓝底，助手左对齐卡片，支持流式增量刷新与思考折叠/消息操作栏 */
@Component
export struct MessageBubble {
  @ObjectLink msg: ChatMessageModel;
  @State reasoningExpanded: boolean = false;
  @State toolCallExpanded: boolean = false;
  @State speaking: boolean = false;
  @State speakingBusy: boolean = false;
  onRetry: () => void = (): void => {
  };
  /** 排队追问撤回（气泡下方"撤回"按钮） */
  onSteerRemove: () => void = (): void => {
  };

  private async copyText(): Promise<void> {
    const text: string = this.msg.text;
    if (text === '') {
      return;
    }
    try {
      const board = pasteboard.getSystemPasteboard();
      const data = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, text);
      await board.setData(data);
      this.getUIContext().getPromptAction().showToast({ message: '已复制' });
    } catch (e) {
    }
  }

  private toggleReasoning(): void {
    this.reasoningExpanded = !this.reasoningExpanded;
  }

  /** 去除 Markdown 标记得到适合朗读的纯文本 */
  private ttsPlainText(): string {
    let text: string = this.msg.text;
    text = text.replace(/```[\s\S]*?```/g, '（代码略）');
    text = text.replace(/`([^`]*)`/g, '$1');
    text = text.replace(/!\[[^\]]*\]\([^)]*\)/g, '');
    text = text.replace(/\[([^\]]*)\]\([^)]*\)/g, '$1');
    text = text.replace(/^#{1,6}\s*/gm, '');
    text = text.replace(/[*_~]{1,3}([^*_~\n]+)[*_~]{1,3}/g, '$1');
    text = text.replace(/^>\s*/gm, '');
    text = text.replace(/^\s*[-*+]\s+/gm, '');
    text = text.replace(/^\s*\d+\.\s+/gm, '');
    text = text.replace(/\|/g, ' ');
    return text.trim();
  }

  /** 朗读/停止朗读：走 CoreSpeechKit 端侧合成（引擎自播），回调驱动按钮三态 */
  private async toggleSpeak(): Promise<void> {
    if (this.speakingBusy) {
      return;
    }
    if (this.speaking) {
      this.speaking = false;
      LocalTtsService.stop();
      return;
    }
    const text: string = this.ttsPlainText();
    if (text === '') {
      return;
    }
    this.speakingBusy = true;
    try {
      await LocalTtsService.speak(text, new BubbleTtsCallbacks(this));
    } catch (e) {
      this.speakingBusy = false;
      this.speaking = false;
      this.getUIContext().getPromptAction().showToast({ message: '本机语音引擎不可用' });
    }
  }

  /** 助手气泡条件最小宽度：流式 0（无操作行不撑宽）；非流式带用量 200 / 无用量 120（三按钮 72+间距+用量 Text 余量+padding 28 核算保底） */
  private bubbleMinWidth(): number {
    if (this.msg.streaming) {
      return 0;
    }
    return this.msg.usageIn > 0 || this.msg.usageOut > 0 ? 200 : 120;
  }

  /** US2：消息内是否含 write_todos 调用（命中即渲染任务进度面板） */
  private hasWriteTodosCall(): boolean {
    for (const call of this.msg.toolCalls) {
      if (isWriteTodosToolName(call.name)) {
        return true;
      }
    }
    return false;
  }

  /** US2：剔除 write_todos 后的通用工具调用序列（其余工具折叠卡渲染不变） */
  private nonTodoToolCalls(): Array<ToolCallModel> {
    const result: Array<ToolCallModel> = [];
    for (const call of this.msg.toolCalls) {
      if (!isWriteTodosToolName(call.name)) {
        result.push(call);
      }
    }
    return result;
  }

  /** US2：单个 write_todos 调用解析——先完整解析（collectTodoItems），为空再截断部分解析兜底
   *  （parsePartialTodoItems，流式 args 不完整时静默跳过、不崩不显示半截） */
  private parseTodoCallItems(call: ToolCallModel): Array<TodoListItem> {
    const full: Array<TodoListItem> = collectTodoItems(call.argsText);
    if (full.length > 0) {
      return full;
    }
    return parsePartialTodoItems(call.argsText);
  }

  /** US2：消息内全部 write_todos 调用按出现顺序链式合并（后写覆盖同 id），输出计划序清单 */
  private todoPanelItems(): Array<TodoListItem> {
    let merged: Array<TodoListItem> = [];
    for (const call of this.msg.toolCalls) {
      if (isWriteTodosToolName(call.name)) {
        merged = mergeTodoItems(merged, this.parseTodoCallItems(call));
      }
    }
    return merged;
  }

  /** US3：流式期折叠行静态思考标签（消除跳动预览）；reasoningStartAt 非空时附秒数计时 */
  private thinkingLabel(): string {
    const startAt: number = this.msg.reasoningStartAt ?? 0;
    if (startAt > 0) {
      const seconds: number = Math.floor((Date.now() - startAt) / 1000);
      return `深度思考中… ${seconds}s`;
    }
    return '深度思考中…';
  }

  @Builder
  reasoningBlock() {
    Column({ space: 8 }) {
      Row({ space: 6 }) {
        SymbolGlyph($r('sys.symbol.lightbulb'))
          .fontSize(13)
          .fontColor([$r('app.color.warning')])
        // US3：流式期标题改静态"深度思考中…（Ns）"消除跳动；结束后恢复"思考过程"
        Text(this.msg.streaming ? this.thinkingLabel() : '思考过程')
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
        // US3：流式期折叠分支不渲染 reasoning 实时预览（静态标签即折叠行全部信息）；
        // streaming=false 恢复现状单行省略预览
        if (!this.reasoningExpanded && !this.msg.streaming) {
          Text(this.msg.reasoning)
            .fontSize(12)
            .fontColor($r('app.color.text_tertiary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
        } else {
          Blank()
        }
        SymbolGlyph($r('sys.symbol.chevron_down'))
          .fontSize(12)
          .fontColor([$r('app.color.text_tertiary')])
          .rotate({ angle: this.reasoningExpanded ? 180 : 0 })
          .animation({ duration: 200, curve: Curve.EaseOut })
      }
      .width('100%')
      .onClick((): void => {
        this.toggleReasoning();
      })

      if (this.reasoningExpanded) {
        // US3：展开态限高 240vp 内部可滚动（长推理不撑爆气泡）
        Scroll() {
          Text(this.msg.reasoning)
            .fontSize(12)
            .fontColor($r('app.color.text_tertiary'))
            .width('100%')
            .padding({ left: 8, right: 8, top: 8, bottom: 8 })
            .borderRadius(8)
            .backgroundColor($r('app.color.bg_card'))
        }
        .width('100%')
        .constraintSize({ maxHeight: 240 })
        .align(Alignment.Top)
      }
    }
    .width('100%')
    .backgroundColor($r('app.color.bg_input'))
    .borderRadius(10)
    .padding({ left: 10, right: 10, top: 8, bottom: 8 })
    .alignItems(HorizontalAlign.Start)
  }

  /** 工具调用折叠卡：名称 + 参数单行摘要，点击展开参数/结果 */
  @Builder
  toolCallBlock(call: ToolCallModel) {
    Column({ space: 5 }) {
      Row({ space: 6 }) {
        SymbolGlyph($r('sys.symbol.wrench_and_screwdriver'))
          .fontSize(12)
          .fontColor([$r('app.color.brand')])
        Text(call.name === '' ? '工具调用' : I18nService.toolLabel(call.name))
          .fontSize(12)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
        if (call.resultText !== '') {
          Text('完成')
            .fontSize(10)
            .fontColor($r('app.color.success'))
            .padding({ left: 6, right: 6, top: 1, bottom: 1 })
            .borderRadius(6)
            .backgroundColor($r('app.color.success_soft'))
        }
        SymbolGlyph($r('sys.symbol.chevron_down'))
          .fontSize(12)
          .fontColor([$r('app.color.text_tertiary')])
          .rotate({ angle: this.toolCallExpanded ? 180 : 0 })
          .animation({ duration: 200, curve: Curve.EaseOut })
      }
      .width('100%')
      .onClick((): void => {
        this.toolCallExpanded = !this.toolCallExpanded;
      })

      if (!this.toolCallExpanded && call.argsText !== '') {
        Text(call.argsText)
          .fontSize(11)
          .fontColor($r('app.color.text_tertiary'))
          .fontFamily('monospace')
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
      }
      if (this.toolCallExpanded) {
        if (call.argsText !== '') {
          Text(call.argsText)
            .fontSize(11)
            .fontColor($r('app.color.text_tertiary'))
            .fontFamily('monospace')
            .width('100%')
            .padding(8)
            .borderRadius(8)
            .backgroundColor($r('app.color.bg_card'))
        }
        if (call.resultText !== '') {
          Text(call.resultText)
            .fontSize(11)
            .fontColor($r('app.color.text_secondary'))
            .width('100%')
            .padding(8)
            .borderRadius(8)
            .backgroundColor($r('app.color.bg_card'))
        }
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding({ left: 10, right: 10, top: 8, bottom: 8 })
    .borderRadius(10)
    .backgroundColor($r('app.color.bg_input'))
    .onClick((): void => {
      this.toolCallExpanded = !this.toolCallExpanded;
    })
  }

  /** 消息内媒体附件（attachment 帧） */
  @Builder
  attachmentBlock(att: MsgAttachmentModel) {
    Column({ space: 4 }) {
      if (att.displayUrl() !== '' && att.isImage()) {
        Image(att.displayUrl())
          .width(160)
          .borderRadius(10)
          .autoResize(true)
          .alt($r('app.media.octop_logo'))
      }
      if (att.filename !== '' || att.altText !== '') {
        Text(att.filename !== '' ? att.filename : att.altText)
          .fontSize(11)
          .fontColor($r('app.color.text_tertiary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .constraintSize({ maxWidth: 180 })
      }
    }
    .alignItems(HorizontalAlign.Start)
    .padding(att.displayUrl() !== '' && att.isImage() ? 4 : { left: 8, right: 8, top: 4, bottom: 4 })
    .backgroundColor($r('app.color.bg_input'))
    .borderRadius(10)
  }

  build() {
    Column() {
      if (this.msg.role === ChatRole.USER) {
        Column({ space: 4 }) {
          Row() {
            Column({ space: 6 }) {
              if (this.msg.text !== '') {
                MarkdownText({ msg: this.msg, fontSize: 16, color: $r('app.color.text_bubble_user') })
              }
              if (this.msg.attachments.length > 0) {
                ForEach(this.msg.attachments, (att: MsgAttachmentModel) => {
                  Text(att.filename !== '' ? att.filename : '附件')
                    .fontSize(12)
                    .fontColor($r('app.color.text_bubble_user'))
                    .maxLines(1)
                    .padding({ left: 2, right: 2, top: 4, bottom: 4 })
                }, (att: MsgAttachmentModel, index: number) => `${index}_${att.filename}`)
              }
              if (this.msg.attachmentNames.length > 0) {
                ForEach(this.msg.attachmentNames, (name: string) => {
                  Row({ space: 5 }) {
                    SymbolGlyph($r('sys.symbol.paperclip'))
                      .fontSize(12)
                      .fontColor([$r('app.color.text_bubble_user')])
                    Text(name)
                      .fontSize(12)
                      .fontColor($r('app.color.text_bubble_user'))
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                      .constraintSize({ maxWidth: 180 })
                  }
                  .padding({ left: 2, right: 2, top: 2, bottom: 2 })
                }, (name: string) => name)
              }
              if (this.msg.text !== '' && !this.msg.streaming) {
                Row({ space: 10 }) {
                  SymbolGlyph($r('sys.symbol.doc_text'))
                    .fontSize(12)
                    .fontColor([$r('app.color.text_bubble_user')])
                    .height(24)
                    .onClick((): void => {
                      this.copyText();
                    })
                }
              }
            }
            .backgroundColor($r('app.color.bg_bubble_user'))
            .borderRadius({ topLeft: 18, topRight: 4, bottomLeft: 18, bottomRight: 18 })
            .padding({ left: 14, right: 14, top: 10, bottom: 10 })
            .constraintSize({ maxWidth: '82%' })
            .alignItems(HorizontalAlign.Start)
            .border({ width: 0.5, color: '#26FFFFFF' })
            .shadow({ radius: 10, color: '#26E85D75', offsetX: 0, offsetY: 3 })
          }
          .width('100%')
          .justifyContent(FlexAlign.End)

          if (this.msg.isSteerQueued) {
            Row() {
              Text('排队中，点击撤回')
                .fontSize(11)
                .fontColor($r('app.color.text_tertiary'))
                .padding({ left: 8, right: 8, top: 3, bottom: 3 })
                .borderRadius(10)
                .backgroundColor($r('app.color.bg_input'))
                .onClick((): void => {
                  this.onSteerRemove();
                })
            }
            .width('100%')
            .justifyContent(FlexAlign.End)
          }
        }
        .width('100%')
        .transition(this.msg.fresh ?
          TransitionEffect.OPACITY
            .combine(TransitionEffect.translate({ x: 12 }))
            .animation({ duration: 300, curve: Curve.EaseOut }) :
          TransitionEffect.IDENTITY)
      } else {
        Column({ space: 6 }) {
          if (this.msg.speakerName !== '') {
            Text(this.msg.speakerName)
              .fontSize(12)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.text_secondary'))
              .maxLines(1)
          }
          // US2：write_todos 面板化——置于 reasoning/text 之前；多次调用链式合并后单个面板呈现
          if (this.hasWriteTodosCall()) {
            TodoProgressPanel({
              items: this.todoPanelItems(),
              streaming: this.msg.streaming
            })
          }
          if (this.msg.reasoning !== '') {
            this.reasoningBlock()
          }
          if (this.nonTodoToolCalls().length > 0) {
            ForEach(this.nonTodoToolCalls(), (call: ToolCallModel) => {
              this.toolCallBlock(call)
            }, (call: ToolCallModel, index: number) => `${index}_${call.id}_${call.name}_${call.resultText !== ''}`)
          }
          if (this.msg.attachments.length > 0) {
            Row({ space: 8 }) {
              ForEach(this.msg.attachments, (att: MsgAttachmentModel) => {
                this.attachmentBlock(att)
              }, (att: MsgAttachmentModel, index: number) => `${index}_${att.filename}_${att.url}`)
            }
            .width('100%')
          }
          if (this.msg.toolNames.length > 0 && this.msg.toolCalls.length === 0) {
            Row({ space: 6 }) {
              Text('已调用')
                .fontSize(11)
                .fontColor($r('app.color.text_secondary'))
              ForEach(this.msg.toolNames, (name: string) => {
                Text(I18nService.toolLabel(name))
                  .fontSize(11)
                  .fontColor($r('app.color.brand'))
                  .backgroundColor($r('app.color.brand_light'))
                  .borderRadius(6)
                  .padding({ left: 8, right: 8, top: 3, bottom: 3 })
                  .maxLines(1)
              }, (name: string) => name)
            }
            .width('100%')
          }
          if (this.msg.text !== '') {
              Column() {
                MarkdownText({ msg: this.msg, fontSize: 16, color: $r('app.color.text_primary') })

                if (!this.msg.streaming) {
                  Row({ space: 6 }) {
                  // 复制
                  Button({ type: ButtonType.Circle, stateEffect: true }) {
                    SymbolGlyph($r('sys.symbol.doc_text'))
                      .fontSize(14)
                      .fontColor([$r('app.color.text_secondary')])
                  }
                  .width(24)
                  .height(24)
                  .backgroundColor(UiMaterialKit.glassBg($r('app.color.bg_input')))
                  .systemMaterial(UiMaterialKit.button())
                  .border({ width: 0.5, color: $r('app.color.card_stroke') })
                  .onClick((): void => {
                    this.copyText();
                  })
                  // 朗读：合成中→加载圈；播放中→玫瑰底停止；空闲→喇叭
                  Button({ type: ButtonType.Circle, stateEffect: true }) {
                    if (this.speakingBusy) {
                      LoadingProgress()
                        .width(14)
                        .height(14)
                    } else if (this.speaking) {
                      SymbolGlyph($r('sys.symbol.stop_circle'))
                        .fontSize(15)
                        .fontColor([$r('app.color.text_on_brand')])
                    } else {
                      SymbolGlyph($r('sys.symbol.speaker'))
                        .fontSize(14)
                        .fontColor([$r('app.color.text_secondary')])
                    }
                  }
                  .width(24)
                  .height(24)
                  .backgroundColor(this.speaking ?
                    $r('app.color.bg_bubble_user') : UiMaterialKit.glassBg($r('app.color.bg_input')))
                  .systemMaterial(UiMaterialKit.button())
                  .border({ width: 0.5, color: this.speaking ? '#59E85D75' : $r('app.color.card_stroke') })
                  .onClick((): void => {
                    this.toggleSpeak();
                  })
                  // 重试
                  Button({ type: ButtonType.Circle, stateEffect: true }) {
                    SymbolGlyph($r('sys.symbol.arrow_clockwise'))
                      .fontSize(14)
                      .fontColor([$r('app.color.text_secondary')])
                  }
                  .width(24)
                  .height(24)
                  .backgroundColor(UiMaterialKit.glassBg($r('app.color.bg_input')))
                  .systemMaterial(UiMaterialKit.button())
                  .border({ width: 0.5, color: $r('app.color.card_stroke') })
                  .onClick((): void => {
                    this.onRetry();
                  })
                  // Token 用量并入操作行：按钮居左、用量靠右，Row 垂直居中实现同行平齐
                  Blank()
                  if (this.msg.usageIn > 0 || this.msg.usageOut > 0) {
                    Text(`↑${this.msg.usageIn}`)
                      .fontSize(10)
                      .fontColor($r('app.color.text_tertiary'))
                    Text(`↓${this.msg.usageOut}`)
                      .fontSize(10)
                      .fontColor($r('app.color.text_tertiary'))
                  }
                }
                .alignSelf(ItemAlign.Stretch)
                .margin({ top: 6 })
              }
              }
              .backgroundColor($r('app.color.bg_card'))
              .borderRadius({ topLeft: 4, topRight: 18, bottomLeft: 18, bottomRight: 18 })
              .padding({ left: 14, right: 14, top: 14, bottom: 7 })
              .constraintSize({ maxWidth: '84%', minWidth: this.bubbleMinWidth() })
              .alignItems(HorizontalAlign.Start)
              .border({ width: 1, color: $r('app.color.card_stroke') })
              .shadow({ radius: 8, color: '#0F05243F', offsetX: 0, offsetY: 2 })
          } else if (this.msg.streaming) {
            Row() {
              BusyOctop()
            }
            .backgroundColor($r('app.color.bg_bubble_assistant'))
            .borderRadius({ topLeft: 18, topRight: 18, bottomLeft: 18, bottomRight: 18 })
            .padding({ left: 14, right: 16, top: 8, bottom: 6 })
          }
          if (this.msg.errorMessage !== '') {
            Row({ space: 6 }) {
              SymbolGlyph($r('sys.symbol.exclamationmark_circle'))
                .fontSize(13)
                .fontColor([$r('app.color.danger')])
              Text(this.msg.errorMessage)
                .fontSize(13)
                .fontColor($r('app.color.danger'))
            }
          }
          if (this.msg.text === '' && this.msg.errorMessage !== '' && !this.msg.streaming) {
            Row({ space: 4 }) {
              SymbolGlyph($r('sys.symbol.arrow_clockwise'))
                .fontSize(13)
                .fontColor([$r('app.color.text_tertiary')])
              Text('重试')
                .fontSize(11)
                .fontColor($r('app.color.text_tertiary'))
            }
            .padding({ left: 8, right: 8, top: 4, bottom: 4 })
            .borderRadius(10)
            .onClick((): void => {
              this.onRetry();
            })
          }
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
      }
    }
    .width('100%')
  }
}
