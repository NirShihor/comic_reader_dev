/**
 * Generate audio files for dictionary words using ElevenLabs API
 *
 * Usage:
 *   1. Get your API key from https://elevenlabs.io/app/settings/api-keys
 *   2. Choose a voice ID from https://elevenlabs.io/app/voice-library
 *   3. Run: ELEVENLABS_API_KEY=your_key VOICE_ID=voice_id node scripts/generate-dictionary-audio.js
 *
 * This will generate MP3 files in assets/audio/dictionary/ for each word
 */

const fs = require('fs');
const path = require('path');

const API_KEY = process.env.ELEVENLABS_API_KEY;
const VOICE_ID = process.env.VOICE_ID || '21m00Tcm4TlvDq8ikWAM'; // Default: Rachel

if (!API_KEY) {
  console.error('Error: Please set ELEVENLABS_API_KEY environment variable');
  console.log('Usage: ELEVENLABS_API_KEY=your_key VOICE_ID=voice_id node scripts/generate-dictionary-audio.js');
  process.exit(1);
}

// Dictionary words to generate audio for
const DICTIONARY_WORDS = [
  // Verbs
  'llegar',
  'llamarse',
  'ser',
  'estar',
  'gustar',
  'encantar',
  'haber',
  'necesitar',
  'encontrar',
  // Nouns
  'apartamento',
  'vecino',
  'gusto',
  'ciudad',
  'barrio',
  'día',
  'hogar',
  'plataforma',
  'tiempo',
  // Adjectives
  'nuevo',
  'bonito',
  'bienvenido',
  'siguiente',
  'bueno',
  'emocionado',
  'correcto',
  'justo',
  // Adverbs
  'muy',
  'bien',
  'nunca',
  'ahora',
  'dónde',
  'cómo',
  'súper',
  // Pronouns
  'yo',
  'tú',
  'me',
  'te',
  'lo',
  // Prepositions
  'a',
  'de',
  'en',
  'al',
  // Articles
  'la',
  // Possessives
  'su',
  'tu',
  'mi',
  'mucho',
  // Conjunctions
  'y',
  // Interjections
  'hola',
  'sí',
  'gracias',
];

const OUTPUT_DIR = path.join(__dirname, '../assets/audio/dictionary');

async function generateAudio(word) {
  console.log(`Generating audio for: ${word}`);

  const response = await fetch(`https://api.elevenlabs.io/v1/text-to-speech/${VOICE_ID}`, {
    method: 'POST',
    headers: {
      'xi-api-key': API_KEY,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      text: word,
      model_id: 'eleven_multilingual_v2',
      voice_settings: {
        stability: 0.5,
        similarity_boost: 0.75,
        style: 0.0,
        use_speaker_boost: true,
      },
    }),
  });

  if (!response.ok) {
    const error = await response.text();
    console.error(`Error generating audio for "${word}":`, response.status, error);
    return false;
  }

  const audioBuffer = await response.arrayBuffer();
  const outputPath = path.join(OUTPUT_DIR, `${word}.mp3`);
  fs.writeFileSync(outputPath, Buffer.from(audioBuffer));
  console.log(`  Saved: ${outputPath}`);
  return true;
}

async function main() {
  // Create output directory if it doesn't exist
  if (!fs.existsSync(OUTPUT_DIR)) {
    fs.mkdirSync(OUTPUT_DIR, { recursive: true });
    console.log(`Created directory: ${OUTPUT_DIR}`);
  }

  console.log(`\nGenerating audio for ${DICTIONARY_WORDS.length} words...`);
  console.log(`Using voice ID: ${VOICE_ID}\n`);

  let successCount = 0;
  let failCount = 0;

  for (const word of DICTIONARY_WORDS) {
    const success = await generateAudio(word);
    if (success) {
      successCount++;
    } else {
      failCount++;
    }
    // Small delay to avoid rate limiting
    await new Promise(resolve => setTimeout(resolve, 500));
  }

  console.log(`\n=== Summary ===`);
  console.log(`Success: ${successCount}`);
  console.log(`Failed: ${failCount}`);

  if (successCount > 0) {
    console.log(`\n=== Next Steps ===`);
    console.log(`1. Add the audio imports to src/utils/audio.ts:`);
    console.log(`\nexport const dictionaryAudio: { [key: string]: AVPlaybackSource } = {`);
    DICTIONARY_WORDS.forEach(word => {
      console.log(`  '${word}': require('@/assets/audio/dictionary/${word}.mp3'),`);
    });
    console.log(`};`);

    console.log(`\n2. Update dictionary entries in src/data/dictionary.ts to include audioUrl:`);
    console.log(`   Example: audioUrl: 'dict:estar',`);
  }
}

main().catch(console.error);
