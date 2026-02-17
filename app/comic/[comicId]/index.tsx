import { StyleSheet, FlatList, Pressable, Image, View } from 'react-native';
import { useLocalSearchParams, Link, Stack } from 'expo-router';
import { Text } from '@/components/Themed';
import { HeaderButtons } from '@/components/HeaderButtons';
import { comics } from '@/src/data/comics';
import { useReadingProgress } from '@/src/hooks/useReadingProgress';
import { getImageSource } from '@/src/utils/images';

export default function ComicOverviewScreen() {
  const { comicId } = useLocalSearchParams<{ comicId: string }>();
  const { getProgress, isLoaded } = useReadingProgress();
  const comic = comics.find((c) => c.id === comicId);
  const progress = comicId ? getProgress(comicId) : null;

  if (!comic) {
    return (
      <View style={styles.container}>
        <Text>Comic not found</Text>
      </View>
    );
  }

  return (
    <View style={styles.container}>
      <Stack.Screen
        options={{
          title: comic.title,
          headerRight: () => <HeaderButtons />,
        }}
      />

      <View style={styles.header}>
        <Image
          source={getImageSource(comic.coverImage)}
          style={styles.coverImage}
          resizeMode="cover"
        />
        <View style={styles.headerInfo}>
          <Text style={styles.title}>{comic.title}</Text>
          <Text style={styles.level}>{comic.level}</Text>
          <Text style={styles.pageCount}>{comic.pages.length} pages</Text>
        </View>
      </View>

      <Text style={styles.description}>{comic.description}</Text>

      <Text style={styles.sectionTitle}>Pages</Text>

      <FlatList
        data={comic.pages}
        keyExtractor={(item) => item.id}
        horizontal
        showsHorizontalScrollIndicator={false}
        contentContainerStyle={styles.pageList}
        renderItem={({ item }) => (
          <Link href={`/comic/${comicId}/page/${item.id}`} asChild>
            <Pressable style={styles.pageCard}>
              <Image
                source={getImageSource(item.masterImage)}
                style={styles.pageImage}
                resizeMode="cover"
              />
              <Text style={styles.pageNumber}>Page {item.pageNumber}</Text>
            </Pressable>
          </Link>
        )}
      />

      <View style={styles.buttonContainer}>
        {progress ? (
          <>
            <Link href={`/comic/${comicId}/page/${progress.pageId}`} asChild>
              <Pressable style={styles.startButton}>
                <Text style={styles.startButtonText}>
                  Continue from Page {progress.pageNumber}
                </Text>
              </Pressable>
            </Link>
            {progress.pageNumber > 1 && (
              <Link href={`/comic/${comicId}/page/${comic.pages[0]?.id}`} asChild>
                <Pressable style={styles.restartButton}>
                  <Text style={styles.restartButtonText}>Start Over</Text>
                </Pressable>
              </Link>
            )}
          </>
        ) : (
          <Link href={`/comic/${comicId}/page/${comic.pages[0]?.id}`} asChild>
            <Pressable style={styles.startButton}>
              <Text style={styles.startButtonText}>Start Reading</Text>
            </Pressable>
          </Link>
        )}
      </View>
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    padding: 16,
  },
  header: {
    flexDirection: 'row',
    marginBottom: 16,
  },
  coverImage: {
    width: 120,
    height: 160,
    borderRadius: 8,
  },
  headerInfo: {
    flex: 1,
    marginLeft: 16,
    justifyContent: 'center',
  },
  title: {
    fontSize: 24,
    fontWeight: '700',
    marginBottom: 8,
  },
  level: {
    fontSize: 14,
    color: '#666',
    textTransform: 'capitalize',
    marginBottom: 4,
  },
  pageCount: {
    fontSize: 14,
    color: '#888',
  },
  description: {
    fontSize: 16,
    lineHeight: 24,
    color: '#444',
    marginBottom: 24,
  },
  sectionTitle: {
    fontSize: 18,
    fontWeight: '600',
    marginBottom: 12,
  },
  pageList: {
    paddingBottom: 16,
  },
  pageCard: {
    marginRight: 12,
    alignItems: 'center',
  },
  pageImage: {
    width: 80,
    height: 120,
    borderRadius: 6,
    backgroundColor: '#e0e0e0',
  },
  pageNumber: {
    marginTop: 4,
    fontSize: 12,
    color: '#666',
  },
  buttonContainer: {
    marginTop: 'auto',
    marginBottom: 16,
    gap: 12,
  },
  startButton: {
    backgroundColor: '#1a1a2e',
    paddingVertical: 16,
    borderRadius: 12,
    alignItems: 'center',
  },
  startButtonText: {
    color: '#fff',
    fontSize: 18,
    fontWeight: '600',
  },
  restartButton: {
    backgroundColor: 'transparent',
    paddingVertical: 12,
    borderRadius: 12,
    alignItems: 'center',
    borderWidth: 1,
    borderColor: '#1a1a2e',
  },
  restartButtonText: {
    color: '#1a1a2e',
    fontSize: 16,
    fontWeight: '500',
  },
});
