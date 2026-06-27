# Handoff: Comic Reader — Visual Refresh

## Overview
A visual + light structural refresh of the **Comic Reader** SwiftUI app (Spanish-learning-through-comics). The goal is a cleaner, playful-but-modern look aimed at adult learners, applied consistently across every screen. The information architecture and core reading model are unchanged; this is mostly a design-system pass plus two structural fixes (merge Library/Store, reorganize the practice menu).

## About the Design Files
The file in this bundle — `Comic Reader Refresh.dc.html` — is a **design reference built in HTML**, not production code. It is an interactive prototype showing the intended look, layout, and behavior. **Do not port the HTML directly.** Your task is to **recreate these designs in the existing SwiftUI codebase** (the `ComicReader` Xcode project), using its established views, navigation, and state objects (`SettingsManager`, `ReadingProgressManager`, `LocalComicStorage`, `ComicStoreService`, etc.).

A second file, `Palette Comparison (Coral vs Indigo).dc.html`, shows the two accent options that were considered. **Indigo was chosen** — Coral is included only for reference.

## Fidelity
**High-fidelity.** Colors, typography, spacing, corner radii, and interactions are final and intentional. Recreate the UI faithfully in SwiftUI. The one exception is imagery: all comic covers and page art in the prototype are **placeholders** — the real artwork (your `ComicImage` / downloaded assets) drops into those slots unchanged.

---

## Design Tokens

### Color — Accent (the single brand color; use ONLY for primary actions)
| Token | Hex | Use |
|---|---|---|
| `accent` | `#5B5BD6` | Primary buttons, Continue/Play/Download, active tab, selected chips, progress fill, tappable-word underline, active toggle |
| `accentPressed` | `#4A48C0` | Pressed/active state of accent buttons |
| `accentTint` | `#ECECFB` | Soft accent backgrounds: practice-row icon chips, "Explain grammar" pill, secondary practice buttons |

> **Critical rule:** accent is reserved for actions. Do **not** use it for comic levels, status, or decoration. This removes the old "green means five different things" collision.

### Color — Neutrals (warm-toned)
| Token | Hex | Use |
|---|---|---|
| `bgGrouped` | `#F4F1ED` | Screen background (grouped) |
| `surface` | `#FFFFFF` | Cards, rows, sheets |
| `surfaceAlt` | `#F1EEEA` | Secondary chips / inactive segment background |
| `readerBg` | `#0B0B0C` | Reader (immersive) background |
| `textPrimary` | `#1F1B18` | Titles, primary text |
| `textSecondary` | `#6B635C` / `#756E67` | Body, descriptions |
| `textTertiary` | `#A39C94` | Metadata, captions, placeholders |
| `hairline` | `#F0ECE6` / `#EDE8E1` | Dividers, row separators, tab-bar top border |
| `progressTrack` | `#EAE5DE` | Empty progress-bar track |

### Color — Level meter (NON-judgmental; replaces traffic-light green/orange/red)
A comic's level is shown as **three dots**, the first *N* filled. Same graphite color regardless of level — difficulty is conveyed by *how many* dots are filled, not by color.
- Filled dot: `#6E675F`
- Empty dot: `#E0DAD2`
- On dark covers (Detail header): filled `#FFFFFF`, empty `rgba(255,255,255,0.4)`
- Mapping: Beginner = ●○○, Intermediate = ●●○, Advanced = ●●●

### Color — Vocabulary review states (semantic; always shown WITH a legend)
| State | Hex | Label |
|---|---|---|
| New | `#7C8595` | "New" |
| Learning | `#D98A2B` | "Learning" |
| Mastered | `#2E9E6B` | "Mastered" |

### Color — Correctness (only in practice/quiz feedback)
- Correct: `#2E9E6B` · Incorrect: `#D6453C`

### Typography
- **Display face** (titles, comic names, big numbers, section headers, button labels): **SF Pro Rounded** — i.e. `Font.system(.title, design: .rounded)` in SwiftUI. The prototype uses Nunito as a web stand-in; **use SF Pro Rounded natively**, do not bundle Nunito.
- **Body / UI text**: SF Pro (system default) — `Font.system(...)` with default design.

| Role | Size / Weight | Notes |
|---|---|---|
| Screen title (Library/Store/etc.) | 31, Heavy (800), rounded | letter-spacing ≈ −0.02em |
| Comic title (detail header, over art) | 27, Heavy, rounded, white |
| Card title (list rows) | 16, Bold (700), rounded |
| Hero "Continue" comic title | 18, Bold, rounded |
| Section label (eyebrow) | 12, Bold, uppercase, tracking 0.04em, tertiary |
| Body / description | 13–15, Regular |
| Metadata / caption | 11.5–12.5, Regular/Medium, tertiary |
| Tappable word (reader) | 21, Bold, rounded |
| Button label | 14–16, Bold, rounded |

### Spacing, Radius, Shadow
- Screen horizontal padding: **18px** (16px on Detail/Reader)
- Card padding: **11–13px**; section gaps: **16–24px**; list item gap: **11px**
- Corner radius: cards **16**, large cards/hero **18–20**, cover thumbnails **9–11**, detail cover banner **18**, buttons **14**, pills **999**, reader bubble card **22**, segment buttons **9**
- Card shadow: `0 1px 3px rgba(31,27,24,0.06)`; hero/elevated: `0 4px 16px rgba(31,27,24,0.08)`; accent button: `0 8px 18px rgba(91,91,214,0.28)`; cover thumb: `0 3px 8px rgba(0,0,0,0.2)`

---

## Screens / Views

### 1. Library (`LibraryView`) — **now the full catalogue**
**Purpose:** Browse every comic. Some are downloaded (open to read), some are not (download inline). This **replaces the separate Library + Store tabs** — there is now one Library.

**Layout:** Vertical scroll. (a) Large rounded title "Library" with a search icon button at trailing; subtitle "Your comics — ready to read or download". (b) **Continue-reading hero card** (only when a comic is in progress): cover 80×112, eyebrow "CONTINUE READING" in accent, title, "Page X of Y", accent progress bar, accent "Continue" pill → opens Reader. (c) **Level filter chips** (All / Beginner / Intermediate / Advanced) — selected chip = accent bg + white text; others = white bg + secondary text. (d) **Comic list**, one card each:
- Cover thumb 64×90 (rounded 9). For not-downloaded comics, dim the cover with `rgba(10,10,12,0.4)` overlay.
- Title (16 bold rounded) + a trailing chevron **only if downloaded**.
- 2-line description.
- Meta row: level dot-meter + level name + "· N pages" (downloaded) or "Np · {size}" (not downloaded).
- Trailing state, by download status:
  - **reading** (downloaded, in progress): thin accent progress bar.
  - **downloaded** (not started): nothing extra (chevron signals it opens).
  - **download** (not downloaded): accent-tint "Download" pill (download glyph + "Download").
  - **downloading**: thin accent progress bar + "Downloading… NN%".
- Tap a **downloaded** card → Comic Detail. Non-downloaded cards' primary action is Download.

**Maps to existing code:** merge `StoreView`'s catalog/download logic into the `LibraryView` list; each row decides Open vs Download from `LocalComicStorage` / `ComicStoreService.downloadState(for:)`. Remove the Store tab from `ContentView`'s `TabView`.

### 2. Vocabulary (`VocabularyView`)
**Purpose:** Review saved words. **Layout:** Title; a **legend row** (New / Learning / Mastered with colored dots — this documents the previously-unlabeled state dots); filter chips (All/New/Learning/Mastered); a white card containing word rows. Each row: state dot + word (17 bold rounded), meaning (13 secondary), optional "base · {form}" (11.5 tertiary); trailing a circular "context" button (`surfaceAlt` bg) and a circular "play audio" button (accent-tint bg, accent icon). Keep swipe-to-delete.

### 3. Settings (`SettingsView`)
**Purpose:** Preferences. **Layout:** Title; grouped white cards with section eyebrows: **Reading** (**Speaking practice** toggle — subtitle "Turn off if you'd rather not speak out loud"; Auto-play audio toggle; Haptic feedback toggle; Playback-speed segmented control 0.5×–1.5×), **Account** (Profile, Subscription — chevron rows), **About** (Help, Terms — chevron rows), centered "Version 1.0.0". Toggles use accent when on (`#5B5BD6` track, white knob right) / `#D8D2CA` when off. Selected speed segment = accent bg + white; others = `surfaceAlt`.

> The **Speaking practice** toggle here is the SAME preference exposed inline on the Comic Detail Practice section (see #5). It maps to the existing "I don't want to speak" setting. Persist via `SettingsManager`; both surfaces read/write the one value.

### 4. Comic Detail (`ComicDetailView`)
**Purpose:** Comic landing — read, restart, or practice. **Layout:** Back ("‹ Library", accent) + overflow nav; **cinematic cover banner** (208px tall, rounded 18, comic art with bottom dark gradient): level dot-meter pill (dark translucent) top-left, title (27 heavy rounded white) + "by {author} · N pages" bottom-left, monospace "YOUR COVER ART" placeholder note top-right (remove when real art is in). Then: actions row — **"Continue reading"** (accent, flex) + **"Restart"** (white). Description paragraph. **Practice section** (see below). **Pages** 2-column grid of page thumbnails (rounded 10, "p.N" monospace label).

### 5. Practice section + flow — **reorganized around On-screen / Off-screen + the speaking preference**
**Purpose:** Replaces the overloaded graduation-cap toolbar menu. The app's real model is two practice modes distinguished by whether the screen is used, plus a global "don't want to speak" preference. This section surfaces them clearly on **Comic Detail**.

**The model (this is the important part — get the logic exactly right):**
- **On screen** = text stays visible; learner reads along AND speaks each line back. (Inherently a speaking mode.)
- **Off screen** = audio only, no text; learner listens and speaks back.
- **Speaking preference** (the existing "I don't want to speak"): when speaking is OFF, the **On-screen mode is removed entirely**, and the **Off-screen mode collapses to listen-only** (no speaking back).

**Layout — "Practice" section on Comic Detail:**
1. A **"Speaking exercises" toggle row** at the top of the section (white card: title + dynamic subtitle + accent switch). This is the same preference as the Settings "Speaking practice" toggle — one stored value, two surfaces. Subtitle reads "Repeat lines aloud and get pronunciation feedback." when ON, "Off — practice is listen-only." when OFF.
2. **Mode cards** (large: 44px accent-tint icon chip + title 16 heavy rounded + small uppercase accent tag + 2-line description):
   - **Speaking ON → two cards:**
     - **Read & speak** · tag **On screen** — "The text stays on screen. Read each line, hear it, and say it back." → opens the **Reader** (text visible).
     - **Listen & speak** · tag **Off screen** — "Screen off, eyes free. Hear each line, repeat it, say what it means." → opens the **audio practice run** (speaking variant).
   - **Speaking OFF → one card + a note:**
     - **Just listen** · tag **Off screen** — "Screen off, eyes free. Hear each line and its meaning — no speaking." → opens the **audio practice run** (listen-only variant).
     - Below it, an info note (ⓘ tertiary): "Speaking is off, so the on-screen read-and-speak mode is hidden. Turn speaking on to practise saying lines aloud." — so a vanished mode never feels like a bug.
3. **Drill the key words** card (neutral icon chip) always present; subtitle is "Writing · Speaking · Listening" when speaking ON, "Writing · Listening" when OFF.

> Naming: "On screen / Off screen" appear as small UPPERCASE tags, not headlines, so the action-based titles stay self-explanatory while preserving your terminology.

**Practice run screen** — a **standardized template** that adapts to the speaking/listen-only variant. All audio practice modes share it:
- **Start:** accent-tint circle (mic icon for speaking / headphones icon for listen-only), comic title, "8 sentences", instructions (speaking: "Listen to each sentence, repeat it aloud, then say what it means in English." / listen-only: "Sit back and listen to each sentence, then reveal its meaning — no speaking needed."), accent "▶ Start" button.
- **Active:** top progress bar + "Sentence X of N"; animated accent waveform bars; large pulsing accent circle.
  - *Speaking:* mic icon, status "Listening… / Repeat the sentence you just heard".
  - *Listen-only:* headphones icon, status "Playing… / Listen, then reveal the meaning", plus a "Show meaning" pill (accent-tint).
  - pause + skip controls.
- **Complete (standardized celebration):** accent-tint trophy circle, "Practice complete!", per-metric score cards — *speaking* shows **Pronunciation** (7/8) + **Comprehension** (6/8) and "81% overall"; *listen-only* shows **Comprehension** only (7/8) and "88% overall" (no pronunciation metric). Big accent "NN% overall", "Try again" (accent) + "Done" (white). **Use this same completion screen across all practice/quiz views.**

**Maps to existing code:** fold the old practice-mode toggles into the single speaking preference on `SettingsManager`; the On-screen mode routes into the existing reader path; the Off-screen modes route into the audio practice flow with a `speakingEnabled` flag that drives the mic-vs-headphones UI and whether a pronunciation score is collected.

### 6. Reader (`PageView` + bubble card)
**Purpose:** Read a page, tap bubbles for word/translation/grammar/audio. **Layout:** Immersive `#0B0B0C` background, light status bar; top bar = home/back + "p. X / N" (centered) + overflow; the comic page art centered; tap-target hotspots shown as pulsing accent rings. The **floating bubble card** docks at the bottom (rounded 22, frosted `rgba(252,250,248,0.97)`): header with ‹ ›, "N of M", ✕; tappable Spanish words (21 bold rounded, dotted accent underline); **unified reveal actions** — "Show translation" (neutral pill) and "Explain grammar" (accent-tint pill); audio row with accent **Play** pill + speed pill.

**Convergence note:** the old codebase has **two** reading implementations — `FloatingBubbleCard` (normal reading) and `PanelView` (practice modes), with duplicated bubble-content logic. Converge them onto one shared bubble-content view so reveal styling/behavior is identical everywhere.

### Tab bar (`ContentView`)
Now **three** tabs: **Library · Vocabulary · Settings** (Store removed — folded into Library). Active tab = accent; inactive = `#A8A199`. Labels in rounded font, 10.5px bold.

---

## Interactions & Behavior
- **Navigation:** Library → tap downloaded comic → Detail → "Continue reading" → Reader. Detail → Practice row → Practice run. Standard push/back; Reader & Practice run are full-screen (no tab bar).
- **Reader bubble card:** ‹ › steps through the page's text bubbles (resets translation/grammar reveal on step); ✕ closes; words are tappable (open meaning/audio/save — existing behavior); "Show translation" and "Explain grammar" toggle their content.
- **Library download:** "Download" starts a download (drive from `ComicStoreService`); show the `downloading` progress state, then the card becomes openable.
- **Filters:** Library level chips and Vocabulary state chips filter their lists in place.
- **Toggles/speed:** persist via `SettingsManager` (existing).
- **Animations:** mic pulse ~1.4s ease-in-out; waveform bars ~1s staggered; hotspot rings expand-and-fade ~1.9s; toggle knob/track 0.2s.

## State Management
Reuse existing observable objects — no new architecture:
- `SettingsManager` (autoPlayAudio, hapticFeedback, playbackSpeed, practice-mode toggles)
- `ReadingProgressManager` (per-comic progress → hero card, "Continue", progress bars, current-page marker)
- `LocalComicStorage` (downloaded comics → Library "owned" state)
- `ComicStoreService` (catalog + `downloadState(for:)` → Library "download/downloading" state)
- Local view state: selected comic, current bubble index, translation/grammar revealed sets, practice step, filter selections.

## Assets
- **None to copy.** All covers/page art in the prototype are placeholders; use the app's real `ComicImage` / downloaded artwork.
- **Icons:** the prototype draws simple inline SVGs (tab icons, chevrons, play, mic, download, eye, etc.). In SwiftUI, replace each with the nearest **SF Symbol** (e.g. `books.vertical`, `bookmark.fill`, `gearshape`/sliders, `chevron.right`, `play.fill`, `mic.fill`, `arrow.down.circle`, `eye`, `headphones`, `trophy.fill`). Match the rounded, medium-weight look.
- **Fonts:** SF Pro + SF Pro Rounded are system — nothing to bundle.

## Files
- `Comic Reader Refresh.dc.html` — the full hi-fi prototype (all 7 screens, navigable). Primary reference.
- `Palette Comparison (Coral vs Indigo).dc.html` — accent-option comparison (Indigo chosen).
- Target codebase screens to edit: `ContentView.swift` (tabs), `LibraryView.swift` (+ merge `StoreView.swift`), `ComicDetailView.swift` (practice section), `PageView.swift` (reader + bubble card), `VocabularyView.swift`, `SettingsView.swift`, and the practice views (`QuizView`, `SpeakingTestView`, `ListeningTestView`, `RepeatPracticeView`, etc.) for the standardized completion screen.
