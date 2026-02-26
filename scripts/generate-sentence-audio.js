/**
 * Generate audio files for comic sentences
 *
 * Usage:
 *   ELEVENLABS_API_KEY=your_key VOICE_ID=voice_id node scripts/generate-sentence-audio.js
 */

const fs = require('fs');
const path = require('path');

const API_KEY = process.env.ELEVENLABS_API_KEY;
const VOICE_ID = process.env.VOICE_ID;

if (!API_KEY) {
  console.error('Error: Please set ELEVENLABS_API_KEY environment variable');
  process.exit(1);
}

if (!VOICE_ID) {
  console.error('Error: Please set VOICE_ID environment variable');
  process.exit(1);
}

// Sentences to generate audio for
const SENTENCES = [
  // El Primer Día - Page 1
  { id: 'primer-dia-s1', text: 'María llega a su nuevo apartamento.', filename: 'primer_dia_s1' },
  { id: 'primer-dia-s2', text: '¡Hola! Me llamo Carlos.', filename: 'primer_dia_s2' },
  { id: 'primer-dia-s3', text: 'Soy tu vecino.', filename: 'primer_dia_s3' },
  { id: 'primer-dia-s4', text: '¡Mucho gusto, Carlos!', filename: 'primer_dia_s4' },
  { id: 'primer-dia-s5', text: 'Yo soy María.', filename: 'primer_dia_s5' },
  { id: 'primer-dia-s6', text: '¿De dónde eres?', filename: 'primer_dia_s6' },
  { id: 'primer-dia-s7', text: 'Soy de Barcelona.', filename: 'primer_dia_s7' },
  // El Primer Día - Page 2
  { id: 'primer-dia-s8', text: '¿Te gusta la ciudad?', filename: 'primer_dia_s8' },
  { id: 'primer-dia-s9', text: '¡Sí, me encanta!', filename: 'primer_dia_s9' },
  { id: 'primer-dia-s10', text: 'Es muy bonita.', filename: 'primer_dia_s10' },
  { id: 'primer-dia-s11', text: '¡Bienvenida al barrio!', filename: 'primer_dia_s11' },
  { id: 'primer-dia-s12', text: '¡Gracias, Carlos!', filename: 'primer_dia_s12' },
  // El Primer Día - Page 3
  { id: 'primer-dia-s13', text: 'Al día siguiente...', filename: 'primer_dia_s13' },
  { id: 'primer-dia-s14', text: '¡Buenos días, María!', filename: 'primer_dia_s14' },
  { id: 'primer-dia-s15', text: '¿Cómo estás?', filename: 'primer_dia_s15' },
  { id: 'primer-dia-s16', text: '¡Muy bien, gracias!', filename: 'primer_dia_s16' },
  { id: 'primer-dia-s17', text: '¿Y tú?', filename: 'primer_dia_s17' },
  { id: 'primer-dia-s18', text: 'Me gusta mi nuevo hogar.', filename: 'primer_dia_s18' },
  // Girona - remaining sentences
  { id: 'girona-s2', text: 'Ahora necesito encontrar la plataforma correcta.', filename: 'girona_s2' },
  { id: 'girona-s3', text: '¡Lo encontré! ¡Está justo a tiempo!', filename: 'girona_s3' },
];

const OUTPUT_DIR = path.join(__dirname, '../assets/audio/sentences');

async function generateAudio(sentence) {
  const outputPath = path.join(OUTPUT_DIR, `${sentence.filename}.mp3`);

  // Skip if already exists
  if (fs.existsSync(outputPath)) {
    console.log(`  Already exists: ${sentence.filename}.mp3`);
    return true;
  }

  console.log(`Generating audio for: "${sentence.text}"`);

  const response = await fetch(`https://api.elevenlabs.io/v1/text-to-speech/${VOICE_ID}`, {
    method: 'POST',
    headers: {
      'xi-api-key': API_KEY,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      text: sentence.text,
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
    console.error(`Error generating audio for "${sentence.text}":`, response.status, error);
    return false;
  }

  const audioBuffer = await response.arrayBuffer();
  fs.writeFileSync(outputPath, Buffer.from(audioBuffer));
  console.log(`  Saved: ${sentence.filename}.mp3`);
  return true;
}

async function main() {
  // Create output directory if it doesn't exist
  if (!fs.existsSync(OUTPUT_DIR)) {
    fs.mkdirSync(OUTPUT_DIR, { recursive: true });
    console.log(`Created directory: ${OUTPUT_DIR}`);
  }

  console.log(`\nGenerating audio for ${SENTENCES.length} sentences...`);
  console.log(`Using voice ID: ${VOICE_ID}\n`);

  let successCount = 0;
  let skipCount = 0;
  let failCount = 0;

  for (const sentence of SENTENCES) {
    const result = await generateAudio(sentence);
    if (result === true) {
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

  // List generated files
  const files = fs.readdirSync(OUTPUT_DIR).filter(f => f.endsWith('.mp3'));
  console.log(`\n=== Generated ${files.length} audio files ===`);

  console.log(`\n=== Next Steps ===`);
  console.log(`1. Normalize volume: cd ${OUTPUT_DIR} && for f in *.mp3; do ffmpeg -i "$f" -filter:a "volume=1.5" -y "temp_$f" && mv "temp_$f" "$f"; done`);
  console.log(`2. Add imports to src/utils/audio.ts`);
  console.log(`3. Update audioUrl in src/data/comics.ts`);
}

main().catch(console.error);
