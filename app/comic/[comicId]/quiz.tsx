import { StyleSheet, View, Pressable, ActivityIndicator, Animated } from 'react-native';
import { useLocalSearchParams, router, Stack } from 'expo-router';
import { useState, useCallback, useRef, useEffect } from 'react';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { Ionicons } from '@expo/vector-icons';
import * as Haptics from 'expo-haptics';
import { Text } from '@/components/Themed';
import { comics } from '@/src/data/comics';
import { useWhisperTranscription } from '@/src/hooks/useWhisperTranscription';
import { useAudio } from '@/src/hooks/useAudio';
import { compareWords } from '@/src/utils/wordComparison';
import { getWordAudioUrl } from '@/src/utils/audio';
import { QuizResult, QuizState } from '@/src/types/quiz';
import { ReviewWord } from '@/src/types/comic';

export default function QuizScreen() {
  const { comicId } = useLocalSearchParams<{ comicId: string }>();
  const insets = useSafeAreaInsets();
  const comic = comics.find((c) => c.id === comicId);
  const reviewWords = comic?.reviewWords || [];

  const [currentIndex, setCurrentIndex] = useState(0);
  const [quizState, setQuizState] = useState<QuizState>('prompting');
  const [results, setResults] = useState<QuizResult[]>([]);
  const [currentResult, setCurrentResult] = useState<QuizResult | null>(null);

  const { isRecording, isProcessing, transcript, error, startRecording, stopRecording, reset } =
    useWhisperTranscription();
  const { play } = useAudio({});

  // Animation for feedback
  const scaleAnim = useRef(new Animated.Value(1)).current;
  const fadeAnim = useRef(new Animated.Value(0)).current;

  const currentWord = reviewWords[currentIndex];
  const isLastWord = currentIndex === reviewWords.length - 1;
  const correctCount = results.filter((r) => r.isCorrect).length;

  useEffect(() => {
    if (transcript && currentWord) {
      // Compare spoken text with expected word
      const comparison = compareWords(transcript, currentWord.word.text);
      const result: QuizResult = {
        wordId: currentWord.word.id,
        word: currentWord.word,
        isCorrect: comparison.isMatch,
        spokenText: transcript,
        expectedText: currentWord.word.text,
        panelId: currentWord.panelId,
        pageId: currentWord.pageId,
      };
      setCurrentResult(result);
      setQuizState('feedback');

      // Animate feedback
      Animated.sequence([
        Animated.spring(scaleAnim, {
          toValue: 1.1,
          useNativeDriver: true,
        }),
        Animated.spring(scaleAnim, {
          toValue: 1,
          useNativeDriver: true,
        }),
      ]).start();

      Animated.timing(fadeAnim, {
        toValue: 1,
        duration: 300,
        useNativeDriver: true,
      }).start();

      // Haptic feedback
      if (comparison.isMatch) {
        Haptics.notificationAsync(Haptics.NotificationFeedbackType.Success);
      } else {
        Haptics.notificationAsync(Haptics.NotificationFeedbackType.Error);
      }

      // Play the correct pronunciation after a short delay
      setTimeout(() => {
        if (currentWord.word.audioUrl) {
          // Phrase with dedicated audio
          play(currentWord.word.audioUrl);
        } else {
          // Single word - use word audio
          const audioUrl = getWordAudioUrl(currentWord.word.text);
          if (audioUrl) {
            play(audioUrl);
          }
        }
      }, 100);
    }
  }, [transcript, currentWord, play]);

  const handleStartRecording = useCallback(async () => {
    setQuizState('listening');
    await startRecording();
  }, [startRecording]);

  const handleStopRecording = useCallback(async () => {
    setQuizState('processing');
    await stopRecording();
  }, [stopRecording]);

  const handleNextWord = useCallback(() => {
    if (currentResult) {
      setResults((prev) => [...prev, currentResult]);
    }

    if (isLastWord) {
      setQuizState('completed');
    } else {
      setCurrentIndex((prev) => prev + 1);
      setQuizState('prompting');
      setCurrentResult(null);
      reset();
      fadeAnim.setValue(0);
    }
  }, [currentResult, isLastWord, reset, fadeAnim]);

  const handleSkip = useCallback(() => {
    if (currentWord) {
      const result: QuizResult = {
        wordId: currentWord.word.id,
        word: currentWord.word,
        isCorrect: false,
        spokenText: '(skipped)',
        expectedText: currentWord.word.text,
        panelId: currentWord.panelId,
        pageId: currentWord.pageId,
      };
      setResults((prev) => [...prev, result]);
    }

    if (isLastWord) {
      setQuizState('completed');
    } else {
      setCurrentIndex((prev) => prev + 1);
      setQuizState('prompting');
      setCurrentResult(null);
      reset();
    }
  }, [currentWord, isLastWord, reset]);

  const handleTryAgain = useCallback(() => {
    setQuizState('prompting');
    setCurrentResult(null);
    reset();
    fadeAnim.setValue(0);
  }, [reset, fadeAnim]);

  const handleSeeContext = useCallback(
    (panelId: string, pageId: string, wordText: string) => {
      router.push(`/comic/${comicId}/page/${pageId}/panel/${panelId}?highlightWord=${encodeURIComponent(wordText)}`);
    },
    [comicId]
  );

  const handlePlayWord = useCallback(async () => {
    if (currentWord?.word.audioUrl) {
      await play(currentWord.word.audioUrl);
    }
  }, [currentWord, play]);

  const handleRetryQuiz = useCallback(() => {
    setCurrentIndex(0);
    setResults([]);
    setCurrentResult(null);
    setQuizState('prompting');
    reset();
  }, [reset]);

  if (!comic || reviewWords.length === 0) {
    return (
      <View style={styles.container}>
        <Stack.Screen options={{ title: 'Vocabulary Quiz' }} />
        <View style={styles.emptyState}>
          <Ionicons name="school-outline" size={64} color="#ccc" />
          <Text style={styles.emptyText}>No review words available for this comic.</Text>
          <Pressable style={styles.backButton} onPress={() => router.back()}>
            <Text style={styles.backButtonText}>Go Back</Text>
          </Pressable>
        </View>
      </View>
    );
  }

  // Quiz completed view
  if (quizState === 'completed') {
    return (
      <View style={styles.container}>
        <Stack.Screen options={{ title: 'Quiz Complete' }} />
        <View style={styles.completedContainer}>
          <Ionicons
            name={correctCount === reviewWords.length ? 'trophy' : 'checkmark-circle'}
            size={80}
            color={correctCount === reviewWords.length ? '#f1c40f' : '#27ae60'}
          />
          <Text style={styles.completedTitle}>Quiz Complete!</Text>
          <Text style={styles.scoreText}>
            {correctCount} / {reviewWords.length} correct
          </Text>

          <View style={styles.resultsContainer}>
            {results.map((result, index) => (
              <View
                key={result.wordId}
                style={[styles.resultRow, result.isCorrect ? styles.resultCorrect : styles.resultIncorrect]}
              >
                <View style={styles.resultInfo}>
                  <Text style={styles.resultWord}>{result.word.text}</Text>
                  <Text style={styles.resultMeaning}>{result.word.meaning}</Text>
                </View>
                <Ionicons
                  name={result.isCorrect ? 'checkmark-circle' : 'close-circle'}
                  size={24}
                  color={result.isCorrect ? '#27ae60' : '#e74c3c'}
                />
              </View>
            ))}
          </View>

          <View style={styles.completedActions}>
            <Pressable style={styles.retryButton} onPress={handleRetryQuiz}>
              <Ionicons name="refresh" size={20} color="#1a1a2e" />
              <Text style={styles.retryButtonText}>Try Again</Text>
            </Pressable>
            <Pressable style={styles.doneButton} onPress={() => router.back()}>
              <Text style={styles.doneButtonText}>Done</Text>
            </Pressable>
          </View>
        </View>
      </View>
    );
  }

  return (
    <View style={styles.container}>
      <Stack.Screen
        options={{
          title: 'Vocabulary Quiz',
          headerRight: () => (
            <Text style={styles.progressText}>
              {currentIndex + 1} / {reviewWords.length}
            </Text>
          ),
        }}
      />

      {/* Progress bar */}
      <View style={styles.progressBar}>
        <View
          style={[styles.progressFill, { width: `${((currentIndex + 1) / reviewWords.length) * 100}%` }]}
        />
      </View>

      {/* Word card */}
      <View style={styles.cardContainer}>
        <Text style={styles.promptLabel}>What is the Spanish word for:</Text>
        <Text style={styles.englishWord}>"{currentWord?.word.meaning}"</Text>
        {currentWord?.word.baseForm && currentWord.word.baseForm !== currentWord.word.text && (
          <Text style={styles.baseFormHint}>(base form: {currentWord.word.baseForm})</Text>
        )}
      </View>

      {/* Feedback section */}
      {quizState === 'feedback' && currentResult && (
        <Animated.View style={[styles.feedbackContainer, { opacity: fadeAnim, transform: [{ scale: scaleAnim }] }]}>
          <View style={[styles.feedbackBadge, currentResult.isCorrect ? styles.correctBadge : styles.incorrectBadge]}>
            <Ionicons
              name={currentResult.isCorrect ? 'checkmark-circle' : 'close-circle'}
              size={32}
              color="#fff"
            />
            <Text style={styles.feedbackTitle}>{currentResult.isCorrect ? 'Correct!' : 'Not quite'}</Text>
          </View>
          <Text style={styles.feedbackSpoken}>You said: "{currentResult.spokenText}"</Text>
          {!currentResult.isCorrect && (
            <Text style={styles.feedbackExpected}>Expected: "{currentResult.expectedText}"</Text>
          )}
        </Animated.View>
      )}

      {/* Recording controls */}
      <View style={styles.controlsContainer}>
        {quizState === 'prompting' && (
          <Pressable
            style={({ pressed }) => [styles.micButton, pressed && styles.micButtonPressed]}
            onPress={handleStartRecording}
          >
            <Ionicons name="mic" size={56} color="#fff" />
            <Text style={styles.micLabel}>Tap to speak</Text>
          </Pressable>
        )}

        {quizState === 'listening' && (
          <Pressable
            style={[styles.micButton, styles.micButtonRecording]}
            onPress={handleStopRecording}
          >
            <Ionicons name="stop" size={56} color="#fff" />
            <Text style={styles.micLabel}>Tap to stop</Text>
          </Pressable>
        )}

        {quizState === 'processing' && (
          <View style={styles.processingContainer}>
            <ActivityIndicator size="large" color="#1a1a2e" />
            <Text style={styles.processingText}>Processing...</Text>
          </View>
        )}

        {quizState === 'feedback' && (
          <View style={styles.feedbackButtons}>
            <Pressable
              style={({ pressed }) => [styles.tryAgainButton, pressed && styles.buttonPressed]}
              onPress={handleTryAgain}
            >
              <Ionicons name="refresh" size={20} color="#1a1a2e" />
              <Text style={styles.tryAgainButtonText}>Try Again</Text>
            </Pressable>
            <Pressable
              style={({ pressed }) => [styles.nextButton, pressed && styles.nextButtonPressed]}
              onPress={handleNextWord}
            >
              <Text style={styles.nextButtonText}>{isLastWord ? 'See Results' : 'Next Word'}</Text>
              <Ionicons name="arrow-forward" size={20} color="#fff" />
            </Pressable>
          </View>
        )}
      </View>

      {/* Action buttons */}
      <View style={styles.actionsContainer}>
        {quizState !== 'feedback' && (
          <Pressable style={styles.skipButton} onPress={handleSkip}>
            <Text style={styles.skipButtonText}>Skip</Text>
          </Pressable>
        )}

        <Pressable
          style={styles.contextButton}
          onPress={() => handleSeeContext(currentWord.panelId, currentWord.pageId, currentWord.word.text)}
        >
          <Ionicons name="image-outline" size={18} color="#1a1a2e" />
          <Text style={styles.contextButtonText}>See in Context</Text>
        </Pressable>

        {currentWord?.word.audioUrl && (
          <Pressable style={styles.listenButton} onPress={handlePlayWord}>
            <Ionicons name="volume-medium" size={18} color="#1a1a2e" />
            <Text style={styles.listenButtonText}>Listen</Text>
          </Pressable>
        )}
      </View>

      {/* Error message */}
      {error && (
        <View style={styles.errorContainer}>
          <Ionicons name="warning" size={20} color="#e74c3c" />
          <Text style={styles.errorText}>{error}</Text>
        </View>
      )}
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: '#f8f8f8',
  },
  progressText: {
    fontSize: 16,
    fontWeight: '600',
    color: '#666',
    marginRight: 8,
  },
  progressBar: {
    height: 4,
    backgroundColor: '#e0e0e0',
  },
  progressFill: {
    height: '100%',
    backgroundColor: '#1a1a2e',
  },
  cardContainer: {
    flex: 1,
    justifyContent: 'center',
    alignItems: 'center',
    paddingHorizontal: 32,
  },
  promptLabel: {
    fontSize: 18,
    color: '#666',
    marginBottom: 16,
  },
  englishWord: {
    fontSize: 32,
    fontWeight: '700',
    color: '#1a1a2e',
    textAlign: 'center',
  },
  baseFormHint: {
    fontSize: 14,
    color: '#999',
    marginTop: 8,
  },
  feedbackContainer: {
    alignItems: 'center',
    paddingHorizontal: 32,
    marginBottom: 24,
  },
  feedbackBadge: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingHorizontal: 24,
    paddingVertical: 12,
    borderRadius: 24,
    gap: 8,
    marginBottom: 12,
  },
  correctBadge: {
    backgroundColor: '#27ae60',
  },
  incorrectBadge: {
    backgroundColor: '#e74c3c',
  },
  feedbackTitle: {
    fontSize: 20,
    fontWeight: '700',
    color: '#fff',
  },
  feedbackSpoken: {
    fontSize: 16,
    color: '#666',
  },
  feedbackExpected: {
    fontSize: 16,
    color: '#e74c3c',
    marginTop: 4,
  },
  controlsContainer: {
    alignItems: 'center',
    paddingBottom: 24,
  },
  micButton: {
    width: 150,
    height: 150,
    borderRadius: 75,
    backgroundColor: '#1a1a2e',
    justifyContent: 'center',
    alignItems: 'center',
  },
  micButtonPressed: {
    opacity: 0.8,
    transform: [{ scale: 0.95 }],
  },
  micButtonRecording: {
    backgroundColor: '#e74c3c',
  },
  micLabel: {
    color: '#fff',
    fontSize: 14,
    marginTop: 4,
  },
  processingContainer: {
    alignItems: 'center',
    gap: 12,
  },
  processingText: {
    fontSize: 16,
    color: '#666',
  },
  feedbackButtons: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 12,
  },
  tryAgainButton: {
    flexDirection: 'row',
    alignItems: 'center',
    backgroundColor: '#e0e0e0',
    paddingHorizontal: 24,
    paddingVertical: 16,
    borderRadius: 12,
    gap: 8,
  },
  tryAgainButtonText: {
    color: '#1a1a2e',
    fontSize: 16,
    fontWeight: '600',
  },
  buttonPressed: {
    opacity: 0.7,
  },
  nextButton: {
    flexDirection: 'row',
    alignItems: 'center',
    backgroundColor: '#27ae60',
    paddingHorizontal: 32,
    paddingVertical: 16,
    borderRadius: 12,
    gap: 8,
  },
  nextButtonPressed: {
    opacity: 0.8,
  },
  nextButtonText: {
    color: '#fff',
    fontSize: 18,
    fontWeight: '600',
  },
  actionsContainer: {
    flexDirection: 'row',
    justifyContent: 'center',
    gap: 16,
    paddingHorizontal: 16,
    paddingBottom: 32,
  },
  skipButton: {
    paddingHorizontal: 20,
    paddingVertical: 12,
    borderRadius: 8,
    backgroundColor: '#e0e0e0',
  },
  skipButtonText: {
    color: '#666',
    fontSize: 14,
    fontWeight: '500',
  },
  contextButton: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingHorizontal: 16,
    paddingVertical: 12,
    borderRadius: 8,
    backgroundColor: '#e0e0e0',
    gap: 6,
  },
  contextButtonText: {
    color: '#1a1a2e',
    fontSize: 14,
    fontWeight: '500',
  },
  listenButton: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingHorizontal: 16,
    paddingVertical: 12,
    borderRadius: 8,
    backgroundColor: '#e0e0e0',
    gap: 6,
  },
  listenButtonText: {
    color: '#1a1a2e',
    fontSize: 14,
    fontWeight: '500',
  },
  errorContainer: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'center',
    gap: 8,
    paddingBottom: 16,
  },
  errorText: {
    color: '#e74c3c',
    fontSize: 14,
  },
  emptyState: {
    flex: 1,
    justifyContent: 'center',
    alignItems: 'center',
    padding: 32,
    gap: 16,
  },
  emptyText: {
    fontSize: 16,
    color: '#666',
    textAlign: 'center',
  },
  backButton: {
    paddingHorizontal: 24,
    paddingVertical: 12,
    borderRadius: 8,
    backgroundColor: '#1a1a2e',
  },
  backButtonText: {
    color: '#fff',
    fontSize: 16,
    fontWeight: '500',
  },
  completedContainer: {
    flex: 1,
    alignItems: 'center',
    paddingTop: 48,
    paddingHorizontal: 16,
  },
  completedTitle: {
    fontSize: 28,
    fontWeight: '700',
    color: '#1a1a2e',
    marginTop: 16,
  },
  scoreText: {
    fontSize: 20,
    color: '#666',
    marginTop: 8,
    marginBottom: 24,
  },
  resultsContainer: {
    width: '100%',
    gap: 8,
    marginBottom: 24,
  },
  resultRow: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    padding: 16,
    borderRadius: 12,
    backgroundColor: '#fff',
  },
  resultCorrect: {
    borderLeftWidth: 4,
    borderLeftColor: '#27ae60',
  },
  resultIncorrect: {
    borderLeftWidth: 4,
    borderLeftColor: '#e74c3c',
  },
  resultInfo: {
    flex: 1,
  },
  resultWord: {
    fontSize: 18,
    fontWeight: '600',
    color: '#1a1a2e',
  },
  resultMeaning: {
    fontSize: 14,
    color: '#666',
  },
  completedActions: {
    flexDirection: 'row',
    gap: 16,
  },
  retryButton: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingHorizontal: 24,
    paddingVertical: 14,
    borderRadius: 12,
    backgroundColor: '#e0e0e0',
    gap: 8,
  },
  retryButtonText: {
    color: '#1a1a2e',
    fontSize: 16,
    fontWeight: '600',
  },
  doneButton: {
    paddingHorizontal: 32,
    paddingVertical: 14,
    borderRadius: 12,
    backgroundColor: '#1a1a2e',
  },
  doneButtonText: {
    color: '#fff',
    fontSize: 16,
    fontWeight: '600',
  },
});
