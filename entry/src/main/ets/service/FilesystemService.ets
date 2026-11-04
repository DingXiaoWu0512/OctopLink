import { HttpClient } from '../net/HttpClient';
import { JsonHelper } from '../utils/JsonHelper';

/**
 * 服务器宿主目录服务（/api/filesystem*，源 filesystem.py）：
 * - 创建专家/连接器时浏览与选择服务器上的工作区目录
 * - probe 探测路径可用性；mkdir 新建；rename 重命名
 * - defaults 提供当前用户的默认选择范围；roots 提供可选根列表
 * - docker-status/ensure-docker/ensure-bwrap 为沙箱准备（创建流程辅助）
 */

/** 目录条目（GET /api/filesystem/dirs 元素） */
export class FsDirEntry {
  readonly name: string;
  readonly path: string;
  readonly isDir: boolean;
  readonly writable: boolean;

  constructor(name: string, path: string, isDir: boolean, writable: boolean) {
    this.name = name;
    this.path = path;
    this.isDir = isDir;
    this.writable = writable;
  }

  static fromRecord(rec: Record<string, Object>): FsDirEntry {
    return new FsDirEntry(
      JsonHelper.getString(rec, 'name', ''),
      JsonHelper.getString(rec, 'path', ''),
      JsonHelper.getBool(rec, 'is_dir', true),
      JsonHelper.getBool(rec, 'writable', true)
    );
  }
}

/** 路径探测结果（POST /api/filesystem/probe） */
export class FsProbeResult {
  readonly ok: boolean;
  readonly exists: boolean;
  readonly writable: boolean;
  readonly message: string;

  constructor(ok: boolean, exists: boolean, writable: boolean, message: string) {
    this.ok = ok;
    this.exists = exists;
    this.writable = writable;
    this.message = message;
  }

  static parse(text: string): FsProbeResult {
    const rec = JsonHelper.parse(text);
    if (rec === null) {
      return new FsProbeResult(false, false, false, '响应解析失败');
    }
    return new FsProbeResult(
      JsonHelper.getBool(rec, 'ok', false),
      JsonHelper.getBool(rec, 'exists', false),
      JsonHelper.getBool(rec, 'writable', false),
      JsonHelper.getString(rec, 'message', '')
    );
  }
}

/** 默认选择范围（GET /api/filesystem/defaults） */
export class FsDefaults {
  readonly min: string;
  readonly max: string;
  readonly suggested: string;

  constructor(min: string, max: string, suggested: string) {
    this.min = min;
    this.max = max;
    this.suggested = suggested;
  }

  static parse(text: string): FsDefaults {
    const rec = JsonHelper.parse(text);
    if (rec === null) {
      return new FsDefaults('', '', '');
    }
    return new FsDefaults(
      JsonHelper.getString(rec, 'min', ''),
      JsonHelper.getString(rec, 'max', ''),
      JsonHelper.getString(rec, 'suggested', '')
    );
  }
}

export class FilesystemService {
  /** 默认 root_dir 选择范围 */
  static async defaults(): Promise<FsDefaults> {
    return FsDefaults.parse(
      await HttpClient.getInstance().get('/api/filesystem/defaults'));
  }

  /** 当前用户可用的浏览根（GET /filesystem/roots，返回原始文本交 UI 解析） */
  static async roots(): Promise<string> {
    return await HttpClient.getInstance().get('/api/filesystem/roots');
  }

  /** 列出服务器目录（path 空串=使用默认根） */
  static async listDirs(path: string): Promise<Array<FsDirEntry>> {
    const suffix: string = path === '' ? '' : `?path=${encodeURIComponent(path)}`;
    const text: string =
      await HttpClient.getInstance().get(`/api/filesystem/dirs${suffix}`);
    const result: Array<FsDirEntry> = [];
    const rec = JsonHelper.parse(text);
    if (rec === null) {
      return result;
    }
    // 兼容 {entries:[...]} 与裸数组两种响应
    let items: Array<Record<string, Object>> = JsonHelper.getRecordArray(rec, 'entries');
    if (items.length === 0) {
      items = JsonHelper.getRecordArray(rec, 'items');
    }
    if (items.length === 0) {
      const arr = JsonHelper.parseArray(text);
      if (arr !== null) {
        for (const item of arr) {
          result.push(FsDirEntry.fromRecord(item));
        }
      }
      return result;
    }
    for (const item of items) {
      result.push(FsDirEntry.fromRecord(item));
    }
    return result;
  }

  /** 探测路径可用性 */
  static async probe(path: string): Promise<FsProbeResult> {
    const body: Record<string, Object> = { 'path': path };
    return FsProbeResult.parse(await HttpClient.getInstance().post(
      '/api/filesystem/probe', JSON.stringify(body)));
  }

  /** 新建目录（base_name 为在 path 下创建的名字） */
  static async mkdir(path: string, baseName: string): Promise<string> {
    const body: Record<string, Object> = { 'path': path, 'base_name': baseName };
    return await HttpClient.getInstance().post('/api/filesystem/mkdir', JSON.stringify(body));
  }

  /** 重命名目录 */
  static async rename(path: string, newName: string): Promise<string> {
    const body: Record<string, Object> = { 'path': path, 'new_name': newName };
    return await HttpClient.getInstance().post('/api/filesystem/rename', JSON.stringify(body));
  }

  /** Docker 可用性（GET /filesystem/docker-status） */
  static async dockerStatus(): Promise<string> {
    return await HttpClient.getInstance().get('/api/filesystem/docker-status');
  }

  /** 尽力安装 Docker Engine（沙箱后端准备） */
  static async ensureDocker(): Promise<string> {
    return await HttpClient.getInstance().post('/api/filesystem/ensure-docker', '{}');
  }

  /** 尽力安装 bubblewrap（scoped root_dir 沙箱准备） */
  static async ensureBwrap(): Promise<string> {
    return await HttpClient.getInstance().post('/api/filesystem/ensure-bwrap', '{}');
  }
}
