import { SessionsTab } from './ChatTab';
import { PageHeader } from '../../components/PageHeader';

/** 会话列表页（原会话 Tab，从聊天页/命令面板 push 进入） */
@Component
export struct SessionsPage {
  build() {
    NavDestination() {
      Column() {
        PageHeader({ title: '会话' })
        SessionsTab({ topInset: 0, bottomPad: 28, asPage: true })
      }
      .width('100%')
      .height('100%')
    }
    .hideTitleBar(true)
    .backgroundColor($r('app.color.bg_page'))
  }
}
