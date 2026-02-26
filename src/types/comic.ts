export interface Word {
  id: string;
  text: string;
  meaning: string;
  baseForm?: string;
  audioUrl?: string;
  startTimeMs?: number;
  endTimeMs?: number;
}

export interface Sentence {
  id: string;
  text: string;
  translation?: string;
  audioUrl?: string;
  words: Word[];
}

export interface Bubble {
  id: string;
  type: 'speech' | 'narration' | 'thought';
  positionX: number; // percentage 0-1 for panel view layout
  positionY: number;
  width: number;
  height: number;
  sentences: Sentence[];
}

export interface Panel {
  id: string;
  artworkImage: string;
  panelOrder: number;
  // Tap zone coordinates for master page (percentage 0-1)
  tapZoneX: number;
  tapZoneY: number;
  tapZoneWidth: number;
  tapZoneHeight: number;
  bubbles: Bubble[];
}

export interface Page {
  id: string;
  pageNumber: number;
  masterImage: string;
  panels: Panel[];
}

export interface Comic {
  id: string;
  title: string;
  description: string;
  coverImage: string;
  level: 'beginner' | 'intermediate' | 'advanced';
  isPremium: boolean;
  pages: Page[];
}

export interface SavedWord {
  wordId: string;
  word: Word;
  savedAt: Date;
  reviewState: 'new' | 'learning' | 'mastered';
}

export interface DictionaryEntry {
  baseForm: string;
  meaning: string;
  partOfSpeech?: 'noun' | 'verb' | 'adjective' | 'adverb' | 'pronoun' | 'preposition' | 'conjunction' | 'interjection' | 'article';
  audioUrl?: string;
}

export interface ReadingProgress {
  comicId: string;
  pageNumber: number;
  panelNumber: number;
  updatedAt: Date;
}
