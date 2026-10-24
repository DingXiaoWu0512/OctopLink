import { ChatMessageModel, ChatRole } from '../model/MessageModels';
import { TimeFormat } from '../utils/TimeFormat';
import { MarkdownText } from './MarkdownText';
import { StreamingOrbit } from './StreamingOrbit';
import { pasteboard } from '@kit.BasicServicesKit';

/** 单条消息气泡：用户右对齐渐变蓝底，助手左对齐卡片，支持流式增量刷新与思考折叠/消息操作栏 */
@Component
export struct MessageBubble {
  @ObjectLink msg: ChatMessageModel;
  @State reasoningExpanded: boolean = false;
  onRetry: () => void = (): void => {
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

  build() {
    Column() {
      if (this.msg.role === ChatRole.USER) {
        Column({ space: 4 }) {
          Row() {
            Column({ space: 6 }) {
              if (this.msg.text !== '') {
                MarkdownText({ text: this.msg.text, fontSize: 16, color: $r('app.color.text_bubble_user') })
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
        }
        .width('100%')
        .transition(this.msg.fresh ?
          TransitionEffect.OPACITY
            .combine(TransitionEffect.translate({ x: 12 }))
            .animation({ duration: 300, curve: Curve.EaseOut }) :
          TransitionEffect.IDENTITY)
      } else {
        Column({ space: 6 }) {
          if (this.msg.reasoning !== '') {
            this.reasoningBlock()
          }
          if (this.msg.toolNames.length > 0) {
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
