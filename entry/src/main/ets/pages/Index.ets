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
import { UsersPage } from './workspace/UsersPage';
import { SkillsPage } from './workspace/SkillsPage';
import { ToolSettingsPage } from './workspace/ToolSettingsPage';
import { SkillPackagesPage } from './workspace/SkillPackagesPage';
import { SubagentsPage } from './workspace/SubagentsPage';
import { WorkspaceFilesPage } from './workspace/WorkspaceFilesPage';
import { UsagePage } from './workspace/UsagePage';
import { UserGroupsPage } from './workspace/UserGroupsPage';
import { MemoryPage } from './workspace/MemoryPage';
import { BridgePage } from './workspace/BridgePage';
import { InvitesPage } from './workspace/InvitesPage';
import { SettingsPage } from './me/SettingsPage';
import { AdminPage } from './me/AdminPage';
import { AdminOpsPage } from './me/AdminOpsPage';
import { SsoPage } from './me/SsoPage';
import { VoiceSettingsPage } from './me/VoiceSettingsPage';
import { ProvidersPage } from './me/ProvidersPage';
import { HelpPage } from './me/HelpPage';
import { AboutPage } from './me/AboutPage';
import { ThreadSettingsPage } from './chat/ThreadSettingsPage';
import { TrajectoryPage } from './chat/TrajectoryPage';
import { SessionsPage } from './chat/SessionsPage';
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
    } else if (name === 'users') {
      UsersPage()
    } else if (name === 'skills') {
      SkillsPage()
    } else if (name === 'skillPackages') {
      SkillPackagesPage()
    } else if (name === 'subagents') {
      SubagentsPage()
    } else if (name === 'workspaceFiles') {
      WorkspaceFilesPage()
    } else if (name === 'usage') {
      UsagePage()
    } else if (name === 'userGroups') {
      UserGroupsPage()
    } else if (name === 'memory') {
      MemoryPage()
    } else if (name === 'bridge') {
      BridgePage()
    } else if (name === 'invites') {
      InvitesPage()
    } else if (name === 'admin') {
      AdminPage()
    } else if (name === 'adminOps') {
      AdminOpsPage()
    } else if (name === 'sso') {
      SsoPage()
    } else if (name === 'voiceSettings') {
      VoiceSettingsPage()
    } else if (name === 'toolSettings') {
      ToolSettingsPage()
    } else if (name === 'settings') {
      SettingsPage()
    } else if (name === 'threadSettings') {
      ThreadSettingsPage()
    } else if (name === 'trajectory') {
      TrajectoryPage()
    } else if (name === 'sessions') {
      SessionsPage()
    } else if (name === 'providers') {
      ProvidersPage()
    } else if (name === 'help') {
      HelpPage()
    } else if (name === 'about') {
      AboutPage()
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
