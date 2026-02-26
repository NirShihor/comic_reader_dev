// Audio source type - can be a require() result or { uri: string }
type AudioSource = number | { uri: string };

// Import sentence audio files - organized by comic
export const gironaAudio = {
  s1: require('@/assets/comics/girona_trip/audio/s1.mp3'),
  s2: require('@/assets/comics/girona_trip/audio/s2.mp3'),
  s3: require('@/assets/comics/girona_trip/audio/s3.mp3'),
};

// Import word form audio files (actual words as they appear in sentences)
export const wordAudio: { [key: string]: AudioSource } = {
  'a': require('@/assets/dictionary/a.mp3'),
  'ahora': require('@/assets/dictionary/ahora.mp3'),
  'al': require('@/assets/dictionary/al.mp3'),
  'apartamento': require('@/assets/dictionary/apartamento.mp3'),
  'barcelona': require('@/assets/dictionary/barcelona.mp3'),
  'barrio': require('@/assets/dictionary/barrio.mp3'),
  'bien': require('@/assets/dictionary/bien.mp3'),
  'bienvenida': require('@/assets/dictionary/bienvenida.mp3'),
  'bonita': require('@/assets/dictionary/bonita.mp3'),
  'buenos': require('@/assets/dictionary/buenos.mp3'),
  'carlos': require('@/assets/dictionary/carlos.mp3'),
  'ciudad': require('@/assets/dictionary/ciudad.mp3'),
  'cómo': require('@/assets/dictionary/cómo.mp3'),
  'correcta': require('@/assets/dictionary/correcta.mp3'),
  'de': require('@/assets/dictionary/de.mp3'),
  'día': require('@/assets/dictionary/día.mp3'),
  'días': require('@/assets/dictionary/días.mp3'),
  'dónde': require('@/assets/dictionary/dónde.mp3'),
  'emocionada': require('@/assets/dictionary/emocionada.mp3'),
  'en': require('@/assets/dictionary/en.mp3'),
  'encanta': require('@/assets/dictionary/encanta.mp3'),
  'encontrar': require('@/assets/dictionary/encontrar.mp3'),
  'encontré': require('@/assets/dictionary/encontré.mp3'),
  'eres': require('@/assets/dictionary/eres.mp3'),
  'es': require('@/assets/dictionary/es.mp3'),
  'está': require('@/assets/dictionary/está.mp3'),
  'estado': require('@/assets/dictionary/estado.mp3'),
  'estás': require('@/assets/dictionary/estás.mp3'),
  'estoy': require('@/assets/dictionary/estoy.mp3'),
  'girona': require('@/assets/dictionary/girona.mp3'),
  'gracias': require('@/assets/dictionary/gracias.mp3'),
  'gusta': require('@/assets/dictionary/gusta.mp3'),
  'gusto': require('@/assets/dictionary/gusto.mp3'),
  'he': require('@/assets/dictionary/he.mp3'),
  'hogar': require('@/assets/dictionary/hogar.mp3'),
  'hola': require('@/assets/dictionary/hola.mp3'),
  'justo': require('@/assets/dictionary/justo.mp3'),
  'la': require('@/assets/dictionary/la.mp3'),
  'llamo': require('@/assets/dictionary/llamo.mp3'),
  'llega': require('@/assets/dictionary/llega.mp3'),
  'lo': require('@/assets/dictionary/lo.mp3'),
  'maría': require('@/assets/dictionary/maría.mp3'),
  'me': require('@/assets/dictionary/me.mp3'),
  'mi': require('@/assets/dictionary/mi.mp3'),
  'mucho': require('@/assets/dictionary/mucho.mp3'),
  'muy': require('@/assets/dictionary/muy.mp3'),
  'necesito': require('@/assets/dictionary/necesito.mp3'),
  'nuevo': require('@/assets/dictionary/nuevo.mp3'),
  'nunca': require('@/assets/dictionary/nunca.mp3'),
  'plataforma': require('@/assets/dictionary/plataforma.mp3'),
  'sí': require('@/assets/dictionary/sí.mp3'),
  'siguiente': require('@/assets/dictionary/siguiente.mp3'),
  'soy': require('@/assets/dictionary/soy.mp3'),
  'su': require('@/assets/dictionary/su.mp3'),
  'súper': require('@/assets/dictionary/súper.mp3'),
  'te': require('@/assets/dictionary/te.mp3'),
  'tiempo': require('@/assets/dictionary/tiempo.mp3'),
  'tu': require('@/assets/dictionary/tu.mp3'),
  'tú': require('@/assets/dictionary/tú.mp3'),
  'vecino': require('@/assets/dictionary/vecino.mp3'),
  'y': require('@/assets/dictionary/y.mp3'),
  'yo': require('@/assets/dictionary/yo.mp3'),
};

// Import dictionary audio files (base forms for definitions)
export const dictionaryAudio: { [key: string]: AudioSource } = {
  'llegar': require('@/assets/dictionary/llegar.mp3'),
  'llamarse': require('@/assets/dictionary/llamarse.mp3'),
  'ser': require('@/assets/dictionary/ser.mp3'),
  'estar': require('@/assets/dictionary/estar.mp3'),
  'gustar': require('@/assets/dictionary/gustar.mp3'),
  'encantar': require('@/assets/dictionary/encantar.mp3'),
  'haber': require('@/assets/dictionary/haber.mp3'),
  'necesitar': require('@/assets/dictionary/necesitar.mp3'),
  'encontrar': require('@/assets/dictionary/encontrar.mp3'),
  'apartamento': require('@/assets/dictionary/apartamento.mp3'),
  'vecino': require('@/assets/dictionary/vecino.mp3'),
  'gusto': require('@/assets/dictionary/gusto.mp3'),
  'ciudad': require('@/assets/dictionary/ciudad.mp3'),
  'barrio': require('@/assets/dictionary/barrio.mp3'),
  'día': require('@/assets/dictionary/día.mp3'),
  'hogar': require('@/assets/dictionary/hogar.mp3'),
  'plataforma': require('@/assets/dictionary/plataforma.mp3'),
  'tiempo': require('@/assets/dictionary/tiempo.mp3'),
  'nuevo': require('@/assets/dictionary/nuevo.mp3'),
  'bonito': require('@/assets/dictionary/bonito.mp3'),
  'bienvenido': require('@/assets/dictionary/bienvenido.mp3'),
  'siguiente': require('@/assets/dictionary/siguiente.mp3'),
  'bueno': require('@/assets/dictionary/bueno.mp3'),
  'emocionado': require('@/assets/dictionary/emocionado.mp3'),
  'correcto': require('@/assets/dictionary/correcto.mp3'),
  'justo': require('@/assets/dictionary/justo.mp3'),
  'muy': require('@/assets/dictionary/muy.mp3'),
  'bien': require('@/assets/dictionary/bien.mp3'),
  'nunca': require('@/assets/dictionary/nunca.mp3'),
  'ahora': require('@/assets/dictionary/ahora.mp3'),
  'dónde': require('@/assets/dictionary/dónde.mp3'),
  'cómo': require('@/assets/dictionary/cómo.mp3'),
  'súper': require('@/assets/dictionary/súper.mp3'),
  'yo': require('@/assets/dictionary/yo.mp3'),
  'tú': require('@/assets/dictionary/tú.mp3'),
  'me': require('@/assets/dictionary/me.mp3'),
  'te': require('@/assets/dictionary/te.mp3'),
  'lo': require('@/assets/dictionary/lo.mp3'),
  'a': require('@/assets/dictionary/a.mp3'),
  'de': require('@/assets/dictionary/de.mp3'),
  'en': require('@/assets/dictionary/en.mp3'),
  'al': require('@/assets/dictionary/al.mp3'),
  'la': require('@/assets/dictionary/la.mp3'),
  'su': require('@/assets/dictionary/su.mp3'),
  'tu': require('@/assets/dictionary/tu.mp3'),
  'mi': require('@/assets/dictionary/mi.mp3'),
  'mucho': require('@/assets/dictionary/mucho.mp3'),
  'y': require('@/assets/dictionary/y.mp3'),
  'hola': require('@/assets/dictionary/hola.mp3'),
  'sí': require('@/assets/dictionary/sí.mp3'),
  'gracias': require('@/assets/dictionary/gracias.mp3'),
};

// Map audio URLs to sources - organized by comic
const localAudioMap: { [key: string]: AudioSource } = {
  // Girona
  'girona-s1': gironaAudio.s1,
  'girona-s2': gironaAudio.s2,
  'girona-s3': gironaAudio.s3,
};

export function getAudioSource(uri: string): AudioSource | null {
  if (!uri) return null;

  if (uri.startsWith('local:')) {
    const key = uri.replace('local:', '');
    return localAudioMap[key] || null;
  }

  if (uri.startsWith('word:')) {
    const key = uri.replace('word:', '');
    return wordAudio[key] || null;
  }

  if (uri.startsWith('dict:')) {
    const key = uri.replace('dict:', '');
    return dictionaryAudio[key] || null;
  }

  // Return as URI for remote files
  return { uri };
}

export function isLocalAudio(uri: string): boolean {
  return uri?.startsWith('local:') ?? false;
}

export function isWordAudio(uri: string): boolean {
  return uri?.startsWith('word:') ?? false;
}

export function isDictionaryAudio(uri: string): boolean {
  return uri?.startsWith('dict:') ?? false;
}

export function hasWordAudio(word: string): boolean {
  // Normalize: lowercase and strip punctuation
  const normalized = word.toLowerCase().replace(/[^a-záéíóúüñ]/g, '');
  return normalized in wordAudio;
}

export function getWordAudioUrl(word: string): string | null {
  const normalized = word.toLowerCase().replace(/[^a-záéíóúüñ]/g, '');
  if (normalized in wordAudio) {
    return `word:${normalized}`;
  }
  return null;
}

export function hasDictionaryAudio(baseForm: string): boolean {
  return baseForm in dictionaryAudio;
}
