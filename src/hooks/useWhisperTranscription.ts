import { useState, useCallback, useRef } from 'react';
import { Audio } from 'expo-av';
import * as Haptics from 'expo-haptics';

// OpenAI API key should be stored securely
// For development, you can use environment variables or a config file
const OPENAI_API_KEY = process.env.EXPO_PUBLIC_OPENAI_API_KEY || '';

interface WhisperResponse {
  text: string;
}

interface UseWhisperTranscriptionReturn {
  isRecording: boolean;
  isProcessing: boolean;
  transcript: string | null;
  error: string | null;
  startRecording: () => Promise<void>;
  stopRecording: () => Promise<string | null>;
  reset: () => void;
}

export function useWhisperTranscription(): UseWhisperTranscriptionReturn {
  const [isRecording, setIsRecording] = useState(false);
  const [isProcessing, setIsProcessing] = useState(false);
  const [transcript, setTranscript] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const recordingRef = useRef<Audio.Recording | null>(null);

  const startRecording = useCallback(async () => {
    try {
      setError(null);
      setTranscript(null);

      // Request permissions
      const { status } = await Audio.requestPermissionsAsync();
      if (status !== 'granted') {
        setError('Microphone permission is required');
        return;
      }

      // Configure audio mode for recording
      await Audio.setAudioModeAsync({
        allowsRecordingIOS: true,
        playsInSilentModeIOS: true,
      });

      // Create and start recording
      const { recording } = await Audio.Recording.createAsync(
        Audio.RecordingOptionsPresets.HIGH_QUALITY
      );

      recordingRef.current = recording;
      setIsRecording(true);
      Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Medium);
    } catch (err) {
      console.error('Failed to start recording:', err);
      setError('Failed to start recording');
    }
  }, []);

  const stopRecording = useCallback(async (): Promise<string | null> => {
    try {
      if (!recordingRef.current) {
        return null;
      }

      setIsRecording(false);
      Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Light);

      // Stop and unload the recording
      await recordingRef.current.stopAndUnloadAsync();
      const uri = recordingRef.current.getURI();
      recordingRef.current = null;

      // Reset audio mode
      await Audio.setAudioModeAsync({
        allowsRecordingIOS: false,
      });

      if (!uri) {
        setError('No recording found');
        return null;
      }

      // Send to Whisper API
      setIsProcessing(true);
      const transcription = await transcribeWithWhisper(uri);
      setTranscript(transcription);
      setIsProcessing(false);

      return transcription;
    } catch (err) {
      console.error('Failed to stop recording:', err);
      setError('Failed to process recording');
      setIsProcessing(false);
      return null;
    }
  }, []);

  const reset = useCallback(() => {
    setTranscript(null);
    setError(null);
    setIsProcessing(false);
    setIsRecording(false);
  }, []);

  return {
    isRecording,
    isProcessing,
    transcript,
    error,
    startRecording,
    stopRecording,
    reset,
  };
}

async function transcribeWithWhisper(audioUri: string): Promise<string> {
  if (!OPENAI_API_KEY) {
    throw new Error('OpenAI API key not configured');
  }

  // Create form data for the API request
  const formData = new FormData();

  // Append the audio file - React Native FormData accepts this format
  formData.append('file', {
    uri: audioUri,
    type: 'audio/m4a',
    name: 'audio.m4a',
  } as unknown as Blob);
  formData.append('model', 'whisper-1');
  formData.append('language', 'es'); // Spanish
  formData.append('response_format', 'json');

  // Send to OpenAI Whisper API
  const apiResponse = await fetch('https://api.openai.com/v1/audio/transcriptions', {
    method: 'POST',
    headers: {
      'Authorization': `Bearer ${OPENAI_API_KEY}`,
    },
    body: formData,
  });

  if (!apiResponse.ok) {
    const errorText = await apiResponse.text();
    console.error('Whisper API error:', errorText);
    throw new Error('Transcription failed');
  }

  const result: WhisperResponse = await apiResponse.json();
  return result.text;
}
