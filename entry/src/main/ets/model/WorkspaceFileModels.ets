import { JsonHelper } from '../utils/JsonHelper';

/** 工作区文件条目（tree/glob 元素：path/is_dir/size?/modified_at?） */
export class WorkspaceEntryModel {
  readonly path: string;
  readonly isDir: boolean;
  readonly size: number;
  readonly modifiedAt: string;

  constructor(path: string, isDir: boolean, size: number, modifiedAt: string) {
    this.path = path;
    this.isDir = isDir;
    this.size = size;
    this.modifiedAt = modifiedAt;
  }

  /** 末段文件/目录名 */
  displayName(): string {
    const parts: Array<string> = this.path.split('/');
    return parts.length > 0 ? parts[parts.length - 1] : this.path;
  }

  static fromRecord(rec: Record<string, Object>): WorkspaceEntryModel {
    return new WorkspaceEntryModel(
      JsonHelper.getString(rec, 'path', ''),
      JsonHelper.getBool(rec, 'is_dir', false),
      JsonHelper.getNumber(rec, 'size', 0),
      JsonHelper.getString(rec, 'modified_at', '')
    );
  }

  static parseList(text: string): Array<WorkspaceEntryModel> {
    const result: Array<WorkspaceEntryModel> = [];
    const arr = JsonHelper.parseArray(text);
    if (arr === null) {
      return result;
    }
    for (const rec of arr) {
      result.push(WorkspaceEntryModel.fromRecord(rec));
    }
    return result;
  }
}

/** grep 匹配行 */
export class WorkspaceGrepMatchModel {
  readonly path: string;
  readonly line: number;
  readonly text: string;

  constructor(path: string, line: number, text: string) {
    this.path = path;
    this.line = line;
    this.text = text;
  }

  static fromRecord(rec: Record<string, Object>): WorkspaceGrepMatchModel {
    return new WorkspaceGrepMatchModel(
      JsonHelper.getString(rec, 'path', ''),
      JsonHelper.getNumber(rec, 'line', 0),
      JsonHelper.getString(rec, 'text', '')
    );
  }

  static parseList(text: string): Array<WorkspaceGrepMatchModel> {
    const result: Array<WorkspaceGrepMatchModel> = [];
    const arr = JsonHelper.parseArray(text);
    if (arr === null) {
      return result;
    }
    for (const rec of arr) {
      result.push(WorkspaceGrepMatchModel.fromRecord(rec));
    }
    return result;
  }
}

/** 提及索引（mention-index） */
export class MentionIndexModel {
  readonly paths: Array<string>;
  readonly truncated: boolean;

  constructor(paths: Array<string>, truncated: boolean) {
    this.paths = paths;
    this.truncated = truncated;
  }

  static parse(text: string): MentionIndexModel {
    const rec = JsonHelper.parse(text);
    if (rec === null) {
      return new MentionIndexModel([], false);
    }
    return new MentionIndexModel(
      JsonHelper.getStringArray(rec, 'paths'),
      JsonHelper.getBool(rec, 'truncated', false)
    );
  }
}
