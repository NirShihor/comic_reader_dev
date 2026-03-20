import Foundation

/// Static comic data - legacy fallback (no longer used, comics are downloaded from server)
enum ComicData {
    static let allComics: [Comic] = []

    // MARK: - Alien Comic
    static let alienComic = Comic(
        id: "comic-alien",
        title: "El Visitante",
        description: "Mía encounters a friendly alien named Zik who got lost while learning Spanish. A beginner-friendly story about helping others.",
        coverImage: "alien_cover",
        level: .beginner,
        isPremium: false,
        pages: alienPages,
        reviewWords: alienReviewWords
    )

    static let alienPages: [Page] = [
        // Cover
        Page(
            id: "alien-page-cover",
            pageNumber: 1,
            masterImage: "alien_cover",
            panels: [
                Panel(
                    id: "alien-panel-cover",
                    artworkImage: "alien_cover",
                    panelOrder: 1,
                    tapZoneX: 0,
                    tapZoneY: 0,
                    tapZoneWidth: 1,
                    tapZoneHeight: 1,
                    bubbles: [
                        Bubble(
                            id: "alien-bubble-cover",
                            type: .narration,
                            positionX: 0.1,
                            positionY: 0.1,
                            width: 0.8,
                            height: 0.15,
                            sentences: [
                                Sentence(
                                    id: "alien-s-cover",
                                    text: "El Visitante",
                                    translation: "The Visitor",
                                    audioUrl: "alien_cover",
                                    words: [
                                        Word(id: "a-cover-1", text: "El", meaning: "The (masculine)", baseForm: "el"),
                                        Word(id: "a-cover-2", text: "Visitante", meaning: "Visitor", baseForm: "visitante")
                                    ]
                                )
                            ]
                        )
                    ]
                )
            ]
        ),
        // Page 1
        Page(
            id: "alien-page-1",
            pageNumber: 2,
            masterImage: "alien_p1",
            panels: [
                Panel(
                    id: "alien-panel-1-1",
                    artworkImage: "alien_p1_s1",
                    panelOrder: 1,
                    tapZoneX: 0,
                    tapZoneY: 0,
                    tapZoneWidth: 1,
                    tapZoneHeight: 0.38,
                    bubbles: [
                        Bubble(
                            id: "alien-bubble-1-1-1",
                            type: .narration,
                            positionX: 0.1,
                            positionY: 0.1,
                            width: 0.8,
                            height: 0.15,
                            sentences: [
                                Sentence(
                                    id: "alien-s1-1",
                                    text: "Tarde en la noche",
                                    translation: "Late at night",
                                    audioUrl: "alien_p1_s1",
                                    words: [
                                        Word(id: "a1", text: "Tarde", meaning: "Late", baseForm: "tarde", startTimeMs: 119, endTimeMs: 519),
                                        Word(id: "a2", text: "en", meaning: "in, at", baseForm: "en", startTimeMs: 540, endTimeMs: 639),
                                        Word(id: "a3", text: "la", meaning: "the (feminine)", baseForm: "la", startTimeMs: 680, endTimeMs: 719),
                                        Word(id: "a4", text: "noche", meaning: "night", baseForm: "noche", startTimeMs: 779, endTimeMs: 1179)
                                    ]
                                )
                            ]
                        )
                    ]
                ),
                Panel(
                    id: "alien-panel-1-2",
                    artworkImage: "alien_p1_s2",
                    panelOrder: 2,
                    tapZoneX: 0,
                    tapZoneY: 0.38,
                    tapZoneWidth: 1,
                    tapZoneHeight: 0.32,
                    bubbles: [
                        Bubble(
                            id: "alien-bubble-1-2-1",
                            type: .thought,
                            positionX: 0.1,
                            positionY: 0.1,
                            width: 0.8,
                            height: 0.15,
                            sentences: [
                                Sentence(
                                    id: "alien-s1-2",
                                    text: "¿Qué fue eso..?",
                                    translation: "What was that..?",
                                    audioUrl: "alien_p1_s2",
                                    words: [
                                        Word(id: "a5", text: "¿Qué", meaning: "What", baseForm: "qué", startTimeMs: 119, endTimeMs: 399),
                                        Word(id: "a6", text: "fue", meaning: "was (ser/ir past)", baseForm: "ser", startTimeMs: 419, endTimeMs: 680),
                                        Word(id: "a7", text: "eso..?", meaning: "that", baseForm: "eso", startTimeMs: 679, endTimeMs: 1660)
                                    ]
                                )
                            ]
                        )
                    ]
                ),
                Panel(
                    id: "alien-panel-1-3",
                    artworkImage: "alien_p1_s3",
                    panelOrder: 3,
                    tapZoneX: 0,
                    tapZoneY: 0.69,
                    tapZoneWidth: 1,
                    tapZoneHeight: 0.31,
                    bubbles: []
                )
            ]
        ),
        // Page 2
        Page(
            id: "alien-page-2",
            pageNumber: 3,
            masterImage: "alien_p2",
            panels: [
                Panel(
                    id: "alien-panel-2-1",
                    artworkImage: "alien_p2_s1",
                    panelOrder: 1,
                    tapZoneX: 0,
                    tapZoneY: 0,
                    tapZoneWidth: 1,
                    tapZoneHeight: 0.36,
                    bubbles: []
                ),
                Panel(
                    id: "alien-panel-2-2",
                    artworkImage: "alien_p2_s2",
                    panelOrder: 2,
                    tapZoneX: 0,
                    tapZoneY: 0.35,
                    tapZoneWidth: 1,
                    tapZoneHeight: 0.32,
                    bubbles: [
                        Bubble(
                            id: "alien-bubble-2-2-1",
                            type: .speech,
                            positionX: 0.1,
                            positionY: 0.1,
                            width: 0.8,
                            height: 0.15,
                            sentences: [
                                Sentence(
                                    id: "alien-s2-2",
                                    text: "¿Qué...? ¿Quién eres?",
                                    translation: "What...? Who are you?",
                                    audioUrl: "alien_p2_s2",
                                    words: [
                                        Word(id: "a8", text: "¿Qué...?", meaning: "What", baseForm: "qué", startTimeMs: 140, endTimeMs: 500),
                                        Word(id: "a9", text: "¿Quién", meaning: "Who", baseForm: "quién", startTimeMs: 939, endTimeMs: 1179),
                                        Word(id: "a10", text: "eres?", meaning: "are you (ser)", baseForm: "ser", startTimeMs: 1259, endTimeMs: 1579)
                                    ]
                                )
                            ]
                        )
                    ]
                ),
                Panel(
                    id: "alien-panel-2-3",
                    artworkImage: "alien_p2_s3",
                    panelOrder: 3,
                    tapZoneX: 0,
                    tapZoneY: 0.67,
                    tapZoneWidth: 0.5,
                    tapZoneHeight: 0.33,
                    bubbles: [
                        Bubble(
                            id: "alien-bubble-2-3-1",
                            type: .speech,
                            positionX: 0.1,
                            positionY: 0.1,
                            width: 0.8,
                            height: 0.15,
                            sentences: [
                                Sentence(
                                    id: "alien-s2-3",
                                    text: "Me llamo Zik. ¿Cómo te llamas?",
                                    translation: "My name is Zik. What's your name?",
                                    audioUrl: "alien_p2_s3",
                                    words: [
                                        Word(id: "a11", text: "Me", meaning: "Myself (reflexive)", baseForm: "me", startTimeMs: 199, endTimeMs: 339),
                                        Word(id: "a12", text: "llamo", meaning: "I call / am called", baseForm: "llamarse", startTimeMs: 379, endTimeMs: 680),
                                        Word(id: "a13", text: "Zik.", meaning: "Zik (name)", baseForm: "Zik", startTimeMs: 759, endTimeMs: 1199),
                                        Word(id: "a14", text: "¿Cómo", meaning: "How", baseForm: "cómo", startTimeMs: 1579, endTimeMs: 1819),
                                        Word(id: "a15", text: "te", meaning: "yourself (reflexive)", baseForm: "te", startTimeMs: 1839, endTimeMs: 1960),
                                        Word(id: "a16", text: "llamas?", meaning: "do you call yourself", baseForm: "llamarse", startTimeMs: 1979, endTimeMs: 2539)
                                    ]
                                )
                            ]
                        )
                    ]
                ),
                Panel(
                    id: "alien-panel-2-4",
                    artworkImage: "alien_p2_s4",
                    panelOrder: 4,
                    tapZoneX: 0.5,
                    tapZoneY: 0.67,
                    tapZoneWidth: 0.5,
                    tapZoneHeight: 0.33,
                    bubbles: [
                        Bubble(
                            id: "alien-bubble-2-4-1",
                            type: .speech,
                            positionX: 0.1,
                            positionY: 0.1,
                            width: 0.8,
                            height: 0.15,
                            sentences: [
                                Sentence(
                                    id: "alien-s2-4",
                                    text: "Me llamo Mía.",
                                    translation: "My name is Mía.",
                                    audioUrl: "alien_p2_s4",
                                    words: [
                                        Word(id: "a17", text: "Me", meaning: "Myself (reflexive)", baseForm: "me", startTimeMs: 119, endTimeMs: 259),
                                        Word(id: "a18", text: "llamo", meaning: "I call / am called", baseForm: "llamarse", startTimeMs: 339, endTimeMs: 679),
                                        Word(id: "a19", text: "Mía.", meaning: "Mía (name)", baseForm: "Mía", startTimeMs: 679, endTimeMs: 1740)
                                    ]
                                )
                            ]
                        )
                    ]
                )
            ]
        ),
        // Page 3
        Page(
            id: "alien-page-3",
            pageNumber: 4,
            masterImage: "alien_p3",
            panels: [
                Panel(
                    id: "alien-panel-3-1",
                    artworkImage: "alien_p3_s1",
                    panelOrder: 1,
                    tapZoneX: 0,
                    tapZoneY: 0,
                    tapZoneWidth: 0.5,
                    tapZoneHeight: 0.999,
                    bubbles: [
                        Bubble(
                            id: "alien-bubble-3-1-1",
                            type: .speech,
                            positionX: 0.1,
                            positionY: 0.1,
                            width: 0.8,
                            height: 0.15,
                            sentences: [
                                Sentence(
                                    id: "alien-s3-1",
                                    text: "¿Estás bien?",
                                    translation: "Are you okay?",
                                    audioUrl: "alien_p3_s1",
                                    words: [
                                        Word(id: "a20", text: "¿Estás", meaning: "Are you (temporary state)", baseForm: "estar", startTimeMs: 119, endTimeMs: 599),
                                        Word(id: "a21", text: "bien?", meaning: "well, okay", baseForm: "bien", startTimeMs: 599, endTimeMs: 1579)
                                    ]
                                )
                            ]
                        )
                    ]
                ),
                Panel(
                    id: "alien-panel-3-2",
                    artworkImage: "alien_p3_s2",
                    panelOrder: 2,
                    tapZoneX: 0.5,
                    tapZoneY: 0.0,
                    tapZoneWidth: 0.5,
                    tapZoneHeight: 0.56,
                    bubbles: [
                        Bubble(
                            id: "alien-bubble-3-2-1",
                            type: .speech,
                            positionX: 0.1,
                            positionY: 0.1,
                            width: 0.8,
                            height: 0.15,
                            sentences: [
                                Sentence(
                                    id: "alien-s3-2",
                                    text: "Yo... tengo miedo.",
                                    translation: "I... I'm scared. (I have fear = I am scared)",
                                    audioUrl: "alien_p3_s2",
                                    words: [
                                        Word(id: "a22", text: "Yo...", meaning: "I", baseForm: "yo", startTimeMs: 119, endTimeMs: 560),
                                        Word(id: "a23", text: "tengo", meaning: "I have", baseForm: "tener", startTimeMs: 859, endTimeMs: 1120),
                                        Word(id: "a24", text: "miedo.", meaning: "fear (I have fear = I am scared)", baseForm: "miedo", startTimeMs: 1180, endTimeMs: 1499)
                                    ]
                                )
                            ]
                        )
                    ]
                ),
                Panel(
                    id: "alien-panel-3-3",
                    artworkImage: "alien_p3_s3",
                    panelOrder: 3,
                    tapZoneX: 0.5,
                    tapZoneY: 0.56,
                    tapZoneWidth: 0.5,
                    tapZoneHeight: 0.44,
                    bubbles: [
                        Bubble(
                            id: "alien-bubble-3-3-1",
                            type: .speech,
                            positionX: 0.1,
                            positionY: 0.1,
                            width: 0.8,
                            height: 0.15,
                            sentences: [
                                Sentence(
                                    id: "alien-s3-3",
                                    text: "¿De dónde eres?",
                                    translation: "Where are you from?",
                                    audioUrl: "alien_p3_s3",
                                    words: [
                                        Word(id: "a25", text: "¿De", meaning: "From", baseForm: "de", startTimeMs: 119, endTimeMs: 319),
                                        Word(id: "a26", text: "dónde", meaning: "where", baseForm: "dónde", startTimeMs: 339, endTimeMs: 619),
                                        Word(id: "a27", text: "eres?", meaning: "are you (ser - origin)", baseForm: "ser", startTimeMs: 659, endTimeMs: 1100)
                                    ]
                                )
                            ]
                        )
                    ]
                )
            ]
        ),
        // Page 4
        Page(
            id: "alien-page-4",
            pageNumber: 5,
            masterImage: "alien_p4",
            panels: [
                Panel(
                    id: "alien-panel-4-1",
                    artworkImage: "alien_p4_s1",
                    panelOrder: 1,
                    tapZoneX: 0,
                    tapZoneY: 0,
                    tapZoneWidth: 1,
                    tapZoneHeight: 0.48,
                    bubbles: [
                        Bubble(
                            id: "alien-bubble-4-1-1",
                            type: .speech,
                            positionX: 0.1,
                            positionY: 0.1,
                            width: 0.8,
                            height: 0.15,
                            sentences: [
                                Sentence(
                                    id: "alien-s4-1",
                                    text: "Vengo de Zizark.",
                                    translation: "I'm from Zizark.",
                                    audioUrl: "alien_p4_s1",
                                    words: [
                                        Word(id: "a28", text: "Vengo", meaning: "I come", baseForm: "venir", startTimeMs: 140, endTimeMs: 539),
                                        Word(id: "a29", text: "de", meaning: "from", baseForm: "de", startTimeMs: 539, endTimeMs: 719),
                                        Word(id: "a30", text: "Zizark.", meaning: "Zizark (planet name)", baseForm: "Zizark", startTimeMs: 759, endTimeMs: 1340)
                                    ]
                                )
                            ]
                        )
                    ]
                ),
                Panel(
                    id: "alien-panel-4-2",
                    artworkImage: "alien_p4_s2",
                    panelOrder: 2,
                    tapZoneX: 0,
                    tapZoneY: 0.48,
                    tapZoneWidth: 0.5,
                    tapZoneHeight: 0.52,
                    bubbles: [
                        Bubble(
                            id: "alien-bubble-4-2-1",
                            type: .speech,
                            positionX: 0.1,
                            positionY: 0.1,
                            width: 0.8,
                            height: 0.15,
                            sentences: [
                                Sentence(
                                    id: "alien-s4-2",
                                    text: "¿Zizark? ¿Dónde está eso?",
                                    translation: "Zizark? Where is that?",
                                    audioUrl: "alien_p4_s2",
                                    words: [
                                        Word(id: "a31", text: "¿Zizark?", meaning: "Zizark (planet name)", baseForm: "Zizark", startTimeMs: 259, endTimeMs: 2000),
                                        Word(id: "a32", text: "¿Dónde", meaning: "Where", baseForm: "dónde", startTimeMs: 1999, endTimeMs: 2379),
                                        Word(id: "a33", text: "está", meaning: "is (location)", baseForm: "estar", startTimeMs: 2539, endTimeMs: 2700),
                                        Word(id: "a34", text: "eso?", meaning: "that", baseForm: "eso", startTimeMs: 2740, endTimeMs: 3179)
                                    ]
                                )
                            ]
                        )
                    ]
                ),
                Panel(
                    id: "alien-panel-4-3",
                    artworkImage: "alien_p4_s3",
                    panelOrder: 3,
                    tapZoneX: 0.5,
                    tapZoneY: 0.48,
                    tapZoneWidth: 0.5,
                    tapZoneHeight: 0.52,
                    bubbles: [
                        Bubble(
                            id: "alien-bubble-4-3-1",
                            type: .speech,
                            positionX: 0.1,
                            positionY: 0.1,
                            width: 0.8,
                            height: 0.15,
                            sentences: [
                                Sentence(
                                    id: "alien-s4-3",
                                    text: "Es un planeta.",
                                    translation: "It's a planet.",
                                    audioUrl: "alien_p4_s3",
                                    words: [
                                        Word(id: "a35", text: "Es", meaning: "It is (ser)", baseForm: "ser", startTimeMs: 79, endTimeMs: 379),
                                        Word(id: "a36", text: "un", meaning: "a (masculine)", baseForm: "un", startTimeMs: 479, endTimeMs: 679),
                                        Word(id: "a37", text: "planeta.", meaning: "planet", baseForm: "planeta", startTimeMs: 699, endTimeMs: 1419)
                                    ]
                                )
                            ]
                        )
                    ]
                )
            ]
        ),
        // Page 5
        Page(
            id: "alien-page-5",
            pageNumber: 6,
            masterImage: "alien_p5",
            panels: [
                Panel(
                    id: "alien-panel-5-1",
                    artworkImage: "alien_p5_s1",
                    panelOrder: 1,
                    tapZoneX: 0,
                    tapZoneY: 0,
                    tapZoneWidth: 0.5,
                    tapZoneHeight: 0.49,
                    bubbles: [
                        Bubble(
                            id: "alien-bubble-5-1-1",
                            type: .speech,
                            positionX: 0.1,
                            positionY: 0.1,
                            width: 0.8,
                            height: 0.15,
                            sentences: [
                                Sentence(
                                    id: "alien-s5-1",
                                    text: "¿Un planeta? ¿Por qué viniste aquí?",
                                    translation: "A planet? Why did you come here?",
                                    audioUrl: "alien_p5_s1",
                                    words: [
                                        Word(id: "a38", text: "¿Un", meaning: "A (masculine)", baseForm: "un", startTimeMs: 199, endTimeMs: 459),
                                        Word(id: "a39", text: "planeta?", meaning: "planet", baseForm: "planeta", startTimeMs: 479, endTimeMs: 2159),
                                        Word(id: "a40", text: "¿Por", meaning: "For, because of", baseForm: "por", startTimeMs: 2219, endTimeMs: 2339),
                                        Word(id: "a41", text: "qué", meaning: "what (por qué = why)", baseForm: "qué", startTimeMs: 2419, endTimeMs: 2500),
                                        Word(id: "a42", text: "viniste", meaning: "did you come (venir past)", baseForm: "venir", startTimeMs: 2539, endTimeMs: 2899),
                                        Word(id: "a43", text: "aquí?", meaning: "here", baseForm: "aquí", startTimeMs: 2919, endTimeMs: 4460)
                                    ]
                                )
                            ]
                        )
                    ]
                ),
                Panel(
                    id: "alien-panel-5-2",
                    artworkImage: "alien_p5_s2",
                    panelOrder: 2,
                    tapZoneX: 0.5,
                    tapZoneY: 0.0,
                    tapZoneWidth: 0.5,
                    tapZoneHeight: 0.49,
                    bubbles: [
                        Bubble(
                            id: "alien-bubble-5-2-1",
                            type: .speech,
                            positionX: 0.1,
                            positionY: 0.1,
                            width: 0.8,
                            height: 0.15,
                            sentences: [
                                Sentence(
                                    id: "alien-s5-2",
                                    text: "Por accidente. Me perdí.",
                                    translation: "By accident. I got lost.",
                                    audioUrl: "alien_p5_s2",
                                    words: [
                                        Word(id: "a44", text: "Por", meaning: "By, because of", baseForm: "por", startTimeMs: 99, endTimeMs: 279),
                                        Word(id: "a45", text: "accidente.", meaning: "accident", baseForm: "accidente", startTimeMs: 319, endTimeMs: 999),
                                        Word(id: "a46", text: "Me", meaning: "Myself (reflexive)", baseForm: "me", startTimeMs: 1439, endTimeMs: 1620),
                                        Word(id: "a47", text: "perdí.", meaning: "I got lost (perderse past)", baseForm: "perderse", startTimeMs: 1639, endTimeMs: 2139)
                                    ]
                                )
                            ]
                        )
                    ]
                ),
                Panel(
                    id: "alien-panel-5-3",
                    artworkImage: "alien_p5_s3",
                    panelOrder: 3,
                    tapZoneX: 0,
                    tapZoneY: 0.48,
                    tapZoneWidth: 0.5,
                    tapZoneHeight: 0.52,
                    bubbles: [
                        Bubble(
                            id: "alien-bubble-5-3-1",
                            type: .speech,
                            positionX: 0.1,
                            positionY: 0.1,
                            width: 0.8,
                            height: 0.15,
                            sentences: [
                                Sentence(
                                    id: "alien-s5-3",
                                    text: "¿Puedes ayudarme? Solo hablo un poco de español. Estoy aprendiendo.",
                                    translation: "Can you help me? I only speak a little Spanish. I'm learning.",
                                    audioUrl: "alien_p5_s3",
                                    words: [
                                        Word(id: "a48", text: "¿Puedes", meaning: "Can you (poder)", baseForm: "poder", startTimeMs: 99, endTimeMs: 579),
                                        Word(id: "a49", text: "ayudarme?", meaning: "help me", baseForm: "ayudar", startTimeMs: 699, endTimeMs: 1680),
                                        Word(id: "a50", text: "Solo", meaning: "Only", baseForm: "solo", startTimeMs: 1860, endTimeMs: 2119),
                                        Word(id: "a51", text: "hablo", meaning: "I speak", baseForm: "hablar", startTimeMs: 2200, endTimeMs: 2459),
                                        Word(id: "a52", text: "un", meaning: "a", baseForm: "un", startTimeMs: 2480, endTimeMs: 2659),
                                        Word(id: "a53", text: "poco", meaning: "little", baseForm: "poco", startTimeMs: 2659, endTimeMs: 2960),
                                        Word(id: "a54", text: "de", meaning: "of", baseForm: "de", startTimeMs: 2960, endTimeMs: 3039),
                                        Word(id: "a55", text: "español.", meaning: "Spanish", baseForm: "español", startTimeMs: 3079, endTimeMs: 3860),
                                        Word(id: "a56", text: "Estoy", meaning: "I am (temporary)", baseForm: "estar", startTimeMs: 3939, endTimeMs: 4339),
                                        Word(id: "a57", text: "aprendiendo.", meaning: "learning", baseForm: "aprender", startTimeMs: 4360, endTimeMs: 5179)
                                    ]
                                )
                            ]
                        )
                    ]
                ),
                Panel(
                    id: "alien-panel-5-4",
                    artworkImage: "alien_p5_s4",
                    panelOrder: 4,
                    tapZoneX: 0.5,
                    tapZoneY: 0.48,
                    tapZoneWidth: 0.5,
                    tapZoneHeight: 0.52,
                    bubbles: [
                        Bubble(
                            id: "alien-bubble-5-4-1",
                            type: .speech,
                            positionX: 0.1,
                            positionY: 0.1,
                            width: 0.8,
                            height: 0.15,
                            sentences: [
                                Sentence(
                                    id: "alien-s5-4",
                                    text: "¡Claro! No te preocupes, te ayudaré. Vamos a la casa.",
                                    translation: "Of course! Don't worry, I'll help you. Let's go to the house.",
                                    audioUrl: "alien_p5_s4",
                                    words: [
                                        Word(id: "a58", text: "¡Claro!", meaning: "Of course!", baseForm: "claro", startTimeMs: 119, endTimeMs: 860),
                                        Word(id: "a59", text: "No", meaning: "No, not", baseForm: "no", startTimeMs: 899, endTimeMs: 979),
                                        Word(id: "a60", text: "te", meaning: "yourself", baseForm: "te", startTimeMs: 1019, endTimeMs: 1079),
                                        Word(id: "a61", text: "preocupes,", meaning: "worry (don't worry)", baseForm: "preocuparse", startTimeMs: 1139, endTimeMs: 1799),
                                        Word(id: "a62", text: "te", meaning: "you (indirect object)", baseForm: "te", startTimeMs: 1819, endTimeMs: 1879),
                                        Word(id: "a63", text: "ayudaré.", meaning: "I will help", baseForm: "ayudar", startTimeMs: 1940, endTimeMs: 2819),
                                        Word(id: "a64", text: "Vamos", meaning: "Let's go", baseForm: "ir", startTimeMs: 2839, endTimeMs: 3059),
                                        Word(id: "a65", text: "a", meaning: "to", baseForm: "a", startTimeMs: 3079, endTimeMs: 3119),
                                        Word(id: "a66", text: "la", meaning: "the (feminine)", baseForm: "la", startTimeMs: 3139, endTimeMs: 3259),
                                        Word(id: "a67", text: "casa.", meaning: "house", baseForm: "casa", startTimeMs: 3279, endTimeMs: 3579)
                                    ]
                                )
                            ]
                        )
                    ]
                )
            ]
        ),
        // Page 6
        Page(
            id: "alien-page-6",
            pageNumber: 7,
            masterImage: "alien_p6",
            panels: [
                Panel(
                    id: "alien-panel-6-1",
                    artworkImage: "alien_p6_s1",
                    panelOrder: 1,
                    tapZoneX: 0,
                    tapZoneY: 0,
                    tapZoneWidth: 1,
                    tapZoneHeight: 0.31,
                    bubbles: []
                ),
                Panel(
                    id: "alien-panel-6-2",
                    artworkImage: "alien_p6_s2",
                    panelOrder: 2,
                    tapZoneX: 0,
                    tapZoneY: 0.31,
                    tapZoneWidth: 0.5,
                    tapZoneHeight: 0.30,
                    bubbles: [
                        Bubble(
                            id: "alien-bubble-6-2-1",
                            type: .speech,
                            positionX: 0.1,
                            positionY: 0.1,
                            width: 0.8,
                            height: 0.15,
                            sentences: [
                                Sentence(
                                    id: "alien-s6-2",
                                    text: "¿Qué está pasando?",
                                    translation: "What's happening?",
                                    audioUrl: "alien_p6_s2",
                                    words: [
                                        Word(id: "a68", text: "¿Qué", meaning: "What", baseForm: "qué", startTimeMs: 79, endTimeMs: 179),
                                        Word(id: "a69", text: "está", meaning: "is (estar)", baseForm: "estar", startTimeMs: 179, endTimeMs: 359),
                                        Word(id: "a70", text: "pasando?", meaning: "happening", baseForm: "pasar", startTimeMs: 360, endTimeMs: 1019)
                                    ]
                                )
                            ]
                        )
                    ]
                ),
                Panel(
                    id: "alien-panel-6-3",
                    artworkImage: "alien_p6_s3",
                    panelOrder: 3,
                    tapZoneX: 0.5,
                    tapZoneY: 0.31,
                    tapZoneWidth: 0.5,
                    tapZoneHeight: 0.30,
                    bubbles: [
                        Bubble(
                            id: "alien-bubble-6-3-1",
                            type: .speech,
                            positionX: 0.1,
                            positionY: 0.1,
                            width: 0.8,
                            height: 0.15,
                            sentences: [
                                Sentence(
                                    id: "alien-s6-3",
                                    text: "Hemos venido a tomar el control.",
                                    translation: "We've come to take control.",
                                    audioUrl: "alien_p6_s3",
                                    words: [
                                        Word(id: "a71", text: "Hemos", meaning: "We have (auxiliary)", baseForm: "haber", startTimeMs: 119, endTimeMs: 740),
                                        Word(id: "a72", text: "venido", meaning: "come (past participle)", baseForm: "venir", startTimeMs: 759, endTimeMs: 1559),
                                        Word(id: "a73", text: "a", meaning: "to", baseForm: "a", startTimeMs: 1579, endTimeMs: 1879),
                                        Word(id: "a74", text: "tomar", meaning: "to take", baseForm: "tomar", startTimeMs: 1899, endTimeMs: 2400),
                                        Word(id: "a75", text: "el", meaning: "the (masculine)", baseForm: "el", startTimeMs: 2460, endTimeMs: 2660),
                                        Word(id: "a76", text: "control.", meaning: "control", baseForm: "control", startTimeMs: 2679, endTimeMs: 3339)
                                    ]
                                )
                            ]
                        )
                    ]
                ),
                Panel(
                    id: "alien-panel-6-4",
                    artworkImage: "alien_p6_s4",
                    panelOrder: 4,
                    tapZoneX: 0,
                    tapZoneY: 0.60,
                    tapZoneWidth: 1,
                    tapZoneHeight: 0.39,
                    bubbles: [
                        Bubble(
                            id: "alien-bubble-6-4-1",
                            type: .thought,
                            positionX: 0.1,
                            positionY: 0.1,
                            width: 0.8,
                            height: 0.15,
                            sentences: [
                                Sentence(
                                    id: "alien-s6-4",
                                    text: "Oh... solo era un sueño...",
                                    translation: "Oh... it was just a dream...",
                                    audioUrl: "alien_p6_s4",
                                    words: [
                                        Word(id: "a77", text: "Oh...", meaning: "Oh (interjection)", baseForm: "oh", startTimeMs: 99, endTimeMs: 819),
                                        Word(id: "a78", text: "solo", meaning: "only, just", baseForm: "solo", startTimeMs: 919, endTimeMs: 1200),
                                        Word(id: "a79", text: "era", meaning: "it was (ser imperfect)", baseForm: "ser", startTimeMs: 1199, endTimeMs: 1320),
                                        Word(id: "a80", text: "un", meaning: "a", baseForm: "un", startTimeMs: 1319, endTimeMs: 1499),
                                        Word(id: "a81", text: "sueño...", meaning: "dream", baseForm: "sueño", startTimeMs: 1519, endTimeMs: 1899)
                                    ]
                                )
                            ]
                        )
                    ]
                )
            ]
        )
    ]

    static let alienReviewWords: [ReviewWord] = [
        ReviewWord(
            word: Word(id: "a4", text: "noche", meaning: "night", baseForm: "noche"),
            panelId: "alien-panel-1-1",
            pageId: "alien-page-1"
        ),
        ReviewWord(
            word: Word(id: "a5", text: "qué", meaning: "what", baseForm: "qué"),
            panelId: "alien-panel-1-2",
            pageId: "alien-page-1"
        ),
        ReviewWord(
            word: Word(id: "a9", text: "quién", meaning: "who", baseForm: "quién"),
            panelId: "alien-panel-2-2",
            pageId: "alien-page-2"
        ),
        ReviewWord(
            word: Word(id: "a12", text: "me llamo", meaning: "my name is / I call myself", baseForm: "llamarse", audioUrl: "phrase_me_llamo"),
            panelId: "alien-panel-2-3",
            pageId: "alien-page-2"
        ),
        ReviewWord(
            word: Word(id: "a21", text: "bien", meaning: "good, well", baseForm: "bien"),
            panelId: "alien-panel-3-1",
            pageId: "alien-page-3"
        ),
        ReviewWord(
            word: Word(id: "a23", text: "tengo", meaning: "I have", baseForm: "tener"),
            panelId: "alien-panel-3-2",
            pageId: "alien-page-3"
        ),
        ReviewWord(
            word: Word(id: "a26", text: "dónde", meaning: "where", baseForm: "dónde"),
            panelId: "alien-panel-3-3",
            pageId: "alien-page-3"
        ),
        ReviewWord(
            word: Word(id: "a51", text: "hablo", meaning: "I speak", baseForm: "hablar"),
            panelId: "alien-panel-5-3",
            pageId: "alien-page-5"
        ),
        ReviewWord(
            word: Word(id: "a67", text: "la casa", meaning: "the house", baseForm: "casa", audioUrl: "phrase_la_casa"),
            panelId: "alien-panel-5-4",
            pageId: "alien-page-5"
        )
    ]
}
