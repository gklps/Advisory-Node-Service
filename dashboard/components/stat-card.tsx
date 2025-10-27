'use client'

import { GlassCard } from './glass-card'
import { LucideIcon } from 'lucide-react'
import { cn } from '@/lib/utils'
import { motion } from 'framer-motion'

interface StatCardProps {
  title: string
  value: string | number
  icon: LucideIcon
  trend?: {
    value: number
    isPositive: boolean
  }
  color?: 'primary' | 'purple' | 'emerald' | 'amber' | 'rose'
}

const colorMap = {
  primary: 'text-primary-400 bg-primary-500/10',
  purple: 'text-purple-400 bg-purple-500/10',
  emerald: 'text-emerald-400 bg-emerald-500/10',
  amber: 'text-amber-400 bg-amber-500/10',
  rose: 'text-rose-400 bg-rose-500/10',
}

export function StatCard({ title, value, icon: Icon, trend, color = 'primary' }: StatCardProps) {
  return (
    <motion.div
      initial={{ opacity: 0, y: 20 }}
      animate={{ opacity: 1, y: 0 }}
      transition={{ duration: 0.4 }}
    >
      <GlassCard hover className="relative overflow-hidden">
        <div className="flex items-start justify-between gap-3">
          <div className="flex-1 min-w-0">
            <p className="text-xs sm:text-sm mb-1 font-medium" style={{color: '#006600'}}>{title}</p>
            <h3 className="text-xl sm:text-2xl lg:text-3xl font-bold mb-2 truncate" style={{color: '#003500'}}>{value}</h3>
            {trend && (
              <div className="flex items-center gap-1 text-xs sm:text-sm">
                <span className={cn(
                  'font-medium',
                  trend.isPositive ? 'text-emerald-400' : 'text-rose-400'
                )}>
                  {trend.isPositive ? '+' : ''}{trend.value}%
                </span>
                <span className="hidden sm:inline" style={{color: '#008800'}}>vs last hour</span>
              </div>
            )}
          </div>
          <div className={cn(
            'p-2 sm:p-3 rounded-xl flex-shrink-0',
            colorMap[color]
          )}>
            <Icon className="w-5 h-5 sm:w-6 sm:h-6" />
          </div>
        </div>
      </GlassCard>
    </motion.div>
  )
}
