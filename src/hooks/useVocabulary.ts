import { useState, useEffect, useCallback } from 'react';
import AsyncStorage from '@react-native-async-storage/async-storage';
import { Word, SavedWord } from '../types/comic';

const VOCABULARY_KEY = '@comic_reader_vocabulary';

interface UseVocabularyReturn {
  savedWords: SavedWord[];
  isLoading: boolean;
  saveWord: (word: Word) => Promise<void>;
  removeWord: (wordId: string) => Promise<void>;
  isWordSaved: (wordId: string) => boolean;
  clearAll: () => Promise<void>;
}

export function useVocabulary(): UseVocabularyReturn {
  const [savedWords, setSavedWords] = useState<SavedWord[]>([]);
  const [isLoading, setIsLoading] = useState(true);

  // Load saved words on mount
  useEffect(() => {
    loadWords();
  }, []);

  const loadWords = async () => {
    try {
      const stored = await AsyncStorage.getItem(VOCABULARY_KEY);
      if (stored) {
        const parsed = JSON.parse(stored) as SavedWord[];
        // Convert date strings back to Date objects
        const withDates = parsed.map(w => ({
          ...w,
          savedAt: new Date(w.savedAt),
        }));
        setSavedWords(withDates);
      }
    } catch (e) {
      console.error('Failed to load vocabulary:', e);
    } finally {
      setIsLoading(false);
    }
  };

  const persistWords = async (words: SavedWord[]) => {
    try {
      await AsyncStorage.setItem(VOCABULARY_KEY, JSON.stringify(words));
    } catch (e) {
      console.error('Failed to save vocabulary:', e);
    }
  };

  const saveWord = useCallback(async (word: Word) => {
    // Check if word already exists
    const exists = savedWords.some(w => w.wordId === word.id);
    if (exists) return;

    const newSavedWord: SavedWord = {
      wordId: word.id,
      word: word,
      savedAt: new Date(),
      reviewState: 'new',
    };

    const updated = [newSavedWord, ...savedWords];
    setSavedWords(updated);
    await persistWords(updated);
  }, [savedWords]);

  const removeWord = useCallback(async (wordId: string) => {
    const updated = savedWords.filter(w => w.wordId !== wordId);
    setSavedWords(updated);
    await persistWords(updated);
  }, [savedWords]);

  const isWordSaved = useCallback((wordId: string) => {
    return savedWords.some(w => w.wordId === wordId);
  }, [savedWords]);

  const clearAll = useCallback(async () => {
    setSavedWords([]);
    await AsyncStorage.removeItem(VOCABULARY_KEY);
  }, []);

  return {
    savedWords,
    isLoading,
    saveWord,
    removeWord,
    isWordSaved,
    clearAll,
  };
}
