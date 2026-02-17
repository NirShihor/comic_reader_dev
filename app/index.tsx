import { StyleSheet, FlatList, Pressable, Image, View } from 'react-native';
import { Link } from 'expo-router';
import { Text } from '@/components/Themed';
import { comics } from '@/src/data/comics';
import { useReadingProgress } from '@/src/hooks/useReadingProgress';
import { getImageSource } from '@/src/utils/images';

export default function LibraryScreen() {
  const { getProgress, isLoaded } = useReadingProgress();

  const getProgressPercent = (comicId: string, totalPages: number) => {
    const progress = getProgress(comicId);
    if (!progress) return 0;
    return Math.round((progress.pageNumber / totalPages) * 100);
  };

  return (
    <View style={styles.container}>
      <FlatList
        data={comics}
        keyExtractor={(item) => item.id}
        contentContainerStyle={styles.list}
        renderItem={({ item }) => {
          const progressPercent = getProgressPercent(item.id, item.pages.length);
          return (
            <Link href={`/comic/${item.id}`} asChild>
              <Pressable style={({ pressed }) => [
                styles.comicCard,
                pressed && styles.cardPressed,
              ]}>
                <View style={styles.coverContainer}>
                  <Image
                    source={getImageSource(item.coverImage)}
                    style={styles.coverImage}
                    resizeMode="cover"
                  />
                  {progressPercent > 0 && (
                    <View style={styles.progressBarContainer}>
                      <View
                        style={[
                          styles.progressBar,
                          { width: `${progressPercent}%` },
                        ]}
                      />
                    </View>
                  )}
                </View>
                <View style={styles.comicInfo}>
                  <Text style={styles.title}>{item.title}</Text>
                  <Text style={styles.level}>{item.level}</Text>
                  <Text style={styles.description} numberOfLines={2}>
                    {item.description}
                  </Text>
                  {progressPercent > 0 && (
                    <Text style={styles.progressText}>
                      {progressPercent}% complete
                    </Text>
                  )}
                  {item.isPremium && (
                    <View style={styles.premiumBadge}>
                      <Text style={styles.premiumText}>Premium</Text>
                    </View>
                  )}
                </View>
              </Pressable>
            </Link>
          );
        }}
      />
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
  },
  list: {
    padding: 16,
  },
  comicCard: {
    flexDirection: 'row',
    backgroundColor: '#f5f5f5',
    borderRadius: 12,
    marginBottom: 16,
    overflow: 'hidden',
    elevation: 2,
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 2 },
    shadowOpacity: 0.1,
    shadowRadius: 4,
  },
  cardPressed: {
    opacity: 0.7,
  },
  coverContainer: {
    position: 'relative',
  },
  coverImage: {
    width: 100,
    height: 140,
  },
  progressBarContainer: {
    position: 'absolute',
    bottom: 0,
    left: 0,
    right: 0,
    height: 4,
    backgroundColor: 'rgba(0,0,0,0.3)',
  },
  progressBar: {
    height: '100%',
    backgroundColor: '#4CAF50',
  },
  comicInfo: {
    flex: 1,
    padding: 12,
  },
  title: {
    fontSize: 18,
    fontWeight: '600',
    marginBottom: 4,
  },
  level: {
    fontSize: 12,
    color: '#666',
    textTransform: 'capitalize',
    marginBottom: 8,
  },
  description: {
    fontSize: 14,
    color: '#444',
    lineHeight: 20,
  },
  progressText: {
    fontSize: 12,
    color: '#4CAF50',
    fontWeight: '500',
    marginTop: 4,
  },
  premiumBadge: {
    position: 'absolute',
    top: 8,
    right: 8,
    backgroundColor: '#FFD700',
    paddingHorizontal: 8,
    paddingVertical: 4,
    borderRadius: 4,
  },
  premiumText: {
    fontSize: 10,
    fontWeight: '600',
    color: '#333',
  },
});
