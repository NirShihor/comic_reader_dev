import { StyleSheet, Pressable, View, Switch } from 'react-native';
import { useState } from 'react';
import { Ionicons } from '@expo/vector-icons';
import { Text } from '@/components/Themed';

export default function SettingsScreen() {
  const [autoPlayAudio, setAutoPlayAudio] = useState(false);
  const [hapticFeedback, setHapticFeedback] = useState(true);

  return (
    <View style={styles.container}>
      <View style={styles.section}>
        <Text style={styles.sectionTitle}>Reading</Text>

        <View style={styles.settingRow}>
          <View style={styles.settingInfo}>
            <Ionicons name="volume-high-outline" size={24} color="#1a1a2e" />
            <Text style={styles.settingLabel}>Auto-play audio</Text>
          </View>
          <Switch
            value={autoPlayAudio}
            onValueChange={setAutoPlayAudio}
            trackColor={{ false: '#e0e0e0', true: '#4CAF50' }}
          />
        </View>

        <View style={styles.settingRow}>
          <View style={styles.settingInfo}>
            <Ionicons name="hand-left-outline" size={24} color="#1a1a2e" />
            <Text style={styles.settingLabel}>Haptic feedback</Text>
          </View>
          <Switch
            value={hapticFeedback}
            onValueChange={setHapticFeedback}
            trackColor={{ false: '#e0e0e0', true: '#4CAF50' }}
          />
        </View>
      </View>

      <View style={styles.section}>
        <Text style={styles.sectionTitle}>Account</Text>

        <Pressable style={styles.settingRow}>
          <View style={styles.settingInfo}>
            <Ionicons name="person-outline" size={24} color="#1a1a2e" />
            <Text style={styles.settingLabel}>Profile</Text>
          </View>
          <Ionicons name="chevron-forward" size={20} color="#999" />
        </Pressable>

        <Pressable style={styles.settingRow}>
          <View style={styles.settingInfo}>
            <Ionicons name="card-outline" size={24} color="#1a1a2e" />
            <Text style={styles.settingLabel}>Subscription</Text>
          </View>
          <Ionicons name="chevron-forward" size={20} color="#999" />
        </Pressable>
      </View>

      <View style={styles.section}>
        <Text style={styles.sectionTitle}>About</Text>

        <Pressable style={styles.settingRow}>
          <View style={styles.settingInfo}>
            <Ionicons name="help-circle-outline" size={24} color="#1a1a2e" />
            <Text style={styles.settingLabel}>Help</Text>
          </View>
          <Ionicons name="chevron-forward" size={20} color="#999" />
        </Pressable>

        <Pressable style={styles.settingRow}>
          <View style={styles.settingInfo}>
            <Ionicons name="document-text-outline" size={24} color="#1a1a2e" />
            <Text style={styles.settingLabel}>Terms of Service</Text>
          </View>
          <Ionicons name="chevron-forward" size={20} color="#999" />
        </Pressable>
      </View>

      <Text style={styles.version}>Version 1.0.0</Text>
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    padding: 16,
  },
  section: {
    marginBottom: 32,
  },
  sectionTitle: {
    fontSize: 14,
    fontWeight: '600',
    color: '#666',
    textTransform: 'uppercase',
    marginBottom: 12,
  },
  settingRow: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    backgroundColor: '#fff',
    padding: 16,
    borderRadius: 12,
    marginBottom: 8,
  },
  settingInfo: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 12,
  },
  settingLabel: {
    fontSize: 16,
  },
  version: {
    textAlign: 'center',
    color: '#999',
    marginTop: 'auto',
  },
});
