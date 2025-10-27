'use client'

import { useState } from 'react'
import Link from 'next/link'
import { usePathname } from 'next/navigation'
import Image from 'next/image'
import {
  LayoutDashboard,
  Users,
  Activity,
  BarChart3,
  Settings,
  Menu,
  X,
  Zap
} from 'lucide-react'
import { cn } from '@/lib/utils'
import { motion, AnimatePresence } from 'framer-motion'

const navigation = [
  { name: 'Overview', href: '/', icon: LayoutDashboard },
  { name: 'Quorums', href: '/quorums', icon: Users },
  { name: 'Transactions', href: '/transactions', icon: Activity },
  { name: 'Analytics', href: '/analytics', icon: BarChart3 },
  { name: 'Settings', href: '/settings', icon: Settings },
]

export function Sidebar() {
  const pathname = usePathname()
  const [isOpen, setIsOpen] = useState(false)

  return (
    <>
      {/* Mobile menu button */}
      <button
        onClick={() => setIsOpen(!isOpen)}
        className="lg:hidden fixed top-4 left-4 z-50 glass-button p-3"
      >
        {isOpen ? <X className="w-6 h-6" /> : <Menu className="w-6 h-6" />}
      </button>

      {/* Backdrop for mobile */}
      <AnimatePresence>
        {isOpen && (
          <motion.div
            initial={{ opacity: 0 }}
            animate={{ opacity: 1 }}
            exit={{ opacity: 0 }}
            className="lg:hidden fixed inset-0 bg-black/50 backdrop-blur-sm z-40"
            onClick={() => setIsOpen(false)}
          />
        )}
      </AnimatePresence>

      {/* Sidebar */}
      <aside
        className={cn(
          'w-full lg:w-1/4 glass-card rounded-none lg:rounded-r-3xl',
          'flex flex-col p-6 transition-transform duration-300',
          'fixed lg:relative left-0 top-0 bottom-0 z-40',
          isOpen ? 'translate-x-0' : '-translate-x-full lg:translate-x-0'
        )}
      >
        {/* Logo */}
        <div className="flex flex-col items-start gap-2 mb-8">
          <div className="w-full">
            <Image
              src="/logo.png"
              alt="Rubix"
              width={240}
              height={60}
              className="w-full h-auto"
              priority
            />
          </div>
          <div className="w-full">
            <h1 className="text-base font-bold" style={{color: '#003500'}}>Advisory Node</h1>
            <p className="text-xs" style={{color: '#006600'}}>Quorum Manager</p>
          </div>
        </div>

        {/* Navigation */}
        <nav className="flex-1 space-y-2">
          {navigation.map((item) => {
            const isActive = pathname === item.href
            return (
              <Link
                key={item.name}
                href={item.href}
                onClick={() => setIsOpen(false)}
                className={cn(
                  'flex items-center gap-3 px-4 py-3 rounded-xl transition-all duration-200',
                  'hover:bg-primary-500/10',
                  isActive
                    ? 'bg-gradient-to-r from-primary-500/30 to-green-500/20 border-2 border-primary-400/50 font-semibold shadow-sm'
                    : 'hover:font-medium'
                )}
                style={{color: isActive ? '#003500' : '#006600'}}
              >
                <item.icon className="w-5 h-5" />
                <span className="font-medium">{item.name}</span>
                {isActive && (
                  <motion.div
                    layoutId="activeIndicator"
                    className="ml-auto w-2 h-2 rounded-full"
                    style={{backgroundColor: '#ffe314'}}
                  />
                )}
              </Link>
            )
          })}
        </nav>

        {/* Footer */}
        <div className="pt-6 border-t" style={{borderColor: 'rgba(0, 53, 0, 0.2)'}}>
          <div className="text-xs space-y-1" style={{color: '#008800'}}>
            <p>Version 2.0.0</p>
            <p>© 2025 RubixGo</p>
          </div>
        </div>
      </aside>
    </>
  )
}
