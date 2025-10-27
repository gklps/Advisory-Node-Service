import type {
  HealthStatus,
  QuorumListResponse,
  QuorumInfoResponse,
  TransactionHistoryResponse,
  Quorum,
} from './types'

// Get API base URL from localStorage or use default
function getApiBase(): string {
  if (typeof window === 'undefined') {
    // Server-side: use localhost for SSR
    return 'http://localhost:8082/api'
  }

  const savedNetwork = localStorage.getItem('network') as 'mainnet' | 'testnet' | null
  const savedEndpoint = localStorage.getItem('apiEndpoint')

  // If custom endpoint is saved, use it
  if (savedEndpoint) {
    return savedEndpoint.endsWith('/') ? savedEndpoint + 'api' : savedEndpoint + '/api'
  }

  // Use network-based endpoint
  if (savedNetwork === 'mainnet') {
    return 'https://mainnet-pool.universe.rubix.net/api'
  } else if (savedNetwork === 'testnet') {
    return 'https://testnet-pool.universe.rubix.net/api'
  }

  // Default to mainnet for production
  return 'https://mainnet-pool.universe.rubix.net/api'
}

export const api = {
  // Health endpoint
  async getHealth(): Promise<HealthStatus> {
    const res = await fetch(`${getApiBase()}/quorum/health`, {
      cache: 'no-store',
    })
    if (!res.ok) throw new Error('Failed to fetch health status')
    return res.json()
  },

  // Get available quorums
  async getAvailableQuorums(
    count: number,
    transactionAmount: number,
    ftName?: string
  ): Promise<QuorumListResponse> {
    const params = new URLSearchParams({
      count: count.toString(),
      transaction_amount: transactionAmount.toString(),
    })
    if (ftName) params.append('ft_name', ftName)

    const res = await fetch(`${getApiBase()}/quorum/available?${params}`, {
      cache: 'no-store',
    })
    if (!res.ok) throw new Error('Failed to fetch available quorums')
    return res.json()
  },

  // Get quorum info
  async getQuorumInfo(did: string): Promise<QuorumInfoResponse> {
    const res = await fetch(`${getApiBase()}/quorum/info/${did}`, {
      cache: 'no-store',
    })
    if (!res.ok) throw new Error('Failed to fetch quorum info')
    return res.json()
  },

  // Get all quorums
  async getAllQuorums(): Promise<{ status: boolean; quorums: Quorum[]; count: number }> {
    const res = await fetch(`${getApiBase()}/quorum/list`, {
      cache: 'no-store',
    })
    if (!res.ok) throw new Error('Failed to fetch quorums')
    return res.json()
  },

  // Get transaction history
  async getTransactionHistory(limit = 100): Promise<TransactionHistoryResponse> {
    const res = await fetch(`${getApiBase()}/quorum/transactions?limit=${limit}`, {
      cache: 'no-store',
    })
    if (!res.ok) throw new Error('Failed to fetch transaction history')
    return res.json()
  },

  // Register quorum
  async registerQuorum(data: {
    did: string
    peer_id: string
    balance: number
    did_type: number
    supported_tokens?: string[]
  }) {
    const res = await fetch(`${getApiBase()}/quorum/register`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(data),
      cache: 'no-store',
    })
    if (!res.ok) throw new Error('Failed to register quorum')
    return res.json()
  },

  // Update balance
  async updateBalance(did: string, balance: number) {
    const res = await fetch(`${getApiBase()}/quorum/balance`, {
      method: 'PUT',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ did, balance }),
      cache: 'no-store',
    })
    if (!res.ok) throw new Error('Failed to update balance')
    return res.json()
  },

  // Send heartbeat
  async sendHeartbeat(did: string) {
    const res = await fetch(`${getApiBase()}/quorum/heartbeat`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ did }),
      cache: 'no-store',
    })
    if (!res.ok) throw new Error('Failed to send heartbeat')
    return res.json()
  },
}
