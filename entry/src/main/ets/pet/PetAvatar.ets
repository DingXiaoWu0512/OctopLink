import { curves } from '@kit.ArkUI';
import { PetMood, PET_AFTERGLOW_HAPPY_MS, PET_AFTERGLOW_ERROR_MS } from './PetMood';

/**
 * 聊天页头部吉祥物（nanoMuse AgentAvatar 模式）：
 * 心情全部由会话状态派生（streaming/hitlPending/wsError），唯一本地记忆是回复结束后的
 * happy/error 余晖（3s/4s）。状态不靠文字表达——靠 nanoMuse 同款动作集：
 * idle 慢呼吸、working 快呼吸+上下浮动、waiting 倾听摆动、happy 弹性 pop、error 快速摇头；
 * 心情图片切换走 260ms 交叉淡入淡出（nanoMuse Crossfade 同款），不跳变。
 * 挂在聊天页上部正中（Muse 式），显隐由 pet.visible 控制（组件外判断）。
 */
@Component
export struct PetAvatar {
  @Prop @Watch('onInputs') streaming: boolean = false;
  @Prop @Watch('onInputs') wsError: string = '';
  @Prop @Watch('onInputs') hitlPending: boolean = false;
  /** 名牌文案（预留：默认不显示，nanoMuse 式纯动作表达） */
  @Prop petName: string = '';
  /** 当前心情（内部派生结果） */
  @State private mood: PetMood = PetMood.Idle;
  /** peek 形象透明度（idle/waiting/happy/error） */
  @State private peekOpacity: number = 1;
  /** type 形象透明度（working） */
  @State private typeOpacity: number = 0;
  /** 待机/工作呼吸缩放（无限往复；working 时更快更明显） */
  @State private breathe: number = 1;
  /** working 时的上下浮动（vp） */
  @State private bob: number = 0;
  /** waiting 时的倾听摆动（角度） */
  @State private tilt: number = 0;
  /** error 时的快速摇头（vp） */
  @State private shake: number = 0;
  /** happy 到来的弹性 pop / 点击彩蛋 */
  @State private pop: number = 1;
  /** 回复正常结束后的 Happy 余晖（3s） */
  @State private afterglowHappy: boolean = false;
  /** 回复出错后的 Error 余晖（4s） */
  @State private afterglowError: boolean = false;
  private prevStreaming: boolean = false;
  private afterglowTimer: number = -1;

  aboutToAppear(): void {
    this.prevStreaming = this.streaming;
    this.recompute();
  }

  aboutToDisappear(): void {
    if (this.afterglowTimer !== -1) {
      clearTimeout(this.afterglowTimer);
      this.afterglowTimer = -1;
    }
  }

  /** 输入变化：检测流式结束的下降沿，落 happy/error 余晖，然后重派生 */
  private onInputs(): void {
    const falling: boolean = this.prevStreaming && !this.streaming;
    this.prevStreaming = this.streaming;
    if (falling) {
      if (this.wsError === '') {
        this.afterglowError = false;
        this.afterglowHappy = true;
        this.scheduleAfterglowClear(PET_AFTERGLOW_HAPPY_MS);
      } else {
        this.afterglowHappy = false;
        this.afterglowError = true;
        this.scheduleAfterglowClear(PET_AFTERGLOW_ERROR_MS);
      }
    }
    this.recompute();
  }

  private scheduleAfterglowClear(durationMs: number): void {
    if (this.afterglowTimer !== -1) {
      clearTimeout(this.afterglowTimer);
    }
    this.afterglowTimer = setTimeout(() => {
      this.afterglowHappy = false;
      this.afterglowError = false;
      this.recompute();
    }, durationMs);
  }

  /** 心情派生：Error > Waiting > Working > 余晖 > Idle */
  private recompute(): void {
    let mood: PetMood;
    if (this.wsError !== '') {
      mood = PetMood.Error;
    } else if (this.hitlPending) {
      mood = PetMood.Waiting;
    } else if (this.streaming) {
      mood = PetMood.Working;
    } else if (this.afterglowError) {
      mood = PetMood.Error;
    } else if (this.afterglowHappy) {
      mood = PetMood.Happy;
    } else {
      mood = PetMood.Idle;
    }
    if (this.mood !== mood) {
      this.mood = mood;
      this.crossfade(mood);
      this.startMoodMotion(mood);
      this.onMoodArrival(mood);
    }
  }

  /** 心情图片 260ms 交叉淡入淡出（nanoMuse Crossfade 同款，避免瞬间跳变） */
  private crossfade(mood: PetMood): void {
    const toType: boolean = mood === PetMood.Working;
    this.getUIContext().animateTo({
      duration: 260,
      curve: Curve.EaseInOut
    }, () => {
      this.typeOpacity = toType ? 1 : 0;
      this.peekOpacity = toType ? 0 : 1;
    });
  }

  /** nanoMuse 同款动作集：每个心情一套循环动作，切心情即换动作 */
  private startMoodMotion(mood: PetMood): void {
    this.breathe = 1;
    this.bob = 0;
    this.tilt = 0;
    const ui = this.getUIContext();
    if (mood === PetMood.Working) {
      // 干活：快呼吸 + 上下浮动脉冲
      ui.animateTo({
        duration: 700,
        curve: Curve.EaseInOut,
        iterations: -1,
        playMode: PlayMode.Alternate
      }, () => {
        this.breathe = 1.045;
        this.bob = -2.5;
      });
    } else if (mood === PetMood.Waiting) {
      // 等待：轻轻左右倾听摆动
      ui.animateTo({
        duration: 1100,
        curve: Curve.EaseInOut,
        iterations: -1,
        playMode: PlayMode.Alternate
      }, () => {
        this.tilt = 4;
      });
    } else {
      // 待机：缓慢到几乎不可见的呼吸
      ui.animateTo({
        duration: 2600,
        curve: Curve.EaseInOut,
        iterations: -1,
        playMode: PlayMode.Alternate
      }, () => {
        this.breathe = 1.018;
      });
    }
  }

  /** 心情到位动画：happy 弹性 pop / error 快速摇头 */
  private onMoodArrival(mood: PetMood): void {
    const ui = this.getUIContext();
    if (mood === PetMood.Happy) {
      this.pop = 1.14;
      ui.animateTo({
        duration: 500,
        curve: curves.springMotion(0.34, 0.6)
      }, () => {
        this.pop = 1;
      });
    } else if (mood === PetMood.Error) {
      // 快速摇头（420ms 关键帧）；SDK 两处 KeyframeAnimateParam 声明不一致，经 AnimateParam 承载后断言
      const shakeParam: AnimateParam = { duration: 420 };
      ui.keyframeAnimateTo(shakeParam as KeyframeAnimateParam, [
        {
          duration: 60,
          curve: Curve.Linear,
          event: (): void => {
            this.shake = -3;
          }
        },
        {
          duration: 80,
          curve: Curve.Linear,
          event: (): void => {
            this.shake = 3;
          }
        },
        {
          duration: 80,
          curve: Curve.Linear,
          event: (): void => {
            this.shake = -1.8;
          }
        },
        {
          duration: 80,
          curve: Curve.Linear,
          event: (): void => {
            this.shake = 1.8;
          }
        },
        {
          duration: 120,
          event: (): void => {
            this.shake = 0;
          }
        }
      ]);
    }
  }

  /** Working 用打字形象，其余用探头形象 */
  private mascotFile(): Resource {
    return this.mood === PetMood.Working ? $rawfile('pet/type.webp') : $rawfile('pet/peek.webp');
  }

  build() {
    Column() {
      // Muse 式圆形底座：白底（深色自适应）+ 描边 + 阴影，吉祥物坐在里面
      Stack({ alignContent: Alignment.Center }) {
        Image($rawfile('pet/peek.webp'))
          .width(58)
          .height(58)
          .objectFit(ImageFit.Contain)
          .draggable(false)
          .opacity(this.peekOpacity)
          .translate({ x: this.shake, y: this.bob })
          .rotate({ angle: this.tilt })
          .scale({
            x: this.breathe * this.pop,
            y: this.breathe * this.pop
          })
        Image($rawfile('pet/type.webp'))
          .width(58)
          .height(58)
          .objectFit(ImageFit.Contain)
          .draggable(false)
          .opacity(this.typeOpacity)
          .translate({ x: this.shake, y: this.bob })
          .rotate({ angle: this.tilt })
          .scale({
            x: this.breathe * this.pop,
            y: this.breathe * this.pop
          })
      }
      .width(62)
      .height(62)
      .borderRadius(31)
      .backgroundColor($r('app.color.pet_circle'))
      .border({ width: 1.5, color: $r('app.color.card_stroke') })
      .shadow({ radius: 10, color: '#1A000000', offsetX: 0, offsetY: 3 })
      .onClick(() => {
        // 彩蛋：点一下弹跳
        this.pop = 1.14;
        this.getUIContext().animateTo({
          duration: 500,
          curve: curves.springMotion(0.34, 0.6)
        }, () => {
          this.pop = 1;
        });
      })
    }
  }
}
