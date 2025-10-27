import { cn } from '@/lib/utils'
import { HTMLAttributes, ReactNode } from 'react'

interface GlassCardProps extends HTMLAttributes<HTMLDivElement> {
  children: ReactNode
  hover?: boolean
  glow?: boolean
}

export function GlassCard({ children, hover = false, glow = false, className, ...props }: GlassCardProps) {
  return (
    <div
      className={cn(
        'glass-card p-4 sm:p-6',
        hover && 'glass-card-hover',
        glow && 'shadow-glow',
        className
      )}
      {...props}
    >
      {children}
    </div>
  )
}
