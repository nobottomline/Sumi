import UIKit
import Sumi
import SumiSheet

// SheetPlaygroundViewController — exercise every flavour of
// the bottom action sheet:
//   • Header variants (title-only, title+message, none)
//   • Icon column vs no icon
//   • Subtitle on action
//   • Destructive style
//   • No cancel button
//   • Many actions (stress vertical layout)

@MainActor
public final class SheetPlaygroundViewController: UIViewController {

    private let scroll = PlaygroundScrollView()
    private let stack = UIStackView()
    private let statusLabel = StatusLabel()

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
        hint.text = "Bottom action sheet with icon column, destructive style, swipe-down dismiss, and Apple-style separate cancel card."
        hint.font = Sumi.Font.caption()
        hint.textColor = Sumi.Color.textSecondary
        hint.numberOfLines = 0
        stack.addArrangedSubview(hint)
        stack.setCustomSpacing(Sumi.Spacing.xl, after: hint)

        addSection("Apple-style (no icons)")
        addRow("Title only — 3 actions") { [weak self] in
            await self?.presentApplyStyle()
        }
        addRow("Title + message + destructive") { [weak self] in
            await self?.presentDestructiveDelete()
        }

        addSection("Icon column (with subtitles)")
        addRow("Chapter options (icons + subtitles)") { [weak self] in
            await self?.presentChapterOptions()
        }
        addRow("Manga options — 6 actions") { [weak self] in
            await self?.presentMangaOptions()
        }

        addSection("Edge cases")
        addRow("No header (actions only)") { [weak self] in
            await self?.presentNoHeader()
        }
        addRow("No cancel button (swipe-down only)") { [weak self] in
            await self?.presentNoCancel()
        }
        addRow("Long list — 10 actions") { [weak self] in
            await self?.presentLongList()
        }

        addSection("Horizontal pills")
        addRow("Photo action — 4 with Cancel") { [weak self] in
            await self?.presentHorizontalPhotoActions(withCancel: true)
        }
        addRow("Photo action — 4 without Cancel") { [weak self] in
            await self?.presentHorizontalPhotoActions(withCancel: false)
        }
        addRow("Share — 5 actions, with Cancel") { [weak self] in
            await self?.presentHorizontalShare()
        }
        addRow("Quick reactions — no Cancel") { [weak self] in
            await self?.presentHorizontalReactions()
        }
        addRow("Overflow — 8 actions (scrolls)") { [weak self] in
            await self?.presentHorizontalOverflow()
        }
    }

    // MARK: - Demos

    private func presentApplyStyle() async {
        let pick = await SumiSheet.present(
            title: "Set as wallpaper",
            actions: [
                .init(title: "Lock screen"),
                .init(title: "Home screen"),
                .init(title: "Both")
            ]
        )
        statusLabel.status = pick.map { "Picked option \($0 + 1)" } ?? "Cancelled"
    }

    private func presentDestructiveDelete() async {
        let pick = await SumiSheet.present(
            title: "Delete this manga?",
            message: "Removes the manga from your library along with all downloaded chapters. Reading progress is preserved.",
            actions: [
                .init(title: "Delete from library only", style: .destructive),
                .init(title: "Delete library + downloads", style: .destructive)
            ]
        )
        statusLabel.status = pick.map { "Destructive #\($0)" } ?? "Cancelled"
    }

    private func presentChapterOptions() async {
        let pick = await SumiSheet.present(
            title: "Chapter 142 — The Final Stand",
            message: nil,
            actions: [
                .init(
                    title: "Mark as read",
                    icon: UIImage(systemName: "checkmark.circle")
                ),
                .init(
                    title: "Download",
                    subtitle: "Wi-Fi only · ~12 MB",
                    icon: UIImage(systemName: "arrow.down.circle")
                ),
                .init(
                    title: "Bookmark",
                    icon: UIImage(systemName: "bookmark")
                ),
                .init(
                    title: "Share link",
                    icon: UIImage(systemName: "square.and.arrow.up")
                ),
                .init(
                    title: "Delete",
                    icon: UIImage(systemName: "trash"),
                    style: .destructive
                )
            ]
        )
        statusLabel.status = pick.map { "Chapter action #\($0)" } ?? "Cancelled"
    }

    private func presentMangaOptions() async {
        let pick = await SumiSheet.present(
            title: "Tokyo Ghoul",
            message: "Sui Ishida · 144 chapters",
            actions: [
                .init(title: "Refresh", icon: UIImage(systemName: "arrow.clockwise")),
                .init(title: "Edit categories", subtitle: "Currently in 2 categories", icon: UIImage(systemName: "folder")),
                .init(title: "Migrate to other source", icon: UIImage(systemName: "arrow.left.arrow.right")),
                .init(title: "Open in browser", icon: UIImage(systemName: "safari")),
                .init(title: "Share", icon: UIImage(systemName: "square.and.arrow.up")),
                .init(title: "Remove from library", icon: UIImage(systemName: "trash"), style: .destructive)
            ]
        )
        statusLabel.status = pick.map { "Manga action #\($0)" } ?? "Cancelled"
    }

    private func presentNoHeader() async {
        let pick = await SumiSheet.present(
            actions: [
                .init(title: "Photo Library", icon: UIImage(systemName: "photo")),
                .init(title: "Take Photo", icon: UIImage(systemName: "camera")),
                .init(title: "Choose File", icon: UIImage(systemName: "doc"))
            ]
        )
        statusLabel.status = pick.map { "No-header action #\($0)" } ?? "Cancelled"
    }

    private func presentNoCancel() async {
        let pick = await SumiSheet.present(
            title: "Reading mode",
            actions: [
                .init(title: "Pager (vertical)", icon: UIImage(systemName: "rectangle.portrait")),
                .init(title: "Pager (horizontal)", icon: UIImage(systemName: "rectangle")),
                .init(title: "Continuous", icon: UIImage(systemName: "arrow.up.and.down"))
            ],
            cancelTitle: nil
        )
        statusLabel.status = pick.map { "Mode #\($0)" } ?? "Cancelled"
    }

    private func presentLongList() async {
        let actions: [SheetAction] = (1...10).map { i in
            SheetAction(
                title: "Action \(i)",
                icon: UIImage(systemName: "\(i).circle")
            )
        }
        let pick = await SumiSheet.present(
            title: "Long list",
            message: "Ten actions to test vertical layout and tap targets near the screen bottom.",
            actions: actions
        )
        statusLabel.status = pick.map { "Long-list pick #\($0)" } ?? "Cancelled"
    }

    // MARK: - Horizontal pill demos
    //
    // Same `SheetAction` data model — only the container
    // changes (`presentHorizontal` instead of `present`). Each
    // action renders as a 48pt rounded icon + 11pt label below
    // it, arranged in a horizontally-scrolling row.

    /// Photo / media action sheet — Play + 3 media-management
    /// actions. Same set of actions in both variants; the only
    /// difference is whether the Cancel card renders below.
    /// Useful side-by-side comparison of "should I include a
    /// Cancel button?" — without Cancel the sheet is roughly
    /// 60pt shorter, but you lose the explicit escape hatch
    /// for users who don't know about swipe-down.
    private func presentHorizontalPhotoActions(withCancel: Bool) async {
        let actions: [SheetAction] = [
            SheetAction(title: "Play", icon: UIImage(systemName: "play.fill")),
            SheetAction(title: "Save to Photos", icon: UIImage(systemName: "photo.on.rectangle.angled")),
            SheetAction(title: "Favorite", icon: UIImage(systemName: "heart.fill")),
            SheetAction(title: "Share", icon: UIImage(systemName: "square.and.arrow.up.fill"))
        ]
        let pick = await SumiSheet.presentHorizontal(
            title: "Photo actions",
            message: withCancel
                ? "4 pills, centred — no scroll. Cancel below."
                : "4 pills, centred — no scroll. Swipe down to dismiss.",
            actions: actions,
            cancelTitle: withCancel ? "Cancel" : nil,
            scrollable: false
        )
        statusLabel.status = pick.map { "Photo action #\($0)" } ?? (withCancel ? "Cancelled" : "Dismissed")
    }

    private func presentHorizontalShare() async {
        let pick = await SumiSheet.presentHorizontal(
            title: "Share",
            message: "Send to apps installed on this device.",
            actions: [
                SheetAction(title: "Messages", icon: UIImage(systemName: "message.fill")),
                SheetAction(title: "Mail", icon: UIImage(systemName: "envelope.fill")),
                SheetAction(title: "Copy", icon: UIImage(systemName: "doc.on.doc.fill")),
                SheetAction(title: "AirDrop", icon: UIImage(systemName: "shareplay")),
                SheetAction(title: "Save", icon: UIImage(systemName: "square.and.arrow.down.fill"))
            ]
        )
        statusLabel.status = pick.map { "Shared via #\($0)" } ?? "Cancelled"
    }

    private func presentHorizontalReactions() async {
        // No `cancelTitle` → only the main card renders.
        // User dismisses by swipe-down or tap-outside.
        let pick = await SumiSheet.presentHorizontal(
            title: nil,
            message: nil,
            actions: [
                SheetAction(title: "Like", icon: UIImage(systemName: "heart.fill")),
                SheetAction(title: "Laugh", icon: UIImage(systemName: "face.smiling.fill")),
                SheetAction(title: "Wow", icon: UIImage(systemName: "sparkles")),
                SheetAction(title: "Sad", icon: UIImage(systemName: "cloud.rain.fill")),
                SheetAction(title: "Angry", icon: UIImage(systemName: "flame.fill"))
            ],
            cancelTitle: nil
        )
        statusLabel.status = pick.map { "Reacted #\($0)" } ?? "Dismissed"
    }

    private func presentHorizontalOverflow() async {
        // Eight pills × 72pt + 8pt gaps = ~640pt content width.
        // Wider than any phone — the internal UIScrollView's
        // bounce + trailing-edge clipping should engage. Last
        // few pills only become visible by scrolling right.
        let pick = await SumiSheet.presentHorizontal(
            title: "Chapter tools",
            message: "Swipe horizontally — actions overflow on phone.",
            actions: [
                SheetAction(title: "Read", icon: UIImage(systemName: "book.fill")),
                SheetAction(title: "Mark", icon: UIImage(systemName: "checkmark.circle.fill")),
                SheetAction(title: "Download", icon: UIImage(systemName: "arrow.down.circle.fill")),
                SheetAction(title: "Share", icon: UIImage(systemName: "square.and.arrow.up.fill")),
                SheetAction(title: "Bookmark", icon: UIImage(systemName: "bookmark.fill")),
                SheetAction(title: "Translate", icon: UIImage(systemName: "character.bubble.fill")),
                SheetAction(title: "Pin", icon: UIImage(systemName: "pin.fill")),
                SheetAction(title: "Delete", icon: UIImage(systemName: "trash.fill"), style: .destructive)
            ]
        )
        statusLabel.status = pick.map { "Tool #\($0)" } ?? "Cancelled"
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
