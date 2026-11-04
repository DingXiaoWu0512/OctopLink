import { JsonHelper } from '../utils/JsonHelper';

/**
 * 桥接设备域数据模型（源：octop/api/routers/bridge.py）：
 * - BridgeConnectionModel：桥接连接（manager.connection_public + 归属/共享扩展）
 * - BridgeProbeAgentModel / BridgeProbeResultModel：对端探测（登录 + 专家列表）
 */

/** 桥接连接（bridge.py _connection_payload） */
export class BridgeConnectionModel {
  readonly connectionId: string;
  readonly peerBaseUrl: string;
  readonly peerUsername: string;
  readonly displayName: string;
  readonly notes: string;
  readonly shared: boolean;
  readonly status: string; // connecting | connected | disconnected | error
  readonly lastError: string;
  readonly lastSeenAtMs: number;
  readonly autoReconnect: boolean;
  readonly createdAtMs: number;
  readonly updatedAtMs: number;
  readonly hasPassword: boolean;
  readonly inbound: boolean;
  readonly isOwner: boolean;
  readonly ownerUsername: string;
  readonly ownerDisplayName: string;

  constructor(connectionId: string, peerBaseUrl: string, peerUsername: string, displayName: string,
    notes: string, shared: boolean, status: string, lastError: string, lastSeenAtMs: number,
    autoReconnect: boolean, createdAtMs: number, updatedAtMs: number, hasPassword: boolean,
    inbound: boolean, isOwner: boolean, ownerUsername: string, ownerDisplayName: string) {
    this.connectionId = connectionId;
    this.peerBaseUrl = peerBaseUrl;
    this.peerUsername = peerUsername;
    this.displayName = displayName;
    this.notes = notes;
    this.shared = shared;
    this.status = status;
    this.lastError = lastError;
    this.lastSeenAtMs = lastSeenAtMs;
    this.autoReconnect = autoReconnect;
    this.createdAtMs = createdAtMs;
    this.updatedAtMs = updatedAtMs;
    this.hasPassword = hasPassword;
    this.inbound = inbound;
    this.isOwner = isOwner;
    this.ownerUsername = ownerUsername;
    this.ownerDisplayName = ownerDisplayName;
  }

  /** 状态中文文案 */
  statusText(): string {
    if (this.status === 'connected') {
      return '已连接';
    }
    if (this.status === 'connecting') {
      return '连接中';
    }
    if (this.status === 'error') {
      return '连接失败';
    }
    return '未连接';
  }

  /** 展示名：显示名 > 对端地址 */
  displayTitle(): string {
    return this.displayName === '' ? this.peerBaseUrl : this.displayName;
  }

  /** 归属者展示名（非本人拥有的共享连接时显示） */
  ownerLabel(): string {
    return this.ownerDisplayName !== '' ? this.ownerDisplayName : this.ownerUsername;
  }

  static fromRecord(rec: Record<string, Object>): BridgeConnectionModel {
    return new BridgeConnectionModel(
      JsonHelper.getString(rec, 'connection_id', ''),
      JsonHelper.getString(rec, 'peer_base_url', ''),
      JsonHelper.getString(rec, 'peer_username', ''),
      JsonHelper.getString(rec, 'display_name', ''),
      JsonHelper.getString(rec, 'notes', ''),
      JsonHelper.getBool(rec, 'shared', false),
      JsonHelper.getString(rec, 'status', 'disconnected'),
      JsonHelper.getString(rec, 'last_error', ''),
      JsonHelper.toMs(rec['last_seen_at']),
      JsonHelper.getBool(rec, 'auto_reconnect', false),
      JsonHelper.toMs(rec['created_at']),
      JsonHelper.toMs(rec['updated_at']),
      JsonHelper.getBool(rec, 'has_password', false),
      JsonHelper.getBool(rec, 'inbound', false),
      JsonHelper.getBool(rec, 'is_owner', true),
      JsonHelper.getString(rec, 'owner_username', ''),
      JsonHelper.getString(rec, 'owner_display_name', '')
    );
  }

  static parseList(text: string): Array<BridgeConnectionModel> {
    const result: Array<BridgeConnectionModel> = [];
    const arr = JsonHelper.parseArray(text);
    if (arr === null) {
      return result;
    }
    for (const rec of arr) {
      result.push(BridgeConnectionModel.fromRecord(rec));
    }
    return result;
  }
}

/** 对端探测出的专家摘要（manager._probe_agent_summary） */
export class BridgeProbeAgentModel {
  readonly agentId: string;
  readonly name: string;
  readonly description: string;

  constructor(agentId: string, name: string, description: string) {
    this.agentId = agentId;
    this.name = name;
    this.description = description;
  }

  static fromRecord(rec: Record<string, Object>): BridgeProbeAgentModel {
    return new BridgeProbeAgentModel(
      JsonHelper.getString(rec, 'agent_id', ''),
      JsonHelper.getString(rec, 'name', ''),
      JsonHelper.getString(rec, 'description', '')
    );
  }
}

/** 对端探测结果（POST /api/bridge/probe） */
export class BridgeProbeResultModel {
  readonly peerBaseUrl: string;
  readonly peerUsername: string;
  readonly peerDisplayName: string;
  readonly agentCount: number;
  readonly agents: Array<BridgeProbeAgentModel>;

  constructor(peerBaseUrl: string, peerUsername: string, peerDisplayName: string,
    agentCount: number, agents: Array<BridgeProbeAgentModel>) {
    this.peerBaseUrl = peerBaseUrl;
    this.peerUsername = peerUsername;
    this.peerDisplayName = peerDisplayName;
    this.agentCount = agentCount;
    this.agents = agents;
  }

  static parse(text: string): BridgeProbeResultModel {
    const rec = JsonHelper.parse(text);
    if (rec === null) {
      return new BridgeProbeResultModel('', '', '', 0, []);
    }
    const agents: Array<BridgeProbeAgentModel> = [];
    const agentRecords: Array<Record<string, Object>> = JsonHelper.getRecordArray(rec, 'agents');
    for (const agentRec of agentRecords) {
      agents.push(BridgeProbeAgentModel.fromRecord(agentRec));
    }
    return new BridgeProbeResultModel(
      JsonHelper.getString(rec, 'peer_base_url', ''),
      JsonHelper.getString(rec, 'peer_username', ''),
      JsonHelper.getString(rec, 'peer_display_name', ''),
      JsonHelper.getNumber(rec, 'agent_count', 0),
      agents
    );
  }
}
