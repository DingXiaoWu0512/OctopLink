import { SettingsRow } from './SettingsRow';

/** 可展开分组卡：头部行 + chevron 旋转 + 内容展开/收起过渡 */
@Component
export struct ExpandableCard {
  @Prop icon: Resource = $r('sys.symbol.gearshape');
  @Prop iconColor: ResourceColor = $r('app.color.brand');
  @Prop iconBg: ResourceColor = $r('app.color.brand_light');
  @Prop title: ResourceStr = '';
  @Prop subtitle: ResourceStr = '';
  @State expanded: boolean = true;
  @BuilderParam content: () => void;

  build() {
    Column() {
      SettingsRow({
        icon: this.icon,
        iconColor: this.iconColor,
        iconBg: this.iconBg,
        title: this.title,
        subtitle: this.subtitle,
        showChevron: true,
        chevronAngle: this.expanded ? 90 : 0,
        onTap: (): void => {
          this.getUIContext().animateTo({ duration: 200, curve: Curve.EaseInOut }, (): void => {
            this.expanded = !this.expanded;
          });
        }
      })
      if (this.expanded) {
        Column() {
          this.content()
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        .transition(TransitionEffect.OPACITY
          .combine(TransitionEffect.move(TransitionEdge.TOP))
          .animation({ duration: 200, curve: Curve.EaseInOut }))
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .borderRadius(16)
    .backgroundColor($r('app.color.bg_card'))
    .border({ width: 1, color: $r('app.color.card_stroke') })
    .shadow({ radius: 10, color: '#0A000000', offsetY: 3 })
  }
}
