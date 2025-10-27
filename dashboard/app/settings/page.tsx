'use client'

import { useState, useEffect } from 'react'
import { useQuery } from '@tanstack/react-query'
import { api } from '@/lib/api'
import { Header } from '@/components/header'
import { GlassCard } from '@/components/glass-card'
import {
  Server,
  Database,
  Bell,
  Shield,
  Info,
  Check,
  AlertCircle
} from 'lucide-react'

export default function SettingsPage() {
  const [network, setNetwork] = useState<'mainnet' | 'testnet'>('mainnet')
  const [refreshInterval, setRefreshInterval] = useState('10')
  const [showNotifications, setShowNotifications] = useState(true)
  const [savedMessage, setSavedMessage] = useState('')

  // Fetch health data for dynamic info
  const { data: health } = useQuery({
    queryKey: ['health'],
    queryFn: api.getHealth,
    refetchInterval: 15000,
  })

  const { data: quorums } = useQuery({
    queryKey: ['quorums'],
    queryFn: api.getAllQuorums,
    refetchInterval: 15000,
  })

  // Load settings from localStorage on mount
  useEffect(() => {
    const savedNetwork = localStorage.getItem('network') as 'mainnet' | 'testnet'
    const savedInterval = localStorage.getItem('refreshInterval')
    const savedNotifications = localStorage.getItem('showNotifications')

    if (savedNetwork) setNetwork(savedNetwork)
    if (savedInterval) setRefreshInterval(savedInterval)
    if (savedNotifications) setShowNotifications(savedNotifications === 'true')
  }, [])

  const apiEndpoint = network === 'mainnet'
    ? 'https://mainnet-pool.universe.rubix.net/'
    : 'https://testnet-pool.universe.rubix.net/'

  const handleSave = () => {
    // Save to localStorage
    localStorage.setItem('network', network)
    localStorage.setItem('apiEndpoint', apiEndpoint)
    localStorage.setItem('refreshInterval', refreshInterval)
    localStorage.setItem('showNotifications', showNotifications.toString())

    setSavedMessage('Settings saved successfully! Reloading page...')

    // Reload page after a short delay to apply new API endpoint
    setTimeout(() => {
      window.location.reload()
    }, 1500)
  }

  return (
    <div className="space-y-8">
      <Header
        title="Settings"
        subtitle="Configure dashboard preferences and API connection"
      />

      {/* Current Network Info */}
      <div className="glass-card p-4 bg-primary-500/10 border-primary-400/30">
        <div className="flex items-start gap-3">
          <Info className="w-5 h-5 text-primary-400 flex-shrink-0 mt-0.5" />
          <div>
            <p className="text-sm text-primary-400 font-semibold mb-1">Development Mode</p>
            <p className="text-xs" style={{color: '#006600'}}>
              Currently using <span className="font-mono">{apiEndpoint}</span> endpoint.
              {network === 'mainnet' || network === 'testnet'
                ? ` Select a network and save to connect to the ${network} pool.`
                : ' For local development, the API will use localhost:8082.'
              }
            </p>
          </div>
        </div>
      </div>

      {/* Save Notification */}
      {savedMessage && (
        <div className="glass-card p-4 bg-emerald-500/10 border-emerald-400/30">
          <div className="flex items-center gap-3 text-emerald-400">
            <Check className="w-5 h-5" />
            <span>{savedMessage}</span>
          </div>
        </div>
      )}

      {/* API Configuration */}
      <GlassCard>
        <div className="flex items-start gap-4 mb-6">
          <div className="p-3 rounded-xl bg-primary-500/20">
            <Server className="w-6 h-6 text-primary-400" />
          </div>
          <div className="flex-1">
            <h3 className="text-xl font-semibold mb-2" style={{color: '#003500'}}>API Configuration</h3>
            <p className="text-sm text-custom-light">Configure backend API endpoint and connection settings</p>
          </div>
        </div>

        <div className="space-y-4">
          <div>
            <label className="block text-sm text-custom-light mb-3 font-medium">
              Network Environment
            </label>

            {/* Toggle Switch for Mainnet/Testnet */}
            <div className="flex items-center gap-4 p-4 rounded-xl bg-white/5 border border-glass-border">
              <span className={`text-sm font-semibold transition-colors ${network === 'testnet' ? 'text-custom-light' : ''}`} style={network === 'testnet' ? {} : {color: '#003500'}}>
                Testnet
              </span>
              <button
                onClick={() => setNetwork(network === 'mainnet' ? 'testnet' : 'mainnet')}
                className={`relative inline-flex h-8 w-16 items-center rounded-full transition-colors ${
                  network === 'mainnet' ? 'bg-primary-500' : 'bg-purple-500'
                }`}
                aria-label="Toggle network"
              >
                <span className="sr-only">Toggle network</span>
                <span
                  className={`inline-block h-6 w-6 transform rounded-full bg-white shadow-lg transition-transform ${
                    network === 'mainnet' ? 'translate-x-9' : 'translate-x-1'
                  }`}
                />
              </button>
              <span className={`text-sm font-semibold transition-colors ${network === 'mainnet' ? 'text-custom-light' : ''}`} style={network === 'mainnet' ? {} : {color: '#003500'}}>
                Mainnet
              </span>
            </div>
            <p className="text-xs text-custom-light mt-2">
              Toggle between testnet and mainnet environments
            </p>
          </div>

          <div>
            <label className="block text-sm text-custom-light mb-2 font-medium">
              API Endpoint
            </label>
            <div className="w-full px-4 py-3 rounded-xl bg-white/5 border border-glass-border font-mono text-sm" style={{color: '#006600'}}>
              {apiEndpoint}
            </div>
            <p className="text-xs text-custom-light mt-2">
              The backend API endpoint for the selected network
            </p>
          </div>

          <div>
            <label className="block text-sm text-custom-light mb-2 font-medium">
              Refresh Interval (seconds)
            </label>
            <input
              type="number"
              value={refreshInterval}
              onChange={(e) => setRefreshInterval(e.target.value)}
              min="5"
              max="300"
              className="w-full px-4 py-3 rounded-xl bg-white/5 border border-glass-border focus:outline-none focus:border-primary-400 transition-colors"
              style={{color: '#003500'}}
            />
            <p className="text-xs text-custom-light mt-2">
              How often to automatically refresh data (minimum 5 seconds)
            </p>
          </div>
        </div>
      </GlassCard>

      {/* Database Info */}
      <GlassCard>
        <div className="flex items-start gap-4 mb-6">
          <div className="p-3 rounded-xl bg-purple-500/20">
            <Database className="w-6 h-6 text-purple-400" />
          </div>
          <div className="flex-1">
            <h3 className="text-xl font-semibold mb-2" style={{color: '#003500'}}>Database Information</h3>
            <p className="text-sm text-custom-light">Current backend database configuration</p>
          </div>
        </div>

        <div className="space-y-3">
          <div className="flex items-center justify-between py-3 border-b border-glass-border/50">
            <span className="text-custom-light font-medium">Total Quorums</span>
            <span className="font-semibold" style={{color: '#003500'}}>{health?.total_quorums || 0}</span>
          </div>
          <div className="flex items-center justify-between py-3 border-b border-glass-border/50">
            <span className="text-custom-light font-medium">Available Quorums</span>
            <span className="font-semibold" style={{color: '#003500'}}>{health?.available_quorums || 0}</span>
          </div>
          <div className="flex items-center justify-between py-3 border-b border-glass-border/50">
            <span className="text-custom-light font-medium">System Uptime</span>
            <span className="font-mono text-sm" style={{color: '#003500'}}>{health?.uptime || 'N/A'}</span>
          </div>
          <div className="flex items-center justify-between py-3 border-b border-glass-border/50">
            <span className="text-custom-light font-medium">System Status</span>
            <span className={`badge-${health?.status === 'healthy' ? 'success' : 'warning'}`}>
              {health?.status === 'healthy' ? 'Healthy' : 'Degraded'}
            </span>
          </div>
          <div className="flex items-center justify-between py-3">
            <span className="text-custom-light font-medium">Total Registered DIDs</span>
            <span className="font-semibold" style={{color: '#003500'}}>{quorums?.count || 0}</span>
          </div>
        </div>
      </GlassCard>

      {/* Notifications */}
      <GlassCard>
        <div className="flex items-start gap-4 mb-6">
          <div className="p-3 rounded-xl bg-amber-500/20">
            <Bell className="w-6 h-6 text-amber-400" />
          </div>
          <div className="flex-1">
            <h3 className="text-xl font-semibold mb-2" style={{color: '#003500'}}>Notifications</h3>
            <p className="text-sm text-custom-light">Manage notification preferences</p>
          </div>
        </div>

        <div className="space-y-4">
          <div className="flex items-center justify-between">
            <div>
              <p className="mb-1" style={{color: '#003500'}}>Show System Notifications</p>
              <p className="text-sm text-custom-light">Receive alerts for system events</p>
            </div>
            <button
              onClick={() => setShowNotifications(!showNotifications)}
              className={`relative inline-flex h-6 w-11 items-center rounded-full transition-colors ${
                showNotifications ? 'bg-primary-500' : ''
              }`}
              style={!showNotifications ? {backgroundColor: '#006600'} : undefined}
            >
              <span
                className={`inline-block h-4 w-4 transform rounded-full bg-white transition-transform ${
                  showNotifications ? 'translate-x-6' : 'translate-x-1'
                }`}
              />
            </button>
          </div>
        </div>
      </GlassCard>

      {/* Security */}
      <GlassCard>
        <div className="flex items-start gap-4 mb-6">
          <div className="p-3 rounded-xl bg-emerald-500/20">
            <Shield className="w-6 h-6 text-emerald-400" />
          </div>
          <div className="flex-1">
            <h3 className="text-xl font-semibold mb-2" style={{color: '#003500'}}>Security</h3>
            <p className="text-sm text-custom-light">Security and authentication settings</p>
          </div>
        </div>

        <div className="glass-card bg-amber-500/5 border-amber-400/20 p-4">
          <div className="flex items-start gap-3">
            <AlertCircle className="w-5 h-5 text-amber-400 flex-shrink-0 mt-0.5" />
            <div>
              <p className="text-sm text-amber-400 font-semibold mb-1">Development Mode</p>
              <p className="text-xs text-custom-light">
                The API is running in debug mode without authentication.
                Enable authentication before deploying to production.
              </p>
            </div>
          </div>
        </div>
      </GlassCard>

      {/* About */}
      <GlassCard>
        <div className="flex items-start gap-4 mb-6">
          <div className="p-3 rounded-xl bg-slate-500/20">
            <Info className="w-6 h-6" style={{color: '#008800'}} />
          </div>
          <div className="flex-1">
            <h3 className="text-xl font-semibold mb-2" style={{color: '#003500'}}>About</h3>
            <p className="text-sm text-custom-light">Dashboard and service information</p>
          </div>
        </div>

        <div className="space-y-3">
          <div className="flex items-center justify-between py-3 border-b border-glass-border/50">
            <span className="text-custom-light font-medium">Dashboard Version</span>
            <span className="font-semibold" style={{color: '#003500'}}>2.0.0</span>
          </div>
          <div className="flex items-center justify-between py-3 border-b border-glass-border/50">
            <span className="text-custom-light font-medium">Advisory Node Version</span>
            <span className="font-semibold" style={{color: '#003500'}}>2.0.0</span>
          </div>
          <div className="flex items-center justify-between py-3 border-b border-glass-border/50">
            <span className="text-custom-light font-medium">Framework</span>
            <span className="font-semibold" style={{color: '#003500'}}>Next.js 16</span>
          </div>
          <div className="flex items-center justify-between py-3">
            <span className="text-custom-light font-medium">Platform</span>
            <span className="font-semibold" style={{color: '#003500'}}>RubixGo</span>
          </div>
        </div>
      </GlassCard>

      {/* Save Button */}
      <div className="flex justify-end gap-4">
        <button
          onClick={() => {
            setNetwork('mainnet')
            setRefreshInterval('10')
            setShowNotifications(true)
          }}
          className="glass-button px-6 py-3"
        >
          Reset to Defaults
        </button>
        <button
          onClick={handleSave}
          className="glass-button-primary px-6 py-3"
        >
          Save Settings
        </button>
      </div>
    </div>
  )
}
