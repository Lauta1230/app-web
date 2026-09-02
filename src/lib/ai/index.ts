import { invoke } from '../../services/api'
import type { QuizQuestion } from '../../types/domain'

/** Browser-safe abstraction. Gemini is only implemented inside Edge Functions. */
export interface AIProvider {
  generateText(input: ChatRequest): Promise<ChatResponse>
  generateStructured(input: QuizRequest): Promise<QuizResponse>
  analyzeImage(documentId: string): Promise<unknown>
  analyzeDocument(documentId: string): Promise<unknown>
}
export type ChatRequest = { message: string; conversationId?: string; subjectId?: string; noteId?: string; documentId?: string; mode?: string }
export type ChatResponse = { conversationId: string; message: string }
export type QuizRequest = { subjectId: string; topic: string; difficulty: 'easy' | 'normal' | 'hard'; questionCount: number; sourceText?: string }
export type QuizResponse = { quizId: string; title: string; questions: QuizQuestion[] }

/** This adapter never knows an API key and transports requests to secure Edge Functions. */
export class GeminiProvider implements AIProvider {
  async generateText(input: ChatRequest): Promise<ChatResponse> { const result = await invoke<{ conversation_id: string; message: string }>('ai-chat', { message: input.message, conversation_id: input.conversationId, subject_id: input.subjectId, note_id: input.noteId, document_id: input.documentId, mode: input.mode }); return { conversationId: result.conversation_id, message: result.message } }
  async generateStructured(input: QuizRequest): Promise<QuizResponse> { const result = await invoke<{ quiz_id: string; title: string; questions: QuizQuestion[] }>('ai-quiz', { subject_id: input.subjectId, topic: input.topic, difficulty: input.difficulty, question_count: input.questionCount, source_text: input.sourceText }); return { quizId: result.quiz_id, title: result.title, questions: result.questions } }
  analyzeImage(documentId: string): Promise<unknown> { return invoke('ocr-document', { document_id: documentId }) }
  analyzeDocument(documentId: string): Promise<unknown> { return this.analyzeImage(documentId) }
}
export class AIContextBuilder { static fromSelection(input: { subjectId?: string; noteId?: string; documentId?: string; mode?: string }) { return input } }
export class AIResponseValidator { static quizCount(questions: QuizQuestion[], expected: number): boolean { return questions.length === expected && questions.every((question) => Boolean(question.id && question.prompt)) } }
export class AIService { constructor(private readonly provider: AIProvider = new GeminiProvider()) {} chat(input: ChatRequest) { return this.provider.generateText(input) } quiz(input: QuizRequest) { return this.provider.generateStructured(input) } }
