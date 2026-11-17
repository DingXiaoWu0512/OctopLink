import { PageHeader } from '../../components/PageHeader';

/** 帮助分节静态内容：标题 + 正文 */
class HelpSection {
  readonly title: string;
  readonly body: string;

  constructor(title: string, body: string) {
    this.title = title;
    this.body = body;
  }
}

/** 使用说明页（路由 'help'）：PageHeader + 六节静态说明卡片，纯本地内容无网络依赖 */
@Component
export struct HelpPage {
  private readonly sections: Array<HelpSection> = [
    new HelpSection('一、快速开始',
      '把 App 连到你的 Octop 服务器并开始对话，只需四步：\n' +
      '1. 服务器配置：进入「我的 → 服务器设置」，填写 Octop 服务器地址（如 http://192.168.1.10:8000），点击保存并测试连通；\n' +
      '2. 登录：使用服务器管理员为你开通的账号密码登录；若服务器开启了 SSO，也可在登录页选择 SSO 方式；\n' +
      '3. 选择专家：进入「专家」页，点击已有专家卡片开始对话；没有专家时可先创建（见"三、专家与团队"）；\n' +
      '4. 开始聊天：进入「聊天」页输入消息发送即可。若提示权限不足，请联系服务器管理员为你的账号分配相应权限。'),
    new HelpSection('二、聊天详解',
      '发送消息：在底部输入框输入文字，点击发送按钮（或键盘回车）发出；流式回复会逐字显示。\n' +
      '附件：点击输入框附件按钮，可选择图片或文件随消息一起发送，专家可读取附件内容作答。\n' +
      '语音输入：点击输入框麦克风按钮开始录音，再点一次结束并转文字；识别结果进入输入框可继续编辑。\n' +
      '朗读：助手消息下方喇叭按钮可将回答朗读出来（三态：合成中/播放中可停止/空闲）；朗读使用设备端本机语音引擎离线合成，无需联网。\n' +
      '会话切换：点击顶部会话名可查看与切换历史会话；下拉会话列表可刷新。\n' +
      '长按菜单：长按助手消息可复制、朗读、重试；长按自己的消息可复制。\n' +
      'Token 用量：助手消息下方"↑输入 ↓输出"数字表示本次回答消耗的 Token 数（输入=你的消息及上下文，输出=回答正文），是计费与统计口径的基础。'),
    new HelpSection('三、专家与团队',
      '专家是你的 AI 助手，每个专家有独立的提示词、模型与工具配置。\n' +
      '创建：进入「专家」页，点击右下角"+"按钮填写名称即可创建；\n' +
      '配置：长按专家卡片弹出菜单，选择"编辑"配置系统提示词、绑定模型、开启工具、挂载子代理与技能；\n' +
      '删除/复制：长按菜单中可删除或复制专家；\n' +
      '团队：进入「团队」页创建团队，把多个专家组织为协作小组（如"写作组"），团队卡片长按同样可编辑与删除。'),
    new HelpSection('四、工作台',
      '渠道：进入「工作台 → 渠道」，点击"新建渠道"选择平台（钉钉/企微/飞书等），按向导扫码或填入凭证即可把专家接入 IM；卡片上可查看在线状态。\n' +
      '知识库：进入「工作台 → 知识库」，新建知识库后点击进入，上传文档（PDF/Word/TXT/Markdown 等）供专家检索引用；文档支持启停与删除。\n' +
      '技能与市场：进入「工作台 → 技能」，"我的技能"管理当前专家已有技能（开关/编辑/导出/删除）；切到"技能市场"默认展示推荐榜单，可直接安装，也可输入关键词搜索后安装。\n' +
      '插件：进入「工作台 → 插件」，从插件市场一键安装或通过 ZIP URL 导入插件，为专家扩展新工具。\n' +
      '连接器：进入「工作台 → 连接器」，浏览连接器目录并完成 OAuth 授权或凭据配置，让专家能访问外部服务（如日历、网盘）。\n' +
      '定时任务：进入「工作台 → 定时任务」，新建任务选择专家与执行指令、设置周期（如每天 9:00），到点自动执行并把结果推送到会话。\n' +
      '用量统计：进入「工作台 → 用量统计」，查看 Token 消耗趋势与各专家/模型占比，帮助优化成本。'),
    new HelpSection('五、我的与设置',
      '个人资料：进入「我的」，点击头像卡片修改昵称与头像。\n' +
      '外观：进入「我的 → 外观」，选择浅色/深色/跟随系统主题；"沉浸光感"开启后界面毛玻璃与光影效果增强，关闭可提升低端设备流畅度。\n' +
      '模型配置：进入「我的 → 模型配置」，管理员可新建/编辑 Provider（接口地址、密钥、模型列表），点击"全局默认模型"卡片选择默认模型；长按 Provider 卡片可测试连通、拉取模型列表、启停、编辑或删除。\n' +
      '语音设置：进入「我的 → 语音设置」，配置语音识别（ASR）云服务与朗读参数（音色、语速、音调、音量）；朗读由设备端本机引擎离线合成，无需服务器支持。\n' +
      '用户与权限：管理员进入「我的 → 用户管理」维护账号、重置密码、分配角色与权限；普通用户仅能看到自己的信息。\n' +
      '服务器设置：进入「我的 → 服务器设置」修改服务器地址，或退出登录切换账号。'),
    new HelpSection('六、常见问题排查',
      '422 与网络错误：请求报 422 一般是参数缺失或格式错误，请检查填写内容后重试；"无法连接服务器"请检查网络、服务器地址拼写以及服务器是否可达（可在「我的 → 服务器设置」重新测试）。\n' +
      '权限不足：操作提示"需要 xx 权限"时，说明当前账号未获授权，请联系服务器管理员在用户管理中为你的账号分配对应权限。\n' +
      '手机工具不可用：工具开关页"手机截图/手机点击/手机滑动"等显示"不可用"，是服务器远程手机能力（capabilities.mobile）未开启或未连接 adb 设备所致，属于服务器侧配置状态而非 App 故障；卡片下方的灰色说明文字为服务端给出的具体原因，请管理员在服务器配置中开启并接入设备。\n' +
      '语音识别无文字：请确认「我的 → 语音设置」已配置 ASR 服务且录音权限已授予；服务器不支持浏览器方式识别时需改用服务端 ASR。\n' +
      '朗读无声音：确认设备未处于静音模式且系统语音引擎可用（可在「我的 → 语音设置 → 配置」查看音色列表）；引擎不可用时朗读按钮会提示"本机语音引擎不可用"。\n' +
      '技能市场为空：市场默认展示推荐榜单，加载失败会显示重试按钮，点击即可重新拉取；也可直接用关键词搜索。')
  ];

  @Builder
  sectionCard(section: HelpSection) {
    Column({ space: 8 }) {
      Text(section.title)
        .fontSize(15)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .width('100%')
      Text(section.body)
        .fontSize(13)
        .lineHeight(21)
        .fontColor($r('app.color.text_secondary'))
        .width('100%')
    }
    .width('100%')
    .padding(14)
    .borderRadius(16)
    .backgroundColor($r('app.color.bg_card'))
    .border({ width: 1, color: $r('app.color.card_stroke') })
    .shadow({ radius: 10, color: '#0A000000', offsetY: 3 })
    .alignItems(HorizontalAlign.Start)
  }

  build() {
    NavDestination() {
      Column() {
        PageHeader({ title: '使用说明' })

        Scroll() {
          Column({ space: 12 }) {
            ForEach(this.sections, (section: HelpSection) => {
              this.sectionCard(section)
            }, (section: HelpSection) => section.title)
          }
          .width('100%')
          .padding({ left: 14, right: 14, top: 4, bottom: 40 })
          .alignItems(HorizontalAlign.Start)
        }
        .layoutWeight(1)
        .width('100%')
        .align(Alignment.Top)
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring)
      }
      .width('100%')
      .height('100%')
    }
    .hideTitleBar(true)
    .backgroundColor($r('app.color.bg_page'))
  }
}
