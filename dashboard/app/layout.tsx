import type { Metadata } from 'next'
import { Inter } from 'next/font/google'
import './globals.css'
import { Providers } from './providers'
import { Sidebar } from '@/components/sidebar'

const inter = Inter({ subsets: ['latin'] })

export const metadata: Metadata = {
  title: 'Advisory Node Dashboard',
  description: 'Real-time monitoring dashboard for Advisory Node Service',
  viewport: {
    width: 'device-width',
    initialScale: 1,
    maximumScale: 5,
  },
}

export default function RootLayout({
  children,
}: {
  children: React.ReactNode
}) {
  return (
    <html lang="en">
      <body className={inter.className}>
        <Providers>
          <div className="flex min-h-screen">
            <Sidebar />
            <main className="flex-1 pt-16 lg:pt-6 pb-6 px-4 sm:px-6 lg:px-6">
              {children}
            </main>
          </div>
        </Providers>
      </body>
    </html>
  )
}
