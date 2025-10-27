'use client'

import { useQuery } from '@tanstack/react-query'
import { api } from '@/lib/api'
import { StatCard } from '@/components/stat-card'
import { GlassCard } from '@/components/glass-card'
import {
  Activity,
  Database,
  TrendingUp,
  Users,
  DollarSign,
  Zap,
} from 'lucide-react'
import { BarChart, Bar, XAxis, YAxis, CartesianGrid, Tooltip, ResponsiveContainer, PieChart, Pie, Cell, LineChart, Line } from 'recharts'
import { formatNumber, formatRelativeTime } from '@/lib/utils'
import { motion } from 'framer-motion'

import { Header } from '@/components/header'

export default function DashboardPage() {
  // Fetch data with React Query
  const { data: health } = useQuery({
    queryKey: ['health'],
    queryFn: api.getHealth,
    refetchInterval: 5000, // Refetch every 5 seconds
  })

  const { data: transactions } = useQuery({
    queryKey: ['transactions'],
    queryFn: () => api.getTransactionHistory(50),
  })

  // Calculate metrics
  const totalBalance = transactions?.history
    ? transactions.history.reduce((sum, tx) => sum + tx.TransactionAmount, 0)
    : 0

  const avgTransactionAmount = transactions?.history?.length
    ? totalBalance / transactions.history.length
    : 0

  // Prepare chart data
  const recentTransactions = transactions?.history?.slice(0, 10).reverse() || []
  const transactionChartData = recentTransactions.map((tx, idx) => ({
    name: `T${idx + 1}`,
    amount: tx.TransactionAmount,
    required: tx.RequiredBalance,
  }))

  // Token distribution (mock data for now - would need to fetch quorum details)
  const tokenDistribution = [
    { name: 'RBT', value: health?.total_quorums ? Math.floor(health.total_quorums * 0.6) : 0, fill: '#ffe314' },
    { name: 'TRI', value: health?.total_quorums ? Math.floor(health.total_quorums * 0.3) : 0, fill: '#a855f7' },
    { name: 'Other', value: health?.total_quorums ? Math.floor(health.total_quorums * 0.1) : 0, fill: '#10b981' },
  ]

  return (
    <div className="space-y-8">
      <Header
        title="Overview"
        subtitle="Real-time monitoring and analytics for quorum management"
      />

        {/* Stats Grid */}
        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
          <StatCard
            title="Total Quorums"
            value={health?.total_quorums || 0}
            icon={Users}
            color="primary"
          />
          <StatCard
            title="Available Quorums"
            value={health?.available_quorums || 0}
            icon={Activity}
            color="emerald"
          />
          <StatCard
            title="Total Transactions"
            value={transactions?.history?.length || 0}
            icon={Database}
            color="purple"
          />
          <StatCard
            title="Total Volume"
            value={`${formatNumber(totalBalance)} RBT`}
            icon={DollarSign}
            color="amber"
          />
          <StatCard
            title="Avg Transaction"
            value={`${formatNumber(avgTransactionAmount)} RBT`}
            icon={TrendingUp}
            color="rose"
          />
          <StatCard
            title="System Status"
            value={health?.status === 'healthy' ? 'Healthy' : 'Degraded'}
            icon={Zap}
            color={health?.status === 'healthy' ? 'emerald' : 'rose'}
          />
        </div>

        {/* Charts Section */}
        <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
          {/* Transaction Volume Chart */}
          <GlassCard>
            <h3 className="text-xl font-semibold mb-6" style={{color: '#003500'}}>Recent Transaction Volume</h3>
            <ResponsiveContainer width="100%" height={300}>
              <BarChart data={transactionChartData}>
                <CartesianGrid strokeDasharray="3 3" stroke="rgba(0,53,0,0.1)" />
                <XAxis dataKey="name" stroke="rgba(0,53,0,0.5)" />
                <YAxis stroke="rgba(0,53,0,0.5)" />
                <Tooltip
                  contentStyle={{
                    backgroundColor: 'rgba(15, 23, 42, 0.9)',
                    border: '1px solid rgba(255,255,255,0.1)',
                    borderRadius: '8px',
                    backdropFilter: 'blur(12px)',
                  }}
                />
                <Bar dataKey="amount" fill="#ffe314" radius={[8, 8, 0, 0]} />
              </BarChart>
            </ResponsiveContainer>
          </GlassCard>

          {/* Token Distribution */}
          <GlassCard>
            <h3 className="text-xl font-semibold mb-6" style={{color: '#003500'}}>Token Distribution</h3>
            <ResponsiveContainer width="100%" height={300}>
              <PieChart>
                <Pie
                  data={tokenDistribution}
                  cx="50%"
                  cy="50%"
                  labelLine={false}
                  label={({ name, percent }) => `${name} ${(Number(percent) * 100).toFixed(0)}%`}
                  outerRadius={100}
                  fill="#8884d8"
                  dataKey="value"
                >
                  {tokenDistribution.map((entry, index) => (
                    <Cell key={`cell-${index}`} fill={entry.fill} />
                  ))}
                </Pie>
                <Tooltip
                  contentStyle={{
                    backgroundColor: 'rgba(15, 23, 42, 0.9)',
                    border: '1px solid rgba(255,255,255,0.1)',
                    borderRadius: '8px',
                    backdropFilter: 'blur(12px)',
                  }}
                />
              </PieChart>
            </ResponsiveContainer>
          </GlassCard>
        </div>

        {/* Recent Transactions */}
        <GlassCard>
          <h3 className="text-lg sm:text-xl font-semibold mb-4 sm:mb-6" style={{color: '#003500'}}>Recent Transactions</h3>

          {/* Mobile Card View */}
          <div className="block md:hidden space-y-3">
            {transactions?.history?.slice(0, 10).map((tx) => {
              const quorumDIDs = JSON.parse(tx.QuorumDIDs)
              return (
                <div key={tx.ID} className="glass-card p-4 hover:bg-white/10 transition-colors">
                  <div className="flex justify-between items-start mb-3">
                    <div className="flex-1 min-w-0">
                      <p className="text-xs text-custom-light mb-1 font-medium">Transaction ID</p>
                      <p className="text-sm font-mono truncate" style={{color: '#004d00'}}>
                        {tx.TransactionID}
                      </p>
                    </div>
                    <span className="badge-info ml-2 flex-shrink-0">{quorumDIDs.length}</span>
                  </div>

                  <div className="grid grid-cols-2 gap-3 mb-2">
                    <div>
                      <p className="text-xs text-custom-light mb-1 font-medium">Amount</p>
                      <p className="text-base font-bold" style={{color: '#003500'}}>
                        {formatNumber(tx.TransactionAmount)} RBT
                      </p>
                    </div>
                    <div>
                      <p className="text-xs text-custom-light mb-1 font-medium">Required</p>
                      <p className="text-sm font-semibold" style={{color: '#004d00'}}>
                        {formatNumber(tx.RequiredBalance)} RBT
                      </p>
                    </div>
                  </div>

                  <div className="flex items-center justify-between pt-2 border-t border-glass-border/30">
                    <p className="text-xs text-custom-light">
                      {formatRelativeTime(tx.Timestamp)}
                    </p>
                  </div>
                </div>
              )
            })}
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
                  <th className="pb-3 text-sm font-medium" style={{color: '#008800'}}>Time</th>
                </tr>
              </thead>
              <tbody>
                {transactions?.history?.slice(0, 10).map((tx) => {
                  const quorumDIDs = JSON.parse(tx.QuorumDIDs)
                  return (
                    <tr key={tx.ID} className="border-b border-glass-border/50 hover:bg-white/5 transition-colors">
                      <td className="py-4 text-sm font-mono" style={{color: '#006600'}}>
                        {tx.TransactionID.substring(0, 20)}...
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
                      <td className="py-4 text-sm" style={{color: '#008800'}}>
                        {formatRelativeTime(tx.Timestamp)}
                      </td>
                    </tr>
                  )
                })}
              </tbody>
            </table>
          </div>
        </GlassCard>

    </div>
  )
}
