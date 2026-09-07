import { useCallback, useEffect, useMemo, useRef, useState, type FormEvent } from 'react'
import { Bot, BrainCircuit, CheckCircle2, ChevronRight, Mic, Pause, Play, RotateCcw, Send, Sparkles, Square, Volume2 } from 'lucide-react'
import { useLocation, useSearchParams } from 'react-router-dom'
import { MarkdownMessage } from '../components/MarkdownMessage'
import { Button, Card, EmptyState, ErrorState, Field } from '../components/ui'
import { useAuth } from '../features/auth/AuthProvider'
import { browserSTT, browserTTS } from '../lib/audio/speech'
import { supabase } from '../lib/supabase/client'
import { appApi, notesApi, subjectsApi } from '../services/api'
import type { Note, QuizQuestion, Subject } from '../types/domain'
import { friendlyError } from '../utils/errors'

type Message = { role: 'user' | 'assistant'; content: string }
type StudyDocument = { id: string; name: string; processing_status: string; confirmed_at: string | null }
const modes = ['Explicame', 'Preguntame', 'Examiname', 'Repasemos', 'Voz'] as const

export function StudyPage() {
  const { user } = useAuth()
  const [params] = useSearchParams()
  const location = useLocation()
  const [subjects, setSubjects] = useState<Subject[]>([])
  const [documents, setDocuments] = useState<StudyDocument[]>([])
  const [documentId, setDocumentId] = useState('')
  const [noteId, setNoteId] = useState(params.get('note') ?? '')
  const [noteContext, setNoteContext] = useState<Note | null>(null)
  const [subjectId, setSubjectId] = useState(params.get('subject') ?? '')
  const [mode, setMode] = useState<(typeof modes)[number]>('Explicame')
  const [message, setMessage] = useState('')
  const [messages, setMessages] = useState<Message[]>([])
  const [conversationId, setConversationId] = useState<string>()
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState('')
  const [listening, setListening] = useState(false)
  const [rate, setRate] = useState(1)
  const [voice, setVoice] = useState('')
  const [voices, setVoices] = useState<SpeechSynthesisVoice[]>([])
  const [sessionStarted, setSessionStarted] = useState<number | null>(null)
  const [quiz, setQuiz] = useState<{ id: string; title: string; questions: QuizQuestion[] } | null>(null)
  const [quizTopic, setQuizTopic] = useState('')
  const [quizLoading, setQuizLoading] = useState(false)
  const [answers, setAnswers] = useState<Record<string, string>>({})
  const [result, setResult] = useState<{ score: number; correct: number; xp: number; feedback: Record<string, string> } | null>(null)
  const stopRecognition = useRef<(() => void) | null>(null)

  const load = useCallback(async () => {
    try {
      const [subjectRows, documentRows, noteRows] = await Promise.all([
        subjectsApi.list(),
        supabase.from('documents').select('id,name,processing_status,confirmed_at').eq('processing_status', 'completed').not('confirmed_at', 'is', null).order('name'),
        notesApi.list(),
      ])
      if (documentRows.error) throw documentRows.error
      setSubjects(subjectRows)
      setDocuments((documentRows.data ?? []) as StudyDocument[])
      setNoteContext(noteRows.find((note) => note.id === params.get('note')) ?? null)
    } catch (err) {
      setError(friendlyError(err))
    }
  }, [params])

  useEffect(() => {
    void load()
    const updateVoices = () => setVoices(browserTTS.voices().filter((item) => item.lang.startsWith('es')))
    updateVoices()
    window.speechSynthesis?.addEventListener('voiceschanged', updateVoices)
    return () => {
      window.speechSynthesis?.removeEventListener('voiceschanged', updateVoices)
      stopRecognition.current?.()
      browserTTS.stop()
    }
  }, [load])

  useEffect(() => {
    setSubjectId(params.get('subject') ?? '')
    setNoteId(params.get('note') ?? '')
  }, [location.search, params])

  const selected = useMemo(() => subjects.find((subject) => subject.id === subjectId), [subjects, subjectId])

  const send = async (event?: FormEvent) => {
    event?.preventDefault()
    const text = message.trim()
    if (!text || loading) return
    setError('')
    setMessage('')
    setLoading(true)
    setMessages((items) => [...items, { role: 'user', content: text }])
    if (!sessionStarted) setSessionStarted(Date.now())
    try {
      const response = await appApi.aiChat({
        message: text,
        conversation_id: conversationId,
        subject_id: subjectId || undefined,
        document_id: documentId || undefined,
        note_id: noteId || undefined,
        mode,
      })
      setConversationId(response.conversation_id)
      setMessages((items) => [...items, { role: 'assistant', content: response.message }])
      if (mode === 'Voz') browserTTS.speak(response.message, rate, voice || undefined)
    } catch (err) {
      setError(friendlyError(err, 'No pudimos obtener una respuesta de la IA. Podés reintentar o continuar con tus apuntes.'))
      setMessages((items) => items.slice(0, -1))
      setMessage(text)
    } finally {
      setLoading(false)
    }
  }

  const dictate = () => {
    if (listening) {
      stopRecognition.current?.()
      setListening(false)
      return
    }
    setError('')
    setListening(true)
    stopRecognition.current = browserSTT.start(
      (text) => {
        setMessage((current) => (current ? `${current} ${text}` : text))
        setListening(false)
      },
      (voiceError) => {
        setError(voiceError)
        setListening(false)
      }
    )
  }

  const finishSession = async () => {
    if (!sessionStarted || !user) return
    const seconds = Math.max(60, Math.round((Date.now() - sessionStarted) / 1000))
    try {
      await appApi.completeStudySession({
        started_at: new Date(sessionStarted).toISOString(),
        duration_seconds: seconds,
        mode: mode === 'Voz' ? 'voice' : 'ai_tutor',
        subject_id: subjectId || null,
      })
      setSessionStarted(null)
    } catch (err) {
      setError(friendlyError(err, 'No pudimos guardar la sesión. Intentá finalizarla nuevamente.'))
    }
  }

  const createQuiz = async () => {
    if (!selected || !quizTopic.trim()) {
      setError('Elegí una materia y escribí un tema para crear el quiz.')
      return
    }
    setQuizLoading(true)
    setError('')
    try {
      const generated = await appApi.createQuiz({
        subject_id: selected.id,
        topic: quizTopic,
        difficulty: 'normal',
        question_count: 5,
        source_text: noteContext?.content,
      })
      setQuiz({ id: generated.quiz_id, title: generated.title, questions: generated.questions })
      setAnswers({})
      setResult(null)
    } catch (err) {
      setError(friendlyError(err, 'No pudimos crear el quiz ahora. Intentá nuevamente más tarde.'))
    } finally {
      setQuizLoading(false)
    }
  }

  const submitQuiz = async () => {
    if (!quiz || Object.keys(answers).length !== quiz.questions.length) {
      setError('Respondé todas las preguntas antes de enviar.')
      return
    }
    try {
      const scored = await appApi.submitQuiz(
        quiz.id,
        quiz.questions.map((question) => ({ question_id: question.id, answer: answers[question.id] }))
      )
      setResult({
        score: scored.score,
        correct: scored.correct_answers,
        xp: scored.xp_awarded,
        feedback: Object.fromEntries(scored.answers.map((item) => [item.question_id, item.feedback])),
      })
    } catch (err) {
      setError(friendlyError(err, 'No pudimos corregir el quiz. Intentá nuevamente.'))
    }
  }

  if (!subjects.length && !error) {
    return (
      <div className="page">
        <header className="page-heading">
          <div>
            <p className="eyebrow">ESTUDIAR CON IA</p>
            <h1>Tu espacio de estudio</h1>
          </div>
        </header>
        <EmptyState title="Primero creá una materia" description="La IA usa la materia y el tema para orientarte mejor." />
      </div>
    )
  }

  return (
    <div className="page study-page">
      <header className="page-heading">
        <div>
          <p className="eyebrow">ESTUDIAR CON IA</p>
          <h1>¿En qué te ayudo hoy?</h1>
          <p>Usamos sólo el contexto que elegís compartir en esta sesión.</p>
        </div>
        {sessionStarted && (
          <Button className="button-secondary" onClick={() => void finishSession()}>
            <Square size={16} /> Finalizar sesión
          </Button>
        )}
      </header>

      {noteContext && (
        <div className="context-banner">
          <Sparkles size={16} /> Estás usando el apunte <strong>{noteContext.title}</strong> como contexto.{' '}
          <button
            onClick={() => {
              setNoteId('')
              setNoteContext(null)
            }}
          >
            Quitar
          </button>
        </div>
      )}

      {error && <ErrorState message={error} retry={() => setError('')} />}

      <div className="study-layout">
        <section className="chat-shell">
          <div className="chat-controls">
            <Field label="Materia">
              <select value={subjectId} onChange={(event) => setSubjectId(event.target.value)}>
                <option value="">Materia general</option>
                {subjects.map((subject) => (
                  <option value={subject.id} key={subject.id}>
                    {subject.name}
                  </option>
                ))}
              </select>
            </Field>

            {documents.length > 0 && (
              <Field label="Documento de contexto">
                <select value={documentId} onChange={(event) => setDocumentId(event.target.value)}>
                  <option value="">Sin documento</option>
                  {documents.map((document) => (
                    <option key={document.id} value={document.id}>
                      {document.name}
                    </option>
                  ))}
                </select>
              </Field>
            )}

            <div className="mode-tabs" role="tablist" aria-label="Modo de estudio">
              {modes.map((item) => (
                <button
                  role="tab"
                  aria-selected={mode === item}
                  className={mode === item ? 'active' : ''}
                  onClick={() => setMode(item)}
                  key={item}
                >
                  {item}
                </button>
              ))}
            </div>
          </div>

          <div className="chat-messages" aria-live="polite">
            {messages.length ? (
              messages.map((item, index) => (
                <article className={`message ${item.role}`} key={`${item.role}-${index}`}>
                  <span className="message-avatar">{item.role === 'assistant' ? <Bot size={18} /> : 'Tú'}</span>
                  <div>
                    <MarkdownMessage content={item.content} />
                    {item.role === 'assistant' && (
                      <button className="speak-message" onClick={() => browserTTS.speak(item.content, rate, voice || undefined)}>
                        <Volume2 size={14} /> Escuchar
                      </button>
                    )}
                  </div>
                </article>
              ))
            ) : (
              <div className="chat-empty">
                <div className="empty-orb">
                  <BrainCircuit size={28} />
                </div>
                <h2>Listo para estudiar{selected ? ` ${selected.name}` : ''}</h2>
                <p>Pedime una explicación, un repaso o que te haga preguntas. Podés escribir o hablar.</p>
                <div>
                  {['Explicame este tema desde cero', 'Haceme 3 preguntas para practicar', 'Ayudame a organizar un repaso'].map(
                    (prompt) => (
                      <button key={prompt} onClick={() => setMessage(prompt)}>
                        {prompt}
                        <ChevronRight size={15} />
                      </button>
                    )
                  )}
                </div>
              </div>
            )}

            {loading && (
              <article className="message assistant">
                <span className="message-avatar">
                  <Bot size={18} />
                </span>
                <div className="typing">
                  <i />
                  <i />
                  <i />
                </div>
              </article>
            )}
          </div>

          <form className="chat-input" onSubmit={(event) => void send(event)}>
            <textarea
              aria-label="Mensaje para la IA"
              value={message}
              onChange={(event) => setMessage(event.target.value)}
              placeholder={mode === 'Voz' ? 'Hablá o escribí tu consulta...' : 'Escribí lo que querés estudiar...'}
              maxLength={6000}
              rows={2}
            />
            <button
              type="button"
              aria-label={listening ? 'Detener dictado' : 'Dictar mensaje'}
              className={`icon-button ${listening ? 'recording' : ''}`}
              onClick={dictate}
            >
              <Mic size={19} />
            </button>
            <button type="submit" aria-label="Enviar" className="send-button" disabled={loading || !message.trim()}>
              <Send size={18} />
            </button>
          </form>

          {!browserSTT.supported && <p className="voice-fallback">Tu navegador no admite dictado. Podés estudiar usando el teclado.</p>}
        </section>

        <aside className="study-side">
          <Card>
            <h2>
              <Volume2 size={18} /> Lectura en voz alta
            </h2>
            <p>Usa las voces gratuitas de tu dispositivo.</p>
            <Field label="Voz">
              <select value={voice} onChange={(event) => setVoice(event.target.value)}>
                <option value="">Predeterminada</option>
                {voices.map((item) => (
                  <option key={item.name} value={item.name}>
                    {item.name}
                  </option>
                ))}
              </select>
            </Field>
            <Field label={`Velocidad ${rate}×`}>
              <input
                type="range"
                min="0.5"
                max="2"
                step="0.1"
                value={rate}
                onChange={(event) => setRate(Number(event.target.value))}
              />
            </Field>
            <div className="audio-actions">
              <button className="icon-button" onClick={() => browserTTS.resume()} aria-label="Reanudar">
                <Play size={17} />
              </button>
              <button className="icon-button" onClick={() => browserTTS.pause()} aria-label="Pausar">
                <Pause size={17} />
              </button>
              <button className="icon-button" onClick={() => browserTTS.stop()} aria-label="Detener">
                <Square size={16} />
              </button>
            </div>
          </Card>

          <Card className="quiz-builder">
            <div className="card-kicker">
              <Sparkles size={16} /> QUIZ CON IA
            </div>
            <h2>Comprobá lo que entendiste</h2>
            <Field label="Tema">
              <input
                value={quizTopic}
                maxLength={150}
                onChange={(event) => setQuizTopic(event.target.value)}
                placeholder="Ej. funciones cuadráticas"
              />
            </Field>
            <Button className="button-secondary full" onClick={() => void createQuiz()} loading={quizLoading}>
              <BrainCircuit size={16} /> Crear 5 preguntas
            </Button>
          </Card>
        </aside>
      </div>

      {quiz && (
        <section className="quiz-runner">
          <Card>
            <header>
              <div>
                <p className="eyebrow">QUIZ ACTIVO</p>
                <h2>{quiz.title}</h2>
              </div>
              {!result && <span>{quiz.questions.length} preguntas</span>}
            </header>

            {quiz.questions.map((question) => (
              <fieldset
                className={`quiz-question ${
                  result ? (result.feedback[question.id] === '¡Correcto!' ? 'correct' : 'incorrect') : ''
                }`}
                key={question.id}
                disabled={Boolean(result)}
              >
                <legend>
                  {question.position}. {question.prompt}
                </legend>
                {question.options?.length ? (
                  <div className="quiz-options">
                    {question.options.map((option, index) => (
                      <label key={option}>
                        <input
                          type="radio"
                          name={question.id}
                          value={String.fromCharCode(65 + index)}
                          checked={answers[question.id] === String.fromCharCode(65 + index)}
                          onChange={(event) => setAnswers({ ...answers, [question.id]: event.target.value })}
                        />
                        <span>{String.fromCharCode(65 + index)}</span>
                        {option}
                      </label>
                    ))}
                  </div>
                ) : (
                  <textarea
                    value={answers[question.id] ?? ''}
                    onChange={(event) => setAnswers({ ...answers, [question.id]: event.target.value })}
                    placeholder="Tu respuesta"
                  />
                )}
                {result && <p className="quiz-feedback">{result.feedback[question.id]}</p>}
              </fieldset>
            ))}

            {result ? (
              <div className="quiz-result">
                <CheckCircle2 size={28} />
                <div>
                  <strong>
                    {result.score}% · {result.correct}/{quiz.questions.length} correctas
                  </strong>
                  <p>{result.xp ? `Ganaste ${result.xp} XP. ` : ''}Usá el feedback para tu próximo repaso.</p>
                </div>
                <Button
                  className="button-secondary"
                  onClick={() => {
                    setQuiz(null)
                    setResult(null)
                  }}
                >
                  <RotateCcw size={16} /> Nuevo quiz
                </Button>
              </div>
            ) : (
              <Button className="button-primary" onClick={() => void submitQuiz()}>
                Enviar respuestas <CheckCircle2 size={16} />
              </Button>
            )}
          </Card>
        </section>
      )}
    </div>
  )
}
