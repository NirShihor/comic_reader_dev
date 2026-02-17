import { StyleSheet, Pressable, Image, View, Dimensions, StatusBar, ScrollView, ActivityIndicator, Animated } from 'react-native';
import { useLocalSearchParams, router } from 'expo-router';
import { useState, useCallback, useRef, useEffect } from 'react';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { Ionicons } from '@expo/vector-icons';
import * as Haptics from 'expo-haptics';
import { Text } from '@/components/Themed';
import { comics } from '@/src/data/comics';
import { Word, Sentence } from '@/src/types/comic';
import { useAudio } from '@/src/hooks/useAudio';
import { useVocabulary } from '@/src/hooks/useVocabulary';
import { getImageSource } from '@/src/utils/images';

const { width: SCREEN_WIDTH } = Dimensions.get('window');

export default function PanelScreen() {
  const { comicId, pageId, panelId } = useLocalSearchParams<{
    comicId: string;
    pageId: string;
    panelId: string;
  }>();
  const insets = useSafeAreaInsets();
  const [selectedWord, setSelectedWord] = useState<Word | null>(null);
  const [playingSentenceId, setPlayingSentenceId] = useState<string | null>(null);
  const [highlightedWordIndex, setHighlightedWordIndex] = useState<number | null>(null);
  const [visibleTranslations, setVisibleTranslations] = useState<Set<string>>(new Set());

  // Animation for dictionary modal
  const slideAnim = useRef(new Animated.Value(300)).current;
  const fadeAnim = useRef(new Animated.Value(0)).current;

  useEffect(() => {
    if (selectedWord) {
      // Animate in
      Animated.parallel([
        Animated.spring(slideAnim, {
          toValue: 0,
          useNativeDriver: true,
          tension: 65,
          friction: 11,
        }),
        Animated.timing(fadeAnim, {
          toValue: 1,
          duration: 200,
          useNativeDriver: true,
        }),
      ]).start();
    } else {
      // Reset for next open
      slideAnim.setValue(300);
      fadeAnim.setValue(0);
    }
  }, [selectedWord]);

  const { saveWord, removeWord, isWordSaved } = useVocabulary();

  const comic = comics.find((c) => c.id === comicId);
  const page = comic?.pages.find((p) => p.id === pageId);
  const panel = page?.panels.find((p) => p.id === panelId);
  const currentPanelIndex = page?.panels.findIndex((p) => p.id === panelId) ?? 0;

  // Build a flat list of all panels across all pages for sequential navigation
  const allPanels = comic?.pages.flatMap((p) =>
    p.panels.map((panel) => ({ pageId: p.id, panelId: panel.id }))
  ) ?? [];
  const currentGlobalIndex = allPanels.findIndex(
    (p) => p.pageId === pageId && p.panelId === panelId
  );

  // Find the currently playing sentence's words for the audio hook
  const playingSentence = panel?.bubbles
    .flatMap(b => b.sentences)
    .find(s => s.id === playingSentenceId);

  const handleWordHighlight = useCallback((index: number | null) => {
    setHighlightedWordIndex(index);
    if (index === null) {
      setPlayingSentenceId(null);
    }
  }, []);

  const { isPlaying, isLoading, play, stop } = useAudio({
    words: playingSentence?.words,
    onWordHighlight: handleWordHighlight,
  });

  if (!comic || !page || !panel) {
    return null;
  }

  const goToNextPanel = () => {
    if (currentGlobalIndex < allPanels.length - 1) {
      Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Light);
      const next = allPanels[currentGlobalIndex + 1];
      router.replace(`/comic/${comicId}/page/${next.pageId}/panel/${next.panelId}`);
    }
  };

  const goToPrevPanel = () => {
    if (currentGlobalIndex > 0) {
      Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Light);
      const prev = allPanels[currentGlobalIndex - 1];
      router.replace(`/comic/${comicId}/page/${prev.pageId}/panel/${prev.panelId}`);
    }
  };

  const toggleTranslation = (sentenceId: string) => {
    Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Light);
    setVisibleTranslations((prev) => {
      const newSet = new Set(prev);
      if (newSet.has(sentenceId)) {
        newSet.delete(sentenceId);
      } else {
        newSet.add(sentenceId);
      }
      return newSet;
    });
  };

  const handleWordPress = (word: Word) => {
    Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Light);
    setSelectedWord(word);
  };

  const handleSentencePress = async (sentence: Sentence) => {
    Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Light);
    if (isPlaying && playingSentenceId === sentence.id) {
      // Stop if already playing this sentence
      await stop();
      setPlayingSentenceId(null);
    } else {
      // Play the sentence
      setPlayingSentenceId(sentence.id);
      if (sentence.audioUrl) {
        await play(sentence.audioUrl);
      } else {
        // Simulate playback if no audio URL
        await play('');
      }
    }
  };

  const closeDictionary = () => {
    Animated.parallel([
      Animated.timing(slideAnim, {
        toValue: 300,
        duration: 200,
        useNativeDriver: true,
      }),
      Animated.timing(fadeAnim, {
        toValue: 0,
        duration: 200,
        useNativeDriver: true,
      }),
    ]).start(() => {
      setSelectedWord(null);
    });
  };

  const handleListenWord = async () => {
    if (selectedWord?.audioUrl) {
      await play(selectedWord.audioUrl);
    }
  };

  const handleSaveWord = async () => {
    if (!selectedWord) return;

    if (isWordSaved(selectedWord.id)) {
      Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Light);
      await removeWord(selectedWord.id);
    } else {
      Haptics.notificationAsync(Haptics.NotificationFeedbackType.Success);
      await saveWord(selectedWord);
    }
  };

  const wordIsSaved = selectedWord ? isWordSaved(selectedWord.id) : false;

  return (
    <View style={styles.container}>
      <StatusBar hidden />

      {/* Panel artwork */}
      <View style={styles.imageContainer}>
        <Image
          source={getImageSource(panel.artworkImage)}
          style={styles.panelImage}
        />
      </View>

      {/* Speech bubbles overlay */}
      <ScrollView
        style={styles.bubblesContainer}
        contentContainerStyle={styles.bubblesContent}
      >
        {panel.bubbles.map((bubble) => (
          <View key={bubble.id} style={styles.bubble}>
            {bubble.type === 'narration' && (
              <Text style={styles.bubbleTypeLabel}>Narration</Text>
            )}
            {bubble.type === 'thought' && (
              <Text style={styles.bubbleTypeLabel}>Thought</Text>
            )}
            {bubble.sentences.map((sentence) => {
              const isCurrentSentence = playingSentenceId === sentence.id;
              const showTranslation = visibleTranslations.has(sentence.id);
              return (
                <View key={sentence.id} style={styles.sentenceWrapper}>
                  <View style={styles.sentenceContainer}>
                    <View style={styles.wordsContainer}>
                      {sentence.words.map((word, index) => {
                        const isHighlighted = isCurrentSentence && highlightedWordIndex === index;
                        const isSaved = isWordSaved(word.id);
                        return (
                          <Pressable
                            key={word.id}
                            onPress={() => handleWordPress(word)}
                            style={({ pressed }) => [
                              styles.wordButton,
                              isHighlighted && styles.wordHighlighted,
                              isSaved && styles.wordSaved,
                              pressed && styles.wordPressed,
                            ]}
                          >
                            <Text
                              style={[
                                styles.wordText,
                                isHighlighted && styles.wordTextHighlighted,
                              ]}
                            >
                              {word.text}
                            </Text>
                          </Pressable>
                        );
                      })}
                    </View>
                    <View style={styles.sentenceActions}>
                      {sentence.translation && (
                        <Pressable
                          onPress={() => toggleTranslation(sentence.id)}
                          style={({ pressed }) => [
                            styles.translateButton,
                            showTranslation && styles.translateButtonActive,
                            pressed && styles.buttonPressed,
                          ]}
                        >
                          <Text style={[
                            styles.translateButtonText,
                            showTranslation && styles.translateButtonTextActive,
                          ]}>
                            EN
                          </Text>
                        </Pressable>
                      )}
                      <Pressable
                        onPress={() => handleSentencePress(sentence)}
                        style={({ pressed }) => [
                          styles.audioButton,
                          pressed && styles.buttonPressed,
                        ]}
                      >
                        {isLoading && isCurrentSentence ? (
                          <ActivityIndicator size="small" color="#1a1a2e" />
                        ) : (
                          <Ionicons
                            name={isPlaying && isCurrentSentence ? 'stop-circle' : 'volume-medium-outline'}
                            size={22}
                            color={isPlaying && isCurrentSentence ? '#e74c3c' : '#666'}
                          />
                        )}
                      </Pressable>
                    </View>
                  </View>
                  {showTranslation && sentence.translation && (
                    <Text style={styles.translationText}>{sentence.translation}</Text>
                  )}
                </View>
              );
            })}
          </View>
        ))}
      </ScrollView>

      {/* Navigation overlay */}
      <View style={[styles.navOverlay, { top: insets.top + 10 }]}>
        <Pressable
          onPress={() => router.back()}
          style={({ pressed }) => [styles.navButton, pressed && styles.buttonPressed]}
        >
          <Ionicons name="close" size={24} color="#fff" />
        </Pressable>

        <View style={styles.rightControls}>
          <View style={styles.panelIndicator}>
            <Pressable
              onPress={goToPrevPanel}
              style={({ pressed }) => [
                styles.arrowButton,
                currentGlobalIndex === 0 && styles.arrowDisabled,
                pressed && currentGlobalIndex !== 0 && styles.buttonPressed,
              ]}
              disabled={currentGlobalIndex === 0}
            >
              <Ionicons name="chevron-back" size={20} color="#fff" />
            </Pressable>

            <Text style={styles.panelNumberText}>
              {currentGlobalIndex + 1}/{allPanels.length}
            </Text>

            <Pressable
              onPress={goToNextPanel}
              style={({ pressed }) => [
                styles.arrowButton,
                currentGlobalIndex === allPanels.length - 1 && styles.arrowDisabled,
                pressed && currentGlobalIndex !== allPanels.length - 1 && styles.buttonPressed,
              ]}
              disabled={currentGlobalIndex === allPanels.length - 1}
            >
              <Ionicons name="chevron-forward" size={20} color="#fff" />
            </Pressable>
          </View>

          <Pressable
            onPress={() => router.push('/vocabulary')}
            style={({ pressed }) => [styles.navButton, pressed && styles.buttonPressed]}
          >
            <Ionicons name="bookmark" size={20} color="#fff" />
          </Pressable>

          <Pressable
            onPress={() => router.push('/settings')}
            style={({ pressed }) => [styles.navButton, pressed && styles.buttonPressed]}
          >
            <Ionicons name="settings-outline" size={20} color="#fff" />
          </Pressable>
        </View>
      </View>

      {/* Dictionary modal */}
      {selectedWord && (
        <Animated.View style={[styles.dictionaryOverlay, { opacity: fadeAnim }]}>
          <Pressable style={styles.dictionaryOverlayPressable} onPress={closeDictionary}>
            <Animated.View
              style={[
                styles.dictionaryModal,
                { transform: [{ translateY: slideAnim }] },
              ]}
            >
              <Pressable onPress={(e) => e.stopPropagation()}>
                <View style={styles.dictionaryHeader}>
                  <Text style={styles.dictionaryWord}>{selectedWord.text}</Text>
                  <Pressable onPress={closeDictionary}>
                    <Ionicons name="close-circle" size={28} color="#666" />
                  </Pressable>
                </View>

                {selectedWord.baseForm && (
                  <Text style={styles.baseForm}>Base: {selectedWord.baseForm}</Text>
                )}

                <Text style={styles.meaning}>{selectedWord.meaning}</Text>

                <View style={styles.dictionaryActions}>
                  <Pressable
                    style={({ pressed }) => [
                      styles.actionButton,
                      pressed && styles.buttonPressed,
                    ]}
                    onPress={handleListenWord}
                  >
                    <Ionicons name="volume-high" size={20} color="#1a1a2e" />
                    <Text style={styles.actionText}>Listen</Text>
                  </Pressable>

                  <Pressable
                    style={({ pressed }) => [
                      styles.actionButton,
                      wordIsSaved && styles.actionButtonSaved,
                      pressed && styles.buttonPressed,
                    ]}
                    onPress={handleSaveWord}
                  >
                    <Ionicons
                      name={wordIsSaved ? 'bookmark' : 'bookmark-outline'}
                      size={20}
                      color={wordIsSaved ? '#fff' : '#1a1a2e'}
                    />
                    <Text style={[styles.actionText, wordIsSaved && styles.actionTextSaved]}>
                      {wordIsSaved ? 'Saved' : 'Save'}
                    </Text>
                  </Pressable>
                </View>
              </Pressable>
            </Animated.View>
          </Pressable>
        </Animated.View>
      )}
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: '#f8f8f8',
  },
  imageContainer: {
    height: 480,
    marginTop: 140,
    alignItems: 'center',
  },
  panelImage: {
    width: '90%',
    height: '100%',
    resizeMode: 'contain',
  },
  bubblesContainer: {
    flex: 1,
  },
  bubblesContent: {
    paddingHorizontal: 16,
    paddingTop: 8,
    paddingBottom: 16,
  },
  bubble: {
    backgroundColor: '#fff',
    borderRadius: 16,
    padding: 16,
    marginBottom: 12,
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 2 },
    shadowOpacity: 0.1,
    shadowRadius: 4,
    elevation: 2,
  },
  bubbleTypeLabel: {
    fontSize: 11,
    fontWeight: '600',
    color: '#999',
    textTransform: 'uppercase',
    letterSpacing: 0.5,
    marginBottom: 8,
  },
  sentenceWrapper: {
    marginBottom: 12,
  },
  sentenceContainer: {
    flexDirection: 'row',
    alignItems: 'center',
  },
  sentenceActions: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 6,
  },
  translateButton: {
    width: 32,
    height: 32,
    borderRadius: 16,
    backgroundColor: '#f0f0f0',
    justifyContent: 'center',
    alignItems: 'center',
  },
  translateButtonActive: {
    backgroundColor: '#3498db',
  },
  translateButtonText: {
    fontSize: 12,
    fontWeight: '700',
    color: '#666',
  },
  translateButtonTextActive: {
    color: '#fff',
  },
  translationText: {
    fontSize: 15,
    color: '#666',
    fontStyle: 'italic',
    marginTop: 6,
    paddingLeft: 2,
    lineHeight: 22,
  },
  wordsContainer: {
    flex: 1,
    flexDirection: 'row',
    flexWrap: 'wrap',
  },
  wordButton: {
    marginRight: 6,
    marginBottom: 4,
    paddingHorizontal: 2,
    paddingVertical: 1,
    borderRadius: 4,
  },
  wordPressed: {
    backgroundColor: 'rgba(26, 26, 46, 0.2)',
  },
  buttonPressed: {
    opacity: 0.5,
  },
  wordHighlighted: {
    backgroundColor: '#ffeaa7',
  },
  wordSaved: {
    borderBottomWidth: 2,
    borderBottomColor: '#3498db',
  },
  wordText: {
    fontSize: 18,
    color: '#1a1a2e',
    lineHeight: 26,
  },
  wordTextHighlighted: {
    color: '#1a1a2e',
    fontWeight: '600',
  },
  audioButton: {
    marginLeft: 8,
    width: 36,
    height: 36,
    borderRadius: 18,
    backgroundColor: '#f0f0f0',
    justifyContent: 'center',
    alignItems: 'center',
  },
  navOverlay: {
    position: 'absolute',
    left: 16,
    right: 16,
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
  },
  rightControls: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 8,
  },
  navButton: {
    width: 40,
    height: 40,
    borderRadius: 20,
    backgroundColor: 'rgba(0,0,0,0.5)',
    justifyContent: 'center',
    alignItems: 'center',
  },
  panelIndicator: {
    flexDirection: 'row',
    alignItems: 'center',
    backgroundColor: 'rgba(0,0,0,0.5)',
    borderRadius: 20,
    paddingHorizontal: 4,
  },
  arrowButton: {
    width: 36,
    height: 36,
    justifyContent: 'center',
    alignItems: 'center',
  },
  arrowDisabled: {
    opacity: 0.3,
  },
  panelNumberText: {
    color: '#fff',
    fontSize: 14,
    fontWeight: '600',
    paddingHorizontal: 4,
  },
  dictionaryOverlay: {
    ...StyleSheet.absoluteFillObject,
    backgroundColor: 'rgba(0,0,0,0.4)',
  },
  dictionaryOverlayPressable: {
    flex: 1,
    justifyContent: 'flex-end',
  },
  dictionaryModal: {
    backgroundColor: '#fff',
    borderTopLeftRadius: 24,
    borderTopRightRadius: 24,
    padding: 24,
    paddingBottom: 40,
  },
  dictionaryHeader: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    marginBottom: 8,
  },
  dictionaryWord: {
    fontSize: 28,
    fontWeight: '700',
    color: '#1a1a2e',
  },
  baseForm: {
    fontSize: 14,
    color: '#666',
    marginBottom: 12,
  },
  meaning: {
    fontSize: 18,
    color: '#333',
    lineHeight: 26,
    marginBottom: 24,
  },
  dictionaryActions: {
    flexDirection: 'row',
    gap: 16,
  },
  actionButton: {
    flex: 1,
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: '#f0f0f0',
    paddingVertical: 12,
    borderRadius: 12,
    gap: 8,
  },
  actionButtonSaved: {
    backgroundColor: '#3498db',
  },
  actionText: {
    fontSize: 16,
    fontWeight: '500',
    color: '#1a1a2e',
  },
  actionTextSaved: {
    color: '#fff',
  },
});
