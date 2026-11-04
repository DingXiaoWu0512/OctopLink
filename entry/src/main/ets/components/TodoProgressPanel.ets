import { TodoItemStatus, TodoListItem } from '../utils/ParseWriteTodos';

/**
 * 任务进度面板（write_todos 清单可视化，与桌面 Web"任务进度"同构）：
 * 标题"任务进度" + 摘要"已完成 x/y" + 逐项状态图标与文案（待处理/进行中/已完成/已取消）；
 * completed/cancelled 项内容删除线；中文文案硬编码（与 App 现状一致）；
 * 样式沿用 MessageBubble 既有玻璃卡片语言（圆角、半透明背景、细边框）。
 */
@Component
export struct TodoProgressPanel {
  /** 合并排序后的清单（MessageBubble 内按消息全部 write_todos 调用链式合并产出） */
  @Prop items: Array<TodoListItem> = [];
  /** 流式标记：标题旁小加载点提示实时更新中 */
  @Prop streaming: boolean = false;

  /** 已完成项数（摘要 x；y = items.length） */
  private completedCount(): number {
    let count: number = 0;
    for (const item of this.items) {
      if (item.status === TodoItemStatus.COMPLETED) {
        count++;
      }
    }
    return count;
  }

  /** 项状态中文文案 */
  private statusLabel(status: TodoItemStatus): string {
    if (status === TodoItemStatus.IN_PROGRESS) {
      return '进行中';
    }
    if (status === TodoItemStatus.COMPLETED) {
      return '已完成';
    }
    if (status === TodoItemStatus.CANCELLED) {
      return '已取消';
    }
    return '待处理';
  }

  /** 项状态图标（系统符号；进行中改用小加载圈，见 statusIconNode） */
  private statusIcon(status: TodoItemStatus): Resource {
    if (status === TodoItemStatus.COMPLETED) {
      return $r('sys.symbol.checkmark_circle_fill');
    }
    if (status === TodoItemStatus.CANCELLED) {
      return $r('sys.symbol.xmark_circle_fill');
    }
    return $r('sys.symbol.circle');
  }

  /** 项状态颜色（图标与状态文案共用） */
  private statusColor(status: TodoItemStatus): Resource {
    if (status === TodoItemStatus.IN_PROGRESS) {
      return $r('app.color.brand');
    }
    if (status === TodoItemStatus.COMPLETED) {
      return $r('app.color.success');
    }
    return $r('app.color.text_tertiary');
  }

  /** 项状态图标节点：进行中用小加载圈（活动感），其余用系统符号 */
  @Builder
  private statusIconNode(status: TodoItemStatus) {
    if (status === TodoItemStatus.IN_PROGRESS) {
      LoadingProgress()
        .width(12)
        .height(12)
        .color($r('app.color.brand'))
    } else {
      SymbolGlyph(this.statusIcon(status))
        .fontSize(12)
        .fontColor([this.statusColor(status)])
    }
  }

  build() {
    Column({ space: 8 }) {
      Row({ space: 6 }) {
        SymbolGlyph($r('sys.symbol.list_bullet'))
          .fontSize(13)
          .fontColor([$r('app.color.brand')])
        Text('任务进度')
          .fontSize(12)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
        if (this.streaming) {
          LoadingProgress()
            .width(10)
            .height(10)
            .color($r('app.color.text_tertiary'))
        }
        Blank()
        Text(`已完成 ${this.completedCount()}/${this.items.length}`)
          .fontSize(11)
          .fontColor($r('app.color.text_secondary'))
      }
      .width('100%')

      ForEach(this.items, (item: TodoListItem) => {
        Row({ space: 6 }) {
          this.statusIconNode(item.status)
          Text(item.content)
            .fontSize(12)
            .fontColor(item.status === TodoItemStatus.CANCELLED ?
              $r('app.color.text_tertiary') : $r('app.color.text_secondary'))
            .decoration(item.status === TodoItemStatus.COMPLETED ||
              item.status === TodoItemStatus.CANCELLED ?
              { type: TextDecorationType.LineThrough } : { type: TextDecorationType.None })
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
          Text(this.statusLabel(item.status))
            .fontSize(10)
            .fontColor(this.statusColor(item.status))
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
      }, (item: TodoListItem) => `${item.id}_${item.content}_${item.status}`)
    }
    .width('100%')
    .padding({ left: 10, right: 10, top: 8, bottom: 8 })
    .borderRadius(10)
    .backgroundColor($r('app.color.bg_input'))
    .border({ width: 0.5, color: $r('app.color.card_stroke') })
    .alignItems(HorizontalAlign.Start)
  }
}
