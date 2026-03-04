import { StyleSheet, View, StatusBar, TouchableOpacity } from 'react-native';
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

  const comic = comicId ? comics.find((c) => c.id === comicId) : undefined;

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
  }, [comicId, saveProgress]);

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
});
