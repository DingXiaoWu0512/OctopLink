/**
 * 通用菜单半模态（US1 统一列表选择弹窗）：
 * - MenuSheetOption：纯数据选项（icon / label / subtitle / danger），不含回调
 * - MenuSheetContent：内容组件，样式基准 = MemoryPage 记忆迁移弹窗
 *   （Column space16、padding{20,20,20,30}、标题 17 Medium / 副题 12、
 *    44×44 图标容器 radius14、行 padding14 radius16 bg_card+card_stroke、
 *    danger 态红色警示配色、SymbolGlyph 20、整行可点）
 * 宿主页用法：menuOptions/menuActions 预置 → bindSheet($$this.menuOpen, this.menuSheetBuilder)
 * → MenuSheetContent onSelect 中先关 sheet（menuOpen=false）再执行 menuActions[index]。
 */
export class MenuSheetOption {
  readonly icon: Resource | null;
  readonly label: string;
  readonly subtitle: string;
  readonly danger: boolean;

  constructor(icon: Resource | null, label: string, subtitle: string, danger: boolean) {
    this.icon = icon;
    this.label = label;
    this.subtitle = subtitle;
    this.danger = danger;
  }
}

@Component
export struct MenuSheetContent {
  @Prop title: string = '';
  @Prop message: string = '';
  @Prop options: Array<MenuSheetOption> = [];
  onSelect: (index: number) => void = (_index: number): void => {
  };
  onDismiss: () => void = (): void => {
  };

  build() {
    Column({ space: 16 }) {
      Column({ space: 6 }) {
        Text(this.title)
          .fontSize(17)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .width('100%')
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        if (this.message !== '') {
          Text(this.message)
            .fontSize(12)
            .fontColor($r('app.color.text_tertiary'))
            .width('100%')
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
      }
      .width('100%')

      ForEach(this.options, (option: MenuSheetOption, index: number) => {
        Row({ space: 12 }) {
          Column() {
            if (option.icon !== null) {
              SymbolGlyph(option.icon)
                .fontSize(20)
                .fontColor([option.danger ? $r('app.color.danger') : $r('app.color.brand')])
            }
          }
          .width(44)
          .height(44)
          .borderRadius(14)
          .backgroundColor(option.danger ? $r('app.color.danger_soft') : $r('app.color.brand_light'))
          .justifyContent(FlexAlign.Center)

          Column({ space: 3 }) {
            Text(option.label)
              .fontSize(15)
              .fontWeight(FontWeight.Medium)
              .fontColor(option.danger ? $r('app.color.danger') : $r('app.color.text_primary'))
            if (option.subtitle !== '') {
              Text(option.subtitle)
                .fontSize(12)
                .fontColor($r('app.color.text_tertiary'))
                .maxLines(2)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
            }
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)
        }
        .width('100%')
        .padding(14)
        .borderRadius(16)
        .backgroundColor($r('app.color.bg_card'))
        .border({ width: 1, color: $r('app.color.card_stroke') })
        .onClick((): void => {
          this.onSelect(index);
        })
      }, (option: MenuSheetOption, index: number) => `${index}_${option.label}`)
    }
    .padding({ left: 20, right: 20, top: 20, bottom: 30 })
    .width('100%')
    .onDetach((): void => {
      this.onDismiss();
    })
  }
}
