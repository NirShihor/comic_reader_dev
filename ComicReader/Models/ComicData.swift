import Foundation

/// Static comic data for SwiftUI previews only
enum ComicData {
    static let allComics: [Comic] = [sampleComic]

    static let sampleComic = Comic(
        id: "preview-comic",
        title: "Sample Comic",
        description: "A sample comic for previews.",
        coverImage: "sample_cover",
        level: .beginner,
        isPremium: false,
        pages: [
            Page(
                id: "preview-page-1",
                pageNumber: 1,
                masterImage: "sample_cover",
                panels: [
                    Panel(
                        id: "preview-panel-1",
                        artworkImage: "sample_cover",
                        noTextImage: nil,
                        floating: false,
                        corners: nil,
                        panelOrder: 1,
                        tapZoneX: 0,
                        tapZoneY: 0,
                        tapZoneWidth: 1,
                        tapZoneHeight: 1,
                        bubbles: [
                            Bubble(
                                id: "preview-bubble-1",
                                type: .speech,
                                positionX: 0.1,
                                positionY: 0.1,
                                width: 0.8,
                                height: 0.15,
                                sentences: [
                                    Sentence(
                                        id: "preview-sentence-1",
                                        text: "¡Hola!",
                                        translation: "Hello!",
                                        words: [
                                            Word(id: "preview-word-1", text: "¡Hola!", meaning: "Hello!", baseForm: "hola")
                                        ]
                                    )
                                ]
                            )
                        ]
                    )
                ]
            )
        ],
        reviewWords: [
            ReviewWord(
                word: Word(id: "preview-word-1", text: "¡Hola!", meaning: "Hello!", baseForm: "hola"),
                panelId: "preview-panel-1",
                pageId: "preview-page-1"
            )
        ]
    )
}
