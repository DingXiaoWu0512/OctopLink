import { LoginPage } from './LoginPage';
import { MainPage } from './MainPage';
import { ExpertCreatePage } from './expert/ExpertCreatePage';
import { AgentEditPage } from './expert/AgentEditPage';
import { TeamsPage } from './expert/TeamsPage';
import { CronPage } from './workspace/CronPage';
import { KnowledgePage } from './workspace/KnowledgePage';
import { KnowledgeDocsPage } from './workspace/KnowledgeDocsPage';
import { ChannelPage } from './workspace/ChannelPage';
import { ConnectorPage } from './workspace/ConnectorPage';
import { PluginPage } from './workspace/PluginPage';
import { MbtiPage } from './workspace/MbtiPage';
import { SettingsPage } from './me/SettingsPage';
import { ThreadSettingsPage } from './chat/ThreadSettingsPage';
import { SessionStore } from '../store/SessionStore';
import { KeyboardAvoidMode } from '@kit.ArkUI';

@Entry
@Component
struct Index {
  @StorageLink(SessionStore.KEY_LOGGED_IN) loggedIn: boolean = false;
  @Provide('navStack') navStack: NavPathStack = new NavPathStack();

  aboutToAppear(): void {
    // 键盘避让压缩模式：软键盘弹起时压缩页面可用高度（顶栏不动、列表收缩），而非整页上移
    this.getUIContext().setKeyboardAvoidMode(KeyboardAvoidMode.RESIZE);
  }

  @Builder
  pageMap(name: string) {
    if (name === 'expertCreate') {
      ExpertCreatePage()
    } else if (name === 'agentEdit') {
      AgentEditPage()
    } else if (name === 'teams') {
      TeamsPage()
    } else if (name === 'cron') {
      CronPage()
    } else if (name === 'knowledge') {
      KnowledgePage()
    } else if (name === 'knowledgeDocs') {
      KnowledgeDocsPage()
    } else if (name === 'connectors') {
      ConnectorPage()
    } else if (name === 'channels') {
      ChannelPage()
    } else if (name === 'plugins') {
      PluginPage()
    } else if (name === 'mbti') {
      MbtiPage()
    } else if (name === 'settings') {
      SettingsPage()
    } else if (name === 'threadSettings') {
      ThreadSettingsPage()
    }
  }

  build() {
    Navigation(this.navStack) {
      if (this.loggedIn) {
        MainPage()
      } else {
        LoginPage()
      }
    }
    .hideTitleBar(true)
    .mode(NavigationMode.Stack)
    .navDestination(this.pageMap)
  }
}
