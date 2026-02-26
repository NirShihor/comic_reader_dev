/**
 * Generate audio files for actual word forms used in comics
 *
 * This generates audio for words as they appear in sentences (e.g., "emocionada")
 * rather than just base forms (e.g., "emocionado")
 *
 * Usage:
 *   ELEVENLABS_API_KEY=your_key VOICE_ID=voice_id node scripts/generate-word-audio.js
 */

const fs = require('fs');
const path = require('path');

const API_KEY = process.env.ELEVENLABS_API_KEY;
const VOICE_ID = process.env.VOICE_ID || '15bJsujCI3tcDWeoZsQP';

if (!API_KEY) {
  console.error('Error: Please set ELEVENLABS_API_KEY environment variable');
  console.log('Usage: ELEVENLABS_API_KEY=your_key VOICE_ID=voice_id node scripts/generate-word-audio.js');
  process.exit(1);
}

// Extract unique words from comics data
// These are the actual word forms as they appear (with punctuation stripped)
const WORD_FORMS = [
  // From Girona comic - sentence 1
  'estoy',
  'súper',
  'emocionada',
  'nunca',
  'he',
  'estado',
  'en',
  'girona',
  // From Girona comic - sentence 2
  'ahora',
  'necesito',
  'encontrar',
  'la',
  'plataforma',
  'correcta',
  // From Girona comic - sentence 3
  'lo',
  'encontré',
  'está',
  'justo',
  'a',
  'tiempo',
  // From El Primer Día comic
  'maría',
  'llega',
  'su',
  'nuevo',
  'apartamento',
  'hola',
  'me',
  'llamo',
  'carlos',
  'soy',
  'tu',
  'vecino',
  'mucho',
  'gusto',
  'yo',
  'de',
  'dónde',
  'eres',
  'barcelona',
  'te',
  'gusta',
  'ciudad',
  'sí',
  'encanta',
  'es',
  'muy',
  'bonita',
  'bienvenida',
  'al',
  'barrio',
  'gracias',
  'día',
  'siguiente',
  'buenos',
  'días',
  'cómo',
  'estás',
  'bien',
  'y',
  'tú',
  'mi',
  'hogar',
];

// Remove duplicates and sort
const uniqueWords = [...new Set(WORD_FORMS)].sort();

const OUTPUT_DIR = path.join(__dirname, '../assets/audio/words');

async function generateAudio(word) {
  const filename = word.toLowerCase().replace(/[^a-záéíóúüñ]/g, '');
  if (!filename) {
    console.log(`  Skipping empty word: "${word}"`);
    return false;
  }

  const outputPath = path.join(OUTPUT_DIR, `${filename}.mp3`);

  // Skip if already exists
  if (fs.existsSync(outputPath)) {
    console.log(`  Already exists: ${filename}.mp3`);
    return true;
  }

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

  console.log(`\nGenerating audio for ${uniqueWords.length} unique word forms...`);
  console.log(`Using voice ID: ${VOICE_ID}\n`);

  let successCount = 0;
  let skipCount = 0;
  let failCount = 0;

  for (const word of uniqueWords) {
    const result = await generateAudio(word);
    if (result === true) {
      successCount++;
    } else if (result === 'skip') {
      skipCount++;
    } else {
      failCount++;
    }
    // Small delay to avoid rate limiting
    await new Promise(resolve => setTimeout(resolve, 300));
  }

  console.log(`\n=== Summary ===`);
  console.log(`Success: ${successCount}`);
  console.log(`Skipped: ${skipCount}`);
  console.log(`Failed: ${failCount}`);

  // List generated files
  const files = fs.readdirSync(OUTPUT_DIR).filter(f => f.endsWith('.mp3'));
  console.log(`\n=== Generated ${files.length} audio files ===`);

  console.log(`\n=== Next Steps ===`);
  console.log(`1. Run: cd ${OUTPUT_DIR} && for f in *.mp3; do ffmpeg -i "$f" -filter:a "volume=4.5" -y "temp_$f" && mv "temp_$f" "$f"; done`);
  console.log(`2. Add imports to src/utils/audio.ts`);
}

main().catch(console.error);
