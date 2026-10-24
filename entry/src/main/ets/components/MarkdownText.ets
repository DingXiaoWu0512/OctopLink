class MdBlock {
  isCode: boolean;
  content: string;

  constructor(isCode: boolean, content: string) {
    this.isCode = isCode;
    this.content = content;
  }
}

/**
 * 轻量 Markdown 渲染：按 ``` 围栏拆分代码块与普通文本。
 * 加粗/标题等富文本样式在 Phase 2 扩展。
 */
@Component
export struct MarkdownText {
  text: string = '';
  fontSize: number = 16;
  color: ResourceColor = '#182431';

  private splitBlocks(): Array<MdBlock> {
    const blocks: Array<MdBlock> = [];
    const parts: Array<string> = this.text.split('```');
    for (let i = 0; i < parts.length; i++) {
      let content: string = parts[i];
      if (content === '') {
        continue;
      }
      const isCode: boolean = i % 2 === 1;
      if (isCode) {
        // 去掉围栏首行的语言标识
        const nl: number = content.indexOf('\n');
        if (nl >= 0) {
          const firstLine: string = content.substring(0, nl);
          if (firstLine.length <= 16 && firstLine.indexOf(' ') < 0) {
            content = content.substring(nl + 1);
          }
        }
        if (content.endsWith('\n')) {
          content = content.substring(0, content.length - 1);
        }
      } else {
        content = content.trim();
      }
      if (content !== '') {
        blocks.push(new MdBlock(isCode, content));
      }
    }
    return blocks;
  }

  build() {
    Column({ space: 6 }) {
      ForEach(this.splitBlocks(), (block: MdBlock, index: number) => {
        if (block.isCode) {
          Text(block.content)
            .fontFamily('monospace')
            .fontSize(this.fontSize - 2)
            .fontColor(this.color)
            .backgroundColor($r('app.color.bg_page'))
            .borderRadius(8)
            .padding(10)
        } else {
          Text(block.content)
            .fontSize(this.fontSize)
            .fontColor(this.color)
            .lineHeight(this.fontSize * 1.5)
        }
      }, (block: MdBlock, index: number) => `${index}`)
    }
    .alignItems(HorizontalAlign.Start)
  }
}
