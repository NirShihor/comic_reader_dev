import { View, Pressable, StyleSheet } from 'react-native';
import { router } from 'expo-router';
import { Ionicons } from '@expo/vector-icons';
import { useColorScheme } from './useColorScheme';

export function HeaderButtons() {
  const colorScheme = useColorScheme();
  const iconColor = colorScheme === 'dark' ? '#ffffff' : '#1a1a2e';

  return (
    <View style={styles.headerButtons}>
      <Pressable
        style={styles.headerButton}
        onPress={() => router.push('/vocabulary')}
      >
        <Ionicons name="bookmark" size={22} color={iconColor} />
      </Pressable>
      <Pressable
        style={styles.headerButton}
        onPress={() => router.push('/settings')}
      >
        <Ionicons name="settings-outline" size={22} color={iconColor} />
      </Pressable>
    </View>
  );
}

const styles = StyleSheet.create({
  headerButtons: {
    flexDirection: 'row',
    gap: 4,
  },
  headerButton: {
    padding: 8,
  },
});
