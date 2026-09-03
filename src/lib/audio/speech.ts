export interface TextToSpeechProvider { supported: boolean; speak(text: string, rate: number, voiceName?: string): void; pause(): void; resume(): void; stop(): void; voices(): SpeechSynthesisVoice[] }
export interface SpeechToTextProvider { supported: boolean; start(onResult: (text: string) => void, onError: (message: string) => void): () => void }

type RecognitionConstructor = new () => SpeechRecognition
interface SpeechRecognition extends EventTarget { lang: string; interimResults: boolean; continuous: boolean; start(): void; stop(): void; onresult: ((event: SpeechRecognitionEvent) => void) | null; onerror: ((event: SpeechRecognitionErrorEvent) => void) | null }
interface SpeechRecognitionEvent { results: { [index: number]: { [index: number]: { transcript: string } } }; resultIndex: number }
interface SpeechRecognitionErrorEvent { error: string }
declare global { interface Window { webkitSpeechRecognition?: RecognitionConstructor; SpeechRecognition?: RecognitionConstructor } }

export const browserTTS: TextToSpeechProvider = {
  get supported() { return 'speechSynthesis' in window },
  speak(text, rate, voiceName) { if (!('speechSynthesis' in window)) return; window.speechSynthesis.cancel(); const utterance = new SpeechSynthesisUtterance(text); utterance.lang = 'es-AR'; utterance.rate = Math.min(2, Math.max(0.5, rate)); const voice = window.speechSynthesis.getVoices().find((item) => item.name === voiceName); if (voice) utterance.voice = voice; window.speechSynthesis.speak(utterance) },
  pause() { window.speechSynthesis?.pause() }, resume() { window.speechSynthesis?.resume() }, stop() { window.speechSynthesis?.cancel() }, voices() { return window.speechSynthesis?.getVoices() ?? [] }
}

export const browserSTT: SpeechToTextProvider = {
  get supported() { return Boolean(window.SpeechRecognition || window.webkitSpeechRecognition) },
  start(onResult, onError) { const Constructor = window.SpeechRecognition || window.webkitSpeechRecognition; if (!Constructor) { onError('Tu navegador no permite dictado por voz. Podés escribir tu consulta.'); return () => undefined } const recognition = new Constructor(); recognition.lang = 'es-AR'; recognition.interimResults = false; recognition.continuous = false; recognition.onresult = (event) => onResult(event.results[event.resultIndex][0].transcript); recognition.onerror = (event) => onError(event.error === 'not-allowed' ? 'Necesitamos permiso para usar el micrófono.' : 'No pudimos reconocer el audio. Probá nuevamente o escribí tu consulta.'); recognition.start(); return () => recognition.stop() }
}
