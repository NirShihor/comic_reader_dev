import { useState, useEffect, useCallback, useRef } from 'react';
import { useAudioPlayer } from 'expo-audio';
import { Word } from '../types/comic';
import { getAudioSource, isLocalAudio, isWordAudio, isDictionaryAudio } from '../utils/audio';

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
  playbackRate: number;
  setPlaybackRate: (rate: number) => void;
}

export function useAudio(options: UseAudioOptions = {}): UseAudioReturn {
  const { words, onWordHighlight } = options;
  const [isPlaying, setIsPlaying] = useState(false);
  const [isLoading, setIsLoading] = useState(false);
  const [currentWordIndex, setCurrentWordIndex] = useState<number | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [audioSource, setAudioSource] = useState<string | null>(null);
  const [playbackRate, setPlaybackRateState] = useState(1.0);

  const highlightIntervalRef = useRef<ReturnType<typeof setInterval> | null>(null);
  const wordsRef = useRef<Word[] | undefined>(words);
  const playbackRateRef = useRef(1.0);

  // Keep refs updated
  useEffect(() => {
    wordsRef.current = words;
  }, [words]);

  useEffect(() => {
    playbackRateRef.current = playbackRate;
  }, [playbackRate]);

  // Create audio player - getAudioSource returns require() result or {uri: string}
  const source = audioSource ? getAudioSource(audioSource) : null;
  const player = useAudioPlayer(source);

  const setPlaybackRate = useCallback((rate: number) => {
    setPlaybackRateState(rate);
    if (player && player.setPlaybackRate) {
      player.setPlaybackRate(rate);
    }
  }, [player]);

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

  // Monitor player state
  useEffect(() => {
    if (!player) return;

    const interval = setInterval(() => {
      // Check if playback finished
      if (isPlaying && !player.playing && player.duration > 0) {
        const atEnd = player.currentTime >= player.duration - 0.1;
        if (atEnd) {
          setIsPlaying(false);
          setCurrentWordIndex(null);
          if (highlightIntervalRef.current) {
            clearInterval(highlightIntervalRef.current);
            highlightIntervalRef.current = null;
          }
        }
      }
    }, 100);

    return () => clearInterval(interval);
  }, [player, isPlaying]);

  const startHighlighting = useCallback((durationMs: number) => {
    const currentWords = wordsRef.current;
    if (!currentWords || currentWords.length === 0) return;

    if (highlightIntervalRef.current) {
      clearInterval(highlightIntervalRef.current);
    }

    const hasTimingData = currentWords.some(w => w.startTimeMs !== undefined);
    setCurrentWordIndex(0);

    if (hasTimingData && player) {
      highlightIntervalRef.current = setInterval(() => {
        if (!player.playing) return;
        const currentPosition = player.currentTime * 1000;

        let wordIndex = currentWords.findIndex((word, idx) => {
          const start = word.startTimeMs ?? 0;
          const end = word.endTimeMs ?? (currentWords[idx + 1]?.startTimeMs ?? Infinity);
          return currentPosition >= start && currentPosition < end;
        });

        if (wordIndex < 0) {
          for (let i = currentWords.length - 1; i >= 0; i--) {
            if (currentPosition >= (currentWords[i].startTimeMs ?? 0)) {
              wordIndex = i;
              break;
            }
          }
        }

        if (wordIndex >= 0) {
          setCurrentWordIndex(wordIndex);
        }
      }, 50);
    } else {
      const adjustedDuration = durationMs / playbackRateRef.current;
      const wordDuration = adjustedDuration / currentWords.length;
      let index = 0;

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

      if (highlightIntervalRef.current) {
        clearInterval(highlightIntervalRef.current);
        highlightIntervalRef.current = null;
      }

      if (!audioUrl || audioUrl === '') {
        return;
      }

      const isLocal = isLocalAudio(audioUrl);
      const isWord = isWordAudio(audioUrl);
      const isDict = isDictionaryAudio(audioUrl);
      const isRemote = audioUrl.startsWith('http');

      if (!isLocal && !isWord && !isDict && !isRemote) {
        return;
      }

      setIsLoading(true);

      // If same source, replay from beginning
      if (audioSource === audioUrl && player) {
        player.seekTo(0);
        if (player.setPlaybackRate) {
          player.setPlaybackRate(playbackRateRef.current);
        }
        player.play();
        setIsPlaying(true);
        setIsLoading(false);
        const duration = player.duration ? player.duration * 1000 : 4500;
        startHighlighting(duration);
        return;
      }

      // Set new source - this triggers useAudioPlayer to load new audio
      setAudioSource(audioUrl);

    } catch (e) {
      setIsLoading(false);
      setIsPlaying(false);
      setError(e instanceof Error ? e.message : 'Failed to play audio');
      console.log('Audio playback error:', e);
    }
  }, [player, audioSource, startHighlighting]);

  // When player changes (new source loaded), start playback
  useEffect(() => {
    if (!player || !audioSource || !isLoading) return;

    // Wait for player to be ready (has duration)
    const checkAndPlay = () => {
      if (player.duration > 0) {
        if (player.setPlaybackRate) {
          player.setPlaybackRate(playbackRateRef.current);
        }
        player.play();
        setIsPlaying(true);
        setIsLoading(false);
        startHighlighting(player.duration * 1000);
      } else {
        // Not ready yet, check again
        setTimeout(checkAndPlay, 50);
      }
    };

    checkAndPlay();
  }, [player, audioSource, isLoading, startHighlighting]);

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
  }, [player]);

  return {
    isPlaying,
    isLoading,
    currentWordIndex,
    play,
    stop,
    error,
    playbackRate,
    setPlaybackRate,
  };
}
