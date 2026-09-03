import { Navigate, Route, Routes } from 'react-router-dom'
import { LoadingBlock } from '../components/ui'
import { useAuth } from '../features/auth/AuthProvider'
import { AppShell } from '../layouts/AppShell'
import { CalendarPage } from '../pages/CalendarPage'
import { DashboardPage } from '../pages/DashboardPage'
import { ForgotPasswordPage, LoginPage, RegisterPage, ResetPasswordPage } from '../pages/AuthPages'
import { MorePage } from '../pages/MorePage'
import { OnboardingPage } from '../pages/OnboardingPage'
import { PetPage } from '../pages/PetPage'
import { StudyPage } from '../pages/StudyPage'
import { SubjectsPage } from '../pages/SubjectsPage'

function Protected() { const { user, loading, configured } = useAuth(); if (loading) return <main className="page-center"><LoadingBlock label="Preparando tu espacio..."/></main>; if (!configured) return <Navigate to="/" replace />; return user ? <AppShell /> : <Navigate to="/login" replace /> }
function PublicOnly({ children }: { children: React.ReactNode }) { const { user, loading } = useAuth(); if (loading) return <main className="page-center"><LoadingBlock /></main>; return user ? <Navigate to="/app" replace /> : <>{children}</> }
function SetupPage() { return <main className="setup-page"><div className="setup-card"><div className="brand-mark">✦</div><p className="eyebrow">Configuración requerida</p><h1>Conectá tu espacio de estudio</h1><p>Agregá <code>VITE_SUPABASE_URL</code> y <code>VITE_SUPABASE_ANON_KEY</code> en <code>.env</code> a partir de <code>.env.example</code>. Tus datos se guardan en tu propio proyecto Supabase.</p></div></main> }
export function App() { const { configured } = useAuth(); if (!configured) return <SetupPage />; return <Routes><Route path="/" element={<Navigate to="/app" replace/>}/><Route path="/login" element={<PublicOnly><LoginPage/></PublicOnly>}/><Route path="/register" element={<PublicOnly><RegisterPage/></PublicOnly>}/><Route path="/forgot-password" element={<PublicOnly><ForgotPasswordPage/></PublicOnly>}/><Route path="/reset-password" element={<ResetPasswordPage/>}/><Route path="/onboarding" element={<OnboardingPage/>}/><Route path="/app" element={<Protected/>}><Route index element={<DashboardPage/>}/><Route path="study" element={<StudyPage/>}/><Route path="subjects" element={<SubjectsPage/>}/><Route path="calendar" element={<CalendarPage/>}/><Route path="pet" element={<PetPage/>}/><Route path="more" element={<MorePage/>}/></Route><Route path="*" element={<Navigate to="/app" replace/>}/></Routes> }
