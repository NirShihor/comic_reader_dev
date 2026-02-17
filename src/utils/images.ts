import { ImageSourcePropType } from 'react-native';
import { gironaImages } from '../data/comics';

const localImageMap: { [key: string]: ImageSourcePropType } = {
  'girona_page1': gironaImages.page1,
  'girona_scene1': gironaImages.scene1,
  'girona_scene2': gironaImages.scene2,
  'girona_scene3': gironaImages.scene3,
};

export function getImageSource(uri: string): ImageSourcePropType {
  if (uri.startsWith('local:')) {
    const key = uri.replace('local:', '');
    return localImageMap[key] || { uri: '' };
  }
  return { uri };
}
