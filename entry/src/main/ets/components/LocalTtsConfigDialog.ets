import { TtsSettingsModel, VoiceOptionModel } from '../model/TtsModels';
import { LocalTtsService } from '../service/LocalTtsService';

/** 本机引擎参数面板：语速/音调/音量滑杆 + 音色单选（动态加载/静态兜底）+ 合成模式，保存回传 clamp 后的完整设置 */
@CustomDialog
export struct LocalTtsConfigDialog {
  controller?: CustomDialogController;
  /** 打开面板时的设置快照（此处只调参数） */
  initial: TtsSettingsModel = TtsSettingsModel.defaults();
  onSaved: (settings: TtsSettingsModel) => void = (): void => {
  };

  @State speed: number = 1.0;
  @State pitch: number = 1.0;
  @State volume: number = 2;
  @State person: number = 13;
  @State online: number = 1;
  @State voices: Array<VoiceOptionModel> = [];
  @State voicesLoading: boolean = true;

  aboutToAppear(): void {
    const s = this.initial;
    this.speed = s.speed;
    this.pitch = s.pitch;
    this.volume = s.volume;
    this.person = s.person;
    this.online = s.online;
    this.loadVoices();
  }

  /** 打开时动态加载音色（listVoices 失败回退静态兜底清单） */
  private async loadVoices(): Promise<void> {
    this.voicesLoading = true;
    const voices: Array<VoiceOptionModel> = await LocalTtsService.listVoices();
    this.voices = voices;
    this.voicesLoading = false;
    // 当前音色不在列表中时回退列表首项，避免选中态悬空
    let found: boolean = false;
    for (const voice of voices) {
      if (voice.person === this.person) {
        found = true;
        break;
      }
    }
    if (!found && voices.length > 0) {
      this.person = voices[0].person;
    }
  }

  /** 保存：构造完整设置（构造器内 clamp），关闭面板并回传 */
  private save(): void {
    const settings: TtsSettingsModel =
      new TtsSettingsModel(this.speed, this.pitch, this.volume, this.person, this.online);
    this.controller?.close();
    this.onSaved(settings);
  }

  @Builder
  fieldLabel(label: string) {
    Text(label)
      .fontSize(12)
      .fontWeight(FontWeight.Medium)
      .fontColor($r('app.color.text_tertiary'))
      .width('100%')
  }

  @Builder
  voicePill(voice: VoiceOptionModel) {
    Row({ space: 5 }) {
      Text(voice.displayName)
        .fontSize(12)
        .fontWeight(this.person === voice.person ? FontWeight.Bold : FontWeight.Normal)
        .fontColor(this.person === voice.person ?
          $r('app.color.brand') : $r('app.color.text_secondary'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .constraintSize({ maxWidth: 150 })
      Text(voice.isInstalled() ? '已安装' : (voice.isUnavailable() ? '不可用' : '可下载'))
        .fontSize(9)
        .fontColor(voice.isInstalled() ?
          $r('app.color.success') : (voice.isUnavailable() ?
          $r('app.color.text_tertiary') : $r('app.color.warning')))
        .padding({ left: 4, right: 4, top: 1, bottom: 1 })
        .borderRadius(4)
        .backgroundColor($r('app.color.bg_input'))
    }
    .padding({ left: 10, right: 10, top: 6, bottom: 6 })
    .borderRadius(14)
    .backgroundColor(this.person === voice.person ?
      $r('app.color.brand_light') : $r('app.color.bg_input'))
    .margin({ right: 8, bottom: 8 })
    .onClick((): void => {
      if (!voice.isUnavailable()) {
        this.person = voice.person;
      }
    })
  }

  @Builder
  modePill(label: string, value: number) {
    Text(label)
      .fontSize(13)
      .fontWeight(this.online === value ? FontWeight.Bold : FontWeight.Normal)
      .fontColor(this.online === value ?
        $r('app.color.brand') : $r('app.color.text_secondary'))
      .padding({ left: 14, right: 14, top: 7, bottom: 7 })
      .borderRadius(16)
      .backgroundColor(this.online === value ?
        $r('app.color.brand_light') : $r('app.color.bg_input'))
      .onClick((): void => {
        this.online = value;
      })
  }

  build() {
    Column({ space: 14 }) {
      Text('本机引擎配置')
        .fontSize(17)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .width('100%')
        .textAlign(TextAlign.Start)

      Text('使用设备端语音引擎合成，离线朗读、无需服务器、不消耗流量。')
        .fontSize(12)
        .fontColor($r('app.color.text_tertiary'))
        .width('100%')
        .lineHeight(17)

      this.fieldLabel('语速（0.5 - 2.0）')
      Column({ space: 6 }) {
        Row() {
          Text('语速')
            .fontSize(13)
            .fontColor($r('app.color.text_secondary'))
          Blank()
          Text(this.speed.toFixed(2))
            .fontSize(13)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.brand'))
        }
        .width('100%')
        Slider({ value: this.speed, min: 0.5, max: 2.0, step: 0.05 })
          .width('100%')
          .blockColor($r('app.color.brand'))
          .selectedColor($r('app.color.brand'))
          .trackColor($r('app.color.bg_input'))
          .onChange((value: number, _mode: SliderChangeMode) => {
            this.speed = value;
          })
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)

      this.fieldLabel('音调（0.5 - 2.0）')
      Column({ space: 6 }) {
        Row() {
          Text('音调')
            .fontSize(13)
            .fontColor($r('app.color.text_secondary'))
          Blank()
          Text(this.pitch.toFixed(2))
            .fontSize(13)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.brand'))
        }
        .width('100%')
        Slider({ value: this.pitch, min: 0.5, max: 2.0, step: 0.05 })
          .width('100%')
          .blockColor($r('app.color.brand'))
          .selectedColor($r('app.color.brand'))
          .trackColor($r('app.color.bg_input'))
          .onChange((value: number, _mode: SliderChangeMode) => {
            this.pitch = value;
          })
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)

      this.fieldLabel('音量（0 - 2）')
      Column({ space: 6 }) {
        Row() {
          Text('音量')
            .fontSize(13)
            .fontColor($r('app.color.text_secondary'))
          Blank()
          Text(this.volume.toFixed(1))
            .fontSize(13)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.brand'))
        }
        .width('100%')
        Slider({ value: this.volume, min: 0, max: 2, step: 0.1 })
          .width('100%')
          .blockColor($r('app.color.brand'))
          .selectedColor($r('app.color.brand'))
          .trackColor($r('app.color.bg_input'))
          .onChange((value: number, _mode: SliderChangeMode) => {
            this.volume = value;
          })
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)

      this.fieldLabel('音色')
      if (this.voicesLoading) {
        Row({ space: 6 }) {
          LoadingProgress()
            .width(14)
            .height(14)
            .color($r('app.color.brand'))
          Text('正在获取可用音色…')
            .fontSize(12)
            .fontColor($r('app.color.text_tertiary'))
        }
        .width('100%')
      } else {
        Flex({ wrap: FlexWrap.Wrap }) {
          ForEach(this.voices, (voice: VoiceOptionModel) => {
            this.voicePill(voice)
          }, (voice: VoiceOptionModel) => `${voice.person}_${voice.displayName}_${voice.status}`)
        }
        .width('100%')
      }

      this.fieldLabel('合成模式')
      Row({ space: 8 }) {
        this.modePill('离线（推荐）', 1)
        this.modePill('在线', 0)
      }
      .width('100%')
      if (this.online === 0) {
        Text('当前引擎版本暂不支持在线模式，合成可能失败，建议使用离线模式。')
          .fontSize(11)
          .fontColor($r('app.color.warning'))
          .width('100%')
          .lineHeight(16)
      }

      if (!LocalTtsService.isEngineAvailable()) {
        Text('未检测到可用的本机语音引擎，参数将保存并在支持的设备上生效。')
          .fontSize(11)
          .fontColor($r('app.color.text_tertiary'))
          .width('100%')
          .lineHeight(16)
      }

      Row({ space: 10 }) {
        Button($r('app.string.common_cancel'))
          .fontSize(14)
          .height(38)
          .layoutWeight(1)
          .borderRadius(19)
          .backgroundColor($r('app.color.bg_input'))
          .fontColor($r('app.color.text_secondary'))
          .onClick((): void => {
            this.controller?.close();
          })
        Button('保存')
          .fontSize(14)
          .height(38)
          .layoutWeight(1)
          .borderRadius(19)
          .linearGradient({
            angle: 140,
            colors: [[$r('app.color.brand_grad_start'), 0], [$r('app.color.brand_grad_end'), 1]]
          })
          .shadow({ radius: 10, color: '#260A59F7', offsetY: 4 })
          .fontColor($r('app.color.text_on_brand'))
          .onClick((): void => {
            this.save();
          })
      }
      .width('100%')
    }
    .padding(20)
    .width('100%')
  }
}
