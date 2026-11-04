import { HttpClient } from '../net/HttpClient';
import { JsonHelper } from '../utils/JsonHelper';
import {
  MentionIndexModel,
  WorkspaceEntryModel,
  WorkspaceGrepMatchModel
} from '../model/WorkspaceFileModels';

/**
 * 智能体工作区文件（/api/agents/{agent_id}/workspace/*，源 workspace.py）。
 * 读路径：from_workspace=false（宿主绝对路径）；写路径一律工作区相对路径。
 */
export class WorkspaceFileService {
  /** 单层目录列表（flat array，非嵌套树） */
  static async tree(agentId: string, path: string = '/'): Promise<Array<WorkspaceEntryModel>> {
    const text: string = await HttpClient.getInstance().get(
      `/api/agents/${agentId}/workspace/tree?path=${encodeURIComponent(path)}`);
    return WorkspaceEntryModel.parseList(text);
  }

  /** 读文本文件（UTF-8 文本，非 base64） */
  static async readFile(agentId: string, path: string): Promise<string> {
    const text: string = await HttpClient.getInstance().get(
      `/api/agents/${agentId}/workspace/file?path=${encodeURIComponent(path)}`);
    const rec = JsonHelper.parse(text);
    return rec === null ? '' : JsonHelper.getString(rec, 'content', '');
  }

  /** 覆写文本文件 */
  static async writeFile(agentId: string, path: string, content: string): Promise<void> {
    const body: Record<string, Object> = { 'content': content };
    await HttpClient.getInstance().put(
      `/api/agents/${agentId}/workspace/file?path=${encodeURIComponent(path)}`,
      JSON.stringify(body));
  }

  static async mkdir(agentId: string, path: string): Promise<void> {
    await HttpClient.getInstance().post(
      `/api/agents/${agentId}/workspace/mkdir?path=${encodeURIComponent(path)}`, '{}');
  }

  static async remove(agentId: string, path: string): Promise<void> {
    await HttpClient.getInstance().delete(
      `/api/agents/${agentId}/workspace/file?path=${encodeURIComponent(path)}`);
  }

  /** 移动/重命名（destination 为工作区相对路径） */
  static async move(agentId: string, path: string, destination: string): Promise<void> {
    const body: Record<string, Object> = { 'destination': destination };
    await HttpClient.getInstance().post(
      `/api/agents/${agentId}/workspace/move?path=${encodeURIComponent(path)}`,
      JSON.stringify(body));
  }

  /** multipart 上传（字段 file；path 缺省为 /{filename}） */
  static async upload(agentId: string, fileName: string, contentType: string,
    data: ArrayBuffer, path: string = ''): Promise<void> {
    const query: string = path === ''
      ? ''
      : `?path=${encodeURIComponent(path)}`;
    await HttpClient.getInstance().postMultipartFile(
      `/api/agents/${agentId}/workspace/upload${query}`, 'file', fileName, contentType, data);
  }

  /** 下载文件字节流 */
  static async download(agentId: string, path: string): Promise<ArrayBuffer> {
    return await HttpClient.getInstance().downloadGet(
      `/api/agents/${agentId}/workspace/download?path=${encodeURIComponent(path)}`);
  }

  /** 可编辑文档读为 markdown（.docx 等） */
  static async readDoc(agentId: string, path: string): Promise<string> {
    const text: string = await HttpClient.getInstance().get(
      `/api/agents/${agentId}/workspace/doc?path=${encodeURIComponent(path)}`);
    const rec = JsonHelper.parse(text);
    return rec === null ? '' : JsonHelper.getString(rec, 'content', '');
  }

  /** markdown 写回可编辑文档 */
  static async writeDoc(agentId: string, path: string, content: string): Promise<void> {
    const body: Record<string, Object> = { 'content': content };
    await HttpClient.getInstance().put(
      `/api/agents/${agentId}/workspace/doc?path=${encodeURIComponent(path)}`,
      JSON.stringify(body));
  }

  /** 提及索引 */
  static async mentionIndex(agentId: string): Promise<MentionIndexModel> {
    const text: string = await HttpClient.getInstance().get(
      `/api/agents/${agentId}/workspace/mention-index`);
    return MentionIndexModel.parse(text);
  }

  /** glob 匹配文件列表 */
  static async glob(agentId: string, pattern: string,
    path: string = '/'): Promise<Array<WorkspaceEntryModel>> {
    const text: string = await HttpClient.getInstance().get(
      `/api/agents/${agentId}/workspace/glob?pattern=${encodeURIComponent(pattern)}` +
      `&path=${encodeURIComponent(path)}`);
    return WorkspaceEntryModel.parseList(text);
  }

  /** 内容 grep（返回匹配行列表） */
  static async grep(agentId: string, pattern: string,
    path: string = '/'): Promise<Array<WorkspaceGrepMatchModel>> {
    const text: string = await HttpClient.getInstance().get(
      `/api/agents/${agentId}/workspace/grep?pattern=${encodeURIComponent(pattern)}` +
      `&path=${encodeURIComponent(path)}`);
    return WorkspaceGrepMatchModel.parseList(text);
  }

  /** 整工作区导出 ZIP（application/zip 字节流） */
  static async archiveDownload(agentId: string): Promise<ArrayBuffer> {
    return await HttpClient.getInstance().downloadGet(
      `/api/agents/${agentId}/workspace/archive`);
  }

  /** 导入 ZIP（mode=merge|replace）→ {ok, mode, imported, warnings} */
  static async archiveUpload(agentId: string, fileName: string, data: ArrayBuffer,
    mode: string = 'merge'): Promise<ArchiveImportResult> {
    const text: string = await HttpClient.getInstance().postMultipartFile(
      `/api/agents/${agentId}/workspace/archive?mode=${mode}`, 'file', fileName,
      'application/zip', data);
    const rec = JsonHelper.parse(text);
    return new ArchiveImportResult(
      rec === null ? false : JsonHelper.getBool(rec, 'ok', false),
      rec === null ? mode : JsonHelper.getString(rec, 'mode', mode),
      rec === null ? 0 : JsonHelper.getNumber(rec, 'imported', 0),
      rec === null ? [] : JsonHelper.getStringArray(rec, 'warnings')
    );
  }
}

/** ZIP 导入结果 */
export class ArchiveImportResult {
  readonly ok: boolean;
  readonly mode: string;
  readonly imported: number;
  readonly warnings: Array<string>;

  constructor(ok: boolean, mode: string, imported: number, warnings: Array<string>) {
    this.ok = ok;
    this.mode = mode;
    this.imported = imported;
    this.warnings = warnings;
  }
}
