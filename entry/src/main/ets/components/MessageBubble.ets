import { ChatMessageModel, ChatRole, ToolCallModel, MsgAttachmentModel } from '../model/MessageModels';
import { TimeFormat } from '../utils/TimeFormat';
import { MarkdownText } from './MarkdownText';
import { StreamingOrbit } from './StreamingOrbit';
import { pasteboard } from '@kit.BasicServicesKit';

/** 单条消息气泡：用户右对齐渐变蓝底，助手左对齐卡片，支持流式增量刷新与思考折叠/消息操作栏 */
@Component
export struct MessageBubble {
  @ObjectLink msg: ChatMessageModel;
  @State reasoningExpanded: boolean = false;
  @State toolCallExpanded: boolean = false;
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

  @Builder
  copyButton() {
    Row({ space: 4 }) {
      SymbolGlyph($r('sys.symbol.doc_text'))
        .fontSize(13)
        .fontColor([$r('app.color.text_tertiary')])
      Text('复制')
        .fontSize(11)
        .fontColor($r('app.color.text_tertiary'))
    }
    .padding({ left: 8, right: 8, top: 4, bottom: 4 })
    .borderRadius(10)
    .onClick((): void => {
      this.copyText();
    })
  }

  @Builder
  reasoningBlock() {
    Column({ space: 8 }) {
      Row({ space: 6 }) {
        SymbolGlyph($r('sys.symbol.lightbulb'))
          .fontSize(13)
          .fontColor([$r('app.color.warning')])
        Text(this.msg.streaming ? '思考中' : '思考过程')
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
        if (!this.reasoningExpanded) {
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
        Text(this.msg.reasoning)
          .fontSize(12)
          .fontColor($r('app.color.text_tertiary'))
          .width('100%')
          .padding({ left: 8, right: 8, top: 8, bottom: 8 })
          .borderRadius(8)
          .backgroundColor($r('app.color.bg_card'))
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
        Text(call.name === '' ? '工具调用' : call.name)
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
                MarkdownText({ text: this.msg.text, fontSize: 16, color: $r('app.color.text_bubble_user') })
              }
              if (this.msg.attachments.length > 0) {
                ForEach(this.msg.attachments, (att: MsgAttachmentModel) => {
                  Text(att.filename !== '' ? att.filename : '附件')
                    .fontSize(12)
                    .fontColor($r('app.color.text_bubble_user'))
                    .maxLines(1)
                    .padding({ left: 8, right: 8, top: 4, bottom: 4 })
                    .borderRadius(9)
                    .backgroundColor('#26000000')
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
                  .padding({ left: 8, right: 8, top: 4, bottom: 4 })
                  .borderRadius(9)
                  .backgroundColor('#26000000')
                }, (name: string) => name)
              }
            }
            .linearGradient({
              angle: 140,
              colors: [[$r('app.color.brand_grad_start'), 0], [$r('app.color.brand_grad_end'), 1]]
            })
            .borderRadius({ topLeft: 18, topRight: 18, bottomLeft: 18, bottomRight: 18 })
            .padding({ left: 14, right: 14, top: 10, bottom: 10 })
            .constraintSize({ maxWidth: '82%' })
            .alignItems(HorizontalAlign.Start)
          }
          .width('100%')
          .justifyContent(FlexAlign.End)

          if (this.msg.text !== '') {
            Row() {
              this.copyButton()
            }
            .width('100%')
            .justifyContent(FlexAlign.End)
          }
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
          if (this.msg.reasoning !== '') {
            this.reasoningBlock()
          }
          if (this.msg.toolCalls.length > 0) {
            ForEach(this.msg.toolCalls, (call: ToolCallModel) => {
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
                Text(name)
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
              MarkdownText({ text: this.msg.text, fontSize: 16, color: $r('app.color.text_primary') })
            }
            .backgroundColor($r('app.color.bg_bubble_assistant'))
            .borderRadius({ topLeft: 18, topRight: 18, bottomLeft: 18, bottomRight: 18 })
            .padding(14)
            .constraintSize({ maxWidth: '88%' })
            .alignItems(HorizontalAlign.Start)
          } else if (this.msg.streaming) {
            Row() {
              StreamingOrbit({ orbitSize: 20 })
            }
            .backgroundColor($r('app.color.bg_bubble_assistant'))
            .borderRadius({ topLeft: 18, topRight: 18, bottomLeft: 18, bottomRight: 18 })
            .padding({ left: 16, right: 16, top: 12, bottom: 12 })
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
          if (!this.msg.streaming && (this.msg.text !== '' || this.msg.errorMessage !== '')) {
            Row({ space: 12 }) {
              this.copyButton()
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
          if (this.msg.timestampMs > 0) {
            Row({ space: 8 }) {
              if (!this.msg.streaming && (this.msg.usageIn > 0 || this.msg.usageOut > 0)) {
                Text(`↑${this.msg.usageIn} ↓${this.msg.usageOut}`)
                  .fontSize(11)
                  .fontColor($r('app.color.text_tertiary'))
              }
              Text(TimeFormat.short(this.msg.timestampMs))
                .fontSize(11)
                .fontColor($r('app.color.text_tertiary'))
            }
          }
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
      }
    }
    .width('100%')
  }
}
