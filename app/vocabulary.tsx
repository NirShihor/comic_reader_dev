import { StyleSheet, FlatList, Pressable, View, ActivityIndicator, Alert } from 'react-native';
import { Ionicons } from '@expo/vector-icons';
import { router, Stack } from 'expo-router';
import { Text } from '@/components/Themed';
import { useVocabulary } from '@/src/hooks/useVocabulary';
import { useAudio } from '@/src/hooks/useAudio';
import { SavedWord } from '@/src/types/comic';

export default function VocabularyScreen() {
  const { savedWords, isLoading, removeWord, clearAll } = useVocabulary();
  const { play } = useAudio();

  const handlePlayWord = async (audioUrl?: string) => {
    if (audioUrl) {
      await play(audioUrl);
    }
  };

  const handleRemoveWord = (wordId: string, wordText: string) => {
    Alert.alert(
      'Remove Word',
      `Remove "${wordText}" from your vocabulary?`,
      [
        { text: 'Cancel', style: 'cancel' },
        {
          text: 'Remove',
          style: 'destructive',
          onPress: () => removeWord(wordId),
        },
      ]
    );
  };

  const handleClearAll = () => {
    if (savedWords.length === 0) return;

    Alert.alert(
      'Clear All',
      'Remove all saved words? This cannot be undone.',
      [
        { text: 'Cancel', style: 'cancel' },
        {
          text: 'Clear All',
          style: 'destructive',
          onPress: clearAll,
        },
      ]
    );
  };

  const renderWordCard = ({ item }: { item: SavedWord }) => (
    <View style={styles.wordCard}>
      <Pressable
        style={styles.wordInfo}
        onLongPress={() => handleRemoveWord(item.wordId, item.word.text)}
      >
        <Text style={styles.wordText}>{item.word.text}</Text>
        {item.word.baseForm && item.word.baseForm !== item.word.text && (
          <Text style={styles.baseForm}>({item.word.baseForm})</Text>
        )}
        <Text style={styles.meaningText}>{item.word.meaning}</Text>
        <Text style={styles.dateText}>
          Saved {formatDate(item.savedAt)}
        </Text>
      </Pressable>
      <View style={styles.cardActions}>
        <Pressable
          style={styles.playButton}
          onPress={() => handlePlayWord(item.word.audioUrl)}
        >
          <Ionicons name="volume-medium" size={22} color="#1a1a2e" />
        </Pressable>
        <Pressable
          style={styles.removeButton}
          onPress={() => handleRemoveWord(item.wordId, item.word.text)}
        >
          <Ionicons name="trash-outline" size={20} color="#e74c3c" />
        </Pressable>
      </View>
    </View>
  );

  if (isLoading) {
    return (
      <View style={styles.centered}>
        <ActivityIndicator size="large" color="#1a1a2e" />
      </View>
    );
  }

  return (
    <View style={styles.container}>
      {savedWords.length === 0 ? (
        <>
          <View style={styles.emptyHeader}>
            <Pressable onPress={() => router.back()} style={styles.doneButton}>
              <Text style={styles.doneButtonText}>Done</Text>
            </Pressable>
          </View>
          <View style={styles.emptyState}>
            <Ionicons name="bookmark-outline" size={64} color="#ccc" />
            <Text style={styles.emptyTitle}>No saved words yet</Text>
            <Text style={styles.emptySubtitle}>
              Tap words while reading to save them here
            </Text>
          </View>
        </>
      ) : (
        <>
          <View style={styles.header}>
            <Pressable onPress={() => router.back()} style={styles.doneButton}>
              <Text style={styles.doneButtonText}>Done</Text>
            </Pressable>
            <Text style={styles.headerText}>
              {savedWords.length} word{savedWords.length !== 1 ? 's' : ''} saved
            </Text>
            <Pressable onPress={handleClearAll} style={styles.clearButton}>
              <Text style={styles.clearButtonText}>Clear All</Text>
            </Pressable>
          </View>
          <FlatList
            data={savedWords}
            keyExtractor={(item) => item.wordId}
            contentContainerStyle={styles.list}
            renderItem={renderWordCard}
          />
        </>
      )}
    </View>
  );
}

function formatDate(date: Date): string {
  const now = new Date();
  const diffMs = now.getTime() - new Date(date).getTime();
  const diffMins = Math.floor(diffMs / 60000);
  const diffHours = Math.floor(diffMs / 3600000);
  const diffDays = Math.floor(diffMs / 86400000);

  if (diffMins < 1) return 'just now';
  if (diffMins < 60) return `${diffMins}m ago`;
  if (diffHours < 24) return `${diffHours}h ago`;
  if (diffDays < 7) return `${diffDays}d ago`;

  return new Date(date).toLocaleDateString();
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
  },
  centered: {
    flex: 1,
    justifyContent: 'center',
    alignItems: 'center',
  },
  header: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    paddingHorizontal: 16,
    paddingVertical: 12,
    borderBottomWidth: 1,
    borderBottomColor: '#e0e0e0',
  },
  headerText: {
    fontSize: 14,
    color: '#666',
  },
  doneButton: {
    paddingHorizontal: 12,
    paddingVertical: 6,
  },
  doneButtonText: {
    fontSize: 14,
    color: '#007AFF',
    fontWeight: '600',
  },
  clearButton: {
    paddingHorizontal: 12,
    paddingVertical: 6,
  },
  clearButtonText: {
    fontSize: 14,
    color: '#e74c3c',
    fontWeight: '500',
  },
  list: {
    padding: 16,
  },
  emptyHeader: {
    paddingHorizontal: 16,
    paddingVertical: 12,
    borderBottomWidth: 1,
    borderBottomColor: '#e0e0e0',
  },
  emptyState: {
    flex: 1,
    justifyContent: 'center',
    alignItems: 'center',
    padding: 32,
  },
  emptyTitle: {
    fontSize: 20,
    fontWeight: '600',
    marginTop: 16,
    color: '#666',
  },
  emptySubtitle: {
    fontSize: 16,
    color: '#999',
    textAlign: 'center',
    marginTop: 8,
  },
  wordCard: {
    flexDirection: 'row',
    alignItems: 'center',
    backgroundColor: '#fff',
    borderRadius: 12,
    padding: 16,
    marginBottom: 12,
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 1 },
    shadowOpacity: 0.1,
    shadowRadius: 2,
    elevation: 1,
  },
  wordInfo: {
    flex: 1,
  },
  wordText: {
    fontSize: 20,
    fontWeight: '600',
    marginBottom: 2,
  },
  baseForm: {
    fontSize: 14,
    color: '#888',
    marginBottom: 4,
  },
  meaningText: {
    fontSize: 15,
    color: '#444',
    marginBottom: 4,
  },
  dateText: {
    fontSize: 12,
    color: '#999',
  },
  cardActions: {
    flexDirection: 'row',
    gap: 8,
  },
  playButton: {
    width: 44,
    height: 44,
    borderRadius: 22,
    backgroundColor: '#f0f0f0',
    justifyContent: 'center',
    alignItems: 'center',
  },
  removeButton: {
    width: 44,
    height: 44,
    borderRadius: 22,
    backgroundColor: '#fef0f0',
    justifyContent: 'center',
    alignItems: 'center',
  },
});
