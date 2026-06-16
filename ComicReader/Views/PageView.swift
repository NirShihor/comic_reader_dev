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
    @StateObject private var help = HelpModeController()

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
                                                withAnimation {
                                                    selectedPanel = panel
                                                }
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

            // Help hints over the page (help mode only, while no panel is open)
            if selectedPanel == nil {
                VStack(spacing: 10) {
                    Spacer()
                    HelpHint(icon: "hand.tap.fill", label: "Tap a panel",
                             title: "Open a panel",
                             text: "Tap any panel on the page to open it and read the dialogue.")
                    HelpHint(icon: "arrow.left.and.right", label: "Swipe",
                             title: "Turn the page",
                             text: "Swipe left or right anywhere on the page — or use the arrows at the top — to move between pages.",
                             animatedSwipe: true)
                }
                .padding(.bottom, 60)
            }

            // Panel view overlay — presented on top of the page instead of as a sheet
            // to avoid iOS sheet presentation scaling the underlying page view
            if let panel = selectedPanel {
                PanelView(
                    comic: comic,
                    page: currentPage,
                    panel: panel,
                    hotspots: currentPage.hotspots ?? [],
                    navigateToPage: $navigateToPage,
                    dismissPanel: {
                        // Remove the overlay without animation — an interrupted
                        // removal transition can leave the page layout stuck
                        var transaction = Transaction()
                        transaction.disablesAnimations = true
                        withTransaction(transaction) {
                            selectedPanel = nil
                        }
                    },
                    dismissToHome: {
                        dismiss()
                    }
                )
                .environmentObject(settingsManager)
                .transition(.move(edge: .bottom))
                .zIndex(1)
            }

        }
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            // Only show the page controls while the panel overlay is closed —
            // the panel's own toolbar items (home/Done/panel nav) render into
            // the same bar, so showing both sets duplicates the buttons
            if selectedPanel == nil {
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
                            withAnimation(.easeInOut(duration: 0.2)) { help.toggle() }
                        } label: {
                            Image(systemName: help.isActive ? "questionmark.circle.fill" : "questionmark.circle")
                                .foregroundStyle(.white)
                        }
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
        }
        .helpTooltipLayer()
        .environmentObject(help)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbarBackground(.visible, for: .tabBar)
        .toolbarColorScheme(.light, for: .tabBar)
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
            // Cross-page navigation from the panel view: close the overlay and
            // swap the page in a single transaction with animations disabled.
            // Running the overlay's removal transition and the page change as
            // concurrent animations can wedge the layout mid-flight, leaving
            // the page rendered small and unresponsive.
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                selectedPanel = nil
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
        .background(DisableInteractivePopGesture())
    }
}

// Disables the enclosing UINavigationController's interactive pop (edge swipe-back)
// gesture while this view is on screen, restoring it when the view goes away.
// A rightward swipe (e.g. "previous panel/page") can otherwise be captured by the
// swipe-back recognizer, starting an interactive pop that gets cancelled mid-flight
// and leaves the view stuck small and unresponsive.
struct DisableInteractivePopGesture: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> Controller { Controller() }
    func updateUIViewController(_ uiViewController: Controller, context: Context) {}

    final class Controller: UIViewController {
        private weak var navController: UINavigationController?
        private var previousState = true

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            // Walk the responder chain to find the enclosing navigation controller
            var responder: UIResponder? = view
            while let current = responder {
                if let nav = current as? UINavigationController {
                    navController = nav
                    break
                }
                if let vc = current as? UIViewController, let nav = vc.navigationController {
                    navController = nav
                    break
                }
                responder = current.next
            }
            if let gesture = navController?.interactivePopGestureRecognizer {
                previousState = gesture.isEnabled
                gesture.isEnabled = false
            }
        }

        override func viewWillDisappear(_ animated: Bool) {
            super.viewWillDisappear(animated)
            navController?.interactivePopGestureRecognizer?.isEnabled = previousState
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
