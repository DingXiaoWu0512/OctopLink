import { VoicePresetModel, VoiceProviderInput, VoiceProviderModel } from '../../model/VoiceModels';
import { TtsSettingsModel, VoiceOptionModel } from '../../model/TtsModels';
import { VoiceService } from '../../service/VoiceService';
import { LocalTtsService } from '../../service/LocalTtsService';
import { AudioIOService } from '../../service/AudioIOService';
import { OctopApiError } from '../../net/HttpClient';
import { JsonHelper } from '../../utils/JsonHelper';
import { Log } from '../../utils/Logger';
import { PageHeader } from '../../components/PageHeader';
import { ErrorRetry } from '../../components/ErrorRetry';
import { UiMaterialKit } from '../../components/UiMaterialKit';
import { LocalTtsConfigDialog } from '../../components/LocalTtsConfigDialog';

/** 语音服务配置弹窗：按 preset kind 动态表单（腾讯 / OpenAI / MiMo），保存后回调刷新 */
@CustomDialog
struct VoiceProviderDialog {
  controller?: CustomDialogController;
  presetId: string = '';
  presetName: string = '';
  presetKind: string = '';
  presetCapability: string = '';
  requiresKey: boolean = false;
  existingId: string = '';
  initialApiKey: string = '';
  initialExtraJson: string = '{}';
  onSaved: () => void = (): void => {
  };

  @State apiKey: string = '';
  @State secretId: string = '';
  @State secretKey: string = '';
  @State realtimeOn: boolean = false;
  @State appId: string = '';
  @State mimoEndpoint: string = 'payg';
  @State mimoVoiceId: string = '冰糖';
  @State saving: boolean = false;
  @State probing: boolean = false;

  private readonly mimoVoices: Array<string> =
    ['冰糖', '茉莉', '苏打', '白桦', 'Mia', 'Chloe', 'Milo', 'Dean'];

  aboutToAppear(): void {
    const extra = JsonHelper.parse(this.initialExtraJson);
    this.secretId = JsonHelper.getString(extra, 'secret_id', '');
    this.secretKey = JsonHelper.getString(extra, 'secret_key', '');
    this.realtimeOn = JsonHelper.getBool(extra, 'realtime_stt', false);
    this.appId = JsonHelper.getString(extra, 'app_id', '');
    this.apiKey = this.initialApiKey;
    this.mimoEndpoint =
      JsonHelper.getString(extra, 'endpoint_type', 'payg') === 'tokenplan' ? 'tokenplan' : 'payg';
    this.mimoVoiceId = JsonHelper.getString(extra, 'voice_id', '冰糖');
  }

  private toast(message: string): void {
    this.getUIContext().getPromptAction().showToast({ message });
  }

  private validate(): boolean {
    if (!this.requiresKey) {
      return true;
    }
    if (this.presetKind === 'tencent') {
      if (this.secretId.trim() === '' || this.secretKey.trim() === '') {
        this.toast('请填写 SecretId 与 SecretKey');
        return false;
      }
      if (this.realtimeOn && this.appId.trim() === '') {
        this.toast('开启实时识别需填写 AppID');
        return false;
      }
      return true;
    }
    if (this.apiKey.trim() === '') {
      this.toast('请填写 API Key');
      return false;
    }
    return true;
  }

  /** 组装保存入参：extra JSON 与 api_key 组合格式与 dashboard 保持一致 */
  private buildInput(): VoiceProviderInput {
    let baseUrl: string = '';
    let apiKey: string = '';
    let extraJson: string = '{}';
    if (this.presetKind === 'tencent') {
      const extra: Record<string, Object> = {
        'secret_id': this.secretId.trim(),
        'secret_key': this.secretKey.trim(),
        'region': 'ap-guangzhou',
        'realtime_stt': this.realtimeOn
      };
      if (this.appId.trim() !== '') {
        extra['app_id'] = this.appId.trim();
      }
      apiKey = this.secretId.trim() !== '' && this.secretKey.trim() !== '' ?
        `${this.secretId.trim()}:${this.secretKey.trim()}` : '';
      extraJson = JSON.stringify(extra);
    } else if (this.presetKind === 'mimo') {
      baseUrl = this.mimoEndpoint === 'tokenplan' ?
        'https://token-plan-cn.xiaomimimo.com/v1' : 'https://api.xiaomimimo.com/v1';
      const extra: Record<string, Object> = { 'endpoint_type': this.mimoEndpoint };
      if (this.presetCapability === 'tts') {
        extra['voice_id'] = this.mimoVoiceId;
      }
      apiKey = this.apiKey.trim();
      extraJson = JSON.stringify(extra);
    } else if (this.presetKind === 'openai') {
      const extra: Record<string, Object> = { 'model': 'whisper-1' };
      apiKey = this.apiKey.trim();
      extraJson = JSON.stringify(extra);
    } else {
      const extra: Record<string, Object> = { 'voice_id': 'zh-CN-XiaoxiaoNeural' };
      extraJson = JSON.stringify(extra);
    }
    return new VoiceProviderInput(this.presetId, this.presetKind, this.presetCapability,
      baseUrl, apiKey, extraJson, '');
  }

  /** 连通性测试：both 能力位依次测 STT 与 TTS，任一失败即提示 */
  private async probe(): Promise<void> {
    if (this.probing || !this.validate()) {
      return;
    }
    this.probing = true;
    try {
      const input = this.buildInput();
      const modes: Array<string> =
        this.presetCapability === 'both' ? ['stt', 'tts'] : [this.presetCapability];
      for (const mode of modes) {
        const result = await VoiceService.testConfiguration(input, mode);
        if (!result.ok) {
          this.toast(result.error === '' ? '测试未通过' : result.error);
          return;
        }
      }
      this.toast('测试通过');
    } catch (e) {
      const message: string = e instanceof OctopApiError ? e.message : '测试失败';
      this.toast(message);
    } finally {
      this.probing = false;
    }
  }

  private async save(): Promise<void> {
    if (this.saving || !this.validate()) {
      return;
    }
    this.saving = true;
    try {
      const input = this.buildInput();
      if (this.existingId !== '') {
        await VoiceService.patchProvider(this.existingId, input);
      } else {
        await VoiceService.createProvider(input);
      }
      this.controller?.close();
      this.onSaved();
    } catch (e) {
      const message: string = e instanceof OctopApiError ? e.message : '保存失败';
      this.toast(message);
    } finally {
      this.saving = false;
    }
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
  hintLabel(text: string) {
    Text(text)
      .fontSize(12)
      .fontColor($r('app.color.text_tertiary'))
      .width('100%')
      .lineHeight(17)
  }

  @Builder
  endpointPill(label: string, value: string) {
    Text(label)
      .fontSize(13)
      .fontWeight(this.mimoEndpoint === value ? FontWeight.Bold : FontWeight.Normal)
      .fontColor(this.mimoEndpoint === value ?
        $r('app.color.brand') : $r('app.color.text_secondary'))
      .padding({ left: 14, right: 14, top: 7, bottom: 7 })
      .borderRadius(16)
      .backgroundColor(this.mimoEndpoint === value ?
        $r('app.color.brand_light') : $r('app.color.bg_input'))
      .onClick((): void => {
        this.mimoEndpoint = value;
      })
  }

  @Builder
  voicePill(name: string) {
    Text(name)
      .fontSize(13)
      .fontWeight(this.mimoVoiceId === name ? FontWeight.Bold : FontWeight.Normal)
      .fontColor(this.mimoVoiceId === name ?
        $r('app.color.brand') : $r('app.color.text_secondary'))
      .padding({ left: 12, right: 12, top: 6, bottom: 6 })
      .borderRadius(14)
      .backgroundColor(this.mimoVoiceId === name ?
        $r('app.color.brand_light') : $r('app.color.bg_input'))
      .margin({ right: 8, bottom: 8 })
      .onClick((): void => {
        this.mimoVoiceId = name;
      })
  }

  build() {
    Column({ space: 14 }) {
      Text(this.existingId === '' ? `配置 ${this.presetName}` : `编辑 ${this.presetName}`)
        .fontSize(17)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .width('100%')
        .textAlign(TextAlign.Start)

      if (this.presetKind === 'tencent') {
        this.hintLabel('使用腾讯云 SecretId / SecretKey，新账号有免费额度。')
        this.fieldLabel('SecretId')
        TextInput({
          text: this.secretId,
          placeholder: 'SecretId'
        })
          .fontSize(15)
          .height(44)
          .backgroundColor($r('app.color.bg_input'))
          .borderRadius(12)
          .onChange((value: string): void => {
            this.secretId = value;
          })

        this.fieldLabel('SecretKey')
        TextInput({
          text: this.secretKey,
          placeholder: 'SecretKey'
        })
          .fontSize(15)
          .height(44)
          .backgroundColor($r('app.color.bg_input'))
          .borderRadius(12)
          .type(InputType.Password)
          .onChange((value: string): void => {
            this.secretKey = value;
          })

        Row() {
          Column({ space: 2 }) {
            Text('实时语音识别')
              .fontSize(15)
              .fontColor($r('app.color.text_primary'))
            Text('边说边识别，需填写 AppID')
              .fontSize(11)
              .fontColor($r('app.color.text_tertiary'))
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start)

          Toggle({ type: ToggleType.Switch, isOn: this.realtimeOn })
            .selectedColor($r('app.color.brand'))
            .onChange((on: boolean): void => {
              this.realtimeOn = on;
            })
        }
        .width('100%')

        this.fieldLabel('AppID')
        TextInput({
          text: this.appId,
          placeholder: '1300000000'
        })
          .fontSize(15)
          .height(44)
          .backgroundColor($r('app.color.bg_input'))
          .borderRadius(12)
          .enabled(this.realtimeOn)
          .onChange((value: string): void => {
            this.appId = value;
          })
      } else if (this.presetKind === 'mimo') {
        this.hintLabel('小米 MiMo 语音服务，支持按量付费或 Token 套餐。')
        this.fieldLabel('接入点')
        Row({ space: 8 }) {
          this.endpointPill('按量付费', 'payg')
          this.endpointPill('Token 套餐', 'tokenplan')
        }
        .width('100%')

        this.fieldLabel('API Key')
        TextInput({
          text: this.apiKey,
          placeholder: 'API Key（sk-... / tp-...）'
        })
          .fontSize(15)
          .height(44)
          .backgroundColor($r('app.color.bg_input'))
          .borderRadius(12)
          .type(InputType.Password)
          .onChange((value: string): void => {
            this.apiKey = value;
          })

        if (this.presetCapability === 'tts') {
          this.fieldLabel('音色')
          Flex({ wrap: FlexWrap.Wrap }) {
            ForEach(this.mimoVoices, (name: string) => {
              this.voicePill(name)
            }, (name: string) => name)
          }
          .width('100%')
        }
      } else if (this.presetKind === 'openai') {
        this.hintLabel('OpenAI Whisper STT 与 OpenAI TTS。')
        this.fieldLabel('API Key')
        TextInput({
          text: this.apiKey,
          placeholder: 'API Key'
        })
          .fontSize(15)
          .height(44)
          .backgroundColor($r('app.color.bg_input'))
          .borderRadius(12)
          .type(InputType.Password)
          .onChange((value: string): void => {
            this.apiKey = value;
          })
      }

      Row({ space: 10 }) {
        Button($r('app.string.common_cancel'))
          .fontSize(14)
          .height(38)
          .layoutWeight(1)
          .borderRadius(19)
          .backgroundColor($r('app.color.bg_input'))
          .fontColor($r('app.color.text_secondary'))
          .enabled(!this.saving && !this.probing)
          .onClick((): void => {
            this.controller?.close();
          })
        Button(this.probing ? '测试中...' : '测试')
          .fontSize(14)
          .height(38)
          .layoutWeight(1)
          .borderRadius(19)
          .backgroundColor($r('app.color.bg_input'))
          .fontColor($r('app.color.brand'))
          .enabled(!this.probing && !this.saving)
          .onClick((): void => {
            this.probe();
          })
        Button(this.saving ? '保存中...' : '保存')
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
          .enabled(!this.saving && !this.probing)
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

/** 语音设置：STT / TTS 预设卡片、激活切换与按类型配置（源 voice.py） */
@Component
export struct VoiceSettingsPage {
  @State loading: boolean = true;
  @State errorMsg: string = '';
  @State refreshing: boolean = false;
  @State presets: Array<VoicePresetModel> = [];
  @State providers: Array<VoiceProviderModel> = [];
  @State activeStt: string = 'browser';
  @State activeTts: string = 'browser';
  /** 本机引擎是否为当前朗读后端（backend='local'） */
  @State localTtsActive: boolean = false;
  @State ttsSettings: TtsSettingsModel = TtsSettingsModel.defaults();
  private dialogController: CustomDialogController | null = null;
  private localDialogController: CustomDialogController | null = null;

  aboutToAppear(): void {
    LocalTtsService.ensureLoaded().then((): void => {
      this.refreshLocalTtsState();
    });
    this.load();
  }

  /** 从 LocalTtsService 缓存刷新本机引擎卡片状态与参数摘要 */
  private refreshLocalTtsState(): void {
    this.ttsSettings = LocalTtsService.getSettings();
    this.localTtsActive = this.ttsSettings.isLocal();
  }

  /** 统一停止两条 TTS 链路朗读（本机引擎 + 服务器播放器），激活动作前调用 */
  private stopAllTts(): void {
    LocalTtsService.stop();
    AudioIOService.stopPlayback();
  }

  /** 以服务器为后端的设置副本（保留本机引擎参数） */
  private serverBackendSettings(): TtsSettingsModel {
    const cur: TtsSettingsModel = LocalTtsService.getSettings();
    return new TtsSettingsModel(TtsSettingsModel.BACKEND_SERVER, cur.speed, cur.pitch,
      cur.volume, cur.person, cur.online);
  }

  /** 「本机引擎」设为当前：停双链路朗读 → backend='local' 持久化 */
  private async activateLocalTts(): Promise<void> {
    await LocalTtsService.ensureLoaded();
    this.stopAllTts();
    const cur: TtsSettingsModel = LocalTtsService.getSettings();
    const next: TtsSettingsModel = new TtsSettingsModel(TtsSettingsModel.BACKEND_LOCAL, cur.speed,
      cur.pitch, cur.volume, cur.person, cur.online);
    await LocalTtsService.setSettings(next);
    this.refreshLocalTtsState();
    this.getUIContext().getPromptAction().showToast({ message: '已切换为本机引擎' });
  }

  /** 「配置」打开本机引擎参数面板并接线保存 */
  private openLocalTtsConfig(): void {
    this.localDialogController = new CustomDialogController({
      builder: LocalTtsConfigDialog({
        initial: LocalTtsService.getSettings(),
        onSaved: (settings: TtsSettingsModel): void => {
          this.saveLocalTtsSettings(settings);
        }
      }),
      autoCancel: true,
      systemMaterial: UiMaterialKit.sheet()
    });
    this.localDialogController.open();
  }

  private async saveLocalTtsSettings(settings: TtsSettingsModel): Promise<void> {
    await LocalTtsService.setSettings(settings);
    this.refreshLocalTtsState();
  }

  /** 音色 ID → 展示名（静态兜底清单内查不到时显示通用名） */
  private localVoiceName(person: number): string {
    for (const voice of VoiceOptionModel.fallbackList()) {
      if (voice.person === person) {
        return voice.displayName;
      }
    }
    return `音色 ${person}`;
  }

  /** 本机引擎卡片参数摘要行 */
  private localTtsSummary(): string {
    const s = this.ttsSettings;
    const voiceName: string = this.localVoiceName(s.person);
    const mode: string = s.online === 1 ? '离线' : '在线';
    return `语速 x${s.speed.toFixed(1)} · 音调 x${s.pitch.toFixed(1)} · 音量 ${s.volume.toFixed(1)} · ${voiceName} · ${mode}`;
  }

  private async load(): Promise<void> {
    this.errorMsg = '';
    try {
      this.presets = await VoiceService.presets();
      this.providers = await VoiceService.providers();
      const active = await VoiceService.active();
      this.activeStt = active.stt;
      this.activeTts = active.tts;
    } catch (e) {
      if (this.presets.length === 0) {
        this.errorMsg = e instanceof OctopApiError ? e.message : '加载失败，请检查网络后重试';
      } else {
        this.getUIContext().getPromptAction().showToast({ message: '刷新失败' });
      }
    } finally {
      this.loading = false;
      this.refreshing = false;
    }
  }

  private sttPresets(): Array<VoicePresetModel> {
    const result: Array<VoicePresetModel> = [];
    for (const preset of this.presets) {
      if (preset.capability === 'stt' || preset.capability === 'both') {
        result.push(preset);
      }
    }
    return result;
  }

  private ttsPresets(): Array<VoicePresetModel> {
    const result: Array<VoicePresetModel> = [];
    for (const preset of this.presets) {
      if (preset.capability === 'tts' || preset.capability === 'both') {
        result.push(preset);
      }
    }
    return result;
  }

  private findConfigured(preset: VoicePresetModel): VoiceProviderModel | null {
    for (const provider of this.providers) {
      if (provider.name === preset.id || provider.name === preset.name) {
        return provider;
      }
    }
    return null;
  }

  private needsSetup(preset: VoicePresetModel): boolean {
    return preset.requiresKey && this.findConfigured(preset) === null && preset.kind !== 'browser';
  }

  private isActive(kind: string, preset: VoicePresetModel): boolean {
    // 本机引擎为当前后端时，服务器 TTS 预设不显示激活态（激活标识在本机引擎卡片上）
    if (kind === 'tts' && this.localTtsActive) {
      return false;
    }
    const current: string = kind === 'stt' ? this.activeStt : this.activeTts;
    return current === preset.id || current === preset.name;
  }

  private async setActiveProvider(kind: string, preset: VoicePresetModel): Promise<void> {
    if (kind === 'tts') {
      // 朗读中切换 TTS：先停双链路朗读
      this.stopAllTts();
    }
    try {
      const active = kind === 'stt' ?
        await VoiceService.putActive(preset.id, null) :
        await VoiceService.putActive(null, preset.id);
      this.activeStt = active.stt;
      this.activeTts = active.tts;
      if (kind === 'tts') {
        // 服务器 TTS 预设设为当前：后端切回 server（本机引擎卡片取消激活态）
        await LocalTtsService.setSettings(this.serverBackendSettings());
        this.refreshLocalTtsState();
      }
      this.getUIContext().getPromptAction().showToast({ message: '已切换' });
    } catch (e) {
      const message: string = e instanceof OctopApiError ? e.message : '切换失败';
      this.getUIContext().getPromptAction().showToast({ message });
    }
  }

  private openConfigure(preset: VoicePresetModel): void {
    const existing = this.findConfigured(preset);
    this.dialogController = new CustomDialogController({
      builder: VoiceProviderDialog({
        presetId: preset.id,
        presetName: preset.name,
        presetKind: preset.kind,
        presetCapability: preset.capability,
        requiresKey: preset.requiresKey,
        existingId: existing === null ? '' : existing.id,
        initialApiKey: existing === null ? '' : existing.apiKey,
        initialExtraJson: existing === null ? '{}' : existing.extraJson,
        onSaved: (): void => {
          this.afterConfigureSaved(preset);
        }
      }),
      autoCancel: true,
      systemMaterial: UiMaterialKit.sheet()
    });
    this.dialogController.open();
  }

  /** 保存成功后刷新；当前生效仍为 browser 时自动启用刚配置的服务（与 dashboard 一致） */
  private async afterConfigureSaved(preset: VoicePresetModel): Promise<void> {
    await this.load();
    if (preset.kind === 'browser') {
      return;
    }
    try {
      if ((preset.capability === 'stt' || preset.capability === 'both') &&
        this.activeStt === 'browser') {
        const active = await VoiceService.putActive(preset.id, null);
        this.activeStt = active.stt;
        this.activeTts = active.tts;
      }
      // 本机引擎为当前后端时不抢后端（本机引擎激活时服务器侧自动启用跳过）
      if ((preset.capability === 'tts' || preset.capability === 'both') &&
        this.activeTts === 'browser' && !this.localTtsActive) {
        this.stopAllTts();
        const active = await VoiceService.putActive(null, preset.id);
        this.activeStt = active.stt;
        this.activeTts = active.tts;
        await LocalTtsService.setSettings(this.serverBackendSettings());
        this.refreshLocalTtsState();
      }
    } catch (e) {
      Log.debug('auto activate voice provider failed');
    }
  }

  @Builder
  private sectionTitle(title: string) {
    Text(title)
      .fontSize(13)
      .fontWeight(FontWeight.Medium)
      .fontColor($r('app.color.text_tertiary'))
      .width('100%')
  }

  /** 本机引擎卡片：与服务器 TTS 预设并列的后端选项（CoreSpeechKit 端侧合成） */
  @Builder
  private localTtsCard() {
    Column({ space: 10 }) {
      Row({ space: 10 }) {
        Column() {
          SymbolGlyph($r('sys.symbol.speaker'))
            .fontSize(16)
            .fontColor([$r('app.color.brand')])
        }
        .width(38)
        .height(38)
        .borderRadius(12)
        .justifyContent(FlexAlign.Center)
        .backgroundColor($r('app.color.brand_light'))

        Column({ space: 2 }) {
          Text('本机引擎（设备端合成）')
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Text('离线朗读·无需服务器·零流量')
            .fontSize(11)
            .fontColor($r('app.color.text_tertiary'))
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')

      Text(this.localTtsSummary())
        .fontSize(12)
        .fontColor($r('app.color.text_secondary'))
        .width('100%')
        .lineHeight(17)

      Row({ space: 8 }) {
        Text('设备端')
          .fontSize(10)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.success'))
          .backgroundColor($r('app.color.success_soft'))
          .borderRadius(5)
          .padding({ left: 6, right: 6, top: 2, bottom: 2 })
        Blank()
        Button(this.localTtsActive ? '使用中' : '设为当前')
          .fontSize(12)
          .height(30)
          .borderRadius(15)
          .padding({ left: 16, right: 16 })
          .backgroundColor(this.localTtsActive ?
            $r('app.color.bg_input') : $r('app.color.brand_light'))
          .fontColor(this.localTtsActive ?
            $r('app.color.text_tertiary') : $r('app.color.brand'))
          .enabled(!this.localTtsActive)
          .onClick((): void => {
            this.activateLocalTts();
          })
        Button('配置')
          .fontSize(12)
          .height(30)
          .borderRadius(15)
          .padding({ left: 16, right: 16 })
          .backgroundColor($r('app.color.bg_input'))
          .fontColor($r('app.color.text_secondary'))
          .onClick((): void => {
            this.openLocalTtsConfig();
          })
      }
      .width('100%')
    }
    .width('100%')
    .padding(14)
    .borderRadius(16)
    .backgroundColor($r('app.color.bg_card'))
    .border({ width: 1, color: $r('app.color.divider') })
  }

  @Builder
  private presetCard(preset: VoicePresetModel, kind: string) {
    Column({ space: 10 }) {
      Row({ space: 10 }) {
        Column() {
          Text(preset.name.substring(0, 1))
            .fontSize(16)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.brand'))
        }
        .width(38)
        .height(38)
        .borderRadius(12)
        .justifyContent(FlexAlign.Center)
        .backgroundColor($r('app.color.brand_light'))

        Column({ space: 2 }) {
          Text(preset.name)
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(preset.kind)
            .fontSize(11)
            .fontColor($r('app.color.text_tertiary'))
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')

      Text(preset.description)
        .fontSize(12)
        .fontColor($r('app.color.text_secondary'))
        .width('100%')
        .lineHeight(17)

      Row({ space: 8 }) {
        if (preset.free) {
          Text('免费')
            .fontSize(10)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.success'))
            .backgroundColor($r('app.color.success_soft'))
            .borderRadius(5)
            .padding({ left: 6, right: 6, top: 2, bottom: 2 })
        }
        if (preset.limitedFree) {
          Text('限时免费')
            .fontSize(10)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.success'))
            .backgroundColor($r('app.color.success_soft'))
            .borderRadius(5)
            .padding({ left: 6, right: 6, top: 2, bottom: 2 })
        }
        Blank()
        if (this.needsSetup(preset)) {
          Button('配置')
            .fontSize(12)
            .height(30)
            .borderRadius(15)
            .padding({ left: 16, right: 16 })
            .linearGradient({
              angle: 140,
              colors: [[$r('app.color.brand_grad_start'), 0], [$r('app.color.brand_grad_end'), 1]]
            })
            .fontColor($r('app.color.text_on_brand'))
            .onClick((): void => {
              this.openConfigure(preset);
            })
        } else {
          Button(this.isActive(kind, preset) ? '使用中' : '设为当前')
            .fontSize(12)
            .height(30)
            .borderRadius(15)
            .padding({ left: 16, right: 16 })
            .backgroundColor(this.isActive(kind, preset) ?
              $r('app.color.bg_input') : $r('app.color.brand_light'))
            .fontColor(this.isActive(kind, preset) ?
              $r('app.color.text_tertiary') : $r('app.color.brand'))
            .enabled(!this.isActive(kind, preset))
            .onClick((): void => {
              this.setActiveProvider(kind, preset);
            })
          if (preset.requiresKey && this.findConfigured(preset) !== null) {
            Button('编辑')
              .fontSize(12)
              .height(30)
              .borderRadius(15)
              .padding({ left: 16, right: 16 })
              .backgroundColor($r('app.color.bg_input'))
              .fontColor($r('app.color.text_secondary'))
              .onClick((): void => {
                this.openConfigure(preset);
              })
          }
        }
      }
      .width('100%')
    }
    .width('100%')
    .padding(14)
    .borderRadius(16)
    .backgroundColor($r('app.color.bg_card'))
    .border({ width: 1, color: $r('app.color.divider') })
  }

  build() {
    NavDestination() {
      Column() {
        PageHeader({ title: '语音设置' })

        if (this.loading) {
          Column() {
            LoadingProgress()
              .width(36)
              .height(36)
              .color($r('app.color.brand'))
          }
          .layoutWeight(1)
          .width('100%')
          .justifyContent(FlexAlign.Center)
        } else if (this.errorMsg !== '') {
          Column() {
            ErrorRetry({
              message: this.errorMsg,
              onRetry: (): void => {
                this.loading = true;
                this.load();
              }
            })
          }
          .layoutWeight(1)
          .width('100%')
          .justifyContent(FlexAlign.Center)
        } else {
          Refresh({ refreshing: $$this.refreshing }) {
            Scroll() {
              Column({ space: 10 }) {
                Text('配置语音识别（STT）与语音合成（TTS）服务，用于语音输入与消息朗读。')
                  .fontSize(12)
                  .fontColor($r('app.color.text_tertiary'))
                  .width('100%')
                  .lineHeight(17)

                this.sectionTitle('语音识别（STT）')
                ForEach(this.sttPresets(), (preset: VoicePresetModel) => {
                  this.presetCard(preset, 'stt')
                }, (preset: VoicePresetModel) =>
                `stt_${preset.id}_${this.activeStt}_${this.findConfigured(preset) === null ? 'n' : 'y'}`)

                this.sectionTitle('语音合成（TTS）')
                this.localTtsCard()
                ForEach(this.ttsPresets(), (preset: VoicePresetModel) => {
                  this.presetCard(preset, 'tts')
                }, (preset: VoicePresetModel) =>
                `tts_${preset.id}_${this.localTtsActive ? 'local' : this.activeTts}_${this.findConfigured(preset) === null ? 'n' : 'y'}`)
              }
              .width('100%')
              .padding({ left: 14, right: 14, top: 4, bottom: 24 })
              .alignItems(HorizontalAlign.Start)
            }
            .scrollBar(BarState.Off)
            .width('100%')
            .height('100%')
            .align(Alignment.Top)
          }
          .onRefreshing((): void => {
            this.load();
          })
          .layoutWeight(1)
          .width('100%')
        }
      }
      .width('100%')
      .height('100%')
    }
    .hideTitleBar(true)
    .backgroundColor($r('app.color.bg_page'))
  }
}
