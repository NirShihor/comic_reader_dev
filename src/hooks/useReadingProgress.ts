import { useState, useEffect, useCallback } from 'react';
import AsyncStorage from '@react-native-async-storage/async-storage';

const PROGRESS_STORAGE_KEY = '@comic_reader_progress';

export interface ReadingProgress {
  comicId: string;
  pageId: string;
  pageNumber: number;
  lastReadAt: string;
}

interface ProgressMap {
  [comicId: string]: ReadingProgress;
}

export function useReadingProgress() {
  const [progressMap, setProgressMap] = useState<ProgressMap>({});
  const [isLoaded, setIsLoaded] = useState(false);

  // Load progress from storage on mount
  useEffect(() => {
    loadProgress();
  }, []);

  const loadProgress = async () => {
    try {
      const stored = await AsyncStorage.getItem(PROGRESS_STORAGE_KEY);
      if (stored) {
        setProgressMap(JSON.parse(stored));
      }
      setIsLoaded(true);
    } catch (error) {
      console.error('Failed to load reading progress:', error);
      setIsLoaded(true);
    }
  };

  const saveProgress = useCallback(async (
    comicId: string,
    pageId: string,
    pageNumber: number
  ) => {
    try {
      const newProgress: ReadingProgress = {
        comicId,
        pageId,
        pageNumber,
        lastReadAt: new Date().toISOString(),
      };

      const newMap = {
        ...progressMap,
        [comicId]: newProgress,
      };

      await AsyncStorage.setItem(PROGRESS_STORAGE_KEY, JSON.stringify(newMap));
      setProgressMap(newMap);
    } catch (error) {
      console.error('Failed to save reading progress:', error);
    }
  }, [progressMap]);

  const getProgress = useCallback((comicId: string): ReadingProgress | null => {
    return progressMap[comicId] || null;
  }, [progressMap]);

  const clearProgress = useCallback(async (comicId: string) => {
    try {
      const newMap = { ...progressMap };
      delete newMap[comicId];
      await AsyncStorage.setItem(PROGRESS_STORAGE_KEY, JSON.stringify(newMap));
      setProgressMap(newMap);
    } catch (error) {
      console.error('Failed to clear reading progress:', error);
    }
  }, [progressMap]);

  const clearAllProgress = useCallback(async () => {
    try {
      await AsyncStorage.removeItem(PROGRESS_STORAGE_KEY);
      setProgressMap({});
    } catch (error) {
      console.error('Failed to clear all reading progress:', error);
    }
  }, []);

  return {
    isLoaded,
    saveProgress,
    getProgress,
    clearProgress,
    clearAllProgress,
  };
}
