import { CalendarDays, Cat, GraduationCap, Home, LogOut, MoreHorizontal, NotebookTabs, Sparkles } from 'lucide-react'
import { NavLink, Outlet, useNavigate } from 'react-router-dom'
import { useAuth } from '../features/auth/AuthProvider'

const primary = [{ to: '/app', label: 'Inicio', icon: Home, end: true }, { to: '/app/study', label: 'Estudiar', icon: Sparkles }, { to: '/app/subjects', label: 'Materias', icon: NotebookTabs }, { to: '/app/pet', label: 'Mascota', icon: Cat }]
const secondary = [{ to: '/app/calendar', label: 'Calendario', icon: CalendarDays, end: false }, { to: '/app/more', label: 'Más', icon: MoreHorizontal, end: false }]
export function AppShell() {
  const { signOut, user } = useAuth(); const navigate = useNavigate()
  const logout = async () => { await signOut(); navigate('/login') }
  return <div className="app-shell"><aside className="sidebar"><NavLink to="/app" className="brand"><span className="brand-mark"><GraduationCap size={21}/></span><span>Companion<span>Study</span></span></NavLink><nav aria-label="Navegación principal">{[...primary, ...secondary].map(({ to, label, icon: Icon, end }) => <NavLink key={to} to={to} end={end} className={({ isActive }) => `nav-item ${isActive ? 'active' : ''}`}><Icon size={19}/><span>{label}</span></NavLink>)}</nav><div className="sidebar-account"><span className="avatar">{user?.email?.slice(0, 1).toUpperCase()}</span><span className="account-email">{user?.email}</span><button className="icon-button" onClick={() => void logout()} aria-label="Cerrar sesión"><LogOut size={18}/></button></div></aside><main className="main-content"><Outlet /></main><nav className="bottom-nav" aria-label="Navegación móvil">{primary.map(({ to, label, icon: Icon, end }) => <NavLink key={to} to={to} end={end} className={({ isActive }) => `bottom-item ${isActive ? 'active' : ''}`}><Icon size={20}/><span>{label}</span></NavLink>)}<NavLink to="/app/more" className={({ isActive }) => `bottom-item ${isActive ? 'active' : ''}`}><MoreHorizontal size={20}/><span>Más</span></NavLink></nav></div>
}
