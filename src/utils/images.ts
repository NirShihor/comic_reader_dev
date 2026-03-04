import { ImageSourcePropType } from 'react-native';
import { gironaImages, horrorImages, alienImages } from '../data/comics';

const localImageMap: { [key: string]: ImageSourcePropType } = {
  // Girona
  'girona_page1': gironaImages.page1,
  'girona_scene1': gironaImages.scene1,
  'girona_scene2': gironaImages.scene2,
  'girona_scene3': gironaImages.scene3,
  // Horror Story - Pages
  'horror_p1': horrorImages.p1,
  'horror_p2': horrorImages.p2,
  'horror_p3': horrorImages.p3,
  'horror_p4': horrorImages.p4,
  // Horror Story - Scenes
  'horror_p1_s1': horrorImages.p1_s1,
  'horror_p1_s2': horrorImages.p1_s2,
  'horror_p1_s3': horrorImages.p1_s3,
  'horror_p2_s1': horrorImages.p2_s1,
  'horror_p2_s2': horrorImages.p2_s2,
  'horror_p3_s1': horrorImages.p3_s1,
  'horror_p3_s2': horrorImages.p3_s2,
  'horror_p3_s3': horrorImages.p3_s3,
  'horror_p4_s1': horrorImages.p4_s1,
  'horror_p4_s2': horrorImages.p4_s2,
  'horror_p4_s3': horrorImages.p4_s3,
  // Alien - Cover and Pages
  'alien_cover': alienImages.cover,
  'alien_p1': alienImages.p1,
  'alien_p2': alienImages.p2,
  'alien_p3': alienImages.p3,
  'alien_p4': alienImages.p4,
  'alien_p5': alienImages.p5,
  'alien_p6': alienImages.p6,
  // Alien - Scenes
  'alien_p1_s1': alienImages.p1_s1,
  'alien_p1_s2': alienImages.p1_s2,
  'alien_p1_s3': alienImages.p1_s3,
  'alien_p2_s1': alienImages.p2_s1,
  'alien_p2_s2': alienImages.p2_s2,
  'alien_p2_s3': alienImages.p2_s3,
  'alien_p2_s4': alienImages.p2_s4,
  'alien_p3_s1': alienImages.p3_s1,
  'alien_p3_s2': alienImages.p3_s2,
  'alien_p3_s3': alienImages.p3_s3,
  'alien_p4_s1': alienImages.p4_s1,
  'alien_p4_s2': alienImages.p4_s2,
  'alien_p4_s3': alienImages.p4_s3,
  'alien_p5_s1': alienImages.p5_s1,
  'alien_p5_s2': alienImages.p5_s2,
  'alien_p5_s3': alienImages.p5_s3,
  'alien_p5_s4': alienImages.p5_s4,
  'alien_p6_s1': alienImages.p6_s1,
  'alien_p6_s2': alienImages.p6_s2,
  'alien_p6_s3': alienImages.p6_s3,
  'alien_p6_s4': alienImages.p6_s4,
};

export function getImageSource(uri: string): ImageSourcePropType {
  if (uri.startsWith('local:')) {
    const key = uri.replace('local:', '');
    return localImageMap[key] || { uri: '' };
  }
  return { uri };
}
