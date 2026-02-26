/**
 * Get word timestamps from ElevenLabs Forced Alignment API
 *
 * Usage:
 *   1. Get your API key from https://elevenlabs.io/app/settings/api-keys
 *   2. Run: ELEVENLABS_API_KEY=your_key node scripts/get-word-timestamps.js
 */

const fs = require('fs');
const path = require('path');

const API_KEY = process.env.ELEVENLABS_API_KEY;

if (!API_KEY) {
  console.error('Error: Please set ELEVENLABS_API_KEY environment variable');
  console.log('Usage: ELEVENLABS_API_KEY=your_key node scripts/get-word-timestamps.js');
  process.exit(1);
}

// Configuration - edit these for each sentence
const AUDIO_FILE = path.join(__dirname, '../assets/audio/girona_trip/girona-s1.mp3');
const TRANSCRIPT = '¡Estoy súper emocionada! Nunca he estado en Girona.';

async function getWordTimestamps() {
  console.log('Reading audio file...');
  const audioBuffer = fs.readFileSync(AUDIO_FILE);

  console.log('Calling ElevenLabs Forced Alignment API...');

  // Create form data
  const formData = new FormData();
  formData.append('audio', new Blob([audioBuffer], { type: 'audio/mpeg' }), 'audio.mp3');
  formData.append('text', TRANSCRIPT);

  const response = await fetch('https://api.elevenlabs.io/v1/speech-to-speech/alignment', {
    method: 'POST',
    headers: {
      'xi-api-key': API_KEY,
    },
    body: formData,
  });

  if (!response.ok) {
    const error = await response.text();
    console.error('API Error:', response.status, error);

    // Try alternative endpoint
    console.log('\nTrying alternative endpoint...');
    return tryAlternativeEndpoint(audioBuffer);
  }

  const data = await response.json();
  processResponse(data);
}

async function tryAlternativeEndpoint(audioBuffer) {
  const formData = new FormData();
  formData.append('file', new Blob([audioBuffer], { type: 'audio/mpeg' }), 'audio.mp3');
  formData.append('text', TRANSCRIPT);

  const response = await fetch('https://api.elevenlabs.io/v1/forced-alignment', {
    method: 'POST',
    headers: {
      'xi-api-key': API_KEY,
    },
    body: formData,
  });

  if (!response.ok) {
    const error = await response.text();
    console.error('API Error:', response.status, error);

    // Try speech-to-text with timestamps
    console.log('\nTrying Speech-to-Text endpoint...');
    return trySpeechToText(audioBuffer);
  }

  const data = await response.json();
  processResponse(data);
}

async function trySpeechToText(audioBuffer) {
  const formData = new FormData();
  formData.append('file', new Blob([audioBuffer], { type: 'audio/mpeg' }), 'audio.mp3');
  formData.append('model_id', 'scribe_v1');
  formData.append('language_code', 'es');

  const response = await fetch('https://api.elevenlabs.io/v1/speech-to-text', {
    method: 'POST',
    headers: {
      'xi-api-key': API_KEY,
    },
    body: formData,
  });

  if (!response.ok) {
    const error = await response.text();
    console.error('API Error:', response.status, error);
    process.exit(1);
  }

  const data = await response.json();
  console.log('\n=== Speech-to-Text Response ===');
  console.log(JSON.stringify(data, null, 2));

  if (data.words) {
    console.log('\n=== Word Timestamps ===');
    console.log('\nCopy this into your comic data:\n');
    console.log('words: [');
    data.words.forEach((word, i) => {
      const startMs = Math.round(word.start * 1000);
      const endMs = Math.round(word.end * 1000);
      console.log(`  { id: 'g${i + 1}', text: '${word.text}', meaning: '...', startTimeMs: ${startMs}, endTimeMs: ${endMs} },`);
    });
    console.log(']');
  }
}

function processResponse(data) {
  console.log('\n=== Raw Alignment Data ===');
  console.log(JSON.stringify(data, null, 2));

  // Convert character timestamps to word timestamps
  if (data.alignment) {
    console.log('\n=== Word Timestamps ===');
    const words = convertToWordTimestamps(data.alignment, TRANSCRIPT);

    console.log('\nCopy this into your comic data:\n');
    console.log('words: [');
    words.forEach((word, i) => {
      console.log(`  { id: 'g${i + 1}', text: '${word.text}', meaning: '...', startTimeMs: ${word.startTimeMs}, endTimeMs: ${word.endTimeMs} },`);
    });
    console.log(']');
  } else if (data.words) {
    // Alternative response format
    console.log('\n=== Word Timestamps ===');
    console.log('\nCopy this into your comic data:\n');
    console.log('words: [');
    data.words.forEach((word, i) => {
      const startMs = Math.round((word.start || word.start_time) * 1000);
      const endMs = Math.round((word.end || word.end_time) * 1000);
      console.log(`  { id: 'g${i + 1}', text: '${word.text || word.word}', meaning: '...', startTimeMs: ${startMs}, endTimeMs: ${endMs} },`);
    });
    console.log(']');
  }
}

function convertToWordTimestamps(alignment, transcript) {
  const { characters, character_start_times_seconds, character_end_times_seconds } = alignment;

  const words = [];
  let currentWord = '';
  let wordStartTime = null;
  let wordEndTime = null;

  for (let i = 0; i < characters.length; i++) {
    const char = characters[i];
    const startTime = character_start_times_seconds[i];
    const endTime = character_end_times_seconds[i];

    if (char === ' ' || char === '\n') {
      if (currentWord) {
        words.push({
          text: currentWord,
          startTimeMs: Math.round(wordStartTime * 1000),
          endTimeMs: Math.round(wordEndTime * 1000),
        });
        currentWord = '';
        wordStartTime = null;
      }
    } else {
      if (wordStartTime === null) {
        wordStartTime = startTime;
      }
      wordEndTime = endTime;
      currentWord += char;
    }
  }

  if (currentWord) {
    words.push({
      text: currentWord,
      startTimeMs: Math.round(wordStartTime * 1000),
      endTimeMs: Math.round(wordEndTime * 1000),
    });
  }

  return words;
}

getWordTimestamps().catch(console.error);
