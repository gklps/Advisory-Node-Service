'use client'

import { useQuery } from '@tanstack/react-query'
import { api } from '@/lib/api'
import { RefreshCw, Circle } from 'lucide-react'
import { formatRelativeTime } from '@/lib/utils'
import { motion } from 'framer-motion'

export function Header({ title, subtitle }: { title: string; subtitle?: string }) {
  const { data: health, refetch, isRefetching } = useQuery({
    queryKey: ['health'],
    queryFn: api.getHealth,
    refetchInterval: 5000,
  })

  return (
    <div className="glass-card p-4 sm:p-6 mb-6 sm:mb-8">
      <div className="flex flex-col lg:flex-row lg:items-start lg:justify-between gap-4">
        <div className="flex-1">
          <h1 className="text-2xl sm:text-3xl font-bold mb-2" style={{color: '#003500'}}>{title}</h1>
          {subtitle && <p className="text-sm sm:text-base" style={{color: '#006600'}}>{subtitle}</p>}
        </div>

        <div className="flex flex-wrap items-center gap-3 sm:gap-4">
          {/* System Status */}
          <div className="flex items-center gap-2">
            <Circle
              className={`w-2 h-2 ${
                health?.status === 'healthy'
                  ? 'text-emerald-500 fill-emerald-500'
                  : 'text-rose-500 fill-rose-500'
              } animate-pulse`}
            />
            <span className="text-xs sm:text-sm font-medium" style={{color: '#004d00'}}>
              {health?.status === 'healthy' ? 'Healthy' : 'Degraded'}
            </span>
          </div>

          {/* Last Updated */}
          <div className="text-xs sm:text-sm hidden sm:block" style={{color: '#006600'}}>
            Updated {health?.last_check ? formatRelativeTime(health.last_check) : 'never'}
          </div>

          {/* Refresh Button */}
          <button
            onClick={() => refetch()}
            disabled={isRefetching}
            className="glass-button-primary flex items-center gap-2 text-xs sm:text-sm px-3 py-2"
          >
            <motion.div
              animate={{ rotate: isRefetching ? 360 : 0 }}
              transition={{ duration: 1, repeat: isRefetching ? Infinity : 0, ease: 'linear' }}
            >
              <RefreshCw className="w-4 h-4" />
            </motion.div>
            <span className="hidden sm:inline">Refresh</span>
          </button>
        </div>
      </div>
    </div>
  )
}
