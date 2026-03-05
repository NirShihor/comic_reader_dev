import { Word } from './comic';

export type QuizState =
  | 'idle'        // Waiting to start
  | 'prompting'   // Showing English word
  | 'listening'   // Recording user speech
  | 'processing'  // Sending to Whisper API
  | 'feedback'    // Showing result
  | 'completed';  // Quiz finished

export interface QuizAttempt {
  wordId: string;
  spokenText: string;      // What Whisper recognized
  expectedText: string;    // Correct Spanish word
  isCorrect: boolean;
  timestamp: Date;
}

export interface QuizResult {
  wordId: string;
  word: Word;
  isCorrect: boolean;
  spokenText: string;
  expectedText: string;
  panelId: string;
  pageId: string;
}

export interface QuizSession {
  comicId: string;
  startedAt: Date;
  completedAt?: Date;
  results: QuizResult[];
  currentIndex: number;
  totalWords: number;
}
