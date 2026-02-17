import { Comic } from '../types/comic';
import { ImageSourcePropType } from 'react-native';

// Local image assets for Girona comic
export const gironaImages = {
  page1: require('@/assets/images/girona_trip_page_1.png'),
  scene1: require('@/assets/images/girona_trip_page_1_scene_1.png'),
  scene2: require('@/assets/images/girona_trip_page_1_scene_2.png'),
  scene3: require('@/assets/images/girona_trip_page_1_scene_3.png'),
};

export const comics: Comic[] = [
  {
    id: 'comic-1',
    title: 'El Primer Día',
    description: 'María arrives in a new city and meets her neighbor. A perfect introduction to basic Spanish greetings and introductions.',
    coverImage: 'https://picsum.photos/seed/comic1cover/400/600',
    level: 'beginner',
    isPremium: false,
    pages: [
      {
        id: 'page-1',
        pageNumber: 1,
        masterImage: 'https://picsum.photos/seed/page1/800/1200',
        panels: [
          {
            id: 'panel-1-1',
            artworkImage: 'https://picsum.photos/seed/panel11/800/600',
            panelOrder: 1,
            tapZoneX: 0.05,
            tapZoneY: 0.05,
            tapZoneWidth: 0.9,
            tapZoneHeight: 0.28,
            bubbles: [
              {
                id: 'bubble-1-1-1',
                type: 'narration',
                positionX: 0.1,
                positionY: 0.1,
                width: 0.8,
                height: 0.15,
                sentences: [
                  {
                    id: 'sentence-1-1-1-1',
                    text: 'María llega a su nuevo apartamento.',
                    audioUrl: 'https://example.com/audio/s1.mp3',
                    words: [
                      { id: 'w1', text: 'María', meaning: 'María (a common Spanish female name)', baseForm: 'María' },
                      { id: 'w2', text: 'llega', meaning: 'arrives', baseForm: 'llegar' },
                      { id: 'w3', text: 'a', meaning: 'to, at', baseForm: 'a' },
                      { id: 'w4', text: 'su', meaning: 'her, his, your (formal)', baseForm: 'su' },
                      { id: 'w5', text: 'nuevo', meaning: 'new', baseForm: 'nuevo' },
                      { id: 'w6', text: 'apartamento.', meaning: 'apartment', baseForm: 'apartamento' },
                    ],
                  },
                ],
              },
            ],
          },
          {
            id: 'panel-1-2',
            artworkImage: 'https://picsum.photos/seed/panel12/800/600',
            panelOrder: 2,
            tapZoneX: 0.05,
            tapZoneY: 0.35,
            tapZoneWidth: 0.45,
            tapZoneHeight: 0.28,
            bubbles: [
              {
                id: 'bubble-1-2-1',
                type: 'speech',
                positionX: 0.5,
                positionY: 0.1,
                width: 0.45,
                height: 0.2,
                sentences: [
                  {
                    id: 'sentence-1-2-1-1',
                    text: '¡Hola! Me llamo Carlos.',
                    audioUrl: 'https://example.com/audio/s2.mp3',
                    words: [
                      { id: 'w7', text: '¡Hola!', meaning: 'Hello!', baseForm: 'hola' },
                      { id: 'w8', text: 'Me', meaning: 'myself (reflexive pronoun)', baseForm: 'me' },
                      { id: 'w9', text: 'llamo', meaning: 'I call (myself) / My name is', baseForm: 'llamarse' },
                      { id: 'w10', text: 'Carlos.', meaning: 'Carlos (a common Spanish male name)', baseForm: 'Carlos' },
                    ],
                  },
                ],
              },
              {
                id: 'bubble-1-2-2',
                type: 'speech',
                positionX: 0.5,
                positionY: 0.35,
                width: 0.45,
                height: 0.2,
                sentences: [
                  {
                    id: 'sentence-1-2-2-1',
                    text: 'Soy tu vecino.',
                    audioUrl: 'https://example.com/audio/s3.mp3',
                    words: [
                      { id: 'w11', text: 'Soy', meaning: 'I am', baseForm: 'ser' },
                      { id: 'w12', text: 'tu', meaning: 'your (informal)', baseForm: 'tu' },
                      { id: 'w13', text: 'vecino.', meaning: 'neighbor', baseForm: 'vecino' },
                    ],
                  },
                ],
              },
            ],
          },
          {
            id: 'panel-1-3',
            artworkImage: 'https://picsum.photos/seed/panel13/800/600',
            panelOrder: 3,
            tapZoneX: 0.5,
            tapZoneY: 0.35,
            tapZoneWidth: 0.45,
            tapZoneHeight: 0.28,
            bubbles: [
              {
                id: 'bubble-1-3-1',
                type: 'speech',
                positionX: 0.1,
                positionY: 0.1,
                width: 0.8,
                height: 0.25,
                sentences: [
                  {
                    id: 'sentence-1-3-1-1',
                    text: '¡Mucho gusto, Carlos!',
                    audioUrl: 'https://example.com/audio/s4.mp3',
                    words: [
                      { id: 'w14', text: '¡Mucho', meaning: 'Much, a lot', baseForm: 'mucho' },
                      { id: 'w15', text: 'gusto,', meaning: 'pleasure (Nice to meet you!)', baseForm: 'gusto' },
                      { id: 'w16', text: 'Carlos!', meaning: 'Carlos', baseForm: 'Carlos' },
                    ],
                  },
                  {
                    id: 'sentence-1-3-1-2',
                    text: 'Yo soy María.',
                    audioUrl: 'https://example.com/audio/s5.mp3',
                    words: [
                      { id: 'w17', text: 'Yo', meaning: 'I (personal pronoun)', baseForm: 'yo' },
                      { id: 'w18', text: 'soy', meaning: 'I am', baseForm: 'ser' },
                      { id: 'w19', text: 'María.', meaning: 'María', baseForm: 'María' },
                    ],
                  },
                ],
              },
            ],
          },
          {
            id: 'panel-1-4',
            artworkImage: 'https://picsum.photos/seed/panel14/800/600',
            panelOrder: 4,
            tapZoneX: 0.05,
            tapZoneY: 0.65,
            tapZoneWidth: 0.9,
            tapZoneHeight: 0.3,
            bubbles: [
              {
                id: 'bubble-1-4-1',
                type: 'speech',
                positionX: 0.1,
                positionY: 0.1,
                width: 0.8,
                height: 0.3,
                sentences: [
                  {
                    id: 'sentence-1-4-1-1',
                    text: '¿De dónde eres?',
                    audioUrl: 'https://example.com/audio/s6.mp3',
                    words: [
                      { id: 'w20', text: '¿De', meaning: 'From (preposition)', baseForm: 'de' },
                      { id: 'w21', text: 'dónde', meaning: 'where (interrogative)', baseForm: 'dónde' },
                      { id: 'w22', text: 'eres?', meaning: 'are you (informal)', baseForm: 'ser' },
                    ],
                  },
                ],
              },
              {
                id: 'bubble-1-4-2',
                type: 'speech',
                positionX: 0.1,
                positionY: 0.45,
                width: 0.8,
                height: 0.3,
                sentences: [
                  {
                    id: 'sentence-1-4-2-1',
                    text: 'Soy de Barcelona.',
                    audioUrl: 'https://example.com/audio/s7.mp3',
                    words: [
                      { id: 'w23', text: 'Soy', meaning: 'I am', baseForm: 'ser' },
                      { id: 'w24', text: 'de', meaning: 'from', baseForm: 'de' },
                      { id: 'w25', text: 'Barcelona.', meaning: 'Barcelona (city in Spain)', baseForm: 'Barcelona' },
                    ],
                  },
                ],
              },
            ],
          },
        ],
      },
      {
        id: 'page-2',
        pageNumber: 2,
        masterImage: 'https://picsum.photos/seed/page2/800/1200',
        panels: [
          {
            id: 'panel-2-1',
            artworkImage: 'https://picsum.photos/seed/panel21/800/600',
            panelOrder: 1,
            tapZoneX: 0.05,
            tapZoneY: 0.05,
            tapZoneWidth: 0.9,
            tapZoneHeight: 0.3,
            bubbles: [
              {
                id: 'bubble-2-1-1',
                type: 'speech',
                positionX: 0.1,
                positionY: 0.1,
                width: 0.8,
                height: 0.25,
                sentences: [
                  {
                    id: 'sentence-2-1-1-1',
                    text: '¿Te gusta la ciudad?',
                    audioUrl: 'https://example.com/audio/s8.mp3',
                    words: [
                      { id: 'w26', text: '¿Te', meaning: 'to you (indirect object)', baseForm: 'te' },
                      { id: 'w27', text: 'gusta', meaning: 'pleases / you like', baseForm: 'gustar' },
                      { id: 'w28', text: 'la', meaning: 'the (feminine)', baseForm: 'la' },
                      { id: 'w29', text: 'ciudad?', meaning: 'city', baseForm: 'ciudad' },
                    ],
                  },
                ],
              },
            ],
          },
          {
            id: 'panel-2-2',
            artworkImage: 'https://picsum.photos/seed/panel22/800/600',
            panelOrder: 2,
            tapZoneX: 0.05,
            tapZoneY: 0.37,
            tapZoneWidth: 0.9,
            tapZoneHeight: 0.28,
            bubbles: [
              {
                id: 'bubble-2-2-1',
                type: 'speech',
                positionX: 0.1,
                positionY: 0.1,
                width: 0.8,
                height: 0.35,
                sentences: [
                  {
                    id: 'sentence-2-2-1-1',
                    text: '¡Sí, me encanta!',
                    audioUrl: 'https://example.com/audio/s9.mp3',
                    words: [
                      { id: 'w30', text: '¡Sí,', meaning: 'Yes', baseForm: 'sí' },
                      { id: 'w31', text: 'me', meaning: 'to me', baseForm: 'me' },
                      { id: 'w32', text: 'encanta!', meaning: 'I love it! (it enchants me)', baseForm: 'encantar' },
                    ],
                  },
                  {
                    id: 'sentence-2-2-1-2',
                    text: 'Es muy bonita.',
                    audioUrl: 'https://example.com/audio/s10.mp3',
                    words: [
                      { id: 'w33', text: 'Es', meaning: 'It is', baseForm: 'ser' },
                      { id: 'w34', text: 'muy', meaning: 'very', baseForm: 'muy' },
                      { id: 'w35', text: 'bonita.', meaning: 'beautiful, pretty', baseForm: 'bonito' },
                    ],
                  },
                ],
              },
            ],
          },
          {
            id: 'panel-2-3',
            artworkImage: 'https://picsum.photos/seed/panel23/800/600',
            panelOrder: 3,
            tapZoneX: 0.05,
            tapZoneY: 0.67,
            tapZoneWidth: 0.9,
            tapZoneHeight: 0.28,
            bubbles: [
              {
                id: 'bubble-2-3-1',
                type: 'speech',
                positionX: 0.1,
                positionY: 0.1,
                width: 0.8,
                height: 0.35,
                sentences: [
                  {
                    id: 'sentence-2-3-1-1',
                    text: '¡Bienvenida al barrio!',
                    audioUrl: 'https://example.com/audio/s11.mp3',
                    words: [
                      { id: 'w36', text: '¡Bienvenida', meaning: 'Welcome (feminine)', baseForm: 'bienvenido' },
                      { id: 'w37', text: 'al', meaning: 'to the (a + el)', baseForm: 'al' },
                      { id: 'w38', text: 'barrio!', meaning: 'neighborhood', baseForm: 'barrio' },
                    ],
                  },
                ],
              },
              {
                id: 'bubble-2-3-2',
                type: 'speech',
                positionX: 0.1,
                positionY: 0.5,
                width: 0.8,
                height: 0.2,
                sentences: [
                  {
                    id: 'sentence-2-3-2-1',
                    text: '¡Gracias, Carlos!',
                    audioUrl: 'https://example.com/audio/s12.mp3',
                    words: [
                      { id: 'w39', text: '¡Gracias,', meaning: 'Thank you', baseForm: 'gracias' },
                      { id: 'w40', text: 'Carlos!', meaning: 'Carlos', baseForm: 'Carlos' },
                    ],
                  },
                ],
              },
            ],
          },
        ],
      },
      {
        id: 'page-3',
        pageNumber: 3,
        masterImage: 'https://picsum.photos/seed/page3/800/1200',
        panels: [
          {
            id: 'panel-3-1',
            artworkImage: 'https://picsum.photos/seed/panel31/800/600',
            panelOrder: 1,
            tapZoneX: 0.05,
            tapZoneY: 0.05,
            tapZoneWidth: 0.9,
            tapZoneHeight: 0.45,
            bubbles: [
              {
                id: 'bubble-3-1-1',
                type: 'narration',
                positionX: 0.1,
                positionY: 0.1,
                width: 0.8,
                height: 0.15,
                sentences: [
                  {
                    id: 'sentence-3-1-1-1',
                    text: 'Al día siguiente...',
                    audioUrl: 'https://example.com/audio/s13.mp3',
                    words: [
                      { id: 'w41', text: 'Al', meaning: 'On the, To the', baseForm: 'al' },
                      { id: 'w42', text: 'día', meaning: 'day', baseForm: 'día' },
                      { id: 'w43', text: 'siguiente...', meaning: 'following, next', baseForm: 'siguiente' },
                    ],
                  },
                ],
              },
              {
                id: 'bubble-3-1-2',
                type: 'speech',
                positionX: 0.1,
                positionY: 0.3,
                width: 0.8,
                height: 0.25,
                sentences: [
                  {
                    id: 'sentence-3-1-2-1',
                    text: '¡Buenos días, María!',
                    audioUrl: 'https://example.com/audio/s14.mp3',
                    words: [
                      { id: 'w44', text: '¡Buenos', meaning: 'Good', baseForm: 'bueno' },
                      { id: 'w45', text: 'días,', meaning: 'days / morning (Good morning!)', baseForm: 'día' },
                      { id: 'w46', text: 'María!', meaning: 'María', baseForm: 'María' },
                    ],
                  },
                  {
                    id: 'sentence-3-1-2-2',
                    text: '¿Cómo estás?',
                    audioUrl: 'https://example.com/audio/s15.mp3',
                    words: [
                      { id: 'w47', text: '¿Cómo', meaning: 'How', baseForm: 'cómo' },
                      { id: 'w48', text: 'estás?', meaning: 'are you (informal)', baseForm: 'estar' },
                    ],
                  },
                ],
              },
            ],
          },
          {
            id: 'panel-3-2',
            artworkImage: 'https://picsum.photos/seed/panel32/800/600',
            panelOrder: 2,
            tapZoneX: 0.05,
            tapZoneY: 0.52,
            tapZoneWidth: 0.9,
            tapZoneHeight: 0.43,
            bubbles: [
              {
                id: 'bubble-3-2-1',
                type: 'speech',
                positionX: 0.1,
                positionY: 0.1,
                width: 0.8,
                height: 0.35,
                sentences: [
                  {
                    id: 'sentence-3-2-1-1',
                    text: '¡Muy bien, gracias!',
                    audioUrl: 'https://example.com/audio/s16.mp3',
                    words: [
                      { id: 'w49', text: '¡Muy', meaning: 'Very', baseForm: 'muy' },
                      { id: 'w50', text: 'bien,', meaning: 'well, good', baseForm: 'bien' },
                      { id: 'w51', text: 'gracias!', meaning: 'thank you', baseForm: 'gracias' },
                    ],
                  },
                  {
                    id: 'sentence-3-2-1-2',
                    text: '¿Y tú?',
                    audioUrl: 'https://example.com/audio/s17.mp3',
                    words: [
                      { id: 'w52', text: '¿Y', meaning: 'And', baseForm: 'y' },
                      { id: 'w53', text: 'tú?', meaning: 'you (informal)', baseForm: 'tú' },
                    ],
                  },
                ],
              },
              {
                id: 'bubble-3-2-2',
                type: 'thought',
                positionX: 0.1,
                positionY: 0.55,
                width: 0.8,
                height: 0.25,
                sentences: [
                  {
                    id: 'sentence-3-2-2-1',
                    text: 'Me gusta mi nuevo hogar.',
                    audioUrl: 'https://example.com/audio/s18.mp3',
                    words: [
                      { id: 'w54', text: 'Me', meaning: 'to me', baseForm: 'me' },
                      { id: 'w55', text: 'gusta', meaning: 'pleases / I like', baseForm: 'gustar' },
                      { id: 'w56', text: 'mi', meaning: 'my', baseForm: 'mi' },
                      { id: 'w57', text: 'nuevo', meaning: 'new', baseForm: 'nuevo' },
                      { id: 'w58', text: 'hogar.', meaning: 'home', baseForm: 'hogar' },
                    ],
                  },
                ],
              },
            ],
          },
        ],
      },
    ],
  },
  {
    id: 'comic-girona',
    title: 'Viaje a Girona',
    description: 'Follow a young traveler on her exciting train journey to Girona. Learn travel vocabulary and expressions.',
    coverImage: 'local:girona_page1',
    level: 'beginner',
    isPremium: false,
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
                    audioUrl: '',
                    words: [
                      { id: 'g1', text: '¡Estoy', meaning: 'I am (temporary state)', baseForm: 'estar' },
                      { id: 'g2', text: 'súper', meaning: 'super, very', baseForm: 'súper' },
                      { id: 'g3', text: 'emocionada!', meaning: 'excited (feminine)', baseForm: 'emocionado' },
                      { id: 'g4', text: 'Nunca', meaning: 'Never', baseForm: 'nunca' },
                      { id: 'g5', text: 'he', meaning: 'I have (auxiliary)', baseForm: 'haber' },
                      { id: 'g6', text: 'estado', meaning: 'been', baseForm: 'estar' },
                      { id: 'g7', text: 'en', meaning: 'in', baseForm: 'en' },
                      { id: 'g8', text: 'Girona.', meaning: 'Girona (city in Catalonia, Spain)', baseForm: 'Girona' },
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
                    audioUrl: '',
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
                    translation: 'I found it! It\'s right on time!',
                    audioUrl: '',
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
  },
];
