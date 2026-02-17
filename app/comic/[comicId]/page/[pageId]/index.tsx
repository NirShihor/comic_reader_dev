import { StyleSheet, Pressable, Image, View, Dimensions, StatusBar, TouchableOpacity } from 'react-native';
import { useLocalSearchParams, router } from 'expo-router';
import { useEffect } from 'react';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { Ionicons } from '@expo/vector-icons';
import * as Haptics from 'expo-haptics';
import { Text } from '@/components/Themed';
import { comics } from '@/src/data/comics';
import { useReadingProgress } from '@/src/hooks/useReadingProgress';
import { getImageSource } from '@/src/utils/images';

const { width: SCREEN_WIDTH, height: SCREEN_HEIGHT } = Dimensions.get('window');

// Debug mode - set to true to see tap zone borders
const DEBUG_TAP_ZONES = false;

export default function PageScreen() {
  const { comicId, pageId } = useLocalSearchParams<{ comicId: string; pageId: string }>();
  const insets = useSafeAreaInsets();
  const { saveProgress } = useReadingProgress();

  const comic = comics.find((c) => c.id === comicId);
  const page = comic?.pages.find((p) => p.id === pageId);
  const currentPageIndex = comic?.pages.findIndex((p) => p.id === pageId) ?? 0;

  // Save reading progress when page is viewed
  useEffect(() => {
    if (comicId && pageId && page) {
      saveProgress(comicId, pageId, page.pageNumber);
    }
  }, [comicId, pageId, page?.pageNumber]);

  if (!comic || !page) {
    return null;
  }

  const goToNextPage = () => {
    if (currentPageIndex < comic.pages.length - 1) {
      Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Light);
      const nextPage = comic.pages[currentPageIndex + 1];
      router.replace(`/comic/${comicId}/page/${nextPage.id}`);
    }
  };

  const goToPrevPage = () => {
    if (currentPageIndex > 0) {
      Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Light);
      const prevPage = comic.pages[currentPageIndex - 1];
      router.replace(`/comic/${comicId}/page/${prevPage.id}`);
    }
  };

  const handlePanelPress = (panelId: string) => {
    Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Medium);
    router.push(`/comic/${comicId}/page/${pageId}/panel/${panelId}`);
  };

  return (
    <View style={styles.container}>
      <StatusBar hidden />

      {/* Master page image */}
      <Image
        source={getImageSource(page.masterImage)}
        style={styles.masterImage}
        resizeMode="contain"
      />

      {/* Panel tap zones - absolute positioned over image */}
      {page.panels.map((panel, index) => (
        <Pressable
          key={panel.id}
          onPress={() => handlePanelPress(panel.id)}
          style={[
            styles.panelTapZone,
            {
              left: panel.tapZoneX * SCREEN_WIDTH,
              top: panel.tapZoneY * SCREEN_HEIGHT,
              width: panel.tapZoneWidth * SCREEN_WIDTH,
              height: panel.tapZoneHeight * SCREEN_HEIGHT,
            },
            DEBUG_TAP_ZONES && styles.debugBorder,
          ]}
        >
          {DEBUG_TAP_ZONES && (
            <Text style={styles.debugLabel}>Panel {index + 1}</Text>
          )}
        </Pressable>
      ))}

      {/* Navigation overlay */}
      <View style={[styles.navOverlay, { top: insets.top + 10 }]}>
        <TouchableOpacity
          onPress={() => router.back()}
          style={styles.navButton}
          activeOpacity={0.5}
        >
          <Ionicons name="close" size={24} color="#fff" />
        </TouchableOpacity>

        <View style={styles.rightControls}>
          <View style={styles.pageIndicator}>
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

      {/* Debug info */}
      {DEBUG_TAP_ZONES && (
        <View style={styles.debugInfo}>
          <Text style={styles.debugInfoText}>
            Page {currentPageIndex + 1} | {page.panels.length} panels
          </Text>
        </View>
      )}
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: '#000',
  },
  masterImage: {
    position: 'absolute',
    top: 0,
    left: 0,
    width: SCREEN_WIDTH,
    height: SCREEN_HEIGHT,
  },
  panelTapZone: {
    position: 'absolute',
    justifyContent: 'center',
    alignItems: 'center',
    zIndex: 1,
  },
  debugBorder: {
    borderWidth: 3,
    borderColor: 'rgba(255, 0, 0, 0.8)',
    backgroundColor: 'rgba(255, 0, 0, 0.2)',
  },
  debugLabel: {
    color: '#fff',
    backgroundColor: 'rgba(255, 0, 0, 0.8)',
    paddingHorizontal: 8,
    paddingVertical: 4,
    fontSize: 12,
    fontWeight: 'bold',
  },
  debugInfo: {
    position: 'absolute',
    bottom: 40,
    left: 0,
    right: 0,
    alignItems: 'center',
  },
  debugInfoText: {
    color: '#fff',
    backgroundColor: 'rgba(0, 0, 0, 0.7)',
    paddingHorizontal: 16,
    paddingVertical: 8,
    borderRadius: 20,
    fontSize: 14,
  },
  navOverlay: {
    position: 'absolute',
    left: 16,
    right: 16,
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    zIndex: 10,
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
  pageIndicator: {
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
  buttonPressed: {
    opacity: 0.5,
  },
});
