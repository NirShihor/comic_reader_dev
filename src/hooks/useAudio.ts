import { useState, useEffect, useCallback, useRef } from 'react';
import { useAudioPlayer, AudioPlayer } from 'expo-audio';
import { Word } from '../types/comic';

interface UseAudioOptions {
  words?: Word[];
  onWordHighlight?: (wordIndex: number | null) => void;
}

interface UseAudioReturn {
  isPlaying: boolean;
  isLoading: boolean;
  currentWordIndex: number | null;
  play: (audioUrl: string) => Promise<void>;
  stop: () => Promise<void>;
  error: string | null;
}

export function useAudio(options: UseAudioOptions = {}): UseAudioReturn {
  const { words, onWordHighlight } = options;
  const [isPlaying, setIsPlaying] = useState(false);
  const [isLoading, setIsLoading] = useState(false);
  const [currentWordIndex, setCurrentWordIndex] = useState<number | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [audioSource, setAudioSource] = useState<string | null>(null);

  const highlightIntervalRef = useRef<ReturnType<typeof setInterval> | null>(null);
  const wordsRef = useRef<Word[] | undefined>(words);

  // Keep words ref updated
  useEffect(() => {
    wordsRef.current = words;
  }, [words]);

  // Create audio player
  const player = useAudioPlayer(audioSource ? { uri: audioSource } : null);

  // Clean up interval on unmount
  useEffect(() => {
    return () => {
      if (highlightIntervalRef.current) {
        clearInterval(highlightIntervalRef.current);
      }
    };
  }, []);

  // Update parent when word index changes
  useEffect(() => {
    onWordHighlight?.(currentWordIndex);
  }, [currentWordIndex, onWordHighlight]);

  // Handle player status changes
  useEffect(() => {
    if (player) {
      if (player.playing) {
        setIsPlaying(true);
        setIsLoading(false);
      } else if (!player.playing && isPlaying) {
        // Playback finished or stopped
        setIsPlaying(false);
        setCurrentWordIndex(null);
        if (highlightIntervalRef.current) {
          clearInterval(highlightIntervalRef.current);
          highlightIntervalRef.current = null;
        }
      }
    }
  }, [player?.playing]);

  const simulateHighlighting = useCallback(() => {
    const currentWords = wordsRef.current;
    if (!currentWords || currentWords.length === 0) return;

    setIsPlaying(true);
    setIsLoading(false);
    const wordDuration = 400; // 400ms per word for demo
    let index = 0;
    setCurrentWordIndex(0);

    highlightIntervalRef.current = setInterval(() => {
      index++;
      if (index < currentWords.length) {
        setCurrentWordIndex(index);
      } else {
        if (highlightIntervalRef.current) {
          clearInterval(highlightIntervalRef.current);
          highlightIntervalRef.current = null;
        }
        setCurrentWordIndex(null);
        setIsPlaying(false);
      }
    }, wordDuration);
  }, []);

  const highlightWordsWithTiming = useCallback((durationMs: number) => {
    const currentWords = wordsRef.current;
    if (!currentWords || currentWords.length === 0) return;

    // Check if words have timing data
    const hasTimingData = currentWords.some(w => w.startTimeMs !== undefined);

    if (hasTimingData) {
      // Use actual timing data for highlighting
      highlightIntervalRef.current = setInterval(() => {
        if (player && player.playing) {
          const currentPosition = player.currentTime * 1000; // Convert to ms

          // Find which word should be highlighted
          const wordIndex = currentWords.findIndex((word, idx) => {
            const start = word.startTimeMs ?? 0;
            const end = word.endTimeMs ?? (currentWords[idx + 1]?.startTimeMs ?? Infinity);
            return currentPosition >= start && currentPosition < end;
          });

          setCurrentWordIndex(wordIndex >= 0 ? wordIndex : null);
        }
      }, 50); // Check every 50ms for smooth highlighting
    } else {
      // Fallback: highlight words sequentially based on audio duration
      const wordDuration = durationMs / currentWords.length;

      let index = 0;
      setCurrentWordIndex(0);

      highlightIntervalRef.current = setInterval(() => {
        index++;
        if (index < currentWords.length) {
          setCurrentWordIndex(index);
        } else {
          if (highlightIntervalRef.current) {
            clearInterval(highlightIntervalRef.current);
            highlightIntervalRef.current = null;
          }
        }
      }, wordDuration);
    }
  }, [player]);

  const play = useCallback(async (audioUrl: string) => {
    try {
      setError(null);
      setIsLoading(true);

      // Clear any existing highlighting
      if (highlightIntervalRef.current) {
        clearInterval(highlightIntervalRef.current);
        highlightIntervalRef.current = null;
      }

      // If no valid URL, simulate playback
      if (!audioUrl || audioUrl === '' || !audioUrl.startsWith('http')) {
        simulateHighlighting();
        return;
      }

      // Set the audio source - this will trigger the player to load
      setAudioSource(audioUrl);

      // Start playback
      if (player) {
        player.play();

        // Start word highlighting
        // Estimate duration as 2 seconds if we can't get it
        const duration = player.duration ? player.duration * 1000 : 2000;
        highlightWordsWithTiming(duration);
      }

    } catch (e) {
      setIsLoading(false);
      setIsPlaying(false);
      setError(e instanceof Error ? e.message : 'Failed to play audio');
      console.log('Audio playback error:', e);

      // Fallback to simulation
      simulateHighlighting();
    }
  }, [player, simulateHighlighting, highlightWordsWithTiming]);

  const stop = useCallback(async () => {
    if (highlightIntervalRef.current) {
      clearInterval(highlightIntervalRef.current);
      highlightIntervalRef.current = null;
    }

    if (player) {
      player.pause();
      player.seekTo(0);
    }

    setIsPlaying(false);
    setCurrentWordIndex(null);
    setAudioSource(null);
  }, [player]);

  return {
    isPlaying,
    isLoading,
    currentWordIndex,
    play,
    stop,
    error,
  };
}
