import SwiftUI

struct ReaderView: View {
    let comic: Comic
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var settingsManager: SettingsManager
    @EnvironmentObject var progressManager: ReadingProgressManager

    @State private var currentPageIndex: Int = 0
    @State private var selectedPanel: Panel?
    @State private var showControls = true
    @State private var textRevealed = false
    @State private var navigateToPage: Int?
    @State private var showingVocabulary = false
    @State private var showingSettings = false

    var currentPage: Page {
        comic.pages[currentPageIndex]
    }

    var body: some View {
        NavigationStack {
            ZStack {
                // Background
                Color.black.ignoresSafeArea()

                // Page image with tap zones
                GeometryReader { geometry in
                    ZStack {
                        // Comic page image - tap to toggle controls
                        pageImage(in: geometry.size)
                            .onTapGesture {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    showControls.toggle()
                                }
                            }

                        // Panel tap zones (invisible, on top)
                        ForEach(currentPage.panels) { panel in
                            panelTapZone(panel: panel, in: geometry.size)
                        }
                    }
                }

                // Navigation overlay
                if showControls {
                    controlsOverlay
                }
            }
            .navigationBarHidden(true)
            .statusBarHidden(!showControls)
            .sheet(item: $selectedPanel) { panel in
                PanelView(comic: comic, page: currentPage, panel: panel, navigateToPage: $navigateToPage)
                    .environmentObject(settingsManager)
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
            .onChange(of: navigateToPage) { _, newPageIndex in
                guard let newPageIndex = newPageIndex else { return }
                withAnimation {
                    currentPageIndex = newPageIndex
                    textRevealed = false
                }
                navigateToPage = nil
            }
        }
        .onAppear {
            // Resume from saved progress or start at beginning
            if let progress = progressManager.getProgress(for: comic.id),
               let index = comic.pages.firstIndex(where: { $0.pageNumber == progress.pageNumber }) {
                currentPageIndex = index
            } else {
                currentPageIndex = 0
            }
        }
        .onChange(of: currentPageIndex) { _, newIndex in
            progressManager.saveProgress(
                comicId: comic.id,
                pageNumber: comic.pages[newIndex].pageNumber,
                panelNumber: 0
            )
            textRevealed = false
        }
    }

    // MARK: - Page Image
    @ViewBuilder
    private func pageImage(in size: CGSize) -> some View {
        let imageName = settingsManager.speakingPracticeMode && !textRevealed
            ? (currentPage.noTextImage ?? currentPage.masterImage)
            : currentPage.masterImage

        ComicImage(imageName: imageName, comicId: comic.id)
            .aspectRatio(contentMode: .fit)
            .frame(width: size.width, height: size.height)
            .onTapGesture {
                if settingsManager.speakingPracticeMode {
                    withAnimation {
                        textRevealed.toggle()
                    }
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                }
            }

    }

    // MARK: - Panel Tap Zone
    private func panelTapZone(panel: Panel, in size: CGSize) -> some View {
        Rectangle()
            .fill(Color.white.opacity(0.001)) // Nearly invisible but tappable
            .frame(
                width: panel.tapZoneWidth * size.width,
                height: panel.tapZoneHeight * size.height
            )
            .contentShape(Rectangle()) // Makes entire area tappable
            .position(
                x: (panel.tapZoneX + panel.tapZoneWidth / 2) * size.width,
                y: (panel.tapZoneY + panel.tapZoneHeight / 2) * size.height
            )
            .onTapGesture {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                selectedPanel = panel
            }
    }

    // MARK: - Controls Overlay
    private var controlsOverlay: some View {
        VStack {
            // Top bar
            HStack {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.title3)
                        .fontWeight(.medium)
                        .foregroundStyle(.white)
                        .frame(width: 40, height: 40)
                        .background(.ultraThinMaterial)
                        .clipShape(Circle())
                }

                Spacer()

                // Page indicator with navigation
                HStack(spacing: 4) {
                    Button {
                        goToPreviousPage()
                    } label: {
                        Image(systemName: "chevron.left")
                            .foregroundStyle(currentPageIndex > 0 ? .white : .gray)
                    }
                    .disabled(currentPageIndex == 0)

                    Text("\(currentPageIndex + 1)/\(comic.pages.count)")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)

                    Button {
                        goToNextPage()
                    } label: {
                        Image(systemName: "chevron.right")
                            .foregroundStyle(currentPageIndex < comic.pages.count - 1 ? .white : .gray)
                    }
                    .disabled(currentPageIndex == comic.pages.count - 1)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial)
                .clipShape(Capsule())

                Spacer()

                // Settings/Vocabulary buttons
                HStack(spacing: 8) {
                    Button {
                        showingVocabulary = true
                    } label: {
                        Image(systemName: "bookmark.fill")
                            .font(.title3)
                            .foregroundStyle(.white)
                            .frame(width: 40, height: 40)
                            .background(.ultraThinMaterial)
                            .clipShape(Circle())
                    }

                    Button {
                        showingSettings = true
                    } label: {
                        Image(systemName: "gear")
                            .font(.title3)
                            .foregroundStyle(.white)
                            .frame(width: 40, height: 40)
                            .background(.ultraThinMaterial)
                            .clipShape(Circle())
                    }
                }
            }
            .padding()
            .padding(.top, 44) // Safe area

            Spacer()
        }
    }

    // MARK: - Navigation
    private func goToNextPage() {
        guard currentPageIndex < comic.pages.count - 1 else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        withAnimation {
            currentPageIndex += 1
        }
    }

    private func goToPreviousPage() {
        guard currentPageIndex > 0 else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        withAnimation {
            currentPageIndex -= 1
        }
    }
}

#Preview {
    ReaderView(comic: ComicData.allComics[0])
        .environmentObject(SettingsManager())
        .environmentObject(ReadingProgressManager())
}
