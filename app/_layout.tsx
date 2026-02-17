import { DarkTheme, DefaultTheme, ThemeProvider } from '@react-navigation/native';
import { useFonts } from 'expo-font';
import { Stack } from 'expo-router';
import * as SplashScreen from 'expo-splash-screen';
import { useEffect } from 'react';
import 'react-native-reanimated';

import { useColorScheme } from '@/components/useColorScheme';
import { HeaderButtons } from '@/components/HeaderButtons';

export { ErrorBoundary } from 'expo-router';

SplashScreen.preventAutoHideAsync();

export default function RootLayout() {
  const colorScheme = useColorScheme();
  const [loaded, error] = useFonts({
    SpaceMono: require('../assets/fonts/SpaceMono-Regular.ttf'),
  });

  useEffect(() => {
    if (error) throw error;
  }, [error]);

  useEffect(() => {
    if (loaded) {
      SplashScreen.hideAsync().catch(() => {
        // Ignore - splash screen may not be registered in dev mode
      });
    }
  }, [loaded]);

  if (!loaded) {
    return null;
  }

  return (
    <ThemeProvider value={colorScheme === 'dark' ? DarkTheme : DefaultTheme}>
      <Stack
        screenOptions={{
          headerStyle: {
            backgroundColor: colorScheme === 'dark' ? '#1a1a2e' : '#ffffff',
          },
          headerTintColor: colorScheme === 'dark' ? '#ffffff' : '#1a1a2e',
          headerTitleStyle: {
            fontWeight: '600',
          },
          headerRight: () => <HeaderButtons />,
        }}
      >
        <Stack.Screen
          name="index"
          options={{ title: 'Library' }}
        />
        <Stack.Screen
          name="comic/[comicId]/index"
          options={{ title: 'Comic' }}
        />
        <Stack.Screen
          name="comic/[comicId]/page/[pageId]/index"
          options={{ headerShown: false }}
        />
        <Stack.Screen
          name="comic/[comicId]/page/[pageId]/panel/[panelId]"
          options={{
            headerShown: false,
            presentation: 'fullScreenModal',
          }}
        />
        <Stack.Screen
          name="vocabulary"
          options={{
            title: 'Vocabulary',
            headerShown: true,
            headerBackVisible: true,
            headerRight: () => null,
          }}
        />
        <Stack.Screen
          name="settings"
          options={{
            title: 'Settings',
            headerShown: true,
            headerBackVisible: true,
            headerRight: () => null,
          }}
        />
      </Stack>
    </ThemeProvider>
  );
}
