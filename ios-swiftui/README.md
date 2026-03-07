# Comic Reader - SwiftUI Version

Native iOS app built with SwiftUI, designed to follow Apple's Human Interface Guidelines for potential App Store featuring.

## Setup Instructions

### Creating the Xcode Project

Since the Swift source files are already created, you need to create an Xcode project to contain them:

1. **Open Xcode** (15.0 or later recommended)

2. **Create a new project:**
   - File → New → Project
   - Choose "App" under iOS
   - Click Next

3. **Configure the project:**
   - Product Name: `ComicReader`
   - Team: Select your Apple Developer team
   - Organization Identifier: `com.yourname` (or your preferred identifier)
   - Interface: **SwiftUI**
   - Language: **Swift**
   - Storage: None
   - Uncheck "Include Tests" for now
   - Click Next

4. **Save location:**
   - Navigate to `comic-reader/ios-swiftui/`
   - Save the project there (it will create ComicReader.xcodeproj)

5. **Add existing Swift files:**
   - In Xcode, right-click on the ComicReader folder in the navigator
   - Select "Add Files to 'ComicReader'..."
   - Navigate to `ios-swiftui/ComicReader/ComicReader/`
   - Select all `.swift` files and the `Assets.xcassets` folder
   - Make sure "Copy items if needed" is **unchecked**
   - Make sure "Create groups" is selected
   - Click Add

6. **Delete the auto-generated files:**
   - Delete the auto-generated `ContentView.swift` and `ComicReaderApp.swift` (the ones Xcode created)
   - Keep the ones you added from the existing files

7. **Add comic assets:**
   - Copy images from `assets/comics/` into `Assets.xcassets`
   - Or reference them via a shared folder

### Project Structure

```
ComicReader/
├── ComicReaderApp.swift      # App entry point
├── ContentView.swift         # Main tab navigation
├── Models/
│   ├── Comic.swift           # Data models
│   └── ComicData.swift       # Sample comic data
├── Views/
│   ├── LibraryView.swift     # Comic library grid
│   ├── ComicDetailView.swift # Comic details & pages
│   ├── ReaderView.swift      # Full-screen reader
│   ├── PageView.swift        # Individual page view
│   ├── PanelView.swift       # Panel detail with text
│   ├── QuizView.swift        # Vocabulary quiz
│   ├── SettingsView.swift    # App settings
│   └── VocabularyView.swift  # Saved vocabulary
├── Services/
│   ├── SettingsManager.swift       # Settings persistence
│   ├── ReadingProgressManager.swift # Reading progress
│   └── VocabularyManager.swift     # Saved words
└── Assets.xcassets/          # Images & colors
```

### Features Implemented

- [x] Library view with comic cards
- [x] Comic detail view with page grid
- [x] Full-screen reader with panel tap zones
- [x] Panel view with word-by-word text
- [x] Speaking Practice Mode (English text display)
- [x] Vocabulary quiz
- [x] Settings with toggles
- [x] Reading progress persistence
- [x] Vocabulary saving

### TODO

- [ ] Audio playback integration (AVFoundation)
- [ ] Speech recognition (Speech framework)
- [ ] Whisper API integration for pronunciation checking
- [ ] Asset migration from React Native app
- [ ] App icon design
- [ ] iPad layout optimization
- [ ] Widgets / Live Activities
- [ ] Accessibility improvements

### Apple Design Guidelines

This app is built to follow Apple's Human Interface Guidelines:

- Uses SF Symbols throughout
- Native iOS navigation patterns
- System colors and materials
- Haptic feedback
- Native list and form styles
- Proper safe area handling
