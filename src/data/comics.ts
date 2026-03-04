import { Comic } from '../types/comic';

import { images as gironaImages, audio as gironaAudio, comic as gironaComic } from '@/assets/comics/girona_trip/comic';
import { images as horrorImages, audio as horrorAudio, comic as horrorComic } from '@/assets/comics/horror_story/comic';
import { images as alienImages, audio as alienAudio, comic as alienComic } from '@/assets/comics/alien/comic';

export { gironaImages, gironaAudio };
export { horrorImages, horrorAudio };
export { alienImages, alienAudio };

export const comics: Comic[] = [
  gironaComic,
  horrorComic,
  alienComic,
];
