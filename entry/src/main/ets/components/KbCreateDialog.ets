import { KnowledgeService } from '../service/WorkspaceService';
import { OctopApiError } from '../net/HttpClient';

/** 知识库创建/编辑对话框（编辑时传 kbId 与回填初值） */
@CustomDialog
export struct KbCreateDialog {
  controller?: CustomDialogController;
  kbId: string = '';
  initialName: string = '';
  initialDesc: string = '';
  initialShared: boolean = false;
  initialDefaultOpen: boolean = false;
  initialMaxDocs: number = 100;
  onSaved: () => void = (): void => {
  };
  @State nameText: string = '';
  @State descText: string = '';
  @State shared: boolean = false;
  @State defaultOpen: boolean = false;
  @State maxDocsText: string = '100';
  @State submitting: boolean = false;

  aboutToAppear(): void {
    this.nameText = this.initialName;
    this.descText = this.initialDesc;
    this.shared = this.initialShared;
    this.defaultOpen = this.initialDefaultOpen;
    this.maxDocsText = this.initialMaxDocs > 0 ? `${this.initialMaxDocs}` : '';
  }

  private async submit(): Promise<void> {
    if (this.submitting) {
      return;
    }
    const name: string = this.nameText.trim();
    if (name === '') {
      this.getUIContext().getPromptAction().showToast({ message: '请填写知识库名称' });
      return;
    }
    let maxDocs: number = 0;
    const maxRaw: string = this.maxDocsText.trim();
    if (maxRaw !== '') {
      maxDocs = Number(maxRaw);
      if (Number.isNaN(maxDocs) || maxDocs < 0 || maxDocs > 10000) {
        this.getUIContext().getPromptAction().showToast({ message: '文档数上限需为 0-10000（0=不限）' });
        return;
      }
    }
    this.submitting = true;
    try {
      if (this.kbId === '') {
        await KnowledgeService.createBase(name, this.descText.trim(), this.shared,
          this.defaultOpen, maxDocs);
      } else {
        const body: Record<string, Object> = {
          'name': name,
          'description': this.descText.trim(),
          'shared': this.shared,
          'default_open': this.defaultOpen
        };
        if (maxDocs > 0) {
          body['max_documents'] = maxDocs;
        }
        await KnowledgeService.patchBase(this.kbId, JSON.stringify(body));
      }
      this.controller?.close();
      this.getUIContext().getPromptAction().showToast({
        message: this.kbId === '' ? '知识库已创建' : '知识库已更新'
      });
      this.onSaved();
    } catch (e) {
      const message: string = e instanceof OctopApiError ? e.message : '保存失败';
      this.getUIContext().getPromptAction().showToast({ message });
    } finally {
      this.submitting = false;
    }
  }

  build() {
    Column({ space: 14 }) {
      Text(this.kbId === '' ? '新建知识库' : '编辑知识库')
        .fontSize(17)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .width('100%')
        .textAlign(TextAlign.Start)
      TextInput({
        text: this.nameText,
        placeholder: '知识库名称（1-200 字符）'
      })
        .fontSize(14)
        .height(42)
        .backgroundColor($r('app.color.bg_input'))
        .borderRadius(12)
        .onChange((value: string): void => {
          this.nameText = value;
        })
      TextArea({
        text: this.descText,
        placeholder: '描述（可选）'
      })
        .fontSize(14)
        .height(64)
        .backgroundColor($r('app.color.bg_input'))
        .borderRadius(12)
        .onChange((value: string): void => {
          this.descText = value;
        })
      TextInput({
        text: this.maxDocsText,
        placeholder: '文档数上限（0-10000，0=不限，默认 100）'
      })
        .fontSize(14)
        .height(42)
        .backgroundColor($r('app.color.bg_input'))
        .borderRadius(12)
        .type(InputType.Number)
        .onChange((value: string): void => {
          this.maxDocsText = value;
        })
      Row() {
        Column({ space: 2 }) {
          Text('共享给其他用户')
            .fontSize(14)
            .fontColor($r('app.color.text_primary'))
          Text('开启后所有用户可见此知识库')
            .fontSize(11)
            .fontColor($r('app.color.text_tertiary'))
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
        Toggle({ type: ToggleType.Switch, isOn: this.shared })
          .selectedColor($r('app.color.brand'))
          .onChange((isOn: boolean): void => {
            this.shared = isOn;
          })
      }
      .width('100%')
      Row() {
        Column({ space: 2 }) {
          Text('默认挂载给新会话')
            .fontSize(14)
            .fontColor($r('app.color.text_primary'))
          Text('开启后专家默认检索此知识库')
            .fontSize(11)
            .fontColor($r('app.color.text_tertiary'))
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
        Toggle({ type: ToggleType.Switch, isOn: this.defaultOpen })
          .selectedColor($r('app.color.brand'))
          .onChange((isOn: boolean): void => {
            this.defaultOpen = isOn;
          })
      }
      .width('100%')
      Row({ space: 12 }) {
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
        Button(this.submitting ? '保存中...' : (this.kbId === '' ? '创建' : '保存'))
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
          .enabled(!this.submitting)
          .onClick((): void => {
            this.submit();
          })
      }
      .width('100%')
    }
    .padding(20)
    .width('100%')
  }
}
