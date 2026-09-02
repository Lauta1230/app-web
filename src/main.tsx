import { StrictMode } from 'react'
import { createRoot } from 'react-dom/client'
import { BrowserRouter } from 'react-router-dom'
import { App } from './app/App'
import { AuthProvider } from './features/auth/AuthProvider'
import './styles.css'

if ('serviceWorker' in navigator) window.addEventListener('load', () => void navigator.serviceWorker.register('/sw.js'))
createRoot(document.getElementById('root')!).render(<StrictMode><BrowserRouter><AuthProvider><App /></AuthProvider></BrowserRouter></StrictMode>)
