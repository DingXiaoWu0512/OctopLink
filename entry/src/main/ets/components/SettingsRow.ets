/** 统一设置行：软色图标盒 + 标题/副标题 + 尾部值 + chevron，支持破坏性样式与按压缩放微交互 */
@Component
export struct SettingsRow {
  @Prop icon: Resource = $r('sys.symbol.gearshape');
  @Prop iconColor: ResourceColor = $r('app.color.brand');
  @Prop iconBg: ResourceColor = $r('app.color.brand_light');
  @Prop title: ResourceStr = '';
  @Prop subtitle: ResourceStr = '';
  @Prop trailing: ResourceStr = '';
  @Prop trailingFailed: boolean = false;
  @Prop destructive: boolean = false;
  @Prop showChevron: boolean = true;
  @Prop chevronAngle: number = 0;
  @State pressed: boolean = false;
  onTap: () => void = (): void => {};

  build() {
    Row({ space: 12 }) {
      Column() {
        SymbolGlyph(this.icon)
          .fontSize(18)
          .fontColor([this.destructive ? $r('app.color.danger') : this.iconColor])
      }
      .width(36)
      .height(36)
      .justifyContent(FlexAlign.Center)
      .backgroundColor(this.destructive ? $r('app.color.danger_soft') : this.iconBg)
      .borderRadius(11)

      Column({ space: 3 }) {
        Text(this.title)
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.destructive ? $r('app.color.danger') : $r('app.color.text_primary'))
        if (this.subtitle !== '') {
          Text(this.subtitle)
            .fontSize(12)
            .fontColor($r('app.color.text_tertiary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      if (this.trailing !== '') {
        Text(this.trailing)
          .fontSize(13)
          .fontColor(this.trailingFailed ? $r('app.color.danger') : $r('app.color.text_secondary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .constraintSize({ maxWidth: 150 })
          .textAlign(TextAlign.End)
          .margin({ left: 12 })
      }
      if (this.showChevron) {
        SymbolGlyph($r('sys.symbol.chevron_right'))
          .fontSize(13)
          .fontColor([$r('app.color.icon_secondary')])
          .rotate({ angle: this.chevronAngle })
          .animation({ duration: 200, curve: Curve.EaseInOut })
      }
    }
    .width('100%')
    .padding({ left: 14, right: 14, top: 13, bottom: 13 })
    .scale({ x: this.pressed ? 0.98 : 1, y: this.pressed ? 0.98 : 1 })
    .animation({ duration: 100, curve: Curve.EaseOut })
    .onClick((): void => {
      this.onTap();
    })
    .onTouch((event: TouchEvent): void => {
      if (event.type === TouchType.Down) {
        this.pressed = true;
      } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
        this.pressed = false;
      }
    })
  }
}
