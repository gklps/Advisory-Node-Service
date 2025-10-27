'use client'

import { useQuery } from '@tanstack/react-query'
import { api } from '@/lib/api'
import { Header } from '@/components/header'
import { GlassCard } from '@/components/glass-card'
import { CardSkeleton } from '@/components/skeleton'
import {
  BarChart,
  Bar,
  LineChart,
  Line,
  PieChart,
  Pie,
  Cell,
  XAxis,
  YAxis,
  CartesianGrid,
  Tooltip,
  ResponsiveContainer,
  Legend,
  Area,
  AreaChart
} from 'recharts'
import { formatNumber } from '@/lib/utils'

export default function AnalyticsPage() {
  // Fetch data
  const { data: quorums } = useQuery({
    queryKey: ['quorums'],
    queryFn: api.getAllQuorums,
    refetchInterval: 15000,
  })

  const { data: transactions } = useQuery({
    queryKey: ['transactions', 'analytics'],
    queryFn: () => api.getTransactionHistory(200),
    refetchInterval: 15000,
  })

  // Token distribution
  const tokenStats = quorums?.quorums?.reduce((acc, q) => {
    q.supported_tokens?.forEach((token) => {
      if (!acc[token]) {
        acc[token] = { count: 0, totalBalance: 0 }
      }
      acc[token].count++
      acc[token].totalBalance += q.balance
    })
    return acc
  }, {} as Record<string, { count: number; totalBalance: number }>) || {}

  const tokenDistribution = Object.entries(tokenStats).map(([token, stats], idx) => ({
    name: token,
    count: stats.count,
    balance: stats.totalBalance,
    fill: ['#ffe314', '#10b981', '#007700', '#d9bf11'][idx % 4]
  }))

  // Balance distribution
  const balanceRanges = [
    { range: '0-20', min: 0, max: 20, count: 0 },
    { range: '20-40', min: 20, max: 40, count: 0 },
    { range: '40-60', min: 40, max: 60, count: 0 },
    { range: '60+', min: 60, max: Infinity, count: 0 },
  ]

  quorums?.quorums?.forEach((q) => {
    const range = balanceRanges.find(r => q.balance >= r.min && q.balance < r.max)
    if (range) range.count++
  })

  // Transaction volume over time (group by hour for recent transactions)
  const txByTime: Record<string, { amount: number; count: number }> = {}

  transactions?.history?.forEach((tx) => {
    const date = new Date(tx.Timestamp)
    const hour = `${date.getHours()}:00`
    if (!txByTime[hour]) {
      txByTime[hour] = { amount: 0, count: 0 }
    }
    txByTime[hour].amount += tx.TransactionAmount
    txByTime[hour].count++
  })

  const volumeData = Object.entries(txByTime)
    .map(([hour, data]) => ({
      hour,
      amount: data.amount,
      count: data.count
    }))
    .sort((a, b) => parseInt(a.hour) - parseInt(b.hour))

  // Top quorums by assignments
  const topQuorums = [...(quorums?.quorums || [])]
    .sort((a, b) => b.assignment_count - a.assignment_count)
    .slice(0, 10)
    .map((q) => ({
      did: q.did.substring(0, 15) + '...',
      fullDid: q.did,
      assignments: q.assignment_count,
      balance: q.balance
    }))

  // Quorum status distribution
  const now = Date.now()
  const statusData = [
    {
      name: 'Online',
      value: quorums?.quorums?.filter(q =>
        q.available && new Date(q.last_ping) > new Date(now - 5 * 60 * 1000)
      ).length || 0,
      fill: '#10b981'
    },
    {
      name: 'Offline',
      value: quorums?.quorums?.filter(q =>
        !q.available || new Date(q.last_ping) <= new Date(now - 5 * 60 * 1000)
      ).length || 0,
      fill: '#64748b'
    }
  ]

  return (
    <div className="space-y-8">
      <Header
        title="Analytics"
        subtitle="Advanced insights and data visualization"
      />

      {/* Token Distribution */}
      <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
        <GlassCard>
          <h3 className="text-xl font-semibold mb-6" style={{color: '#003500'}}>Token Distribution by Count</h3>
          {!quorums ? (
            <CardSkeleton />
          ) : (
            <ResponsiveContainer width="100%" height={300}>
              <PieChart>
                <Pie
                  data={tokenDistribution}
                  cx="50%"
                  cy="50%"
                  labelLine={false}
                  label={(entry) => {
                    return (
                      <text
                        x={entry.x}
                        y={entry.y}
                        fill="#ffffff"
                        textAnchor={entry.x > entry.cx ? 'start' : 'end'}
                        dominantBaseline="central"
                        fontSize="14"
                        fontWeight="600"
                      >
                        {`${entry.name}: ${entry.count}`}
                      </text>
                    )
                  }}
                  outerRadius={100}
                  fill="#8884d8"
                  dataKey="count"
                >
                  {tokenDistribution.map((entry, index) => (
                    <Cell key={`cell-${index}`} fill={entry.fill} />
                  ))}
                </Pie>
                <Tooltip
                  contentStyle={{
                    backgroundColor: 'rgba(15, 23, 42, 0.95)',
                    border: '1px solid rgba(255,255,255,0.2)',
                    borderRadius: '8px',
                    backdropFilter: 'blur(12px)',
                    color: '#ffffff',
                  }}
                  itemStyle={{
                    color: '#ffffff',
                  }}
                  labelStyle={{
                    color: '#cbd5e1',
                  }}
                />
              </PieChart>
            </ResponsiveContainer>
          )}
        </GlassCard>

        <GlassCard>
          <h3 className="text-xl font-semibold mb-6" style={{color: '#003500'}}>Quorum Status</h3>
          {!quorums ? (
            <CardSkeleton />
          ) : (
            <ResponsiveContainer width="100%" height={300}>
              <PieChart>
                <Pie
                  data={statusData}
                  cx="50%"
                  cy="50%"
                  labelLine={false}
                  label={(entry) => {
                    return (
                      <text
                        x={entry.x}
                        y={entry.y}
                        fill="#ffffff"
                        textAnchor={entry.x > entry.cx ? 'start' : 'end'}
                        dominantBaseline="central"
                        fontSize="14"
                        fontWeight="600"
                      >
                        {`${entry.name}: ${entry.value}`}
                      </text>
                    )
                  }}
                  outerRadius={100}
                  fill="#8884d8"
                  dataKey="value"
                >
                  {statusData.map((entry, index) => (
                    <Cell key={`cell-${index}`} fill={entry.fill} />
                  ))}
                </Pie>
                <Tooltip
                  contentStyle={{
                    backgroundColor: 'rgba(15, 23, 42, 0.95)',
                    border: '1px solid rgba(255,255,255,0.2)',
                    borderRadius: '8px',
                    backdropFilter: 'blur(12px)',
                    color: '#ffffff',
                  }}
                  itemStyle={{
                    color: '#ffffff',
                  }}
                  labelStyle={{
                    color: '#cbd5e1',
                  }}
                />
              </PieChart>
            </ResponsiveContainer>
          )}
        </GlassCard>
      </div>

      {/* Balance Distribution */}
      <GlassCard>
        <h3 className="text-xl font-semibold mb-6" style={{color: '#003500'}}>Balance Distribution (RBT)</h3>
        {!quorums ? (
          <CardSkeleton />
        ) : (
          <ResponsiveContainer width="100%" height={300}>
            <BarChart data={balanceRanges}>
              <CartesianGrid strokeDasharray="3 3" stroke="rgba(0,53,0,0.1)" />
              <XAxis dataKey="range" stroke="rgba(0,53,0,0.5)" />
              <YAxis stroke="rgba(0,53,0,0.5)" />
              <Tooltip
                contentStyle={{
                  backgroundColor: 'rgba(15, 23, 42, 0.9)',
                  border: '1px solid rgba(255,255,255,0.1)',
                  borderRadius: '8px',
                  backdropFilter: 'blur(12px)',
                }}
              />
              <Bar dataKey="count" fill="#ffe314" radius={[8, 8, 0, 0]} />
            </BarChart>
          </ResponsiveContainer>
        )}
      </GlassCard>

      {/* Transaction Volume Over Time */}
      <GlassCard>
        <h3 className="text-xl font-semibold mb-6" style={{color: '#003500'}}>Transaction Volume by Hour</h3>
        {!transactions ? (
          <CardSkeleton />
        ) : (
          <ResponsiveContainer width="100%" height={300}>
            <AreaChart data={volumeData}>
              <defs>
                <linearGradient id="colorAmount" x1="0" y1="0" x2="0" y2="1">
                  <stop offset="5%" stopColor="#ffe314" stopOpacity={0.8}/>
                  <stop offset="95%" stopColor="#ffe314" stopOpacity={0}/>
                </linearGradient>
              </defs>
              <CartesianGrid strokeDasharray="3 3" stroke="rgba(0,53,0,0.1)" />
              <XAxis dataKey="hour" stroke="rgba(0,53,0,0.5)" />
              <YAxis stroke="rgba(0,53,0,0.5)" />
              <Tooltip
                contentStyle={{
                  backgroundColor: 'rgba(15, 23, 42, 0.9)',
                  border: '1px solid rgba(255,255,255,0.1)',
                  borderRadius: '8px',
                  backdropFilter: 'blur(12px)',
                }}
              />
              <Area
                type="monotone"
                dataKey="amount"
                stroke="#ffe314"
                fillOpacity={1}
                fill="url(#colorAmount)"
              />
            </AreaChart>
          </ResponsiveContainer>
        )}
      </GlassCard>

      {/* Top Quorums by Assignments */}
      <GlassCard>
        <h3 className="text-xl font-semibold mb-6" style={{color: '#003500'}}>Top Quorums by Assignments</h3>
        {!quorums ? (
          <CardSkeleton />
        ) : (
          <ResponsiveContainer width="100%" height={400}>
            <BarChart data={topQuorums} layout="vertical">
              <CartesianGrid strokeDasharray="3 3" stroke="rgba(0,53,0,0.1)" />
              <XAxis type="number" stroke="rgba(0,53,0,0.5)" />
              <YAxis
                type="category"
                dataKey="did"
                stroke="rgba(0,53,0,0.5)"
                width={120}
              />
              <Tooltip
                contentStyle={{
                  backgroundColor: 'transparent',
                  border: 'none',
                }}
                content={({ active, payload }) => {
                  if (active && payload && payload.length) {
                    const data = payload[0].payload
                    return (
                      <div className="p-4 rounded-xl" style={{
                        background: 'linear-gradient(135deg, rgba(255, 255, 255, 0.15), rgba(255, 255, 255, 0.1))',
                        backdropFilter: 'blur(24px)',
                        border: '1px solid rgba(255, 255, 255, 0.25)',
                        boxShadow: '0 8px 32px 0 rgba(31, 38, 135, 0.5)'
                      }}>
                        <p className="text-xs mb-1 font-medium" style={{color: '#006600'}}>DID</p>
                        <p className="text-sm font-mono mb-3 break-all max-w-xs" style={{color: '#003500'}}>
                          {data.fullDid}
                        </p>
                        <div className="space-y-1">
                          <p className="text-sm" style={{color: '#003500'}}>
                            <span style={{color: '#006600'}}>Assignments:</span> <span className="font-semibold">{data.assignments}</span>
                          </p>
                          <p className="text-sm" style={{color: '#003500'}}>
                            <span style={{color: '#006600'}}>Balance:</span> <span className="font-semibold">{formatNumber(data.balance)} RBT</span>
                          </p>
                        </div>
                      </div>
                    )
                  }
                  return null
                }}
              />
              <Bar dataKey="assignments" fill="#10b981" radius={[0, 8, 8, 0]} />
            </BarChart>
          </ResponsiveContainer>
        )}
      </GlassCard>

      {/* Token Balance Distribution */}
      <GlassCard>
        <h3 className="text-xl font-semibold mb-6" style={{color: '#003500'}}>Total Balance by Token</h3>
        {!quorums ? (
          <CardSkeleton />
        ) : (
          <ResponsiveContainer width="100%" height={300}>
            <BarChart data={tokenDistribution}>
              <CartesianGrid strokeDasharray="3 3" stroke="rgba(0,53,0,0.1)" />
              <XAxis dataKey="name" stroke="rgba(0,53,0,0.5)" />
              <YAxis stroke="rgba(0,53,0,0.5)" />
              <Tooltip
                contentStyle={{
                  backgroundColor: 'rgba(15, 23, 42, 0.95)',
                  border: '1px solid rgba(255,255,255,0.2)',
                  borderRadius: '8px',
                  backdropFilter: 'blur(12px)',
                  color: '#ffffff',
                }}
                itemStyle={{
                  color: '#ffffff',
                }}
                labelStyle={{
                  color: '#cbd5e1',
                }}
                formatter={(value: number) => formatNumber(value) + ' RBT'}
              />
              <Bar dataKey="balance" radius={[8, 8, 0, 0]}>
                {tokenDistribution.map((entry, index) => (
                  <Cell key={`cell-${index}`} fill={entry.fill} />
                ))}
              </Bar>
            </BarChart>
          </ResponsiveContainer>
        )}
      </GlassCard>
    </div>
  )
}
