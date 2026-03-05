import { StyleSheet, View, StatusBar, TouchableOpacity, Modal, Pressable, Animated } from 'react-native';
import { useLocalSearchParams, router } from 'expo-router';
import { useRef, useState, useCallback, useEffect } from 'react';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { Ionicons } from '@expo/vector-icons';
import * as Haptics from 'expo-haptics';
import { Text } from '@/components/Themed';
import SkiaPageReader, { SkiaPageReaderRef } from '@/components/SkiaPageReader';
import { comics } from '@/src/data/comics';
import { useReadingProgress } from '@/src/hooks/useReadingProgress';
import { Page } from '@/src/types/comic';

export default function ReaderScreen() {
  const { comicId, startOver } = useLocalSearchParams<{ comicId: string; startOver?: string }>();
  const insets = useSafeAreaInsets();
  const { getProgress, saveProgress, isLoaded } = useReadingProgress();
  const readerRef = useRef<SkiaPageReaderRef>(null);
  const [currentPageIndex, setCurrentPageIndex] = useState(0);
  const [showQuizPrompt, setShowQuizPrompt] = useState(false);
  const [hasShownQuizPrompt, setHasShownQuizPrompt] = useState(false);

  const comic = comicId ? comics.find((c) => c.id === comicId) : undefined;
  const hasReviewWords = comic?.reviewWords && comic.reviewWords.length > 0;

  // Update initial page when progress loads (skip if startOver=true)
  useEffect(() => {
    if (isLoaded && comic && comicId && startOver !== 'true') {
      const savedProgress = getProgress(comicId);
      if (savedProgress) {
        const index = comic.pages.findIndex(p => p.pageNumber === savedProgress.pageNumber);
        if (index >= 0 && index !== currentPageIndex) {
          setCurrentPageIndex(index);
          readerRef.current?.goToPage(index);
        }
      }
    }
  }, [isLoaded, comicId, comic, startOver]);

  if (!comic || !comicId) {
    return null;
  }

  const handlePageChange = useCallback((pageIndex: number, page: Page) => {
    setCurrentPageIndex(pageIndex);
    saveProgress(comicId, page.id, page.pageNumber);

    // Show quiz prompt when user finishes the comic (reaches last page)
    // The SkiaPageReader tracks panels, so we check if this is the last page
    if (comic && pageIndex === comic.pages.length - 1 && hasReviewWords && !hasShownQuizPrompt) {
      // Delay showing the prompt so user can see the final panel
      setTimeout(() => {
        setShowQuizPrompt(true);
        setHasShownQuizPrompt(true);
      }, 1500);
    }
  }, [comicId, saveProgress, comic, hasReviewWords, hasShownQuizPrompt]);

  const handlePanelPress = useCallback((panelId: string, pageId: string) => {
    Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Medium);
    router.push(`/comic/${comicId}/page/${pageId}/panel/${panelId}`);
  }, [comicId]);

  const goToNextPage = useCallback(() => {
    if (currentPageIndex < comic.pages.length - 1) {
      Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Light);
      readerRef.current?.nextPage();
    }
  }, [currentPageIndex, comic.pages.length]);

  const goToPrevPage = useCallback(() => {
    if (currentPageIndex > 0) {
      Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Light);
      readerRef.current?.previousPage();
    }
  }, [currentPageIndex]);

  const currentPage = comic.pages[currentPageIndex];

  return (
    <View style={styles.container}>
      <StatusBar hidden />

      <SkiaPageReader
        ref={readerRef}
        comic={comic}
        initialPageIndex={currentPageIndex}
        onPageChange={handlePageChange}
        onPanelPress={handlePanelPress}
      />

      {/* Navigation overlay - side buttons */}
      <View style={[styles.navOverlay, { top: insets.top + 10 }]}>
        <TouchableOpacity
          onPress={() => router.back()}
          style={styles.navButton}
          activeOpacity={0.5}
        >
          <Ionicons name="close" size={24} color="#fff" />
        </TouchableOpacity>

        <View style={styles.rightControls}>
          <TouchableOpacity
            onPress={() => router.push('/vocabulary')}
            style={styles.navButton}
            activeOpacity={0.5}
          >
            <Ionicons name="bookmark" size={20} color="#fff" />
          </TouchableOpacity>

          <TouchableOpacity
            onPress={() => router.push('/settings')}
            style={styles.navButton}
            activeOpacity={0.5}
          >
            <Ionicons name="settings-outline" size={20} color="#fff" />
          </TouchableOpacity>
        </View>
      </View>

      {/* Centered page indicator - absolutely centered */}
      <View style={[styles.centerIndicator, { top: insets.top + 10 }]} pointerEvents="box-none">
        <View style={styles.pageIndicatorInner}>
          <TouchableOpacity
            onPress={goToPrevPage}
            style={[
              styles.arrowButton,
              currentPageIndex === 0 && styles.arrowDisabled,
            ]}
            activeOpacity={0.5}
            disabled={currentPageIndex === 0}
          >
            <Ionicons name="chevron-back" size={20} color="#fff" />
          </TouchableOpacity>

          <View style={styles.pageNumberContainer}>
            <Text style={styles.pageNumberText}>
              {currentPageIndex + 1}/{comic.pages.length}
            </Text>
          </View>

          <TouchableOpacity
            onPress={goToNextPage}
            style={[
              styles.arrowButton,
              currentPageIndex === comic.pages.length - 1 && styles.arrowDisabled,
            ]}
            activeOpacity={0.5}
            disabled={currentPageIndex === comic.pages.length - 1}
          >
            <Ionicons name="chevron-forward" size={20} color="#fff" />
          </TouchableOpacity>
        </View>
      </View>

      {/* Quiz prompt modal */}
      <Modal
        visible={showQuizPrompt}
        transparent
        animationType="fade"
        onRequestClose={() => setShowQuizPrompt(false)}
      >
        <View style={styles.modalOverlay}>
          <View style={styles.modalContent}>
            <Ionicons name="school" size={48} color="#1a1a2e" />
            <Text style={styles.modalTitle}>Great job!</Text>
            <Text style={styles.modalText}>
              You've finished reading! Ready to practice the vocabulary?
            </Text>
            <View style={styles.modalButtons}>
              <Pressable
                style={styles.modalButtonSecondary}
                onPress={() => setShowQuizPrompt(false)}
              >
                <Text style={styles.modalButtonSecondaryText}>Later</Text>
              </Pressable>
              <Pressable
                style={styles.modalButtonPrimary}
                onPress={() => {
                  setShowQuizPrompt(false);
                  router.push(`/comic/${comicId}/quiz`);
                }}
              >
                <Text style={styles.modalButtonPrimaryText}>Start Quiz</Text>
              </Pressable>
            </View>
          </View>
        </View>
      </Modal>
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: '#000',
  },
  navOverlay: {
    position: 'absolute',
    left: 16,
    right: 16,
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    zIndex: 100,
    pointerEvents: 'box-none',
  },
  rightControls: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 8,
  },
  centerIndicator: {
    position: 'absolute',
    left: 0,
    right: 0,
    alignItems: 'center',
    zIndex: 101,
  },
  navButton: {
    width: 40,
    height: 40,
    borderRadius: 20,
    backgroundColor: 'rgba(0,0,0,0.5)',
    justifyContent: 'center',
    alignItems: 'center',
  },
  pageIndicatorInner: {
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
  pageNumberContainer: {
    paddingHorizontal: 8,
  },
  pageNumberText: {
    color: '#fff',
    fontSize: 14,
    fontWeight: '600',
  },
  modalOverlay: {
    flex: 1,
    backgroundColor: 'rgba(0, 0, 0, 0.6)',
    justifyContent: 'center',
    alignItems: 'center',
    padding: 24,
  },
  modalContent: {
    backgroundColor: '#fff',
    borderRadius: 20,
    padding: 32,
    alignItems: 'center',
    width: '100%',
    maxWidth: 340,
  },
  modalTitle: {
    fontSize: 24,
    fontWeight: '700',
    color: '#1a1a2e',
    marginTop: 16,
    marginBottom: 8,
  },
  modalText: {
    fontSize: 16,
    color: '#666',
    textAlign: 'center',
    marginBottom: 24,
    lineHeight: 22,
  },
  modalButtons: {
    flexDirection: 'row',
    gap: 12,
  },
  modalButtonSecondary: {
    paddingHorizontal: 24,
    paddingVertical: 14,
    borderRadius: 12,
    backgroundColor: '#e0e0e0',
  },
  modalButtonSecondaryText: {
    color: '#666',
    fontSize: 16,
    fontWeight: '600',
  },
  modalButtonPrimary: {
    paddingHorizontal: 24,
    paddingVertical: 14,
    borderRadius: 12,
    backgroundColor: '#1a1a2e',
  },
  modalButtonPrimaryText: {
    color: '#fff',
    fontSize: 16,
    fontWeight: '600',
  },
});
