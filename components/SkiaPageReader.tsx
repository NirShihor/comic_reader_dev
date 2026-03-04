import React, { forwardRef, useImperativeHandle, useState, useCallback, useMemo } from 'react';
import { View, StyleSheet, Dimensions, Image } from 'react-native';
import Animated, {
  useSharedValue,
  useAnimatedStyle,
  withTiming,
  runOnJS,
} from 'react-native-reanimated';
import { Gesture, GestureDetector } from 'react-native-gesture-handler';
import { Comic, Page, Panel } from '@/src/types/comic';
import { getImageSource } from '@/src/utils/images';

const { width: SCREEN_WIDTH, height: SCREEN_HEIGHT } = Dimensions.get('window');

export interface SkiaPageReaderRef {
  nextPage: () => void;
  previousPage: () => void;
  goToPage: (index: number) => void;
}

interface SkiaPageReaderProps {
  comic: Comic;
  initialPageIndex: number;
  onPageChange: (pageIndex: number, page: Page) => void;
  onPanelPress: (panelId: string, pageId: string) => void;
}

// Flatten all panels from all pages into a linear sequence
interface FlatPanel {
  panel: Panel;
  page: Page;
  pageIndex: number;
  panelIndex: number;
  globalIndex: number;
}

function flattenPanels(comic: Comic): FlatPanel[] {
  const result: FlatPanel[] = [];
  let globalIndex = 0;

  comic.pages.forEach((page, pageIndex) => {
    page.panels.forEach((panel, panelIndex) => {
      result.push({
        panel,
        page,
        pageIndex,
        panelIndex,
        globalIndex,
      });
      globalIndex++;
    });
  });

  return result;
}

// Individual panel view component
const PanelView = React.memo(({
  flatPanel,
  offset,
}: {
  flatPanel: FlatPanel;
  offset: Animated.SharedValue<number>;
}) => {
  const panelStyle = useAnimatedStyle(() => {
    'worklet';
    return {
      transform: [{ translateX: offset.value + flatPanel.globalIndex * SCREEN_WIDTH }],
    };
  });

  return (
    <Animated.View style={[styles.panelContainer, panelStyle]}>
      <Image
        source={getImageSource(flatPanel.panel.artworkImage)}
        style={styles.panelImage}
        resizeMode="contain"
      />
    </Animated.View>
  );
});

PanelView.displayName = 'PanelView';

const SkiaPageReader = forwardRef<SkiaPageReaderRef, SkiaPageReaderProps>(
  ({ comic, initialPageIndex, onPageChange, onPanelPress }, ref) => {
    // Flatten all panels
    const flatPanels = useMemo(() => flattenPanels(comic), [comic]);

    // Find the starting global index based on initial page
    const initialGlobalIndex = useMemo(() => {
      const found = flatPanels.find(fp => fp.pageIndex === initialPageIndex && fp.panelIndex === 0);
      return found?.globalIndex ?? 0;
    }, [flatPanels, initialPageIndex]);

    const [currentGlobalIndex, setCurrentGlobalIndex] = useState(initialGlobalIndex);
    const [isAnimating, setIsAnimating] = useState(false);

    const offset = useSharedValue(-initialGlobalIndex * SCREEN_WIDTH);

    const currentFlatPanel = flatPanels[currentGlobalIndex];

    const completeTransition = useCallback((newIndex: number) => {
      setCurrentGlobalIndex(newIndex);
      const newFlatPanel = flatPanels[newIndex];
      if (newFlatPanel) {
        onPageChange(newFlatPanel.pageIndex, newFlatPanel.page);
      }
      setIsAnimating(false);
    }, [flatPanels, onPageChange]);

    const animateToIndex = useCallback((targetIndex: number) => {
      if (targetIndex >= 0 && targetIndex < flatPanels.length && !isAnimating) {
        setIsAnimating(true);
        offset.value = withTiming(-targetIndex * SCREEN_WIDTH, { duration: 250 }, (finished) => {
          if (finished) {
            runOnJS(completeTransition)(targetIndex);
          }
        });
      }
    }, [flatPanels.length, isAnimating, completeTransition, offset]);

    // Go to first panel of a specific page
    const goToPageFirstPanel = useCallback((pageIndex: number) => {
      const found = flatPanels.find(fp => fp.pageIndex === pageIndex && fp.panelIndex === 0);
      if (found) {
        offset.value = -found.globalIndex * SCREEN_WIDTH;
        setCurrentGlobalIndex(found.globalIndex);
        onPageChange(found.pageIndex, found.page);
      }
    }, [flatPanels, offset, onPageChange]);

    useImperativeHandle(ref, () => ({
      nextPage: () => animateToIndex(currentGlobalIndex + 1),
      previousPage: () => animateToIndex(currentGlobalIndex - 1),
      goToPage: goToPageFirstPanel,
    }));

    const handleTap = useCallback(() => {
      if (currentFlatPanel) {
        onPanelPress(currentFlatPanel.panel.id, currentFlatPanel.page.id);
      }
    }, [currentFlatPanel, onPanelPress]);

    // Tap gesture - tap anywhere to open current panel detail
    const tapGesture = Gesture.Tap()
      .maxDuration(250)
      .maxDistance(10)
      .onEnd(() => {
        'worklet';
        runOnJS(handleTap)();
      });

    // Pan gesture for swiping between panels
    const panGesture = Gesture.Pan()
      .enabled(!isAnimating)
      .activeOffsetX([-15, 15])
      .onUpdate((event) => {
        'worklet';
        const baseOffset = -currentGlobalIndex * SCREEN_WIDTH;
        let newOffset = baseOffset + event.translationX;

        const minOffset = -(flatPanels.length - 1) * SCREEN_WIDTH;
        const maxOffset = 0;

        if (newOffset > maxOffset) {
          newOffset = maxOffset + (newOffset - maxOffset) * 0.3;
        } else if (newOffset < minOffset) {
          newOffset = minOffset + (newOffset - minOffset) * 0.3;
        }

        offset.value = newOffset;
      })
      .onEnd((event) => {
        'worklet';
        const threshold = SCREEN_WIDTH * 0.25;
        const velocity = event.velocityX;
        const fastSwipe = Math.abs(velocity) > 500;

        let targetIndex = currentGlobalIndex;

        if ((event.translationX < -threshold || (event.translationX < -50 && fastSwipe && velocity < 0)) &&
            currentGlobalIndex < flatPanels.length - 1) {
          targetIndex = currentGlobalIndex + 1;
        } else if ((event.translationX > threshold || (event.translationX > 50 && fastSwipe && velocity > 0)) &&
                   currentGlobalIndex > 0) {
          targetIndex = currentGlobalIndex - 1;
        }

        offset.value = withTiming(-targetIndex * SCREEN_WIDTH, { duration: 200 }, (finished) => {
          if (finished && targetIndex !== currentGlobalIndex) {
            runOnJS(completeTransition)(targetIndex);
          } else if (finished) {
            runOnJS(setIsAnimating)(false);
          }
        });

        if (targetIndex !== currentGlobalIndex) {
          runOnJS(setIsAnimating)(true);
        }
      });

    // Combine gestures
    const composedGesture = Gesture.Race(panGesture, tapGesture);

    // Render current panel + neighbors for smooth transitions
    const panelsToRender = useMemo(() => {
      const indices: number[] = [];
      if (currentGlobalIndex > 0) indices.push(currentGlobalIndex - 1);
      indices.push(currentGlobalIndex);
      if (currentGlobalIndex < flatPanels.length - 1) indices.push(currentGlobalIndex + 1);
      return indices;
    }, [currentGlobalIndex, flatPanels.length]);

    return (
      <GestureDetector gesture={composedGesture}>
        <Animated.View style={styles.container}>
          {panelsToRender.map((globalIndex) => (
            <PanelView
              key={`${flatPanels[globalIndex].page.id}-${flatPanels[globalIndex].panel.id}`}
              flatPanel={flatPanels[globalIndex]}
              offset={offset}
            />
          ))}
        </Animated.View>
      </GestureDetector>
    );
  }
);

SkiaPageReader.displayName = 'SkiaPageReader';

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: '#000',
    overflow: 'hidden',
  },
  panelContainer: {
    position: 'absolute',
    top: 0,
    left: 0,
    width: SCREEN_WIDTH,
    height: SCREEN_HEIGHT,
    justifyContent: 'center',
    alignItems: 'center',
  },
  panelImage: {
    width: SCREEN_WIDTH,
    height: SCREEN_HEIGHT,
  },
});

export default SkiaPageReader;
