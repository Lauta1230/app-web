import { AlertCircle, LoaderCircle, X } from 'lucide-react'
import { type ButtonHTMLAttributes, type PropsWithChildren, type ReactNode } from 'react'

export function Button({ children, className = '', loading, ...props }: PropsWithChildren<ButtonHTMLAttributes<HTMLButtonElement> & { loading?: boolean }>) {
  return <button className={`button ${className}`} disabled={loading || props.disabled} {...props}>{loading && <LoaderCircle className="spin" size={17} aria-hidden="true" />}{children}</button>
}
export function Card({ children, className = '' }: PropsWithChildren<{ className?: string }>) { return <section className={`card ${className}`}>{children}</section> }
export function EmptyState({ title, description, action }: { title: string; description: string; action?: ReactNode }) { return <div className="empty-state"><div className="empty-orb">✦</div><h3>{title}</h3><p>{description}</p>{action}</div> }
export function ErrorState({ message, retry }: { message: string; retry?: () => void }) { return <div className="error-state" role="alert"><AlertCircle size={20} /><div><strong>Algo no salió bien</strong><p>{message}</p>{retry && <button className="text-button" onClick={retry}>Reintentar</button>}</div></div> }
export function Modal({ title, children, onClose }: PropsWithChildren<{ title: string; onClose: () => void }>) { return <div className="modal-backdrop" role="presentation" onMouseDown={onClose}><section className="modal" role="dialog" aria-modal="true" aria-label={title} onMouseDown={(event) => event.stopPropagation()}><header><h2>{title}</h2><button className="icon-button" aria-label="Cerrar" onClick={onClose}><X size={20} /></button></header>{children}</section></div> }
export function Field({ label, children }: PropsWithChildren<{ label: string }>) { return <label className="field"><span>{label}</span>{children}</label> }
export function LoadingBlock({ label = 'Cargando...' }: { label?: string }) { return <div className="loading-block"><LoaderCircle className="spin" size={22}/>{label}</div> }
