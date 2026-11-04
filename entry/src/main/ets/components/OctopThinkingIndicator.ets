/** 思考态动效组件：Octop 形象环绕动画 + 输入卡流式流光边框 */

import { hdsEffect } from '@kit.UIDesignKit';

/** 思考指示器：Octop 形象居中，玫瑰/品牌蓝双弧线反向环绕循环旋转
 *  参照 Cube Agent 实测几何：弧线环绕直径 ≈ 吉祥体尺寸 1.85 倍（弧线贴着吉祥体绕），
 *  弧长约 130°，弧线粗 ≈ 环绕直径 1/22，正圆轨道
 *  弧线实现：整圆 Circle + strokeDashArray 留空
 *  LTPO 低功耗：小区域持续动效按 30Hz 期望帧率驱动，系统自适应降频省电 */
@Component
export struct OctopThinkingIndicator {
  @State private spinAngle: number = 0;
  indSize: number = 44;

  aboutToAppear(): void {
    this.getUIContext().animateTo({
      duration: 1400,
      curve: Curve.Linear,
      iterations: -1,
      playMode: PlayMode.Normal,
      expectedFrameRateRange: { expected: 30, min: 0, max: 120 }
    }, (): void => {
      this.spinAngle = 360;
    });
  }

  /** 弧段 dash 数组：130° 弧 + 230° 空隙（视觉半径 = (indSize - strokeWidth) / 2） */
  private dashArc(): number[] {
    const radius: number = (this.indSize - 2) / 2;
    const circumference: number = 2 * Math.PI * radius;
    const arcLen: number = circumference * 130 / 360;
    return [arcLen, circumference - arcLen];
  }

  build() {
    Stack() {
      Circle({ width: this.indSize, height: this.indSize })
        .fill(Color.Transparent)
        .stroke('#CCE85D75')
        .strokeWidth(2)
        .strokeLineCap(LineCapStyle.Round)
        .strokeDashArray(this.dashArc())
        .rotate({ angle: this.spinAngle })
      Circle({ width: this.indSize, height: this.indSize })
        .fill(Color.Transparent)
        .stroke('#990A59F7')
        .strokeWidth(2)
        .strokeLineCap(LineCapStyle.Round)
        .strokeDashArray(this.dashArc())
        .strokeDashOffset(Math.PI * (this.indSize - 2) / 2)
        .rotate({ angle: -this.spinAngle })
      Image($r('app.media.octop_mascot_type'))
        .width(32)
        .height(16)
        .objectFit(ImageFit.Contain)
        .interpolation(ImageInterpolation.None)
    }
    .width(this.indSize)
    .height(this.indSize)
  }
}

/** 输入卡流式流光边框：官方 hdsEffect 双边边缘流光（DUAL_EDGE_FLOW_LIGHT）
 *  玫瑰 + 品牌蓝两条流光相互追逐、重叠环绕整圈循环流动（参照 Cube 实测约 9s 一圈）。
 *  实现：通用属性 visualEffect 挂载 HdsEffectBuilder 构建的 shader 视效，
 *  动画由系统 shader 驱动（替代此前 setInterval 手动步进 strokeDashOffset 方案），
 *  并按 LTPO 策略设置期望帧率 30Hz 降低功耗。
 *  挂载方式：输入卡 .overlay()（align Center 覆盖宿主），streaming 时随 if 条件
 *  挂载/卸载，autoPlay 自动启停。流光几何 = 挂载组件外接矩形，必须显式传入宿主
 *  onAreaChange 量得的宽高：overlay 内 '100%' 宽度正常但高度不按宿主解析，
 *  实测会拉出约卡片 2 倍高的几何，导致流光下边缘远超卡片底边、光带随周长变宽。
 *  颜色参数采用官方示例的重叠环绕模式（0→1.0 + 0.5→1.5）：两条流光各自越过
 *  起点（1.0≡0、1.5≡0.5）平滑回绕、全程追逐，消除半圈分段（0→0.5 + 0.5→1.0）
 *  每半圈在底/顶中点产生的"颜色中途重置"瞬移。模拟机已验证 shader 生效。 */
@Component
export struct InputFlowBorder {
  /** 宿主量得的宽/高（vp，onAreaChange 传入；overlay 内百分比高度不可靠） */
  w: number = 0;
  h: number = 0;
  /** 单圈流动周期 ms（Cube 实测光带 9-12s 一圈） */
  flowDuration: number = 9000;

  /** 双边流光参数：玫瑰/品牌蓝重叠环绕互相追逐（官方示例模式） */
  private flowParams(): hdsEffect.DualEdgeFlowLightParam {
    const first: hdsEffect.EdgeFlowLightParam = {
      startPos: 0,
      endPos: 1.0,
      color: '#99E85D75'
    };
    const second: hdsEffect.EdgeFlowLightParam = {
      startPos: 0.5,
      endPos: 1.5,
      color: '#990A59F7'
    };
    return { firstEdgeFlowLight: first, secondEdgeFlowLight: second };
  }

  build() {
    Stack() {
      // 占位内容：保证组件有渲染输出（官方示例结构：容器承载视效）
      Rect({ width: '100%', height: '100%', radiusWidth: 24, radiusHeight: 24 })
        .fillOpacity(0)
        .hitTestBehavior(HitTestMode.None)
    }
    .width(this.w)
    .height(this.h)
    .borderRadius(24)
    .clip(true)
    .visualEffect(new hdsEffect.HdsEffectBuilder()
      .shaderEffect({
        effectType: hdsEffect.EffectType.DUAL_EDGE_FLOW_LIGHT,
        animation: {
          duration: this.flowDuration,
          iterations: -1,
          autoPlay: true,
          expectedFrameRateRange: {
            expected: hdsEffect.FrameRateType.FRAME_RATE_30,
            min: hdsEffect.FrameRateType.FRAME_RATE_15,
            max: hdsEffect.FrameRateType.FRAME_RATE_60
          }
        },
        params: this.flowParams()
      })
      .buildEffect())
    .hitTestBehavior(HitTestMode.None)
  }
}
