import SumiMenu
import SumiMenuKit
import Sumi
import UIKit

// MenuPlaygroundViewController — feature catalog for Menu.
//
// Each row triggers a Menu variant so the developer can
// verify every behaviour in isolation. The playground is
// minimal on chrome — no floating positional buttons, no
// inline status readout — to leave maximum vertical space
// for the menus themselves (some are tall, some need scroll
// room to demonstrate flip-above behaviour).

@MainActor
public final class MenuPlaygroundViewController: UIViewController {

    private let scroll = PlaygroundScrollView()
    private let stack = UIStackView()

    // State held only so demo menus can show check-marked
    // current selection / live toggle values. Not displayed
    // anywhere on the playground itself.
    private var currentSort = "title"
    private var notificationsOn = true
    private var autoUpdatesOn = false
    private var skipDuplicatesOn = true
    private var blurMatureOn = false
    private var pageDelay: Double = 0.4
    private var brightness: Double = 0.7

    public override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Sumi.Color.surface

        // Nav-bar anchors — primary place users encounter Menu
        // in production. Left = "filter / sort hub", right =
        // "more actions".
        //
        // Target/action form (not `primaryAction: UIAction(...)`)
        // — `UIBarButtonItem(image:primaryAction:)` is iOS 14+.
        // The selector handlers below resolve the bar button's
        // backing view via the same `value(forKey: "view")` KVC
        // trick.
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            image: UIImage(systemName: "line.3.horizontal.decrease"),
            style: .plain,
            target: self,
            action: #selector(handleLeftBarTap(_:))
        )
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            image: UIImage(systemName: "ellipsis.circle"),
            style: .plain,
            target: self,
            action: #selector(handleRightBarTap(_:))
        )

        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.alwaysBounceVertical = true
        view.addSubview(scroll)

        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.spacing = Sumi.Spacing.m
        stack.alignment = .fill
        scroll.addSubview(stack)

        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            stack.topAnchor.constraint(
                equalTo: scroll.contentLayoutGuide.topAnchor, constant: Sumi.Spacing.l),
            stack.bottomAnchor.constraint(
                equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -Sumi.Spacing.xxl),
            stack.leadingAnchor.constraint(
                equalTo: scroll.contentLayoutGuide.leadingAnchor, constant: Sumi.Spacing.l),
            stack.trailingAnchor.constraint(
                equalTo: scroll.contentLayoutGuide.trailingAnchor, constant: -Sumi.Spacing.l),
            stack.widthAnchor.constraint(
                equalTo: scroll.frameLayoutGuide.widthAnchor, constant: -Sumi.Spacing.l * 2),
        ])

        let hint = UILabel()
        hint.text =
            "Tap the nav-bar icons to anchor from the top corners. The rows below cover every feature combination."
        hint.font = Sumi.Font.caption()
        hint.textColor = Sumi.Color.textSecondary
        hint.numberOfLines = 0
        stack.addArrangedSubview(hint)
        stack.setCustomSpacing(Sumi.Spacing.xl, after: hint)

        addSection("Feature demos")
        addRow("Sort menu — checkmark for active option") { [weak self] btn in
            self?.presentSortMenu(from: btn)
        }
        addRow("Filter menu — counts on the right") { [weak self] btn in
            self?.presentFilterMenu(from: btn)
        }
        addRow("Library actions — subtitles") { [weak self] btn in
            self?.presentLibraryActionsMenu(from: btn)
        }
        addRow("Grouped sections — multi-card") { [weak self] btn in
            self?.presentRichSectionedMenu(from: btn)
        }
        addRow("Badges — NEW / PRO / counters") { [weak self] btn in
            self?.presentBadgeMenu(from: btn)
        }
        addRow("Long menu — scrolls when overflowing") { [weak self] btn in
            self?.presentLongMenu(from: btn)
        }
        addRow("No-bounce icons — opt-out") { [weak self] btn in
            self?.presentNoBounceMenu(from: btn)
        }
        addRow("Submenu — Android M3 navigation") { [weak self] btn in
            self?.presentSubmenuDemo(from: btn)
        }
        addRow("Toggles + sticky — settings panel") { [weak self] btn in
            self?.presentTogglesPanel(from: btn)
        }
        addRow("Sliders — live-tweak panel") { [weak self] btn in
            self?.presentSlidersPanel(from: btn)
        }
        addRow("Searchable — genre picker (40 items)") { [weak self] btn in
            self?.presentSearchablePicker(from: btn)
        }
    }

    // MARK: - Menus

    private func presentSortMenu(from anchor: UIView) {
        Menu.present(
            from: anchor,
            actions: [
                MenuAction(title: "Title", isSelected: currentSort == "title") { [weak self] in
                    self?.currentSort = "title"
                },
                MenuAction(title: "Date added", isSelected: currentSort == "added") { [weak self] in
                    self?.currentSort = "added"
                },
                MenuAction(title: "Last read", isSelected: currentSort == "read") { [weak self] in
                    self?.currentSort = "read"
                },
                MenuAction(title: "Unread chapters", isSelected: currentSort == "unread") {
                    [weak self] in
                    self?.currentSort = "unread"
                },
            ])
    }

    private func presentFilterMenu(from anchor: UIView) {
        Menu.present(
            from: anchor,
            actions: [
                MenuAction(title: "Show all", detail: "142", systemImage: "tray.full") {},
                MenuAction(title: "Unread only", detail: "23", systemImage: "bell.badge") {},
                MenuAction(title: "Downloaded only", detail: "58", systemImage: "arrow.down.circle")
                {},
            ])
    }

    private func presentLibraryActionsMenu(from anchor: UIView) {
        Menu.present(
            from: anchor,
            actions: [
                MenuAction(
                    title: "Mark all as read",
                    subtitle: "142 chapters · won't sync to AniList",
                    systemImage: "checkmark.circle"
                ) {},
                MenuAction(
                    title: "Download all chapters",
                    subtitle: "~340 MB · Wi-Fi only",
                    systemImage: "arrow.down.circle"
                ) {},
                MenuAction(
                    title: "Reset reading progress",
                    subtitle: "Mark all as unread",
                    systemImage: "arrow.counterclockwise"
                ) {},
                MenuAction(
                    title: "Remove from library",
                    subtitle: "Keeps downloads on device",
                    systemImage: "trash",
                    style: .destructive
                ) {},
            ])
    }

    private func presentRichSectionedMenu(from anchor: UIView) {
        Menu.present(
            from: anchor,
            sections: [
                MenuSection(
                    title: "Reading",
                    actions: [
                        MenuAction(title: "Mark all read", systemImage: "checkmark.circle") {},
                        MenuAction(title: "Reset progress", systemImage: "arrow.counterclockwise") {
                        },
                    ]),
                MenuSection(
                    title: "Manage",
                    actions: [
                        MenuAction(title: "Edit categories", systemImage: "folder") {},
                        MenuAction(title: "Migrate", systemImage: "arrow.left.arrow.right") {},
                        MenuAction(
                            title: "Remove from library", systemImage: "trash", style: .destructive
                        ) {},
                    ]),
                MenuSection(
                    title: "Share",
                    actions: [
                        MenuAction(title: "Copy link", systemImage: "link") {},
                        MenuAction(title: "Share…", systemImage: "square.and.arrow.up") {},
                    ]),
            ])
    }

    private func presentBadgeMenu(from anchor: UIView) {
        Menu.present(
            from: anchor,
            actions: [
                MenuAction(title: "Translate page", badge: "NEW", systemImage: "character.bubble") {
                },
                MenuAction(title: "AI upscale", badge: "PRO", systemImage: "wand.and.stars") {},
                MenuAction(
                    title: "Library updates", badge: "12", systemImage: "tray.and.arrow.down"
                ) {},
                MenuAction(title: "Browse", systemImage: "globe") {},
            ])
    }

    private func presentLongMenu(from anchor: UIView) {
        let actions: [MenuAction] = (1...18).map { i in
            MenuAction(title: "Action \(i)", systemImage: "\(i).circle") {}
        }
        Menu.present(from: anchor, actions: actions)
    }

    private func presentNoBounceMenu(from anchor: UIView) {
        Menu.present(
            from: anchor,
            actions: [
                MenuAction(title: "With bounce (default)", systemImage: "star") {},
                MenuAction(title: "No bounce", systemImage: "pause", animateIconOnHighlight: false)
                {},
                MenuAction(
                    title: "Also no bounce", systemImage: "arrow.right",
                    animateIconOnHighlight: false
                ) {},
            ])
    }

    private func presentSubmenuDemo(from anchor: UIView) {
        Menu.present(
            from: anchor,
            actions: [
                MenuAction(
                    title: "Sort", systemImage: "arrow.up.arrow.down",
                    submenu: [
                        MenuSection(
                            title: "Order",
                            actions: [
                                MenuAction(title: "Title", isSelected: currentSort == "title") {
                                    [weak self] in
                                    self?.currentSort = "title"
                                },
                                MenuAction(title: "Date added", isSelected: currentSort == "added")
                                { [weak self] in
                                    self?.currentSort = "added"
                                },
                                MenuAction(title: "Last read", isSelected: currentSort == "read") {
                                    [weak self] in
                                    self?.currentSort = "read"
                                },
                            ]),
                        MenuSection(
                            title: "Direction",
                            actions: [
                                MenuAction(title: "Ascending", systemImage: "arrow.up") {},
                                MenuAction(title: "Descending", systemImage: "arrow.down") {},
                            ]),
                    ]),
                MenuAction(
                    title: "Filter", systemImage: "line.3.horizontal.decrease.circle",
                    submenu: [
                        MenuSection(actions: [
                            MenuAction(title: "Show all", detail: "142") {},
                            MenuAction(title: "Unread only", detail: "23", badge: "NEW") {},
                            MenuAction(title: "Downloaded only", detail: "58") {},
                            MenuAction(
                                title: "By category",
                                submenu: [
                                    MenuSection(actions: [
                                        MenuAction(title: "Action") {},
                                        MenuAction(title: "Romance") {},
                                        MenuAction(
                                            title: "Sci-fi",
                                            submenu: [
                                                MenuSection(actions: [
                                                    MenuAction(title: "Sci-fi") {}
                                                ])
                                            ]),
                                        MenuAction(title: "Horror") {},
                                    ])
                                ]),
                        ])
                    ]),
                MenuAction(
                    title: "View", systemImage: "rectangle.grid.2x2",
                    submenu: [
                        MenuSection(actions: [
                            MenuAction(title: "Grid", isSelected: true) {},
                            MenuAction(title: "List", isSelected: false) {},
                            MenuAction(title: "Compact") {},
                        ])
                    ]),
                MenuAction(title: "Refresh", systemImage: "arrow.clockwise") {},
            ])
    }

    private func presentTogglesPanel(from anchor: UIView) {
        Menu.present(
            from: anchor,
            sections: [
                MenuSection(
                    title: "Library updates",
                    actions: [
                        MenuAction(
                            title: "Auto-check daily",
                            toggle: .init(isOn: autoUpdatesOn) { [weak self] on in
                                self?.autoUpdatesOn = on
                            }
                        ),
                        MenuAction(
                            title: "Skip duplicates",
                            toggle: .init(isOn: skipDuplicatesOn) { [weak self] on in
                                self?.skipDuplicatesOn = on
                            }
                        ),
                    ]),
                MenuSection(
                    title: "Notifications",
                    actions: [
                        MenuAction(
                            title: "Push notifications",
                            toggle: .init(isOn: notificationsOn) { [weak self] on in
                                self?.notificationsOn = on
                            }
                        )
                    ]),
                MenuSection(
                    title: "Content",
                    actions: [
                        MenuAction(
                            title: "Blur mature covers",
                            toggle: .init(isOn: blurMatureOn) { [weak self] on in
                                self?.blurMatureOn = on
                            }
                        ),
                        MenuAction(title: "Reset all settings", style: .destructive) {},
                    ]),
            ], dismissOnAction: false)
    }

    private func presentSlidersPanel(from anchor: UIView) {
        Menu.present(
            from: anchor,
            actions: [
                MenuAction(
                    title: "Page delay",
                    slider: .init(
                        value: pageDelay,
                        range: 0.1...1.5,
                        formatter: { String(format: "%.2fs", $0) }
                    ) { [weak self] newValue in
                        self?.pageDelay = newValue
                    }
                ),
                MenuAction(
                    title: "Brightness",
                    slider: .init(
                        value: brightness,
                        range: 0...1,
                        formatter: { String(format: "%.0f%%", $0 * 100) }
                    ) { [weak self] newValue in
                        self?.brightness = newValue
                    }
                ),
            ], dismissOnAction: false)
    }

    private func presentSearchablePicker(from anchor: UIView) {
        let genres = [
            "Action", "Adventure", "Comedy", "Drama",
            "Fantasy", "Horror", "Mystery", "Romance",
            "Sci-Fi", "Slice of Life", "Sports", "Supernatural",
            "Thriller", "Historical", "Psychological", "Mecha",
            "Isekai", "Shounen", "Shoujo", "Seinen",
            "Josei", "Harem", "Magical Girl", "Martial Arts",
            "Music", "School", "Military", "Cooking",
            "Medical", "Detective", "Tragedy", "Demons",
            "Vampire", "Samurai", "Time Travel", "Superhero",
            "Mythology", "Western", "Post-Apocalyptic", "Steampunk",
        ]
        let actions: [MenuAction] = genres.map { genre in
            MenuAction(title: genre, systemImage: "tag") {}
        }
        Menu.present(from: anchor, actions: actions, searchable: true)
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

    private func addRow(_ title: String, action: @escaping (UIView) -> Void) {
        let button = PlaygroundButtonRow(title: title, accent: Sumi.Color.accent)
        button.onTap = { [weak button] in
            guard let button = button else { return }
            action(button)
        }
        stack.addArrangedSubview(button)
    }

    // MARK: - Bar button targets
    //
    // `UIBarButtonItem(image:primaryAction:)` is iOS 14+. We use
    // the target/action form for iOS 13 compatibility. The anchor
    // view (needed by the menu to position itself relative to the
    // bar button) is recovered via the documented-but-private
    // `value(forKey: "view")` KVC trick, same as the iOS 14
    // closure path was doing.

    @objc private func handleLeftBarTap(_ sender: UIBarButtonItem) {
        guard let anchor = sender.value(forKey: "view") as? UIView else { return }
        presentRichSectionedMenu(from: anchor)
    }

    @objc private func handleRightBarTap(_ sender: UIBarButtonItem) {
        guard let anchor = sender.value(forKey: "view") as? UIView else { return }
        presentSortMenu(from: anchor)
    }
}
