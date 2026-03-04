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
  'tener': {
    baseForm: 'tener',
    meaning: 'to have',
    partOfSpeech: 'verb',
    audioUrl: 'dict:tener',
  },
  'venir': {
    baseForm: 'venir',
    meaning: 'to come',
    partOfSpeech: 'verb',
    audioUrl: 'dict:venir',
  },
  'perderse': {
    baseForm: 'perderse',
    meaning: 'to get lost',
    partOfSpeech: 'verb',
    audioUrl: 'dict:perderse',
  },
  'poder': {
    baseForm: 'poder',
    meaning: 'to be able, can',
    partOfSpeech: 'verb',
    audioUrl: 'dict:poder',
  },
  'ayudar': {
    baseForm: 'ayudar',
    meaning: 'to help',
    partOfSpeech: 'verb',
    audioUrl: 'dict:ayudar',
  },
  'hablar': {
    baseForm: 'hablar',
    meaning: 'to speak',
    partOfSpeech: 'verb',
    audioUrl: 'dict:hablar',
  },
  'aprender': {
    baseForm: 'aprender',
    meaning: 'to learn',
    partOfSpeech: 'verb',
    audioUrl: 'dict:aprender',
  },
  'preocuparse': {
    baseForm: 'preocuparse',
    meaning: 'to worry',
    partOfSpeech: 'verb',
    audioUrl: 'dict:preocuparse',
  },
  'ir': {
    baseForm: 'ir',
    meaning: 'to go',
    partOfSpeech: 'verb',
    audioUrl: 'dict:ir',
  },
  'pasar': {
    baseForm: 'pasar',
    meaning: 'to happen, to pass',
    partOfSpeech: 'verb',
    audioUrl: 'dict:pasar',
  },
  'tomar': {
    baseForm: 'tomar',
    meaning: 'to take',
    partOfSpeech: 'verb',
    audioUrl: 'dict:tomar',
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
  'visitante': {
    baseForm: 'visitante',
    meaning: 'visitor',
    partOfSpeech: 'noun',
    audioUrl: 'dict:visitante',
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
  'tarde': {
    baseForm: 'tarde',
    meaning: 'afternoon, late',
    partOfSpeech: 'noun',
    audioUrl: 'dict:tarde',
  },
  'noche': {
    baseForm: 'noche',
    meaning: 'night',
    partOfSpeech: 'noun',
    audioUrl: 'dict:noche',
  },
  'miedo': {
    baseForm: 'miedo',
    meaning: 'fear',
    partOfSpeech: 'noun',
    audioUrl: 'dict:miedo',
  },
  'planeta': {
    baseForm: 'planeta',
    meaning: 'planet',
    partOfSpeech: 'noun',
    audioUrl: 'dict:planeta',
  },
  'accidente': {
    baseForm: 'accidente',
    meaning: 'accident',
    partOfSpeech: 'noun',
    audioUrl: 'dict:accidente',
  },
  'casa': {
    baseForm: 'casa',
    meaning: 'house, home',
    partOfSpeech: 'noun',
    audioUrl: 'dict:casa',
  },
  'control': {
    baseForm: 'control',
    meaning: 'control',
    partOfSpeech: 'noun',
    audioUrl: 'dict:control',
  },
  'sueño': {
    baseForm: 'sueño',
    meaning: 'dream, sleep',
    partOfSpeech: 'noun',
    audioUrl: 'dict:sueño',
  },
  'español': {
    baseForm: 'español',
    meaning: 'Spanish (language)',
    partOfSpeech: 'noun',
    audioUrl: 'dict:español',
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
  'solo': {
    baseForm: 'solo',
    meaning: 'only, alone',
    partOfSpeech: 'adjective',
    audioUrl: 'dict:solo',
  },
  'poco': {
    baseForm: 'poco',
    meaning: 'little, few',
    partOfSpeech: 'adjective',
    audioUrl: 'dict:poco',
  },
  'claro': {
    baseForm: 'claro',
    meaning: 'clear, of course',
    partOfSpeech: 'adjective',
    audioUrl: 'dict:claro',
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
  'aquí': {
    baseForm: 'aquí',
    meaning: 'here',
    partOfSpeech: 'adverb',
    audioUrl: 'dict:aquí',
  },
  'no': {
    baseForm: 'no',
    meaning: 'no, not',
    partOfSpeech: 'adverb',
    audioUrl: 'dict:no',
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
  'qué': {
    baseForm: 'qué',
    meaning: 'what (interrogative)',
    partOfSpeech: 'pronoun',
    audioUrl: 'dict:qué',
  },
  'eso': {
    baseForm: 'eso',
    meaning: 'that (demonstrative)',
    partOfSpeech: 'pronoun',
    audioUrl: 'dict:eso',
  },
  'quién': {
    baseForm: 'quién',
    meaning: 'who (interrogative)',
    partOfSpeech: 'pronoun',
    audioUrl: 'dict:quién',
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
  'por': {
    baseForm: 'por',
    meaning: 'for, by, because of',
    partOfSpeech: 'preposition',
    audioUrl: 'dict:por',
  },

  // Articles
  'la': {
    baseForm: 'la',
    meaning: 'the (feminine)',
    partOfSpeech: 'article',
    audioUrl: 'dict:la',
  },
  'el': {
    baseForm: 'el',
    meaning: 'the (masculine)',
    partOfSpeech: 'article',
    audioUrl: 'dict:el',
  },
  'un': {
    baseForm: 'un',
    meaning: 'a, an (masculine)',
    partOfSpeech: 'article',
    audioUrl: 'dict:un',
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
  'oh': {
    baseForm: 'oh',
    meaning: 'oh (interjection)',
    partOfSpeech: 'interjection',
    audioUrl: 'dict:oh',
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
