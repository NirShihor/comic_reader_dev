/**
 * Generate audio files for new alien comic dictionary words using ElevenLabs API
 *
 * Usage:
 *   ELEVENLABS_API_KEY=your_key node scripts/generate-alien-dictionary-audio.js
 */

const fs = require('fs');
const path = require('path');

const API_KEY = process.env.ELEVENLABS_API_KEY;
const VOICE_ID = 'nuzVc5hpXBWZjFEe4izg';

if (!API_KEY) {
  console.error('Error: Please set ELEVENLABS_API_KEY environment variable');
  console.log('Usage: ELEVENLABS_API_KEY=your_key node scripts/generate-alien-dictionary-audio.js');
  process.exit(1);
}

// New dictionary words for alien comic
const DICTIONARY_WORDS = [
  // Verbs
  'tener',
  'venir',
  'perderse',
  'poder',
  'ayudar',
  'hablar',
  'aprender',
  'preocuparse',
  'ir',
  'pasar',
  'tomar',
  // Nouns
  'tarde',
  'noche',
  'miedo',
  'planeta',
  'accidente',
  'casa',
  'control',
  'sueño',
  // Adjectives/Adverbs
  'solo',
  'poco',
  'claro',
  'español',
  // Pronouns
  'qué',
  'eso',
  'quién',
  // Articles/Prepositions
  'un',
  'por',
  'aquí',
  'no',
  'el',
  // Interjections
  'oh',
];

const OUTPUT_DIR = path.join(__dirname, '../assets/dictionary');

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
    console.log(`1. Add entries to src/data/dictionary.ts`);
    console.log(`2. Add audio imports to src/utils/audio.ts dictionaryAudio map`);
  }
}

main().catch(console.error);
