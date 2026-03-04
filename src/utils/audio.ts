import { gironaAudio, alienAudio } from '../data/comics';

type AudioSource = number | { uri: string };

// Import word form audio files (actual words as they appear in sentences)
export const wordAudio: { [key: string]: AudioSource } = {
  'a': require('@/assets/dictionary/a.mp3'),
  'accidente': require('@/assets/dictionary/accidente.mp3'),
  'ahora': require('@/assets/dictionary/ahora.mp3'),
  'al': require('@/assets/dictionary/al.mp3'),
  'apartamento': require('@/assets/dictionary/apartamento.mp3'),
  'aprendiendo': require('@/assets/dictionary/aprendiendo.mp3'),
  'aquí': require('@/assets/dictionary/aquí.mp3'),
  'ayudaré': require('@/assets/dictionary/ayudaré.mp3'),
  'ayudarme': require('@/assets/dictionary/ayudarme.mp3'),
  'barcelona': require('@/assets/dictionary/barcelona.mp3'),
  'barrio': require('@/assets/dictionary/barrio.mp3'),
  'bien': require('@/assets/dictionary/bien.mp3'),
  'bienvenida': require('@/assets/dictionary/bienvenida.mp3'),
  'bonita': require('@/assets/dictionary/bonita.mp3'),
  'buenos': require('@/assets/dictionary/buenos.mp3'),
  'carlos': require('@/assets/dictionary/carlos.mp3'),
  'casa': require('@/assets/dictionary/casa.mp3'),
  'ciudad': require('@/assets/dictionary/ciudad.mp3'),
  'claro': require('@/assets/dictionary/claro.mp3'),
  'control': require('@/assets/dictionary/control.mp3'),
  'cómo': require('@/assets/dictionary/cómo.mp3'),
  'correcta': require('@/assets/dictionary/correcta.mp3'),
  'de': require('@/assets/dictionary/de.mp3'),
  'día': require('@/assets/dictionary/día.mp3'),
  'días': require('@/assets/dictionary/días.mp3'),
  'dónde': require('@/assets/dictionary/dónde.mp3'),
  'el': require('@/assets/dictionary/el.mp3'),
  'emocionada': require('@/assets/dictionary/emocionada.mp3'),
  'en': require('@/assets/dictionary/en.mp3'),
  'encanta': require('@/assets/dictionary/encanta.mp3'),
  'encontrar': require('@/assets/dictionary/encontrar.mp3'),
  'encontré': require('@/assets/dictionary/encontré.mp3'),
  'era': require('@/assets/dictionary/era.mp3'),
  'eres': require('@/assets/dictionary/eres.mp3'),
  'es': require('@/assets/dictionary/es.mp3'),
  'eso': require('@/assets/dictionary/eso.mp3'),
  'español': require('@/assets/dictionary/español.mp3'),
  'está': require('@/assets/dictionary/está.mp3'),
  'estado': require('@/assets/dictionary/estado.mp3'),
  'estás': require('@/assets/dictionary/estás.mp3'),
  'estoy': require('@/assets/dictionary/estoy.mp3'),
  'fue': require('@/assets/dictionary/fue.mp3'),
  'girona': require('@/assets/dictionary/girona.mp3'),
  'gracias': require('@/assets/dictionary/gracias.mp3'),
  'gusta': require('@/assets/dictionary/gusta.mp3'),
  'gusto': require('@/assets/dictionary/gusto.mp3'),
  'hablo': require('@/assets/dictionary/hablo.mp3'),
  'he': require('@/assets/dictionary/he.mp3'),
  'hemos': require('@/assets/dictionary/hemos.mp3'),
  'hogar': require('@/assets/dictionary/hogar.mp3'),
  'hola': require('@/assets/dictionary/hola.mp3'),
  'justo': require('@/assets/dictionary/justo.mp3'),
  'la': require('@/assets/dictionary/la.mp3'),
  'llamas': require('@/assets/dictionary/llamas.mp3'),
  'llamo': require('@/assets/dictionary/llamo.mp3'),
  'llega': require('@/assets/dictionary/llega.mp3'),
  'lo': require('@/assets/dictionary/lo.mp3'),
  'maría': require('@/assets/dictionary/maría.mp3'),
  'me': require('@/assets/dictionary/me.mp3'),
  'mi': require('@/assets/dictionary/mi.mp3'),
  'miedo': require('@/assets/dictionary/miedo.mp3'),
  'mucho': require('@/assets/dictionary/mucho.mp3'),
  'muy': require('@/assets/dictionary/muy.mp3'),
  'necesito': require('@/assets/dictionary/necesito.mp3'),
  'no': require('@/assets/dictionary/no.mp3'),
  'noche': require('@/assets/dictionary/noche.mp3'),
  'nuevo': require('@/assets/dictionary/nuevo.mp3'),
  'nunca': require('@/assets/dictionary/nunca.mp3'),
  'oh': require('@/assets/dictionary/oh.mp3'),
  'pasando': require('@/assets/dictionary/pasando.mp3'),
  'perdí': require('@/assets/dictionary/perdí.mp3'),
  'planeta': require('@/assets/dictionary/planeta.mp3'),
  'plataforma': require('@/assets/dictionary/plataforma.mp3'),
  'poco': require('@/assets/dictionary/poco.mp3'),
  'por': require('@/assets/dictionary/por.mp3'),
  'preocupes': require('@/assets/dictionary/preocupes.mp3'),
  'puedes': require('@/assets/dictionary/puedes.mp3'),
  'qué': require('@/assets/dictionary/qué.mp3'),
  'quién': require('@/assets/dictionary/quién.mp3'),
  'sí': require('@/assets/dictionary/sí.mp3'),
  'siguiente': require('@/assets/dictionary/siguiente.mp3'),
  'solo': require('@/assets/dictionary/solo.mp3'),
  'soy': require('@/assets/dictionary/soy.mp3'),
  'su': require('@/assets/dictionary/su.mp3'),
  'sueño': require('@/assets/dictionary/sueño.mp3'),
  'súper': require('@/assets/dictionary/súper.mp3'),
  'tarde': require('@/assets/dictionary/tarde.mp3'),
  'te': require('@/assets/dictionary/te.mp3'),
  'tengo': require('@/assets/dictionary/tengo.mp3'),
  'tiempo': require('@/assets/dictionary/tiempo.mp3'),
  'tomar': require('@/assets/dictionary/tomar.mp3'),
  'tu': require('@/assets/dictionary/tu.mp3'),
  'tú': require('@/assets/dictionary/tú.mp3'),
  'un': require('@/assets/dictionary/un.mp3'),
  'vamos': require('@/assets/dictionary/vamos.mp3'),
  'vecino': require('@/assets/dictionary/vecino.mp3'),
  'vengo': require('@/assets/dictionary/vengo.mp3'),
  'venido': require('@/assets/dictionary/venido.mp3'),
  'viniste': require('@/assets/dictionary/viniste.mp3'),
  'visitante': require('@/assets/dictionary/visitante.mp3'),
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
  'visitante': require('@/assets/dictionary/visitante.mp3'),
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
  // New words for alien comic
  'tener': require('@/assets/dictionary/tener.mp3'),
  'venir': require('@/assets/dictionary/venir.mp3'),
  'perderse': require('@/assets/dictionary/perderse.mp3'),
  'poder': require('@/assets/dictionary/poder.mp3'),
  'ayudar': require('@/assets/dictionary/ayudar.mp3'),
  'hablar': require('@/assets/dictionary/hablar.mp3'),
  'aprender': require('@/assets/dictionary/aprender.mp3'),
  'preocuparse': require('@/assets/dictionary/preocuparse.mp3'),
  'ir': require('@/assets/dictionary/ir.mp3'),
  'pasar': require('@/assets/dictionary/pasar.mp3'),
  'tomar': require('@/assets/dictionary/tomar.mp3'),
  'tarde': require('@/assets/dictionary/tarde.mp3'),
  'noche': require('@/assets/dictionary/noche.mp3'),
  'miedo': require('@/assets/dictionary/miedo.mp3'),
  'planeta': require('@/assets/dictionary/planeta.mp3'),
  'accidente': require('@/assets/dictionary/accidente.mp3'),
  'casa': require('@/assets/dictionary/casa.mp3'),
  'control': require('@/assets/dictionary/control.mp3'),
  'sueño': require('@/assets/dictionary/sueño.mp3'),
  'español': require('@/assets/dictionary/español.mp3'),
  'solo': require('@/assets/dictionary/solo.mp3'),
  'poco': require('@/assets/dictionary/poco.mp3'),
  'claro': require('@/assets/dictionary/claro.mp3'),
  'qué': require('@/assets/dictionary/qué.mp3'),
  'eso': require('@/assets/dictionary/eso.mp3'),
  'quién': require('@/assets/dictionary/quién.mp3'),
  'un': require('@/assets/dictionary/un.mp3'),
  'por': require('@/assets/dictionary/por.mp3'),
  'aquí': require('@/assets/dictionary/aquí.mp3'),
  'no': require('@/assets/dictionary/no.mp3'),
  'el': require('@/assets/dictionary/el.mp3'),
  'oh': require('@/assets/dictionary/oh.mp3'),
};

// Map audio URLs to sources - organized by comic
const localAudioMap: { [key: string]: AudioSource } = {
  // Girona
  'girona-s1': gironaAudio.s1,
  'girona-s2': gironaAudio.s2,
  'girona-s3': gironaAudio.s3,
  // Alien
  'alien_cover': alienAudio.cover,
  'alien_p1_s1': alienAudio.p1_s1,
  'alien_p1_s2': alienAudio.p1_s2,
  'alien_p2_s2': alienAudio.p2_s2,
  'alien_p2_s3': alienAudio.p2_s3,
  'alien_p2_s4': alienAudio.p2_s4,
  'alien_p3_s1': alienAudio.p3_s1,
  'alien_p3_s2': alienAudio.p3_s2,
  'alien_p3_s3': alienAudio.p3_s3,
  'alien_p4_s1': alienAudio.p4_s1,
  'alien_p4_s2': alienAudio.p4_s2,
  'alien_p4_s3': alienAudio.p4_s3,
  'alien_p5_s1': alienAudio.p5_s1,
  'alien_p5_s2': alienAudio.p5_s2,
  'alien_p5_s3': alienAudio.p5_s3,
  'alien_p5_s4': alienAudio.p5_s4,
  'alien_p6_s2': alienAudio.p6_s2,
  'alien_p6_s3': alienAudio.p6_s3,
  'alien_p6_s4': alienAudio.p6_s4,
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
