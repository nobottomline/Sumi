import UIKit
import Sumi
import SumiPicker
import SumiAlert  // text-input for the "+ New category" sub-flow

// ChoiceDialogPlaygroundViewController — exercise every flavour
// of the dialog plus the extra-feature combos.

@MainActor
public final class ChoiceDialogPlaygroundViewController: UIViewController {

    private let scroll = PlaygroundScrollView()
    private let stack = UIStackView()
    private let statusLabel = StatusLabel()

    // Live state for the demos so each repeated open shows the
    // last picked value (proves async return is propagating).
    private enum Quality: String { case small, medium, large }
    private var quality: Quality = .large
    private var theme: ThemeID = .system
    private var selectedCategories: Set<CategoryID> = [.action, .romance]
    private var chapterFilters: [ChapterFilter: TriState] = [:]
    /// "Add to library" demo state — typical Mihon-style library
    /// categories. `LibraryCategory.uncategorized` plays the
    /// pseudo-"Default" role: ticking it represents "no
    /// category". A host app can collapse that to `nil` /
    /// empty-set before storing the manga's category mapping.
    private var libraryCategories: Set<LibraryCategory> = [.uncategorized]
    /// 3-category "tiny" demo state.
    private var tinyCategories: Set<TinyCat> = [.favorites]
    /// 100-category "huge" demo state — keyed by Int.
    private var hugeCategories: Set<Int> = []
    /// Live category list for the +New / empty-state demo.
    /// Starts empty so the first open shows the empty state.
    private var dynamicCategories: [String] = []
    private var dynamicSelected: Set<String> = []

    public override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Sumi.Color.surface

        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.alwaysBounceVertical = true
        view.addSubview(scroll)

        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.spacing = Sumi.Spacing.m
        stack.alignment = .fill
        scroll.addSubview(stack)

        view.addSubview(statusLabel)

        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: statusLabel.topAnchor, constant: -Sumi.Spacing.m),
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),

            statusLabel.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: Sumi.Spacing.l),
            statusLabel.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -Sumi.Spacing.l),
            statusLabel.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -Sumi.Spacing.m),

            stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: Sumi.Spacing.l),
            stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -Sumi.Spacing.xxl),
            stack.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor, constant: Sumi.Spacing.l),
            stack.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor, constant: -Sumi.Spacing.l),
            stack.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor, constant: -Sumi.Spacing.l * 2)
        ])

        let hint = UILabel()
        hint.text = "Centered modal dialog with animated radio / checkbox / tri-state indicators. Tap outside to cancel; multi & tri have a Done button."
        hint.font = Sumi.Font.caption()
        hint.textColor = Sumi.Color.textSecondary
        hint.numberOfLines = 0
        stack.addArrangedSubview(hint)
        stack.setCustomSpacing(Sumi.Spacing.xl, after: hint)

        addSection("Single-select")
        addRow("Thumbnail quality (3 choices)") { [weak self] in
            await self?.presentQuality()
        }
        addRow("Theme picker — colour swatch variant") { [weak self] in
            await self?.presentTheme()
        }

        addSection("Multi-select")
        addRow("Categories — counter + Done button") { [weak self] in
            await self?.presentCategories()
        }
        addRow("Languages (25 items) — internal scroll") { [weak self] in
            await self?.presentLanguages()
        }

        addSection("Tri-state")
        addRow("Chapter filter — off / on / negated cycle") { [weak self] in
            await self?.presentChapterFilters()
        }

        addSection("Library flow — recommended pattern")
        addRow("Add to library — 8 categories (typical)") { [weak self] in
            await self?.presentAddToLibrary()
        }
        addRow("Tiny — 3 categories (no scroll)") { [weak self] in
            await self?.presentTinyLibrary()
        }
        addRow("Huge — 100 categories (auto-scroll)") { [weak self] in
            await self?.presentHugeLibrary()
        }
        addRow("With + New category — dynamic flow") { [weak self] in
            await self?.presentDynamicLibraryLoop()
        }
    }

    // MARK: - Demos

    private func presentQuality() async {
        let pick = await ChoiceDialog.presentSingle(
            title: "Thumbnail quality",
            message: "Higher quality uses more bandwidth but looks sharper on retina displays.",
            choices: [
                Choice(value: Quality.small, title: "Small", subtitle: "~50 KB per cover"),
                Choice(value: Quality.medium, title: "Medium", subtitle: "~150 KB per cover", badge: "REC"),
                Choice(value: Quality.large, title: "Large", subtitle: "~400 KB per cover")
            ],
            selected: quality
        )
        if let pick {
            quality = pick
            statusLabel.status = "Quality: \(pick.rawValue)"
        } else {
            statusLabel.status = "Cancelled"
        }
    }

    private func presentTheme() async {
        let pick = await ChoiceDialog.presentSingle(
            title: "App theme",
            message: nil,
            choices: [
                Choice(value: ThemeID.system, title: "System", colorSwatch: .systemGray),
                Choice(value: ThemeID.light, title: "Light", colorSwatch: .systemBackground),
                Choice(value: ThemeID.dark, title: "Dark", colorSwatch: .black),
                Choice(value: ThemeID.crimson, title: "Crimson", subtitle: "Manga-style red", colorSwatch: UIColor(red: 0.85, green: 0.20, blue: 0.30, alpha: 1)),
                Choice(value: ThemeID.midnight, title: "Midnight", subtitle: "Deep blue", colorSwatch: UIColor(red: 0.06, green: 0.10, blue: 0.25, alpha: 1))
            ],
            selected: theme
        )
        if let pick {
            theme = pick
            statusLabel.status = "Theme: \(pick.label)"
        } else {
            statusLabel.status = "Cancelled"
        }
    }

    /// The canonical "Add to library" picker. Same shape Mihon
    /// uses, mapped to ChoiceDialog.presentMulti. Calling site
    /// in a host app might live on a detail screen's
    /// "Add to library" button.
    ///
    ///   • title — "Add to library" reads as the action; the
    ///     manga's own name lives in the message line below.
    ///   • "Uncategorized" sits at the top as a Mihon-compatible
    ///     "Default" pseudo-category. Apps that don't want it
    ///     can just omit it from the choices array.
    ///   • Initial selection: whatever the user picked last time
    ///     (`libraryCategories` field) — repeat-opens are
    ///     stateful, just like a real settings flow.
    ///   • Returns `Set<LibraryCategory>?` — `nil` if cancelled,
    ///     the picked set otherwise. Empty set ≠ cancel: empty
    ///     means "add to library, no categories".
    private func presentAddToLibrary() async {
        let result = await ChoiceDialog.presentMulti(
            title: "Add to library",
            message: "Pick categories for Tokyo Ghoul. Manga can be in multiple categories at once.",
            choices: [
                Choice(value: LibraryCategory.uncategorized, title: "Uncategorized", subtitle: "Default — no category"),
                Choice(value: LibraryCategory.reading, title: "Reading", badge: "12"),
                Choice(value: LibraryCategory.planToRead, title: "Plan to read", badge: "8"),
                Choice(value: LibraryCategory.completed, title: "Completed", badge: "47"),
                Choice(value: LibraryCategory.onHold, title: "On hold"),
                Choice(value: LibraryCategory.dropped, title: "Dropped"),
                Choice(value: LibraryCategory.favorites, title: "Favorites", subtitle: "Pinned to top of library"),
                Choice(value: LibraryCategory.rereading, title: "Re-reading", badge: "NEW")
            ],
            selected: libraryCategories
        )
        if let result {
            libraryCategories = result
            if result.isEmpty {
                statusLabel.status = "Added to library — no categories"
            } else {
                let names = result.map { $0.label }.sorted().joined(separator: ", ")
                statusLabel.status = "Added: \(names)"
            }
        } else {
            statusLabel.status = "Cancelled — not added"
        }
    }

    /// Smallest realistic case — 3 categories. With these few
    /// rows the dialog renders at intrinsic content height,
    /// no internal scroll ever engages. Tests that
    /// `computeScrollHeight()` correctly returns the natural
    /// stack height (not the clamped max) when content is
    /// short.
    private func presentTinyLibrary() async {
        let result = await ChoiceDialog.presentMulti(
            title: "Add to library",
            message: "You have just three categories — picker fits without scrolling.",
            choices: [
                Choice(value: TinyCat.favorites, title: "Favorites"),
                Choice(value: TinyCat.reading, title: "Reading"),
                Choice(value: TinyCat.completed, title: "Completed")
            ],
            selected: tinyCategories
        )
        if let result {
            tinyCategories = result
            statusLabel.status = result.isEmpty ? "Added (no categories)" : "Added to \(result.count)"
        } else {
            statusLabel.status = "Cancelled"
        }
    }

    /// 100-category stress test. ChoiceDialog's
    /// `computeScrollHeight()` clamps to 52 % of the screen
    /// height; content is much taller, so internal scroll
    /// engages automatically. The clamp is screen-driven so
    /// the dialog adapts to iPhone-SE, iPhone-Pro-Max, iPad
    /// portrait and iPad landscape without per-device tuning.
    private func presentHugeLibrary() async {
        let choices = (1...100).map { i in
            Choice(value: i, title: "Category \(i)", subtitle: i.isMultiple(of: 10) ? "Auto-tagged" : nil)
        }
        let result = await ChoiceDialog.presentMulti(
            title: "Add to library",
            message: "Picker auto-scrolls when content exceeds half the screen height.",
            choices: choices,
            selected: hugeCategories
        )
        if let result {
            hugeCategories = result
            statusLabel.status = "Selected: \(result.count) of 100"
        } else {
            statusLabel.status = "Cancelled"
        }
    }

    /// Realistic library-add flow with the "+ New category"
    /// accessory. Starts with `dynamicCategories` empty — the
    /// picker shows the empty-state layout (icon + helper text
    /// + accessory CTA as the only tappable thing). User picks
    /// the accessory → we run `Alert.presentText` for the new
    /// category name → push it onto `dynamicCategories` →
    /// re-present the picker. The loop keeps the user in a
    /// single mental "add" task without round-tripping through
    /// a separate settings screen.
    ///
    /// `MultiPickResult` cases:
    ///   • `.picked(set)` — user tapped Done. Apply selection
    ///     and exit the loop.
    ///   • `.accessory` — caller's turn: run create flow, then
    ///     re-present.
    ///   • `.cancelled` — tap-outside. Exit silently.
    private func presentDynamicLibraryLoop() async {
        while true {
            let choices = dynamicCategories.map {
                Choice(value: $0, title: $0)
            }
            let result = await ChoiceDialog.presentMulti(
                title: "Add to library",
                message: dynamicCategories.isEmpty
                    ? "Create your first category to start organizing your library."
                    : "Pick categories for Tokyo Ghoul. Tap “New category” to add another.",
                choices: choices,
                selected: dynamicSelected,
                accessory: ChoiceDialog.PickerAccessory(
                    title: "New category",
                    systemImage: "plus.circle"
                )
            )
            switch result {
            case .picked(let chosen):
                dynamicSelected = chosen
                statusLabel.status = chosen.isEmpty
                    ? "Added — no categories"
                    : "Added to \(chosen.sorted().joined(separator: ", "))"
                return
            case .accessory:
                // User tapped "New category" — present a text
                // alert for the name, append on confirm.
                let pick = await Alert.presentText(
                    title: "New category",
                    message: "Pick a name for the new category.",
                    textField: .init(
                        placeholder: "Category name",
                        autocapitalization: .words
                    ),
                    actions: [
                        .init(title: "Cancel", style: .cancel),
                        .init(title: "Create", style: .primary)
                    ]
                )
                if let pick, pick.action.style == .primary {
                    let name = pick.text.trimmingCharacters(in: .whitespaces)
                    if !name.isEmpty,
                       !dynamicCategories.contains(where: { $0.caseInsensitiveCompare(name) == .orderedSame }) {
                        dynamicCategories.append(name)
                        // Auto-tick the new one so the user
                        // doesn't have to look for it.
                        dynamicSelected.insert(name)
                    }
                }
                // Loop continues — re-presents the picker with
                // updated `dynamicCategories`.
            case .cancelled:
                statusLabel.status = "Cancelled"
                return
            }
        }
    }

    private func presentCategories() async {
        let result = await ChoiceDialog.presentMulti(
            title: "Filter by category",
            message: "Manga with at least one selected tag will appear in your library.",
            choices: [
                Choice(value: CategoryID.action, title: "Action"),
                Choice(value: CategoryID.romance, title: "Romance"),
                Choice(value: CategoryID.sciFi, title: "Sci-fi"),
                Choice(value: CategoryID.horror, title: "Horror"),
                Choice(value: CategoryID.slice, title: "Slice of life"),
                Choice(value: CategoryID.fantasy, title: "Fantasy", badge: "NEW"),
                Choice(value: CategoryID.mystery, title: "Mystery"),
                Choice(value: CategoryID.comedy, title: "Comedy")
            ],
            selected: selectedCategories
        )
        if let result {
            selectedCategories = result
            statusLabel.status = "Categories: \(result.count) selected"
        } else {
            statusLabel.status = "Cancelled"
        }
    }

    // Long multi-select demo — 25 choices, exceeds card cap
    // (72% of screen height), so the dialog's internal scroll
    // engages. Verifies both the soft `stack ≈ scrollView`
    // height constraint AND tap-on-row when scrolled to a
    // middle item.
    private var selectedLanguages: Set<String> = ["en", "ja"]

    private func presentLanguages() async {
        let langs: [(code: String, name: String)] = [
            ("en", "English"), ("ja", "Japanese"), ("ko", "Korean"),
            ("zh", "Chinese (Simplified)"), ("zh-Hant", "Chinese (Traditional)"),
            ("ru", "Russian"), ("es", "Spanish"), ("fr", "French"),
            ("de", "German"), ("it", "Italian"), ("pt", "Portuguese"),
            ("pl", "Polish"), ("nl", "Dutch"), ("sv", "Swedish"),
            ("no", "Norwegian"), ("fi", "Finnish"), ("da", "Danish"),
            ("tr", "Turkish"), ("ar", "Arabic"), ("hi", "Hindi"),
            ("vi", "Vietnamese"), ("th", "Thai"), ("id", "Indonesian"),
            ("uk", "Ukrainian"), ("cs", "Czech")
        ]
        let choices: [Choice<String>] = langs.map { lang in
            Choice(value: lang.code, title: lang.name, subtitle: lang.code.uppercased())
        }
        let result = await ChoiceDialog.presentMulti(
            title: "Translation source languages",
            message: "Manga in any selected language will appear in your library searches.",
            choices: choices,
            selected: selectedLanguages
        )
        if let result {
            selectedLanguages = result
            statusLabel.status = "Languages: \(result.count) selected"
        } else {
            statusLabel.status = "Cancelled"
        }
    }

    private func presentChapterFilters() async {
        let result = await ChoiceDialog.presentTriState(
            title: "Chapter filters",
            message: "Tap to cycle: empty → checked (only matching) → red minus (only NOT matching).",
            choices: [
                Choice(value: ChapterFilter.unread, title: "Unread"),
                Choice(value: ChapterFilter.downloaded, title: "Downloaded"),
                Choice(value: ChapterFilter.bookmarked, title: "Bookmarked")
            ],
            states: chapterFilters
        )
        if let result {
            chapterFilters = result
            let on = result.filter { $0.value == .on }.count
            let neg = result.filter { $0.value == .negated }.count
            statusLabel.status = "\(on) on, \(neg) negated"
        } else {
            statusLabel.status = "Cancelled"
        }
    }

    // MARK: - Builder helpers

    private func addSection(_ title: String) {
        let label = UILabel()
        label.text = title.uppercased()
        label.font = Sumi.Font.captionEmphasised()
        label.textColor = Sumi.Color.textSecondary
        stack.addArrangedSubview(label)
        stack.setCustomSpacing(Sumi.Spacing.s, after: label)
    }

    private func addRow(_ title: String, action: @escaping () async -> Void) {
        let button = PlaygroundButtonRow(title: title, accent: Sumi.Color.accent)
        button.onTap = {
            Task { await action() }
        }
        stack.addArrangedSubview(button)
    }
}

// MARK: - Demo value types

private enum ThemeID: Hashable, Sendable {
    case system, light, dark, crimson, midnight
    var label: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        case .crimson: return "Crimson"
        case .midnight: return "Midnight"
        }
    }
}

private enum CategoryID: Hashable, Sendable {
    case action, romance, sciFi, horror, slice, fantasy, mystery, comedy
}

private enum ChapterFilter: Hashable, Sendable {
    case unread, downloaded, bookmarked
}

private enum TinyCat: Hashable, Sendable {
    case favorites, reading, completed
}

private enum LibraryCategory: Hashable, Sendable {
    case uncategorized
    case reading
    case planToRead
    case completed
    case onHold
    case dropped
    case favorites
    case rereading
    var label: String {
        switch self {
        case .uncategorized: return "Uncategorized"
        case .reading:       return "Reading"
        case .planToRead:    return "Plan to read"
        case .completed:     return "Completed"
        case .onHold:        return "On hold"
        case .dropped:       return "Dropped"
        case .favorites:     return "Favorites"
        case .rereading:     return "Re-reading"
        }
    }
}
