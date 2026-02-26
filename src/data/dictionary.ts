import { DictionaryEntry } from '../types/comic';

/**
 * Central Spanish dictionary for the app.
 * Each entry has a unique base form with its meaning and audio.
 * Audio uses a consistent "dictionary voice" distinct from narrative voices.
 */
export const dictionary: Record<string, DictionaryEntry> = {
  // Verbs
  'llegar': {
    baseForm: 'llegar',
    meaning: 'to arrive',
    partOfSpeech: 'verb',
    audioUrl: 'dict:llegar',
  },
  'llamarse': {
    baseForm: 'llamarse',
    meaning: 'to be called, to call oneself',
    partOfSpeech: 'verb',
    audioUrl: 'dict:llamarse',
  },
  'ser': {
    baseForm: 'ser',
    meaning: 'to be (permanent characteristics)',
    partOfSpeech: 'verb',
    audioUrl: 'dict:ser',
  },
  'estar': {
    baseForm: 'estar',
    meaning: 'to be (temporary state/location)',
    partOfSpeech: 'verb',
    audioUrl: 'dict:estar',
  },
  'gustar': {
    baseForm: 'gustar',
    meaning: 'to please, to like',
    partOfSpeech: 'verb',
    audioUrl: 'dict:gustar',
  },
  'encantar': {
    baseForm: 'encantar',
    meaning: 'to love, to enchant',
    partOfSpeech: 'verb',
    audioUrl: 'dict:encantar',
  },
  'haber': {
    baseForm: 'haber',
    meaning: 'to have (auxiliary)',
    partOfSpeech: 'verb',
    audioUrl: 'dict:haber',
  },
  'necesitar': {
    baseForm: 'necesitar',
    meaning: 'to need',
    partOfSpeech: 'verb',
    audioUrl: 'dict:necesitar',
  },
  'encontrar': {
    baseForm: 'encontrar',
    meaning: 'to find',
    partOfSpeech: 'verb',
    audioUrl: 'dict:encontrar',
  },

  // Nouns
  'apartamento': {
    baseForm: 'apartamento',
    meaning: 'apartment',
    partOfSpeech: 'noun',
    audioUrl: 'dict:apartamento',
  },
  'vecino': {
    baseForm: 'vecino',
    meaning: 'neighbor',
    partOfSpeech: 'noun',
    audioUrl: 'dict:vecino',
  },
  'gusto': {
    baseForm: 'gusto',
    meaning: 'pleasure, taste',
    partOfSpeech: 'noun',
    audioUrl: 'dict:gusto',
  },
  'ciudad': {
    baseForm: 'ciudad',
    meaning: 'city',
    partOfSpeech: 'noun',
    audioUrl: 'dict:ciudad',
  },
  'barrio': {
    baseForm: 'barrio',
    meaning: 'neighborhood',
    partOfSpeech: 'noun',
    audioUrl: 'dict:barrio',
  },
  'día': {
    baseForm: 'día',
    meaning: 'day',
    partOfSpeech: 'noun',
    audioUrl: 'dict:día',
  },
  'hogar': {
    baseForm: 'hogar',
    meaning: 'home',
    partOfSpeech: 'noun',
    audioUrl: 'dict:hogar',
  },
  'plataforma': {
    baseForm: 'plataforma',
    meaning: 'platform',
    partOfSpeech: 'noun',
    audioUrl: 'dict:plataforma',
  },
  'tiempo': {
    baseForm: 'tiempo',
    meaning: 'time, weather',
    partOfSpeech: 'noun',
    audioUrl: 'dict:tiempo',
  },

  // Adjectives
  'nuevo': {
    baseForm: 'nuevo',
    meaning: 'new',
    partOfSpeech: 'adjective',
    audioUrl: 'dict:nuevo',
  },
  'bonito': {
    baseForm: 'bonito',
    meaning: 'beautiful, pretty',
    partOfSpeech: 'adjective',
    audioUrl: 'dict:bonito',
  },
  'bienvenido': {
    baseForm: 'bienvenido',
    meaning: 'welcome',
    partOfSpeech: 'adjective',
    audioUrl: 'dict:bienvenido',
  },
  'siguiente': {
    baseForm: 'siguiente',
    meaning: 'following, next',
    partOfSpeech: 'adjective',
    audioUrl: 'dict:siguiente',
  },
  'bueno': {
    baseForm: 'bueno',
    meaning: 'good',
    partOfSpeech: 'adjective',
    audioUrl: 'dict:bueno',
  },
  'emocionado': {
    baseForm: 'emocionado',
    meaning: 'excited',
    partOfSpeech: 'adjective',
    audioUrl: 'dict:emocionado',
  },
  'correcto': {
    baseForm: 'correcto',
    meaning: 'correct, right',
    partOfSpeech: 'adjective',
    audioUrl: 'dict:correcto',
  },
  'justo': {
    baseForm: 'justo',
    meaning: 'just, right, fair',
    partOfSpeech: 'adjective',
    audioUrl: 'dict:justo',
  },

  // Adverbs
  'muy': {
    baseForm: 'muy',
    meaning: 'very',
    partOfSpeech: 'adverb',
    audioUrl: 'dict:muy',
  },
  'bien': {
    baseForm: 'bien',
    meaning: 'well, good',
    partOfSpeech: 'adverb',
    audioUrl: 'dict:bien',
  },
  'nunca': {
    baseForm: 'nunca',
    meaning: 'never',
    partOfSpeech: 'adverb',
    audioUrl: 'dict:nunca',
  },
  'ahora': {
    baseForm: 'ahora',
    meaning: 'now',
    partOfSpeech: 'adverb',
    audioUrl: 'dict:ahora',
  },
  'dónde': {
    baseForm: 'dónde',
    meaning: 'where (interrogative)',
    partOfSpeech: 'adverb',
    audioUrl: 'dict:dónde',
  },
  'cómo': {
    baseForm: 'cómo',
    meaning: 'how (interrogative)',
    partOfSpeech: 'adverb',
    audioUrl: 'dict:cómo',
  },
  'súper': {
    baseForm: 'súper',
    meaning: 'super, very',
    partOfSpeech: 'adverb',
    audioUrl: 'dict:súper',
  },

  // Pronouns
  'yo': {
    baseForm: 'yo',
    meaning: 'I',
    partOfSpeech: 'pronoun',
    audioUrl: 'dict:yo',
  },
  'tú': {
    baseForm: 'tú',
    meaning: 'you (informal)',
    partOfSpeech: 'pronoun',
    audioUrl: 'dict:tú',
  },
  'me': {
    baseForm: 'me',
    meaning: 'me, myself',
    partOfSpeech: 'pronoun',
    audioUrl: 'dict:me',
  },
  'te': {
    baseForm: 'te',
    meaning: 'you (object)',
    partOfSpeech: 'pronoun',
    audioUrl: 'dict:te',
  },
  'lo': {
    baseForm: 'lo',
    meaning: 'it, him (direct object)',
    partOfSpeech: 'pronoun',
    audioUrl: 'dict:lo',
  },

  // Prepositions
  'a': {
    baseForm: 'a',
    meaning: 'to, at',
    partOfSpeech: 'preposition',
    audioUrl: 'dict:a',
  },
  'de': {
    baseForm: 'de',
    meaning: 'of, from',
    partOfSpeech: 'preposition',
    audioUrl: 'dict:de',
  },
  'en': {
    baseForm: 'en',
    meaning: 'in, on',
    partOfSpeech: 'preposition',
    audioUrl: 'dict:en',
  },
  'al': {
    baseForm: 'al',
    meaning: 'to the (a + el)',
    partOfSpeech: 'preposition',
    audioUrl: 'dict:al',
  },

  // Articles
  'la': {
    baseForm: 'la',
    meaning: 'the (feminine)',
    partOfSpeech: 'article',
    audioUrl: 'dict:la',
  },

  // Possessives / Determiners
  'su': {
    baseForm: 'su',
    meaning: 'his, her, your (formal), their',
    partOfSpeech: 'pronoun',
    audioUrl: 'dict:su',
  },
  'tu': {
    baseForm: 'tu',
    meaning: 'your (informal)',
    partOfSpeech: 'pronoun',
    audioUrl: 'dict:tu',
  },
  'mi': {
    baseForm: 'mi',
    meaning: 'my',
    partOfSpeech: 'pronoun',
    audioUrl: 'dict:mi',
  },
  'mucho': {
    baseForm: 'mucho',
    meaning: 'much, a lot',
    partOfSpeech: 'adjective',
    audioUrl: 'dict:mucho',
  },

  // Conjunctions
  'y': {
    baseForm: 'y',
    meaning: 'and',
    partOfSpeech: 'conjunction',
    audioUrl: 'dict:y',
  },

  // Interjections
  'hola': {
    baseForm: 'hola',
    meaning: 'hello',
    partOfSpeech: 'interjection',
    audioUrl: 'dict:hola',
  },
  'sí': {
    baseForm: 'sí',
    meaning: 'yes',
    partOfSpeech: 'interjection',
    audioUrl: 'dict:sí',
  },
  'gracias': {
    baseForm: 'gracias',
    meaning: 'thank you',
    partOfSpeech: 'interjection',
    audioUrl: 'dict:gracias',
  },
};

/**
 * Get a dictionary entry by base form
 */
export function getDictionaryEntry(baseForm: string): DictionaryEntry | undefined {
  return dictionary[baseForm.toLowerCase()];
}

/**
 * Get all dictionary entries as an array
 */
export function getAllDictionaryEntries(): DictionaryEntry[] {
  return Object.values(dictionary);
}

/**
 * Get all unique base forms that need audio files
 */
export function getWordsNeedingAudio(): string[] {
  return Object.keys(dictionary).filter(key => !dictionary[key].audioUrl);
}
