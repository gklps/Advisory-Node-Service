'use client'

import { useState } from 'react'
import { useQuery } from '@tanstack/react-query'
import { api } from '@/lib/api'
import type { Quorum } from '@/lib/types'
import { Header } from '@/components/header'
import { GlassCard } from '@/components/glass-card'
import { TableSkeleton } from '@/components/skeleton'
import {
  Search,
  Filter,
  Circle,
  Zap,
  Coins,
  Users,
  Clock,
  Activity
} from 'lucide-react'
import { formatNumber, formatRelativeTime } from '@/lib/utils'
import { motion, AnimatePresence } from 'framer-motion'

export default function QuorumsPage() {
  const [searchTerm, setSearchTerm] = useState('')
  const [statusFilter, setStatusFilter] = useState<'all' | 'online' | 'offline'>('all')
  const [tokenFilter, setTokenFilter] = useState<string>('all')
  const [selectedQuorum, setSelectedQuorum] = useState<Quorum | null>(null)

  // Fetch all quorums
  const { data, isLoading, error, refetch } = useQuery({
    queryKey: ['quorums'],
    queryFn: api.getAllQuorums,
    refetchInterval: 10000, // Refetch every 10 seconds
  })

  // Derive filtered quorums
  const filteredQuorums = data?.quorums?.filter((q) => {
    // Search filter
    const matchesSearch =
      q.did.toLowerCase().includes(searchTerm.toLowerCase()) ||
      q.peer_id.toLowerCase().includes(searchTerm.toLowerCase())

    // Status filter (online = available and pinged within 5 min)
    const isOnline = q.available && new Date(q.last_ping) > new Date(Date.now() - 5 * 60 * 1000)
    const matchesStatus =
      statusFilter === 'all' ||
      (statusFilter === 'online' && isOnline) ||
      (statusFilter === 'offline' && !isOnline)

    // Token filter
    const matchesToken =
      tokenFilter === 'all' ||
      q.supported_tokens?.includes(tokenFilter)

    return matchesSearch && matchesStatus && matchesToken
  }) || []

  // Get unique tokens for filter dropdown
  const allTokens = Array.from(
    new Set(
      data?.quorums?.flatMap((q) => q.supported_tokens || []) || []
    )
  ).sort()

  return (
    <div className="space-y-8">
      <Header
        title="Quorums"
        subtitle="Manage and monitor all registered quorums"
      />

      {/* Stats Bar */}
      <div className="grid grid-cols-1 md:grid-cols-4 gap-4">
        <GlassCard>
          <div className="flex items-center gap-3">
            <div className="p-3 rounded-xl bg-primary-500/20">
              <Users className="w-5 h-5 text-primary-400" />
            </div>
            <div>
              <p className="text-sm text-custom-light font-medium">Total Quorums</p>
              <p className="text-2xl font-bold" style={{color: '#003500'}}>{data?.count || 0}</p>
            </div>
          </div>
        </GlassCard>

        <GlassCard>
          <div className="flex items-center gap-3">
            <div className="p-3 rounded-xl bg-emerald-500/20">
              <Activity className="w-5 h-5 text-emerald-400" />
            </div>
            <div>
              <p className="text-sm text-custom-light font-medium">Online</p>
              <p className="text-2xl font-bold" style={{color: '#003500'}}>
                {filteredQuorums.filter(q =>
                  q.available && new Date(q.last_ping) > new Date(Date.now() - 5 * 60 * 1000)
                ).length}
              </p>
            </div>
          </div>
        </GlassCard>

        <GlassCard>
          <div className="flex items-center gap-3">
            <div className="p-3 rounded-xl bg-amber-500/20">
              <Coins className="w-5 h-5 text-amber-400" />
            </div>
            <div>
              <p className="text-sm text-custom-light font-medium">Total Balance</p>
              <p className="text-2xl font-bold" style={{color: '#003500'}}>
                {formatNumber(
                  data?.quorums?.reduce((sum, q) => sum + q.balance, 0) || 0
                )} RBT
              </p>
            </div>
          </div>
        </GlassCard>

        <GlassCard>
          <div className="flex items-center gap-3">
            <div className="p-3 rounded-xl bg-purple-500/20">
              <Zap className="w-5 h-5 text-purple-400" />
            </div>
            <div>
              <p className="text-sm text-custom-light font-medium">Avg Balance</p>
              <p className="text-2xl font-bold" style={{color: '#003500'}}>
                {formatNumber(
                  data?.quorums && data.quorums.length > 0
                    ? data.quorums.reduce((sum, q) => sum + q.balance, 0) / data.quorums.length
                    : 0
                )} RBT
              </p>
            </div>
          </div>
        </GlassCard>
      </div>

      {/* Search and Filters */}
      <GlassCard>
        <div className="flex flex-col md:flex-row gap-4">
          {/* Search */}
          <div className="flex-1 relative">
            <Search className="absolute left-3 top-1/2 -translate-y-1/2 w-5 h-5" style={{color: '#008800'}} />
            <input
              type="text"
              placeholder="Search by DID or Peer ID..."
              value={searchTerm}
              onChange={(e) => setSearchTerm(e.target.value)}
              className="w-full pl-11 pr-4 py-3 rounded-xl bg-white/5 border border-glass-border focus:outline-none focus:border-primary-400 transition-colors"
              style={{color: '#003500'}}
            />
          </div>

          {/* Status Filter */}
          <div className="relative">
            <Filter className="absolute left-3 top-1/2 -translate-y-1/2 w-5 h-5 pointer-events-none" style={{color: '#008800'}} />
            <select
              value={statusFilter}
              onChange={(e) => setStatusFilter(e.target.value as 'all' | 'online' | 'offline')}
              className="pl-11 pr-8 py-3 rounded-xl bg-white/5 border border-glass-border focus:outline-none focus:border-primary-400 transition-colors appearance-none cursor-pointer min-w-[150px]"
              style={{color: '#003500'}}
            >
              <option value="all">All Status</option>
              <option value="online">Online</option>
              <option value="offline">Offline</option>
            </select>
          </div>

          {/* Token Filter */}
          <div className="relative">
            <Coins className="absolute left-3 top-1/2 -translate-y-1/2 w-5 h-5 pointer-events-none" style={{color: '#008800'}} />
            <select
              value={tokenFilter}
              onChange={(e) => setTokenFilter(e.target.value)}
              className="pl-11 pr-8 py-3 rounded-xl bg-white/5 border border-glass-border focus:outline-none focus:border-primary-400 transition-colors appearance-none cursor-pointer min-w-[150px]"
              style={{color: '#003500'}}
            >
              <option value="all">All Tokens</option>
              {allTokens.map((token) => (
                <option key={token} value={token}>
                  {token}
                </option>
              ))}
            </select>
          </div>
        </div>
      </GlassCard>

      {/* Quorums Table */}
      <GlassCard>
        <div className="flex items-center justify-between mb-6">
          <h3 className="text-xl font-semibold" style={{color: '#003500'}}>
            Registered Quorums ({filteredQuorums.length})
          </h3>
          <button
            onClick={() => refetch()}
            className="glass-button-primary text-sm"
          >
            Refresh
          </button>
        </div>

        {isLoading ? (
          <TableSkeleton rows={5} />
        ) : error ? (
          <div className="text-center py-12">
            <p className="text-rose-400">Failed to load quorums</p>
            <button
              onClick={() => refetch()}
              className="glass-button-primary mt-4"
            >
              Try Again
            </button>
          </div>
        ) : filteredQuorums.length === 0 ? (
          <div className="text-center py-12">
            <Users className="w-12 h-12 mx-auto mb-3" style={{color: '#006600'}} />
            <p style={{color: '#008800'}}>No quorums found</p>
          </div>
        ) : (
          <div className="overflow-x-auto glass-scrollbar">
            <table className="w-full">
              <thead>
                <tr className="border-b border-glass-border text-left">
                  <th className="pb-3 text-sm font-medium text-custom-light" style={{color: '#008800'}}>Status</th>
                  <th className="pb-3 text-sm font-medium text-custom-light" style={{color: '#008800'}}>DID</th>
                  <th className="pb-3 text-sm font-medium text-custom-light" style={{color: '#008800'}}>Peer ID</th>
                  <th className="pb-3 text-sm font-medium text-custom-light" style={{color: '#008800'}}>Balance</th>
                  <th className="pb-3 text-sm font-medium text-custom-light" style={{color: '#008800'}}>Tokens</th>
                  <th className="pb-3 text-sm font-medium text-custom-light" style={{color: '#008800'}}>Assignments</th>
                  <th className="pb-3 text-sm font-medium text-custom-light" style={{color: '#008800'}}>Last Ping</th>
                </tr>
              </thead>
              <tbody>
                <AnimatePresence>
                  {filteredQuorums.map((quorum) => {
                    const isOnline = quorum.available &&
                      new Date(quorum.last_ping) > new Date(Date.now() - 5 * 60 * 1000)

                    return (
                      <motion.tr
                        key={quorum.did}
                        initial={{ opacity: 0, y: 20 }}
                        animate={{ opacity: 1, y: 0 }}
                        exit={{ opacity: 0, y: -20 }}
                        onClick={() => setSelectedQuorum(quorum)}
                        className="border-b border-glass-border/50 hover:bg-white/5 cursor-pointer transition-colors"
                      >
                        <td className="py-4">
                          <div className="flex items-center gap-2">
                            <Circle
                              className={`w-2 h-2 ${
                                isOnline
                                  ? 'text-emerald-400 fill-emerald-400 animate-pulse'
                                  : ''
                              }`}
                              style={!isOnline ? {color: '#006600', fill: '#006600'} : undefined}
                            />
                            <span
                              className={`text-sm ${isOnline ? 'text-emerald-400' : ''}`}
                              style={!isOnline ? {color: '#008800'} : undefined}
                            >
                              {isOnline ? 'Online' : 'Offline'}
                            </span>
                          </div>
                        </td>
                        <td className="py-4 text-sm font-mono max-w-[200px] truncate" style={{color: '#004d00'}}>
                          {quorum.did}
                        </td>
                        <td className="py-4 text-sm font-mono" style={{color: '#004d00'}}>
                          {quorum.peer_id}
                        </td>
                        <td className="py-4 text-sm font-semibold" style={{color: '#003500'}}>
                          {formatNumber(quorum.balance)} RBT
                        </td>
                        <td className="py-4">
                          <div className="flex gap-1">
                            {quorum.supported_tokens?.map((token) => (
                              <span key={token} className="badge-info text-xs">
                                {token}
                              </span>
                            ))}
                          </div>
                        </td>
                        <td className="py-4">
                          <span className="badge-primary">{quorum.assignment_count}</span>
                        </td>
                        <td className="py-4 text-sm flex items-center gap-2" style={{color: '#008800'}}>
                          <Clock className="w-4 h-4" />
                          {formatRelativeTime(quorum.last_ping)}
                        </td>
                      </motion.tr>
                    )
                  })}
                </AnimatePresence>
              </tbody>
            </table>
          </div>
        )}
      </GlassCard>

      {/* Quorum Detail Modal */}
      <AnimatePresence>
        {selectedQuorum && (
          <>
            <motion.div
              initial={{ opacity: 0 }}
              animate={{ opacity: 1 }}
              exit={{ opacity: 0 }}
              className="fixed inset-0 bg-black/50 backdrop-blur-sm z-50"
              onClick={() => setSelectedQuorum(null)}
            />
            <motion.div
              initial={{ opacity: 0, scale: 0.95, y: 20 }}
              animate={{ opacity: 1, scale: 1, y: 0 }}
              exit={{ opacity: 0, scale: 0.95, y: 20 }}
              className="fixed top-1/2 left-1/2 -translate-x-1/2 -translate-y-1/2 w-full max-w-2xl z-50 p-4"
            >
              <GlassCard>
                <div className="flex items-start justify-between mb-6">
                  <div>
                    <h3 className="text-2xl font-bold mb-1" style={{color: '#003500'}}>Quorum Details</h3>
                    <p className="text-sm text-custom-light">Full information and statistics</p>
                  </div>
                  <button
                    onClick={() => setSelectedQuorum(null)}
                    className="glass-button p-2"
                  >
                    ×
                  </button>
                </div>

                <div className="space-y-4">
                  <div>
                    <label className="text-xs text-custom-light uppercase tracking-wider font-medium">DID</label>
                    <p className="font-mono text-sm mt-1 break-all" style={{color: '#003500'}}>{selectedQuorum.did}</p>
                  </div>

                  <div className="grid grid-cols-2 gap-4">
                    <div>
                      <label className="text-xs text-custom-light uppercase tracking-wider font-medium">Peer ID</label>
                      <p className="font-mono text-sm mt-1" style={{color: '#003500'}}>{selectedQuorum.peer_id}</p>
                    </div>
                    <div>
                      <label className="text-xs text-custom-light uppercase tracking-wider font-medium">DID Type</label>
                      <p className="text-sm mt-1" style={{color: '#003500'}}>{selectedQuorum.did_type}</p>
                    </div>
                  </div>

                  <div className="grid grid-cols-2 gap-4">
                    <div>
                      <label className="text-xs text-custom-light uppercase tracking-wider font-medium">Balance</label>
                      <p className="font-semibold text-lg mt-1" style={{color: '#003500'}}>
                        {formatNumber(selectedQuorum.balance)} RBT
                      </p>
                    </div>
                    <div>
                      <label className="text-xs text-custom-light uppercase tracking-wider font-medium">Assignments</label>
                      <p className="font-semibold text-lg mt-1" style={{color: '#003500'}}>
                        {selectedQuorum.assignment_count}
                      </p>
                    </div>
                  </div>

                  <div>
                    <label className="text-xs text-custom-light uppercase tracking-wider font-medium">Supported Tokens</label>
                    <div className="flex gap-2 mt-2">
                      {selectedQuorum.supported_tokens?.map((token) => (
                        <span key={token} className="badge-info">
                          {token}
                        </span>
                      ))}
                    </div>
                  </div>

                  <div className="grid grid-cols-2 gap-4">
                    <div>
                      <label className="text-xs text-custom-light uppercase tracking-wider font-medium">Last Ping</label>
                      <p className="text-sm mt-1" style={{color: '#003500'}}>
                        {formatRelativeTime(selectedQuorum.last_ping)}
                      </p>
                      <p className="text-xs text-custom-light mt-1">
                        {new Date(selectedQuorum.last_ping).toLocaleString()}
                      </p>
                    </div>
                    <div>
                      <label className="text-xs text-custom-light uppercase tracking-wider font-medium">Registered</label>
                      <p className="text-sm mt-1" style={{color: '#003500'}}>
                        {formatRelativeTime(selectedQuorum.registration_time)}
                      </p>
                      <p className="text-xs text-custom-light mt-1">
                        {new Date(selectedQuorum.registration_time).toLocaleString()}
                      </p>
                    </div>
                  </div>

                  {selectedQuorum.last_assignment && selectedQuorum.last_assignment !== '0001-01-01T00:00:00Z' && (
                    <div>
                      <label className="text-xs text-custom-light uppercase tracking-wider font-medium">Last Assignment</label>
                      <p className="text-sm mt-1" style={{color: '#003500'}}>
                        {formatRelativeTime(selectedQuorum.last_assignment)}
                      </p>
                      <p className="text-xs text-custom-light mt-1">
                        {new Date(selectedQuorum.last_assignment).toLocaleString()}
                      </p>
                    </div>
                  )}
                </div>

                <div className="flex gap-3 mt-6 pt-6 border-t border-glass-border">
                  <button
                    onClick={() => setSelectedQuorum(null)}
                    className="glass-button-primary flex-1"
                  >
                    Close
                  </button>
                </div>
              </GlassCard>
            </motion.div>
          </>
        )}
      </AnimatePresence>
    </div>
  )
}
