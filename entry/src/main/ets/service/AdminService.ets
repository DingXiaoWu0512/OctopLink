import { HttpClient } from '../net/HttpClient';
import { UserAccountModel, UserRoleModel } from '../model/AuthModels';
import { AdminAuditLogModel, AdminOverviewModel } from '../model/AdminModels';

/**
 * 管理员控制台服务（源：octop/api/routers/admin.py、users.py、user_roles.py、
 * backup.py、storage_backends.py、security.py、envs.py、observability.py、update.py、tls.py）：
 * - 系统概览 / 审计日志 / 指标（需 admin_console 权限）
 * - 用户管理：启停/重置密码/改角色/解锁/删除（需 users 权限）+ 权限目录
 * - 备份：状态/列表/创建/恢复/删除/导入导出/自动备份
 * - 存储后端 CRUD + 探测/测试；安全策略 + 命令守卫规则
 * - 全局环境变量；Langfuse 可观测；服务自更新；TLS 证书签发
 */
export class AdminService {
  /** 系统概览：用户 + 专家列表与总数（GET /api/admin/overview） */
  static async overview(): Promise<AdminOverviewModel> {
    const text: string = await HttpClient.getInstance().get('/api/admin/overview');
    return AdminOverviewModel.parse(text);
  }

  /** 审计日志（GET /api/admin/audit-log?limit=，limit 1~500） */
  static async auditLog(limit: number = 100): Promise<Array<AdminAuditLogModel>> {
    const text: string =
      await HttpClient.getInstance().get(`/api/admin/audit-log?limit=${limit}`);
    return AdminAuditLogModel.parseList(text);
  }

  /** 用户列表（GET /api/users，含停用用户） */
  static async listUsers(): Promise<Array<UserAccountModel>> {
    const text: string = await HttpClient.getInstance().get('/api/users');
    return UserAccountModel.parseList(text);
  }

  /** 角色模板列表（GET /api/users/roles，改角色候选） */
  static async listRoles(): Promise<Array<UserRoleModel>> {
    const text: string = await HttpClient.getInstance().get('/api/users/roles');
    return UserRoleModel.parseList(text);
  }

  /** 启用/停用用户（PATCH /api/users/{id} {disabled}） */
  static async setUserEnabled(userId: number, enabled: boolean): Promise<void> {
    const body: Record<string, Object> = { 'disabled': !enabled };
    await HttpClient.getInstance().patch(`/api/users/${userId}`, JSON.stringify(body));
  }

  /** 重置用户密码（POST /api/users/{id}/reset-password，204） */
  static async resetPassword(userId: number, newPassword: string): Promise<void> {
    const body: Record<string, Object> = { 'new_password': newPassword };
    await HttpClient.getInstance()
      .post(`/api/users/${userId}/reset-password`, JSON.stringify(body));
  }

  /** 更换用户角色（PATCH /api/users/{id} {role}，role 为角色模板 public id） */
  static async changeRole(userId: number, roleId: string): Promise<void> {
    const body: Record<string, Object> = { 'role': roleId };
    await HttpClient.getInstance().patch(`/api/users/${userId}`, JSON.stringify(body));
  }

  /** 清除登录锁定（POST /api/users/{id}/unlock-login，204） */
  static async unlockLogin(userId: number): Promise<void> {
    await HttpClient.getInstance().post(`/api/users/${userId}/unlock-login`, '{}');
  }

  /** 删除用户（DELETE /api/users/{id}，204；不可删除自己） */
  static async deleteUser(userId: number): Promise<void> {
    await HttpClient.getInstance().delete(`/api/users/${userId}`);
  }

  /** 可分配权限目录（GET /api/users/permissions，数组原始文本交 UI 解析） */
  static async permissionCatalog(): Promise<string> {
    return await HttpClient.getInstance().get('/api/users/permissions');
  }

  // ---- 备份（admin/backup）----

  /** 备份/恢复进行中状态（GET /admin/backup/status） */
  static async backupStatus(): Promise<string> {
    return await HttpClient.getInstance().get('/api/admin/backup/status');
  }

  /** 已存备份列表（GET /admin/backup/list） */
  static async backupList(): Promise<string> {
    return await HttpClient.getInstance().get('/api/admin/backup/list');
  }

  /** 读取自动备份设置（GET /admin/backup/auto） */
  static async backupAutoGet(): Promise<string> {
    return await HttpClient.getInstance().get('/api/admin/backup/auto');
  }

  /** 更新自动备份设置（PUT /admin/backup/auto，字段可空表示不改） */
  static async backupAutoPut(bodyStr: string): Promise<string> {
    return await HttpClient.getInstance().put('/api/admin/backup/auto', bodyStr);
  }

  /** 立即创建备份并存入备份目录（POST /admin/backup/create） */
  static async backupCreate(bodyStr: string): Promise<string> {
    return await HttpClient.getInstance().post('/api/admin/backup/create', bodyStr);
  }

  /** 立即按自动备份配置跑一次（POST /admin/backup/auto/run） */
  static async backupRunNow(): Promise<string> {
    return await HttpClient.getInstance().post('/api/admin/backup/auto/run', '{}');
  }

  /** 从已存备份恢复（restore_config=true 时恢复配置） */
  static async backupRestore(filename: string, restoreConfig: boolean): Promise<string> {
    const suffix: string = restoreConfig ? '?restore_config=true' : '';
    return await HttpClient.getInstance().post(
      `/api/admin/backup/files/${encodeURIComponent(filename)}/restore${suffix}`, '{}');
  }

  /** 删除已存备份 */
  static async backupDelete(filename: string): Promise<void> {
    await HttpClient.getInstance().delete(
      `/api/admin/backup/files/${encodeURIComponent(filename)}`);
  }

  /** 下载系统备份（ephemeral zip，返回字节） */
  static async backupExport(bodyStr: string): Promise<ArrayBuffer> {
    // export 为 GET + 查询串；bodyStr 形如 include_config=true&include_chats=false
    return await HttpClient.getInstance().downloadGet(`/api/admin/backup/export?${bodyStr}`);
  }

  /** 上传备份压缩包到备份目录（multipart 字段 file） */
  static async backupImport(fileName: string, data: ArrayBuffer): Promise<string> {
    return await HttpClient.getInstance().postMultipartFile(
      '/api/admin/backup/import', 'file', fileName, 'application/zip', data);
  }

  // ---- 存储后端（admin/storage-backends）----

  static async storageList(): Promise<string> {
    return await HttpClient.getInstance().get('/api/admin/storage-backends');
  }

  static async storageCreate(bodyStr: string): Promise<string> {
    return await HttpClient.getInstance().post('/api/admin/storage-backends', bodyStr);
  }

  /** 探测未保存的存储后端草稿（POST /probe） */
  static async storageProbe(bodyStr: string): Promise<string> {
    return await HttpClient.getInstance().post('/api/admin/storage-backends/probe', bodyStr);
  }

  static async storagePatch(backendId: number, bodyStr: string): Promise<string> {
    return await HttpClient.getInstance().patch(
      `/api/admin/storage-backends/${backendId}`, bodyStr);
  }

  static async storageDelete(backendId: number): Promise<void> {
    await HttpClient.getInstance().delete(`/api/admin/storage-backends/${backendId}`);
  }

  static async storageTest(backendId: number): Promise<string> {
    return await HttpClient.getInstance().post(
      `/api/admin/storage-backends/${backendId}/test`, '{}');
  }

  /** 存储后端对象树浏览（GET .../tree?path=） */
  static async storageTree(backendId: number, path: string): Promise<string> {
    const suffix: string = path === '' ? '' : `?path=${encodeURIComponent(path)}`;
    return await HttpClient.getInstance().get(
      `/api/admin/storage-backends/${backendId}/tree${suffix}`);
  }

  /** 读存储后端文件（GET .../file?path=） */
  static async storageFile(backendId: number, path: string): Promise<string> {
    return await HttpClient.getInstance().get(
      `/api/admin/storage-backends/${backendId}/file?path=${encodeURIComponent(path)}`);
  }

  // ---- 安全策略（admin/security）----

  static async securityGet(): Promise<string> {
    return await HttpClient.getInstance().get('/api/admin/security');
  }

  static async securityPut(bodyStr: string): Promise<string> {
    return await HttpClient.getInstance().put('/api/admin/security', bodyStr);
  }

  static async securityDefaults(): Promise<string> {
    return await HttpClient.getInstance().get('/api/admin/security/defaults');
  }

  /** 命令守卫规则（激活视图） */
  static async toolGuardRules(): Promise<string> {
    return await HttpClient.getInstance().get('/api/admin/security/tool-guard/rules');
  }

  /** 命令守卫规则（可编辑 YAML 原文） */
  static async toolGuardRulesRaw(): Promise<string> {
    return await HttpClient.getInstance().get('/api/admin/security/tool-guard/rules/raw');
  }

  /** 保存命令守卫规则 YAML */
  static async toolGuardRulesPut(content: string): Promise<string> {
    const body: Record<string, Object> = { 'content': content };
    return await HttpClient.getInstance().put(
      '/api/admin/security/tool-guard/rules/raw', JSON.stringify(body));
  }

  /** 恢复命令守卫规则为出厂默认 */
  static async toolGuardRulesReset(): Promise<string> {
    return await HttpClient.getInstance().post(
      '/api/admin/security/tool-guard/rules/reset', '{}');
  }

  // ---- 全局环境变量（envs）----

  static async envsList(): Promise<string> {
    return await HttpClient.getInstance().get('/api/envs');
  }

  static async envsPut(bodyStr: string): Promise<string> {
    return await HttpClient.getInstance().put('/api/envs', bodyStr);
  }

  static async envsDelete(key: string): Promise<string> {
    return await HttpClient.getInstance().delete(`/api/envs/${encodeURIComponent(key)}`);
  }

  // ---- 可观测（Langfuse）/ 指标 ----

  static async langfuseGet(): Promise<string> {
    return await HttpClient.getInstance().get('/api/admin/observability/langfuse');
  }

  static async langfusePut(bodyStr: string): Promise<string> {
    return await HttpClient.getInstance().put('/api/admin/observability/langfuse', bodyStr);
  }

  static async langfuseTest(bodyStr: string): Promise<string> {
    return await HttpClient.getInstance().post(
      '/api/admin/observability/langfuse/test', bodyStr);
  }

  static async metrics(): Promise<string> {
    return await HttpClient.getInstance().get('/api/admin/metrics');
  }

  // ---- 服务自更新（update）----

  static async updateStatus(): Promise<string> {
    return await HttpClient.getInstance().get('/api/update/status');
  }

  /** 升级任务进度（task_id 从 upgrade/check 响应取） */
  static async updateProgress(taskId: string): Promise<string> {
    return await HttpClient.getInstance().get(
      `/api/update/progress?task_id=${encodeURIComponent(taskId)}`);
  }

  static async updateSettings(stableOnly: boolean): Promise<string> {
    const body: Record<string, Object> = { 'stable_only': stableOnly };
    return await HttpClient.getInstance().patch(
      '/api/update/settings', JSON.stringify(body));
  }

  static async updateCheck(): Promise<string> {
    return await HttpClient.getInstance().post('/api/update/check', '{}');
  }

  /** 执行升级（version 空串=最新） */
  static async updateUpgrade(version: string): Promise<string> {
    const body: Record<string, Object> = {};
    if (version !== '') {
      body['version'] = version;
    }
    return await HttpClient.getInstance().post('/api/update/upgrade', JSON.stringify(body));
  }

  static async updateRestart(): Promise<string> {
    return await HttpClient.getInstance().post('/api/update/restart', '{}');
  }

  // ---- TLS（admin/tls）----

  static async tlsStatus(): Promise<string> {
    return await HttpClient.getInstance().get('/api/admin/tls/status');
  }

  static async tlsPreflight(domain: string): Promise<string> {
    const body: Record<string, Object> = { 'domain': domain };
    return await HttpClient.getInstance().post(
      '/api/admin/tls/preflight', JSON.stringify(body));
  }

  static async tlsIssue(domain: string, staging: boolean): Promise<string> {
    const body: Record<string, Object> = { 'domain': domain, 'staging': staging };
    return await HttpClient.getInstance().post('/api/admin/tls/issue', JSON.stringify(body));
  }

  // ---- 全局用量（admin/usage）----

  /** 全局用量汇总（window=all|7d|30d 等；granularity=day；可按 user/agent 过滤） */
  static async usageSummary(window: string, granularity: string,
    userId: number, agentId: string): Promise<string> {
    const params: string[] = [];
    if (window !== '') {
      params.push(`window=${encodeURIComponent(window)}`);
    }
    if (granularity !== '') {
      params.push(`granularity=${encodeURIComponent(granularity)}`);
    }
    if (userId > 0) {
      params.push(`user_id=${userId}`);
    }
    if (agentId !== '') {
      params.push(`agent_id=${encodeURIComponent(agentId)}`);
    }
    const suffix: string = params.length > 0 ? `?${params.join('&')}` : '';
    return await HttpClient.getInstance().get(`/api/admin/usage/summary${suffix}`);
  }

  /** 全局用量 Excel 导出（返回 xlsx 字节） */
  static async usageExportXlsx(window: string): Promise<ArrayBuffer> {
    const suffix: string = window === '' ? '' : `?window=${encodeURIComponent(window)}`;
    return await HttpClient.getInstance().downloadGet(`/api/admin/usage/export.xlsx${suffix}`);
  }
}
