export interface Quorum {
  did: string
  peer_id: string
  balance: number
  did_type: number
  available: boolean
  last_ping: string
  assignment_count: number
  last_assignment?: string
  registration_time: string
  supported_tokens?: string[]
}

export interface QuorumData {
  type: number
  address: string
}

export interface Transaction {
  ID: number
  TransactionID: string
  TransactionAmount: number
  QuorumDIDs: string
  RequiredBalance: number
  Timestamp: string
  CreatedAt: string
}

export interface HealthStatus {
  status: string
  total_quorums: number
  available_quorums: number
  uptime: string
  last_check: string
}

export interface QuorumListResponse {
  status: boolean
  message: string
  quorums: QuorumData[] | null
}

export interface QuorumInfoResponse {
  status: boolean
  quorum: Quorum
}

export interface TransactionHistoryResponse {
  status: boolean
  history: Transaction[]
}

export interface BasicResponse {
  status: boolean
  message: string
}

// Chart data types
export interface ChartDataPoint {
  name: string
  value: number
  fill?: string
}

export interface BalanceTrendData {
  timestamp: string
  totalBalance: number
  avgBalance: number
  quorumCount: number
}

export interface TokenDistribution {
  token: string
  count: number
  percentage: number
  fill: string
}
