'use client'

import { useState } from 'react'
import { useQuery } from '@tanstack/react-query'
import { api } from '@/lib/api'
import type { Transaction } from '@/lib/types'
import { Header } from '@/components/header'
import { GlassCard } from '@/components/glass-card'
import { TableSkeleton } from '@/components/skeleton'
import {
  Search,
  TrendingUp,
  Database,
  DollarSign,
  Clock,
  Users,
  ArrowUpDown
} from 'lucide-react'
import { formatNumber, formatRelativeTime } from '@/lib/utils'
import { motion, AnimatePresence } from 'framer-motion'

export default function TransactionsPage() {
  const [searchTerm, setSearchTerm] = useState('')
  const [sortBy, setSortBy] = useState<'date' | 'amount'>('date')
  const [sortOrder, setSortOrder] = useState<'asc' | 'desc'>('desc')
  const [selectedTransaction, setSelectedTransaction] = useState<Transaction | null>(null)

  // Fetch transactions
  const { data, isLoading, error, refetch } = useQuery({
    queryKey: ['transactions', 'all'],
    queryFn: () => api.getTransactionHistory(500),
    refetchInterval: 15000, // Refetch every 15 seconds
  })

  // Derive filtered and sorted transactions
  const processedTransactions = data?.history
    ?.filter((tx) =>
      tx.TransactionID.toLowerCase().includes(searchTerm.toLowerCase())
    )
    .sort((a, b) => {
      const multiplier = sortOrder === 'asc' ? 1 : -1
      if (sortBy === 'amount') {
        return multiplier * (a.TransactionAmount - b.TransactionAmount)
      }
      // Sort by date
      return multiplier * (new Date(a.Timestamp).getTime() - new Date(b.Timestamp).getTime())
    }) || []

  // Calculate stats
  const totalVolume = data?.history?.reduce((sum, tx) => sum + tx.TransactionAmount, 0) || 0
  const avgTransaction = data?.history && data.history.length > 0
    ? totalVolume / data.history.length
    : 0
  const totalQuorums = data?.history?.reduce((sum, tx) => {
    try {
      const quorums = JSON.parse(tx.QuorumDIDs)
      return sum + quorums.length
    } catch {
      return sum
    }
  }, 0) || 0

  const toggleSort = (field: 'date' | 'amount') => {
    if (sortBy === field) {
      setSortOrder(sortOrder === 'asc' ? 'desc' : 'asc')
    } else {
      setSortBy(field)
      setSortOrder('desc')
    }
  }

  return (
    <div className="space-y-5">
      <Header
        title="Transactions"
        subtitle="Complete transaction history and analytics"
      />

      {/* Stats Bar */}
      <div className="grid grid-cols-1 md:grid-cols-[1fr_1fr_1fr_0.7fr] gap-4">
        <GlassCard>
          <div className="flex items-center gap-3">
            <div className="p-3 rounded-xl bg-purple-500/20">
              <Database className="w-5 h-5 text-purple-400" />
            </div>
            <div>
              <p className="text-sm text-custom-light font-medium">Total Transactions</p>
              <p className="text-2xl font-bold" style={{color: '#003500'}}>{data?.history?.length || 0}</p>
            </div>
          </div>
        </GlassCard>

        <GlassCard>
          <div className="flex items-center gap-3">
            <div className="p-3 rounded-xl bg-amber-500/20">
              <DollarSign className="w-5 h-5 text-amber-400" />
            </div>
            <div>
              <p className="text-sm text-custom-light font-medium">Total Volume</p>
              <p className="text-2xl font-bold" style={{color: '#003500'}}>
                {formatNumber(totalVolume)} RBT
              </p>
            </div>
          </div>
        </GlassCard>

        <GlassCard>
          <div className="flex items-center gap-3">
            <div className="p-3 rounded-xl bg-emerald-500/20">
              <TrendingUp className="w-5 h-5 text-emerald-400" />
            </div>
            <div>
              <p className="text-sm text-custom-light font-medium">Avg Transaction</p>
              <p className="text-2xl font-bold" style={{color: '#003500'}}>
                {formatNumber(avgTransaction)} RBT
              </p>
            </div>
          </div>
        </GlassCard>

        <GlassCard>
          <div className="flex items-center gap-3">
            <div className="p-3 rounded-xl bg-primary-500/20">
              <Users className="w-5 h-5 text-primary-400" />
            </div>
            <div>
              <p className="text-sm text-custom-light font-medium">Total Quorums</p>
              <p className="text-2xl font-bold" style={{color: '#003500'}}>{totalQuorums}</p>
            </div>
          </div>
        </GlassCard>
      </div>

      {/* Search and Controls */}
      <GlassCard>
        <div className="flex flex-col md:flex-row gap-4">
          {/* Search */}
          <div className="flex-1 relative">
            <Search className="absolute left-3 top-1/2 -translate-y-1/2 w-5 h-5" style={{color: '#008800'}} />
            <input
              type="text"
              placeholder="Search by Transaction ID..."
              value={searchTerm}
              onChange={(e) => setSearchTerm(e.target.value)}
              className="w-full pl-11 pr-4 py-3 rounded-xl bg-white/5 border border-glass-border focus:outline-none focus:border-primary-400 transition-colors"
              style={{color: '#003500'}}
            />
          </div>

          {/* Sort Controls */}
          <div className="flex gap-2">
            <button
              onClick={() => toggleSort('date')}
              className={`flex items-center gap-2 px-4 py-3 rounded-xl transition-all ${
                sortBy === 'date'
                  ? 'glass-button-primary'
                  : 'glass-button hover:bg-white/10'
              }`}
            >
              <Clock className="w-4 h-4" />
              Date
              {sortBy === 'date' && (
                <ArrowUpDown className="w-3 h-3" />
              )}
            </button>
            <button
              onClick={() => toggleSort('amount')}
              className={`flex items-center gap-2 px-4 py-3 rounded-xl transition-all ${
                sortBy === 'amount'
                  ? 'glass-button-primary'
                  : 'glass-button hover:bg-white/10'
              }`}
            >
              <DollarSign className="w-4 h-4" />
              Amount
              {sortBy === 'amount' && (
                <ArrowUpDown className="w-3 h-3" />
              )}
            </button>
          </div>
        </div>
      </GlassCard>

      {/* Transactions Table */}
      <GlassCard>
        <div className="flex items-center justify-between mb-6">
          <h3 className="text-xl font-semibold" style={{color: '#003500'}}>
            Transaction History ({processedTransactions.length})
          </h3>
          <button
            onClick={() => refetch()}
            className="glass-button-primary text-sm"
          >
            Refresh
          </button>
        </div>

        {isLoading ? (
          <TableSkeleton rows={10} />
        ) : error ? (
          <div className="text-center py-12">
            <p className="text-rose-400">Failed to load transactions</p>
            <button
              onClick={() => refetch()}
              className="glass-button-primary mt-4"
            >
              Try Again
            </button>
          </div>
        ) : processedTransactions.length === 0 ? (
          <div className="text-center py-12">
            <Database className="w-12 h-12 mx-auto mb-3" style={{color: '#006600'}} />
            <p style={{color: '#008800'}}>No transactions found</p>
          </div>
        ) : (
          <>
            {/* Mobile Card View */}
            <div className="block md:hidden space-y-3">
              <AnimatePresence>
                {processedTransactions.map((tx) => {
                  let quorumDIDs: string[] = []
                  try {
                    quorumDIDs = JSON.parse(tx.QuorumDIDs)
                  } catch {
                    quorumDIDs = []
                  }

                  return (
                    <motion.div
                      key={tx.ID}
                      initial={{ opacity: 0, y: 20 }}
                      animate={{ opacity: 1, y: 0 }}
                      exit={{ opacity: 0, y: -20 }}
                      onClick={() => setSelectedTransaction(tx)}
                      className="glass-card p-4 hover:bg-white/10 transition-colors cursor-pointer"
                    >
                      <div className="flex justify-between items-start mb-3">
                        <div className="flex-1 min-w-0">
                          <p className="text-xs mb-1 font-medium" style={{color: '#008800'}}>Transaction ID</p>
                          <p className="text-sm font-mono truncate" style={{color: '#004d00'}}>
                            {tx.TransactionID}
                          </p>
                        </div>
                        <span className="badge-info ml-2 flex-shrink-0">{quorumDIDs.length}</span>
                      </div>

                      <div className="grid grid-cols-2 gap-3 mb-2">
                        <div>
                          <p className="text-xs mb-1 font-medium" style={{color: '#008800'}}>Amount</p>
                          <p className="text-base font-bold" style={{color: '#003500'}}>
                            {formatNumber(tx.TransactionAmount)} RBT
                          </p>
                        </div>
                        <div>
                          <p className="text-xs mb-1 font-medium" style={{color: '#008800'}}>Required</p>
                          <p className="text-sm font-semibold" style={{color: '#004d00'}}>
                            {formatNumber(tx.RequiredBalance)} RBT
                          </p>
                        </div>
                      </div>

                      <div className="flex items-center justify-between pt-2 border-t border-glass-border/30">
                        <div className="flex items-center gap-2">
                          <Clock className="w-3 h-3" style={{color: '#008800'}} />
                          <p className="text-xs" style={{color: '#006600'}}>
                            {formatRelativeTime(tx.Timestamp)}
                          </p>
                        </div>
                      </div>
                    </motion.div>
                  )
                })}
              </AnimatePresence>
            </div>

            {/* Desktop Table View */}
            <div className="hidden md:block overflow-x-auto glass-scrollbar">
              <table className="w-full">
                <thead>
                  <tr className="border-b border-glass-border text-left">
                    <th className="pb-3 text-sm font-medium" style={{color: '#008800'}}>Transaction ID</th>
                    <th className="pb-3 text-sm font-medium" style={{color: '#008800'}}>Amount</th>
                    <th className="pb-3 text-sm font-medium" style={{color: '#008800'}}>Required Balance</th>
                    <th className="pb-3 text-sm font-medium" style={{color: '#008800'}}>Quorums</th>
                    <th className="pb-3 text-sm font-medium" style={{color: '#008800'}}>Timestamp</th>
                  </tr>
                </thead>
                <tbody>
                  <AnimatePresence>
                    {processedTransactions.map((tx) => {
                      let quorumDIDs: string[] = []
                      try {
                        quorumDIDs = JSON.parse(tx.QuorumDIDs)
                      } catch {
                        quorumDIDs = []
                      }

                      return (
                        <motion.tr
                          key={tx.ID}
                          initial={{ opacity: 0, y: 20 }}
                          animate={{ opacity: 1, y: 0 }}
                          exit={{ opacity: 0, y: -20 }}
                          onClick={() => setSelectedTransaction(tx)}
                          className="border-b border-glass-border/50 hover:bg-white/5 cursor-pointer transition-colors"
                        >
                          <td className="py-4 text-sm font-mono max-w-[300px] truncate" style={{color: '#006600'}}>
                            {tx.TransactionID}
                          </td>
                          <td className="py-4 text-sm font-semibold" style={{color: '#003500'}}>
                            {formatNumber(tx.TransactionAmount)} RBT
                        </td>
                        <td className="py-4 text-sm" style={{color: '#006600'}}>
                          {formatNumber(tx.RequiredBalance)} RBT
                        </td>
                        <td className="py-4">
                          <span className="badge-info">{quorumDIDs.length} quorums</span>
                        </td>
                        <td className="py-4 text-sm flex items-center gap-2" style={{color: '#008800'}}>
                          <Clock className="w-4 h-4" />
                          {formatRelativeTime(tx.Timestamp)}
                        </td>
                      </motion.tr>
                    )
                    })}
                  </AnimatePresence>
                </tbody>
              </table>
            </div>
          </>
        )}
      </GlassCard>

      {/* Transaction Detail Modal */}
      <AnimatePresence>
        {selectedTransaction && (
          <>
            <motion.div
              initial={{ opacity: 0 }}
              animate={{ opacity: 1 }}
              exit={{ opacity: 0 }}
              className="fixed inset-0 bg-black/50 backdrop-blur-sm z-50"
              onClick={() => setSelectedTransaction(null)}
            />
            <motion.div
              initial={{ opacity: 0, scale: 0.95, y: 20 }}
              animate={{ opacity: 1, scale: 1, y: 0 }}
              exit={{ opacity: 0, scale: 0.95, y: 20 }}
              className="fixed top-1/2 left-1/2 -translate-x-1/2 -translate-y-1/2 w-full max-w-3xl z-50 p-4 max-h-[90vh] overflow-y-auto"
            >
              <GlassCard>
                <div className="flex items-start justify-between mb-6">
                  <div>
                    <h3 className="text-2xl font-bold mb-1" style={{color: '#003500'}}>Transaction Details</h3>
                    <p className="text-sm text-custom-light">Complete transaction information</p>
                  </div>
                  <button
                    onClick={() => setSelectedTransaction(null)}
                    className="glass-button p-2"
                  >
                    ×
                  </button>
                </div>

                <div className="space-y-4">
                  <div>
                    <label className="text-xs text-custom-light uppercase tracking-wider font-medium">Transaction ID</label>
                    <p className="font-mono text-sm mt-1 break-all" style={{color: '#003500'}}>
                      {selectedTransaction.TransactionID}
                    </p>
                  </div>

                  <div className="grid grid-cols-2 gap-4">
                    <div>
                      <label className="text-xs text-custom-light uppercase tracking-wider font-medium">Amount</label>
                      <p className="font-semibold text-xl mt-1" style={{color: '#003500'}}>
                        {formatNumber(selectedTransaction.TransactionAmount)} RBT
                      </p>
                    </div>
                    <div>
                      <label className="text-xs text-custom-light uppercase tracking-wider font-medium">Required Balance</label>
                      <p className="font-semibold text-xl mt-1" style={{color: '#003500'}}>
                        {formatNumber(selectedTransaction.RequiredBalance)} RBT
                      </p>
                    </div>
                  </div>

                  <div>
                    <label className="text-xs text-custom-light uppercase tracking-wider font-medium">Timestamp</label>
                    <p className="text-sm mt-1" style={{color: '#003500'}}>
                      {formatRelativeTime(selectedTransaction.Timestamp)}
                    </p>
                    <p className="text-xs text-custom-light mt-1">
                      {new Date(selectedTransaction.Timestamp).toLocaleString()}
                    </p>
                  </div>

                  <div>
                    <label className="text-xs text-custom-light uppercase tracking-wider mb-2 block font-medium">
                      Assigned Quorums ({JSON.parse(selectedTransaction.QuorumDIDs).length})
                    </label>
                    <div className="space-y-2 max-h-64 overflow-y-auto glass-scrollbar">
                      {JSON.parse(selectedTransaction.QuorumDIDs).map((did: string, idx: number) => (
                        <div
                          key={idx}
                          className="glass-card p-3 hover:bg-white/10 transition-colors"
                        >
                          <div className="flex items-center justify-between">
                            <div>
                              <p className="text-xs text-custom-light font-medium">Quorum {idx + 1}</p>
                              <p className="text-sm font-mono mt-1 break-all" style={{color: '#003500'}}>{did}</p>
                            </div>
                          </div>
                        </div>
                      ))}
                    </div>
                  </div>
                </div>

                <div className="flex gap-3 mt-6 pt-6 border-t border-glass-border">
                  <button
                    onClick={() => setSelectedTransaction(null)}
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
