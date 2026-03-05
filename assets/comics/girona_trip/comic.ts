import { Comic } from '@/src/types/comic';

export const images = {
  page1: require('./images/page_1.png'),
  scene1: require('./images/page_1_scene_1.png'),
  scene2: require('./images/page_1_scene_2.png'),
  scene3: require('./images/page_1_scene_3.png'),
};

export const audio = {
  s1: require('./audio/s1.mp3'),
  s2: require('./audio/s2.mp3'),
  s3: require('./audio/s3.mp3'),
};

export const comic: Comic = {
  id: 'comic-girona',
  title: 'Viaje a Girona',
  description: 'Follow a young traveler on her exciting train journey to Girona. Learn travel vocabulary and expressions.',
  coverImage: 'local:girona_page1',
  level: 'beginner',
  isPremium: false,
  reviewWords: [
    {
      word: { id: 'g3', text: 'emocionada', meaning: 'excited (feminine)', baseForm: 'emocionado' },
      panelId: 'girona-panel-1',
      pageId: 'girona-page-1',
    },
    {
      word: { id: 'g4', text: 'nunca', meaning: 'never', baseForm: 'nunca' },
      panelId: 'girona-panel-1',
      pageId: 'girona-page-1',
    },
    {
      word: { id: 'g10', text: 'necesito', meaning: 'I need', baseForm: 'necesitar' },
      panelId: 'girona-panel-2',
      pageId: 'girona-page-1',
    },
    {
      word: { id: 'g11', text: 'encontrar', meaning: 'to find', baseForm: 'encontrar' },
      panelId: 'girona-panel-2',
      pageId: 'girona-page-1',
    },
    {
      word: { id: 'g13', text: 'plataforma', meaning: 'platform', baseForm: 'plataforma' },
      panelId: 'girona-panel-2',
      pageId: 'girona-page-1',
    },
    {
      word: { id: 'g20', text: 'tiempo', meaning: 'time', baseForm: 'tiempo' },
      panelId: 'girona-panel-3',
      pageId: 'girona-page-1',
    },
  ],
  pages: [
    {
      id: 'girona-page-1',
      pageNumber: 1,
      masterImage: 'local:girona_page1',
      panels: [
        {
          id: 'girona-panel-1',
          artworkImage: 'local:girona_scene1',
          panelOrder: 1,
          tapZoneX: 0,
          tapZoneY: 0,
          tapZoneWidth: 1,
          tapZoneHeight: 0.52,
          bubbles: [
            {
              id: 'girona-bubble-1-1',
              type: 'speech',
              positionX: 0.5,
              positionY: 0.1,
              width: 0.45,
              height: 0.2,
              sentences: [
                {
                  id: 'girona-s1',
                  text: '¡Estoy súper emocionada! Nunca he estado en Girona.',
                  translation: "I'm super excited! I've never been to Girona.",
                  audioUrl: 'local:girona-s1',
                  words: [
                    { id: 'g1', text: '¡Estoy', meaning: 'I am (temporary state)', baseForm: 'estar', startTimeMs: 159, endTimeMs: 699 },
                    { id: 'g2', text: 'súper', meaning: 'super, very', baseForm: 'súper', startTimeMs: 960, endTimeMs: 1350 },
                    { id: 'g3', text: 'emocionada!', meaning: 'excited (feminine)', baseForm: 'emocionado', startTimeMs: 1350, endTimeMs: 1939 },
                    { id: 'g4', text: 'Nunca', meaning: 'Never', baseForm: 'nunca', startTimeMs: 2679, endTimeMs: 2939 },
                    { id: 'g5', text: 'he', meaning: 'I have (auxiliary)', baseForm: 'haber', startTimeMs: 2939, endTimeMs: 3019 },
                    { id: 'g6', text: 'estado', meaning: 'been', baseForm: 'estar', startTimeMs: 3079, endTimeMs: 3359 },
                    { id: 'g7', text: 'en', meaning: 'in', baseForm: 'en', startTimeMs: 3379, endTimeMs: 3459 },
                    { id: 'g8', text: 'Girona.', meaning: 'Girona (city in Catalonia, Spain)', baseForm: 'Girona', startTimeMs: 3519, endTimeMs: 3899 },
                  ],
                },
              ],
            },
          ],
        },
        {
          id: 'girona-panel-2',
          artworkImage: 'local:girona_scene2',
          panelOrder: 2,
          tapZoneX: 0,
          tapZoneY: 0.52,
          tapZoneWidth: 0.5,
          tapZoneHeight: 0.48,
          bubbles: [
            {
              id: 'girona-bubble-2-1',
              type: 'thought',
              positionX: 0.1,
              positionY: 0.1,
              width: 0.8,
              height: 0.3,
              sentences: [
                {
                  id: 'girona-s2',
                  text: 'Ahora necesito encontrar la plataforma correcta.',
                  translation: 'Now I need to find the right platform.',
                  audioUrl: 'local:girona-s2',
                  words: [
                    { id: 'g9', text: 'Ahora', meaning: 'Now', baseForm: 'ahora' },
                    { id: 'g10', text: 'necesito', meaning: 'I need', baseForm: 'necesitar' },
                    { id: 'g11', text: 'encontrar', meaning: 'to find', baseForm: 'encontrar' },
                    { id: 'g12', text: 'la', meaning: 'the (feminine)', baseForm: 'la' },
                    { id: 'g13', text: 'plataforma', meaning: 'platform', baseForm: 'plataforma' },
                    { id: 'g14', text: 'correcta.', meaning: 'correct (feminine)', baseForm: 'correcto' },
                  ],
                },
              ],
            },
          ],
        },
        {
          id: 'girona-panel-3',
          artworkImage: 'local:girona_scene3',
          panelOrder: 3,
          tapZoneX: 0.5,
          tapZoneY: 0.52,
          tapZoneWidth: 0.5,
          tapZoneHeight: 0.48,
          bubbles: [
            {
              id: 'girona-bubble-3-1',
              type: 'speech',
              positionX: 0.5,
              positionY: 0.1,
              width: 0.45,
              height: 0.25,
              sentences: [
                {
                  id: 'girona-s3',
                  text: '¡Lo encontré! ¡Está justo a tiempo!',
                  translation: "I found it! It's right on time!",
                  audioUrl: 'local:girona-s3',
                  words: [
                    { id: 'g15', text: '¡Lo', meaning: 'It (direct object)', baseForm: 'lo' },
                    { id: 'g16', text: 'encontré!', meaning: 'I found', baseForm: 'encontrar' },
                    { id: 'g17', text: '¡Está', meaning: 'It is (location/state)', baseForm: 'estar' },
                    { id: 'g18', text: 'justo', meaning: 'just, right', baseForm: 'justo' },
                    { id: 'g19', text: 'a', meaning: 'on', baseForm: 'a' },
                    { id: 'g20', text: 'tiempo!', meaning: 'time', baseForm: 'tiempo' },
                  ],
                },
              ],
            },
          ],
        },
      ],
    },
  ],
};
