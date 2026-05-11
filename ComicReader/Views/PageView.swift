import SwiftUI

struct PageView: View {
    let comic: Comic
    let page: Page
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var settingsManager: SettingsManager
    @EnvironmentObject var progressManager: ReadingProgressManager

    @State private var textRevealed = false
    @State private var selectedPanel: Panel?
    @State private var currentPageIndex: Int
    @State private var navigateToPage: Int?
    @State private var showingVocabulary = false
    @State private var showingSettings = false
    @State private var showDebugZones = false
    @State private var showEndOfEpisode = false

    // Pages sorted by pageNumber for consistent navigation
    private var sortedPages: [Page] {
        comic.pages.sorted { $0.pageNumber < $1.pageNumber }
    }

    init(comic: Comic, page: Page) {
        self.comic = comic
        self.page = page
        // Initialize currentPageIndex to the correct page in sorted order
        let sorted = comic.pages.sorted { $0.pageNumber < $1.pageNumber }
        let index = sorted.firstIndex(where: { $0.id == page.id }) ?? 0
        _currentPageIndex = State(initialValue: index)
    }

    var currentPage: Page {
        sortedPages[currentPageIndex]
    }

    private func goToNextPage() {
        guard currentPageIndex < sortedPages.count - 1 else {
            showEndOfEpisode = true
            return
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        withAnimation {
            currentPageIndex += 1
            textRevealed = false
        }
    }

    private func goToPreviousPage() {
        guard currentPageIndex > 0 else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        withAnimation {
            currentPageIndex -= 1
            textRevealed = false
        }
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            GeometryReader { geometry in
                // Page image
                let imageName = settingsManager.speakingPracticeMode && !textRevealed
                    ? (currentPage.noTextImage ?? currentPage.masterImage)
                    : currentPage.masterImage

                ComicImage(imageName: imageName, comicId: comic.id)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .overlay {
                        // Panel tap overlay - coordinates are relative to the image
                        GeometryReader { imageGeometry in
                            ZStack {
                                // Debug: Show tap zones when enabled (triple-tap to toggle)
                                if showDebugZones {
                                    ForEach(currentPage.panels.sorted { $0.panelOrder < $1.panelOrder }) { panel in
                                        Rectangle()
                                            .stroke(Color.red, lineWidth: 2)
                                            .background(Color.blue.opacity(0.2))
                                            .frame(
                                                width: panel.tapZoneWidth * imageGeometry.size.width,
                                                height: panel.tapZoneHeight * imageGeometry.size.height
                                            )
                                            .overlay {
                                                Text("P\(panel.panelOrder)")
                                                    .font(.title)
                                                    .foregroundColor(.white)
                                                    .shadow(radius: 2)
                                            }
                                            .position(
                                                x: (panel.tapZoneX + panel.tapZoneWidth / 2) * imageGeometry.size.width,
                                                y: (panel.tapZoneY + panel.tapZoneHeight / 2) * imageGeometry.size.height
                                            )
                                    }
                                }

                                // Tap handler
                                Color.clear
                                    .contentShape(Rectangle())
                                    .onTapGesture(count: 3) {
                                        // Triple-tap to toggle debug zones
                                        withAnimation {
                                            showDebugZones.toggle()
                                        }
                                    }
                                    .onTapGesture { location in
                                        // Convert tap location to normalized coordinates (0-1)
                                        let normalizedX = location.x / imageGeometry.size.width
                                        let normalizedY = location.y / imageGeometry.size.height

                                        // Find which panel was tapped
                                        // Check floating panels first (they render on top), then non-floating
                                        let floatingPanels = currentPage.panels.filter { $0.floating }.sorted { $0.panelOrder < $1.panelOrder }
                                        let nonFloatingPanels = currentPage.panels.filter { !$0.floating }.sorted { $0.panelOrder < $1.panelOrder }
                                        let allPanelsInTapOrder = floatingPanels + nonFloatingPanels

                                        for panel in allPanelsInTapOrder {
                                            let inXRange = normalizedX >= panel.tapZoneX &&
                                                          normalizedX <= (panel.tapZoneX + panel.tapZoneWidth)
                                            let inYRange = normalizedY >= panel.tapZoneY &&
                                                          normalizedY <= (panel.tapZoneY + panel.tapZoneHeight)
                                            if inXRange && inYRange {
                                                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                                selectedPanel = panel
                                                break
                                            }
                                        }
                                    }
                            }
                        }
                    }
                .gesture(
                    DragGesture(minimumDistance: 50)
                        .onEnded { value in
                            let horizontalDistance = value.translation.width
                            if horizontalDistance > 50 {
                                // Swiped right → previous page
                                goToPreviousPage()
                            } else if horizontalDistance < -50 {
                                // Swiped left → next page
                                goToNextPage()
                            }
                        }
                )
            }

        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "house.fill")
                        .foregroundStyle(.white)
                }
            }
            ToolbarItem(placement: .principal) {
                HStack(spacing: 20) {
                    Button {
                        goToPreviousPage()
                    } label: {
                        Image(systemName: "chevron.left")
                            .foregroundStyle(currentPageIndex > 0 ? .white : .gray)
                    }
                    .disabled(currentPageIndex == 0)

                    Text("\(currentPage.pageNumber) / \(sortedPages.count)")
                        .foregroundStyle(.white)

                    Button {
                        goToNextPage()
                    } label: {
                        Image(systemName: "chevron.right")
                            .foregroundStyle(currentPageIndex < sortedPages.count - 1 ? .white : .gray)
                    }
                    .disabled(currentPageIndex >= sortedPages.count - 1)
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 12) {
                    Button {
                        showingVocabulary = true
                    } label: {
                        Image(systemName: "bookmark.fill")
                            .foregroundStyle(.white)
                    }
                    Button {
                        showingSettings = true
                    } label: {
                        Image(systemName: "gear")
                            .foregroundStyle(.white)
                    }
                }
            }
        }
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbarBackground(.visible, for: .tabBar)
        .toolbarColorScheme(.light, for: .tabBar)
        .sheet(item: $selectedPanel) { panel in
            PanelView(
                comic: comic,
                page: currentPage,
                panel: panel,
                hotspots: currentPage.hotspots ?? [],
                navigateToPage: $navigateToPage,
                dismissToHome: {
                    dismiss()
                }
            )
            .environmentObject(settingsManager)
        }
        .onAppear {
            // Save progress when view appears
            progressManager.saveProgress(
                comicId: comic.id,
                pageNumber: currentPage.pageNumber,
                panelNumber: 0
            )
        }
        .onChange(of: currentPageIndex) { _, _ in
            // Save progress when page changes
            progressManager.saveProgress(
                comicId: comic.id,
                pageNumber: currentPage.pageNumber,
                panelNumber: 0
            )
        }
        .onChange(of: navigateToPage) { _, newPageIndex in
            guard let newPageIndex = newPageIndex else { return }
            // Navigate to the requested page
            withAnimation {
                currentPageIndex = newPageIndex
                textRevealed = false
            }
            navigateToPage = nil
        }
        .sheet(isPresented: $showingVocabulary) {
            NavigationStack {
                VocabularyView()
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button("Done") {
                                showingVocabulary = false
                            }
                        }
                    }
            }
        }
        .sheet(isPresented: $showingSettings) {
            NavigationStack {
                SettingsView()
                    .environmentObject(settingsManager)
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button("Done") {
                                showingSettings = false
                            }
                        }
                    }
            }
        }
        .alert("End of Episode", isPresented: $showEndOfEpisode) {
            Button("Back to home page") {
                dismiss()
            }
            Button("Stay", role: .cancel) { }
        } message: {
            Text("You've reached the last page of this episode.")
        }
    }
}

#Preview {
    NavigationStack {
        PageView(comic: ComicData.allComics[0], page: ComicData.allComics[0].pages[0])
            .environmentObject(SettingsManager())
            .environmentObject(ReadingProgressManager())
    }
}
