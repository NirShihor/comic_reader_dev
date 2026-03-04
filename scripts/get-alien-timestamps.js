/**
 * Batch get word timestamps for all alien comic audio files
 *
 * Usage:
 *   ELEVENLABS_API_KEY=your_key node scripts/get-alien-timestamps.js
 */

const fs = require('fs');
const path = require('path');

const API_KEY = process.env.ELEVENLABS_API_KEY;

if (!API_KEY) {
  console.error('Error: Please set ELEVENLABS_API_KEY environment variable');
  process.exit(1);
}

const AUDIO_DIR = path.join(__dirname, '../assets/comics/alien/audio');

const sentences = [
  { file: 'alien_p1_s1.mp3', transcript: 'Tarde en la noche' },
  { file: 'alien_p1_s2.mp3', transcript: '¿Qué fue eso..?' },
  { file: 'alien_p2_s2.mp3', transcript: '¿Qué...? ¿Quién eres?' },
  { file: 'alien_p2_s3.mp3', transcript: 'Me llamo Zik. ¿Cómo te llamas?' },
  { file: 'alien_p2_s4.mp3', transcript: 'Me llamo Mía.' },
  { file: 'alien_p3_s1.mp3', transcript: '¿Estás bien?' },
  { file: 'alien_p3_s2.mp3', transcript: 'Yo.. tengo miedo.' },
  { file: 'alien_p3_s3.mp3', transcript: '¿De dónde eres?' },
  { file: 'alien_p4_s1.mp3', transcript: 'Vengo de Zizark.' },
  { file: 'alien_p4_s2.mp3', transcript: '¿Zizark? ¿Dónde está eso?' },
  { file: 'alien_p4_s3.mp3', transcript: 'Es un planeta.' },
  { file: 'alien_p5_s1.mp3', transcript: '¿Un planeta? ¿Por qué viniste aquí?' },
  { file: 'alien_p5_s2.mp3', transcript: 'Por accidente. Me perdí.' },
  { file: 'alien_p5_s3.mp3', transcript: '¿Puedes ayudarme? Solo hablo un poco de español. Estoy aprendiendo.' },
  { file: 'alien_p5_s4.mp3', transcript: '¡Claro! No te preocupes, te ayudaré. Vamos a la casa.' },
  { file: 'alien_p6_s2.mp3', transcript: '¿Qué está pasando?' },
  { file: 'alien_p6_s3.mp3', transcript: 'Hemos venido a tomar el control.' },
  { file: 'alien_p6_s4.mp3', transcript: 'Oh... solo era un sueño...' },
];

async function getTimestampsForSentence(audioFile, transcript) {
  const audioPath = path.join(AUDIO_DIR, audioFile);
  const audioBuffer = fs.readFileSync(audioPath);

  const formData = new FormData();
  formData.append('file', new Blob([audioBuffer], { type: 'audio/mpeg' }), 'audio.mp3');
  formData.append('model_id', 'scribe_v1');
  formData.append('language_code', 'es');

  const response = await fetch('https://api.elevenlabs.io/v1/speech-to-text', {
    method: 'POST',
    headers: { 'xi-api-key': API_KEY },
    body: formData,
  });

  if (!response.ok) {
    const error = await response.text();
    console.error(`Error for ${audioFile}:`, error);
    return null;
  }

  const data = await response.json();
  return data.words || [];
}

async function processAll() {
  const results = {};

  for (const { file, transcript } of sentences) {
    console.log(`Processing ${file}...`);
    const words = await getTimestampsForSentence(file, transcript);
    if (words) {
      results[file] = words.map(w => ({
        text: w.text,
        startTimeMs: Math.round(w.start * 1000),
        endTimeMs: Math.round(w.end * 1000),
      }));
    }
    // Small delay to avoid rate limiting
    await new Promise(r => setTimeout(r, 500));
  }

  // Output results
  console.log('\n\n=== TIMESTAMPS FOR COMIC DATA ===\n');
  for (const [file, words] of Object.entries(results)) {
    console.log(`// ${file}`);
    console.log('words: [');
    words.forEach((w, i) => {
      console.log(`  { id: '${i + 1}', text: '${w.text}', meaning: '...', startTimeMs: ${w.startTimeMs}, endTimeMs: ${w.endTimeMs} },`);
    });
    console.log('],\n');
  }

  // Also save to JSON file for reference
  const outputPath = path.join(__dirname, '../assets/comics/alien/timestamps.json');
  fs.writeFileSync(outputPath, JSON.stringify(results, null, 2));
  console.log(`\nSaved to ${outputPath}`);
}

processAll().catch(console.error);
