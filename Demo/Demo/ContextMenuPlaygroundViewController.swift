import UIKit
import Sumi
import SumiMenuKit
import SumiContextMenu

// ContextMenuPlaygroundViewController — long-press a variety
// of mock source surfaces (manga reader / library / chat
// messenger / edge cases) to exercise the context-menu in
// every realistic shape.
//
// Coverage matrix:
//
//   shape           size           menu shape
//   ────────        ─────          ─────────────
//   reader page     wide  16:9     4 actions, destructive
//   manga cover     2:3 tall       6 actions in 3 sections
//   chapter row     thin           4 actions, destructive
//   message in      bubble L       7 actions in 4 sections
//   message out     bubble R       5 actions in 3 sections
//   photo attach    square         5 actions
//   voice note      pill           4 actions
//   link preview    rect card      4 actions
//   avatar          circle 56pt    4 actions — tiny source
//   bottom tile     wide near edge 3 actions — flip-above test

@MainActor
public final class ContextMenuPlaygroundViewController: UIViewController {

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
        stack.spacing = Sumi.Spacing.l
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
            stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -Sumi.Spacing.huge),
            stack.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor, constant: Sumi.Spacing.l),
            stack.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor, constant: -Sumi.Spacing.l),
            stack.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor, constant: -Sumi.Spacing.l * 2)
        ])

        let hint = UILabel()
        hint.text = "Long-press any tile (0.28s) to open its context menu. Each shape is a different real-world surface — reader page, manga cover, chat bubble, voice note, etc."
        hint.font = Sumi.Font.caption()
        hint.textColor = Sumi.Color.textSecondary
        hint.numberOfLines = 0
        stack.addArrangedSubview(hint)

        addMangaSection()
        addMessengerSection()
        addEdgeCasesSection()
    }

    // MARK: - App-specific examples

    private func addMangaSection() {
        addSectionHeader("Manga reader / library")

        // 1. Reader page — wide 16:9
        let pageTile = makeMockTile(
            title: "Chapter 12 · Page 8",
            subtitle: "Long-press to translate, save, or share this page.",
            height: 200,
            accent: Sumi.Color.accent,
            decoration: .reader
        )
        stack.addArrangedSubview(pageTile)
        ContextMenu.attachLongPress(to: pageTile) { [weak self] in
            self?.sectionsFor("page") ?? []
        }

        // 2. Manga cover — 2:3 vertical, centered with side gutters
        let coverRow = UIStackView()
        coverRow.axis = .horizontal
        coverRow.alignment = .center
        coverRow.distribution = .fill
        coverRow.translatesAutoresizingMaskIntoConstraints = false
        let cover = makeMangaCover()
        coverRow.addArrangedSubview(UIView())
        coverRow.addArrangedSubview(cover)
        coverRow.addArrangedSubview(UIView())
        coverRow.arrangedSubviews[0].widthAnchor.constraint(
            equalTo: coverRow.arrangedSubviews[2].widthAnchor
        ).isActive = true
        stack.addArrangedSubview(coverRow)
        ContextMenu.attachLongPress(to: cover) { [weak self] in
            self?.sectionsFor("cover") ?? []
        }

        // 3. Chapter row — thin horizontal
        let chapterRow = makeMockTile(
            title: "Chapter 47 — The Quiet King",
            subtitle: "Released 2 days ago · 28 pages · Not downloaded",
            height: 64,
            accent: Sumi.Color.warning,
            decoration: .chapterRow
        )
        stack.addArrangedSubview(chapterRow)
        ContextMenu.attachLongPress(to: chapterRow) { [weak self] in
            self?.sectionsFor("chapter") ?? []
        }
    }

    // MARK: - Messenger-style

    private func addMessengerSection() {
        addSectionHeader("Messenger surfaces")

        // 4. Incoming chat bubble (left-aligned)
        let inBubble = makeChatBubble(
            text: "Did you finish reading chapter 47? The cliffhanger at the end was insane",
            incoming: true
        )
        let inRow = wrapAlignedRow(view: inBubble, alignment: .leading)
        stack.addArrangedSubview(inRow)
        ContextMenu.attachLongPress(to: inBubble) { [weak self] in
            self?.sectionsFor("messageIn") ?? []
        }

        // 5. Outgoing chat bubble (right-aligned, accent fill)
        let outBubble = makeChatBubble(
            text: "Yeah just finished. Best chapter so far",
            incoming: false
        )
        let outRow = wrapAlignedRow(view: outBubble, alignment: .trailing)
        stack.addArrangedSubview(outRow)
        ContextMenu.attachLongPress(to: outBubble) { [weak self] in
            self?.sectionsFor("messageOut") ?? []
        }

        // 6. Photo attachment — square
        let photoRow = UIStackView()
        photoRow.axis = .horizontal
        photoRow.alignment = .center
        photoRow.translatesAutoresizingMaskIntoConstraints = false
        let photo = makePhotoAttachment()
        photoRow.addArrangedSubview(UIView())
        photoRow.addArrangedSubview(photo)
        photoRow.addArrangedSubview(UIView())
        photoRow.arrangedSubviews[0].widthAnchor.constraint(
            equalTo: photoRow.arrangedSubviews[2].widthAnchor
        ).isActive = true
        stack.addArrangedSubview(photoRow)
        ContextMenu.attachLongPress(to: photo) { [weak self] in
            self?.sectionsFor("photo") ?? []
        }

        // 7. Voice note — pill with mock waveform
        let voicePill = makeVoiceNote(duration: "0:42")
        let voiceRow = wrapAlignedRow(view: voicePill, alignment: .leading)
        stack.addArrangedSubview(voiceRow)
        ContextMenu.attachLongPress(to: voicePill) { [weak self] in
            self?.sectionsFor("voice") ?? []
        }

        // 8. Link preview card
        let link = makeLinkPreview(
            host: "inkwell.app",
            title: "Tokyo Ghoul · Inkwell",
            description: "Latest chapter releases, reading progress, and discussion."
        )
        stack.addArrangedSubview(link)
        ContextMenu.attachLongPress(to: link) { [weak self] in
            self?.sectionsFor("link") ?? []
        }
    }

    // MARK: - Edge cases

    private func addEdgeCasesSection() {
        addSectionHeader("Edge cases — sizing + position")

        // 9. Avatar circle — tiny source, tests anchor + clamping
        // for very small sources (preview shouldn't scale up).
        let avatarRow = UIStackView()
        avatarRow.axis = .horizontal
        avatarRow.alignment = .center
        avatarRow.spacing = Sumi.Spacing.l
        avatarRow.translatesAutoresizingMaskIntoConstraints = false
        let avatar = makeAvatarCircle(initial: "A")
        let avatarHint = UILabel()
        avatarHint.text = "Tiny source — preview stays small, menu sits below."
        avatarHint.font = Sumi.Font.caption()
        avatarHint.textColor = Sumi.Color.textSecondary
        avatarHint.numberOfLines = 0
        avatarRow.addArrangedSubview(avatar)
        avatarRow.addArrangedSubview(avatarHint)
        stack.addArrangedSubview(avatarRow)
        ContextMenu.attachLongPress(to: avatar) { [weak self] in
            self?.sectionsFor("avatar") ?? []
        }

        // Push down so the next tile is near the screen bottom
        // — exercises the "flip menu above" path.
        for _ in 0..<4 {
            let spacer = UIView()
            spacer.heightAnchor.constraint(equalToConstant: 0).isActive = false
            stack.addArrangedSubview(spacer)
        }

        // 10. Bottom-of-screen tile (flip-above test)
        let bottomTile = makeMockTile(
            title: "Near screen bottom",
            subtitle: "Menu should open ABOVE this tile.",
            height: 88,
            accent: Sumi.Color.danger,
            decoration: .reader
        )
        stack.addArrangedSubview(bottomTile)
        ContextMenu.attachLongPress(to: bottomTile) { [weak self] in
            [
                MenuAction(title: "Action one") {
                    self?.statusLabel.status = "Action one"
                },
                MenuAction(title: "Action two") {
                    self?.statusLabel.status = "Action two"
                },
                MenuAction(title: "Remove", systemImage: "trash", style: .destructive) {
                    self?.statusLabel.status = "Removed"
                }
            ].asSections
        }
    }

    // MARK: - Section catalog

    /// Action menus per source — extracted so the long-press
    /// closures don't bloat the demo registration. Returns
    /// `[MenuSection]` so longer menus group neatly (e.g. chat
    /// bubble's 7 actions split into 4 sections).
    private func sectionsFor(_ kind: String) -> [MenuSection] {
        switch kind {
        case "page":
            return [
                MenuAction(title: "Translate page", systemImage: "character.bubble") {
                    self.statusLabel.status = "Translate page"
                },
                MenuAction(title: "Save image", systemImage: "square.and.arrow.down") {
                    self.statusLabel.status = "Save image"
                },
                MenuAction(title: "Share", systemImage: "square.and.arrow.up") {
                    self.statusLabel.status = "Share page"
                },
                MenuAction(title: "Report issue", systemImage: "flag", style: .destructive) {
                    self.statusLabel.status = "Reported"
                }
            ].asSections

        case "cover":
            return [
                MenuSection(title: "Reading", actions: [
                    MenuAction(title: "Mark all as read", systemImage: "checkmark.circle") {
                        self.statusLabel.status = "Marked all read"
                    },
                    MenuAction(title: "Resume from latest", systemImage: "play.fill") {
                        self.statusLabel.status = "Resume reading"
                    }
                ]),
                MenuSection(title: "Manage", actions: [
                    MenuAction(title: "Edit categories", systemImage: "folder") {
                        self.statusLabel.status = "Edit categories"
                    },
                    MenuAction(title: "Migrate to another source", systemImage: "arrow.left.arrow.right") {
                        self.statusLabel.status = "Migrate"
                    },
                    MenuAction(title: "Download all chapters", systemImage: "arrow.down.circle") {
                        self.statusLabel.status = "Download all"
                    }
                ]),
                MenuSection(actions: [
                    MenuAction(title: "Remove from library", systemImage: "trash", style: .destructive) {
                        self.statusLabel.status = "Removed"
                    }
                ])
            ]

        case "chapter":
            return [
                MenuAction(title: "Mark as read", systemImage: "checkmark") {
                    self.statusLabel.status = "Marked read"
                },
                MenuAction(title: "Download", systemImage: "arrow.down.circle") {
                    self.statusLabel.status = "Download chapter"
                },
                MenuAction(title: "Share link", systemImage: "square.and.arrow.up") {
                    self.statusLabel.status = "Share chapter"
                },
                MenuAction(title: "Delete downloaded", systemImage: "trash", style: .destructive) {
                    self.statusLabel.status = "Deleted download"
                }
            ].asSections

        case "messageIn":
            return [
                MenuSection(actions: [
                    MenuAction(title: "Reply", systemImage: "arrowshape.turn.up.left") {
                        self.statusLabel.status = "Reply"
                    },
                    MenuAction(title: "Copy text", systemImage: "doc.on.doc") {
                        self.statusLabel.status = "Copied"
                    },
                    MenuAction(title: "Forward", systemImage: "arrowshape.turn.up.right") {
                        self.statusLabel.status = "Forward"
                    }
                ]),
                MenuSection(actions: [
                    MenuAction(title: "Pin", systemImage: "pin") {
                        self.statusLabel.status = "Pinned"
                    },
                    MenuAction(title: "Save to favorites", systemImage: "star") {
                        self.statusLabel.status = "Saved"
                    }
                ]),
                MenuSection(actions: [
                    MenuAction(title: "Report", systemImage: "exclamationmark.bubble") {
                        self.statusLabel.status = "Reported"
                    },
                    MenuAction(title: "Delete for me", systemImage: "trash", style: .destructive) {
                        self.statusLabel.status = "Deleted"
                    }
                ])
            ]

        case "messageOut":
            return [
                MenuSection(actions: [
                    MenuAction(title: "Edit", systemImage: "pencil") {
                        self.statusLabel.status = "Edit message"
                    },
                    MenuAction(title: "Reply", systemImage: "arrowshape.turn.up.left") {
                        self.statusLabel.status = "Reply"
                    }
                ]),
                MenuSection(actions: [
                    MenuAction(title: "Copy text", systemImage: "doc.on.doc") {
                        self.statusLabel.status = "Copied"
                    },
                    MenuAction(title: "Forward", systemImage: "arrowshape.turn.up.right") {
                        self.statusLabel.status = "Forward"
                    }
                ]),
                MenuSection(actions: [
                    MenuAction(title: "Delete", systemImage: "trash", style: .destructive) {
                        self.statusLabel.status = "Deleted"
                    }
                ])
            ]

        case "photo":
            return [
                MenuAction(title: "Save to photos", systemImage: "square.and.arrow.down") {
                    self.statusLabel.status = "Saved to photos"
                },
                MenuAction(title: "Share", systemImage: "square.and.arrow.up") {
                    self.statusLabel.status = "Share photo"
                },
                MenuAction(title: "Forward", systemImage: "arrowshape.turn.up.right") {
                    self.statusLabel.status = "Forward"
                },
                MenuAction(title: "Copy image", systemImage: "doc.on.doc") {
                    self.statusLabel.status = "Copied"
                },
                MenuAction(title: "Delete", systemImage: "trash", style: .destructive) {
                    self.statusLabel.status = "Deleted"
                }
            ].asSections

        case "voice":
            return [
                MenuAction(title: "Play at 1.5×", systemImage: "play.rectangle") {
                    self.statusLabel.status = "Playing 1.5×"
                },
                MenuAction(title: "Transcribe", systemImage: "text.bubble") {
                    self.statusLabel.status = "Transcribing"
                },
                MenuAction(title: "Save", systemImage: "square.and.arrow.down") {
                    self.statusLabel.status = "Saved"
                },
                MenuAction(title: "Delete", systemImage: "trash", style: .destructive) {
                    self.statusLabel.status = "Deleted"
                }
            ].asSections

        case "link":
            return [
                MenuAction(title: "Open in browser", systemImage: "safari") {
                    self.statusLabel.status = "Open link"
                },
                MenuAction(title: "Copy link", systemImage: "link") {
                    self.statusLabel.status = "Copied link"
                },
                MenuAction(title: "Share", systemImage: "square.and.arrow.up") {
                    self.statusLabel.status = "Share link"
                },
                MenuAction(title: "Block site", systemImage: "nosign", style: .destructive) {
                    self.statusLabel.status = "Blocked"
                }
            ].asSections

        case "avatar":
            return [
                MenuAction(title: "Message", systemImage: "bubble.left") {
                    self.statusLabel.status = "Message"
                },
                MenuAction(title: "Mute notifications", systemImage: "bell.slash") {
                    self.statusLabel.status = "Muted"
                },
                MenuAction(title: "View profile", systemImage: "person.crop.circle") {
                    self.statusLabel.status = "View profile"
                },
                MenuAction(title: "Block", systemImage: "nosign", style: .destructive) {
                    self.statusLabel.status = "Blocked"
                }
            ].asSections

        default:
            return []
        }
    }

    // MARK: - Builders

    private func addSectionHeader(_ title: String) {
        let label = UILabel()
        label.text = title.uppercased()
        label.font = Sumi.Font.captionEmphasised()
        label.textColor = Sumi.Color.textTertiary
        stack.addArrangedSubview(label)
        stack.setCustomSpacing(Sumi.Spacing.s, after: label)
    }

    private enum Decoration { case reader, chapterRow }

    private func makeMockTile(
        title: String,
        subtitle: String,
        height: CGFloat,
        accent: UIColor,
        decoration: Decoration
    ) -> UIView {
        let tile = GradientTile(accentColor: accent)
        tile.translatesAutoresizingMaskIntoConstraints = false
        tile.backgroundColor = Sumi.Color.surfaceElevated
        tile.layer.cornerRadius = Sumi.Radius.card
        tile.layer.cornerCurve = .continuous
        tile.layer.masksToBounds = true

        let titleLabel = UILabel()
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.text = title
        titleLabel.font = Sumi.Font.bodyEmphasised()
        titleLabel.textColor = Sumi.Color.textPrimary
        titleLabel.numberOfLines = 2

        let subLabel = UILabel()
        subLabel.translatesAutoresizingMaskIntoConstraints = false
        subLabel.text = subtitle
        subLabel.font = Sumi.Font.caption()
        subLabel.textColor = Sumi.Color.textSecondary
        subLabel.numberOfLines = 0

        tile.addSubview(titleLabel)
        tile.addSubview(subLabel)

        NSLayoutConstraint.activate([
            tile.heightAnchor.constraint(greaterThanOrEqualToConstant: height),
            titleLabel.topAnchor.constraint(equalTo: tile.topAnchor, constant: Sumi.Spacing.l),
            titleLabel.leadingAnchor.constraint(equalTo: tile.leadingAnchor, constant: Sumi.Spacing.l),
            titleLabel.trailingAnchor.constraint(equalTo: tile.trailingAnchor, constant: -Sumi.Spacing.l),

            subLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: Sumi.Spacing.xs),
            subLabel.leadingAnchor.constraint(equalTo: tile.leadingAnchor, constant: Sumi.Spacing.l),
            subLabel.trailingAnchor.constraint(equalTo: tile.trailingAnchor, constant: -Sumi.Spacing.l),
            subLabel.bottomAnchor.constraint(lessThanOrEqualTo: tile.bottomAnchor, constant: -Sumi.Spacing.l)
        ])

        return tile
    }

    /// 2:3 vertical manga cover — 140pt × 210pt, stylised
    /// kanji title centred over a warm-umber background.
    /// Returned WITHOUT a wrapper container so the gesture
    /// recogniser attaches to a view with explicit bounds.
    /// (The previous version wrapped this in a `UIView` with
    /// no width/height constraints — its bounds were 0×0,
    /// the cover art was visually outside its parent's bounds,
    /// and hit-testing failed for any tap on the cover.)
    private func makeMangaCover() -> UIView {
        let coverArt = GradientTile(accentColor: Sumi.Color.accent)
        coverArt.translatesAutoresizingMaskIntoConstraints = false
        coverArt.backgroundColor = UIColor(red: 0.18, green: 0.10, blue: 0.06, alpha: 1)
        coverArt.layer.cornerRadius = Sumi.Radius.card
        coverArt.layer.cornerCurve = .continuous
        coverArt.clipsToBounds = true

        let coverTitle = UILabel()
        coverTitle.translatesAutoresizingMaskIntoConstraints = false
        coverTitle.text = "東京\n喰種"  // Tokyo Ghoul kanji
        coverTitle.font = UIFont.systemFont(ofSize: 28, weight: .black)
        coverTitle.textColor = .white
        coverTitle.numberOfLines = 0
        coverTitle.textAlignment = .center
        coverArt.addSubview(coverTitle)

        NSLayoutConstraint.activate([
            coverArt.widthAnchor.constraint(equalToConstant: 140),
            coverArt.heightAnchor.constraint(equalToConstant: 210),

            coverTitle.centerXAnchor.constraint(equalTo: coverArt.centerXAnchor),
            coverTitle.centerYAnchor.constraint(equalTo: coverArt.centerYAnchor)
        ])
        return coverArt
    }

    /// Chat-bubble shape — asymmetric corner radii, accent
    /// fill on outgoing, surface-elevated on incoming. Width
    /// hugs the text up to a 70 % cap.
    private func makeChatBubble(text: String, incoming: Bool) -> UIView {
        let bubble = UIView()
        bubble.translatesAutoresizingMaskIntoConstraints = false
        bubble.backgroundColor = incoming
            ? Sumi.Color.surfaceElevated
            : Sumi.Color.accent
        // Asymmetric corners — the bubble's "tail" corner is
        // sharper than the others, matching chat clients'
        // bubble aesthetic.
        bubble.layer.cornerRadius = 16
        bubble.layer.cornerCurve = .continuous
        if incoming {
            bubble.layer.maskedCorners = [
                .layerMinXMinYCorner,
                .layerMaxXMinYCorner,
                .layerMaxXMaxYCorner
            ]
        } else {
            bubble.layer.maskedCorners = [
                .layerMinXMinYCorner,
                .layerMaxXMinYCorner,
                .layerMinXMaxYCorner
            ]
        }

        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = text
        label.font = Sumi.Font.body()
        label.textColor = incoming
            ? Sumi.Color.textPrimary
            : .white
        label.numberOfLines = 0
        bubble.addSubview(label)

        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: bubble.topAnchor, constant: 10),
            label.bottomAnchor.constraint(equalTo: bubble.bottomAnchor, constant: -10),
            label.leadingAnchor.constraint(equalTo: bubble.leadingAnchor, constant: 14),
            label.trailingAnchor.constraint(equalTo: bubble.trailingAnchor, constant: -14),
            // Cap bubble width at ~280pt so it doesn't span the
            // whole row — chat bubbles always leave gutter.
            bubble.widthAnchor.constraint(lessThanOrEqualToConstant: 280)
        ])
        return bubble
    }

    /// Square photo attachment with a gradient stand-in for
    /// real image content. 220pt × 220pt — typical chat photo
    /// dimensions.
    private func makePhotoAttachment() -> UIView {
        let photo = GradientTile(accentColor: Sumi.Color.success)
        photo.translatesAutoresizingMaskIntoConstraints = false
        photo.backgroundColor = UIColor(red: 0.10, green: 0.18, blue: 0.12, alpha: 1)
        photo.layer.cornerRadius = Sumi.Radius.card
        photo.layer.cornerCurve = .continuous
        photo.layer.masksToBounds = true

        let icon = UIImageView(image: UIImage(systemName: "photo.fill"))
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.tintColor = UIColor.white.withAlphaComponent(0.5)
        icon.contentMode = .scaleAspectFit
        photo.addSubview(icon)

        NSLayoutConstraint.activate([
            photo.widthAnchor.constraint(equalToConstant: 220),
            photo.heightAnchor.constraint(equalToConstant: 220),
            icon.centerXAnchor.constraint(equalTo: photo.centerXAnchor),
            icon.centerYAnchor.constraint(equalTo: photo.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 48),
            icon.heightAnchor.constraint(equalToConstant: 48)
        ])
        return photo
    }

    /// Voice-note pill — circular play button + 12 mock
    /// waveform bars + duration text. Compact pill shape, 48pt
    /// tall, ~240pt wide. Tests context menu on a narrow
    /// horizontal source.
    private func makeVoiceNote(duration: String) -> UIView {
        let pill = UIView()
        pill.translatesAutoresizingMaskIntoConstraints = false
        pill.backgroundColor = Sumi.Color.surfaceElevated
        pill.layer.cornerRadius = 24
        pill.layer.cornerCurve = .continuous

        let playIcon = UIImageView(image: UIImage(systemName: "play.fill"))
        playIcon.translatesAutoresizingMaskIntoConstraints = false
        playIcon.tintColor = Sumi.Color.accent
        playIcon.contentMode = .scaleAspectFit
        pill.addSubview(playIcon)

        let waveform = UIStackView()
        waveform.translatesAutoresizingMaskIntoConstraints = false
        waveform.axis = .horizontal
        waveform.alignment = .center
        waveform.distribution = .equalSpacing
        waveform.spacing = 3
        // Pseudo-random bar heights — feels like a real
        // waveform without needing actual audio analysis.
        let heights: [CGFloat] = [10, 14, 8, 22, 16, 26, 12, 18, 8, 14, 20, 10]
        for h in heights {
            let bar = UIView()
            bar.translatesAutoresizingMaskIntoConstraints = false
            bar.backgroundColor = Sumi.Color.textSecondary
            bar.layer.cornerRadius = 1.5
            bar.widthAnchor.constraint(equalToConstant: 3).isActive = true
            bar.heightAnchor.constraint(equalToConstant: h).isActive = true
            waveform.addArrangedSubview(bar)
        }
        pill.addSubview(waveform)

        let durationLabel = UILabel()
        durationLabel.translatesAutoresizingMaskIntoConstraints = false
        durationLabel.text = duration
        durationLabel.font = Sumi.Font.caption()
        durationLabel.textColor = Sumi.Color.textSecondary
        pill.addSubview(durationLabel)

        NSLayoutConstraint.activate([
            pill.heightAnchor.constraint(equalToConstant: 48),
            pill.widthAnchor.constraint(equalToConstant: 260),
            playIcon.leadingAnchor.constraint(equalTo: pill.leadingAnchor, constant: 14),
            playIcon.centerYAnchor.constraint(equalTo: pill.centerYAnchor),
            playIcon.widthAnchor.constraint(equalToConstant: 18),
            playIcon.heightAnchor.constraint(equalToConstant: 18),

            waveform.leadingAnchor.constraint(equalTo: playIcon.trailingAnchor, constant: 12),
            waveform.centerYAnchor.constraint(equalTo: pill.centerYAnchor),
            waveform.trailingAnchor.constraint(equalTo: durationLabel.leadingAnchor, constant: -10),

            durationLabel.trailingAnchor.constraint(equalTo: pill.trailingAnchor, constant: -14),
            durationLabel.centerYAnchor.constraint(equalTo: pill.centerYAnchor)
        ])
        return pill
    }

    /// Link preview card — left accent stripe + host / title /
    /// description column. Reads like an iMessage link preview.
    private func makeLinkPreview(host: String, title: String, description: String) -> UIView {
        let card = UIView()
        card.translatesAutoresizingMaskIntoConstraints = false
        card.backgroundColor = Sumi.Color.surfaceElevated
        card.layer.cornerRadius = Sumi.Radius.card
        card.layer.cornerCurve = .continuous
        card.layer.masksToBounds = true

        let stripe = UIView()
        stripe.translatesAutoresizingMaskIntoConstraints = false
        stripe.backgroundColor = Sumi.Color.accent
        card.addSubview(stripe)

        let hostLabel = UILabel()
        hostLabel.translatesAutoresizingMaskIntoConstraints = false
        hostLabel.text = host
        hostLabel.font = Sumi.Font.caption()
        hostLabel.textColor = Sumi.Color.accent

        let titleLabel = UILabel()
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.text = title
        titleLabel.font = Sumi.Font.bodyEmphasised()
        titleLabel.textColor = Sumi.Color.textPrimary
        titleLabel.numberOfLines = 1

        let descLabel = UILabel()
        descLabel.translatesAutoresizingMaskIntoConstraints = false
        descLabel.text = description
        descLabel.font = Sumi.Font.caption()
        descLabel.textColor = Sumi.Color.textSecondary
        descLabel.numberOfLines = 2

        card.addSubview(hostLabel)
        card.addSubview(titleLabel)
        card.addSubview(descLabel)

        NSLayoutConstraint.activate([
            card.heightAnchor.constraint(greaterThanOrEqualToConstant: 84),

            stripe.topAnchor.constraint(equalTo: card.topAnchor),
            stripe.bottomAnchor.constraint(equalTo: card.bottomAnchor),
            stripe.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            stripe.widthAnchor.constraint(equalToConstant: 3),

            hostLabel.topAnchor.constraint(equalTo: card.topAnchor, constant: Sumi.Spacing.m),
            hostLabel.leadingAnchor.constraint(equalTo: stripe.trailingAnchor, constant: Sumi.Spacing.m),
            hostLabel.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -Sumi.Spacing.l),

            titleLabel.topAnchor.constraint(equalTo: hostLabel.bottomAnchor, constant: 2),
            titleLabel.leadingAnchor.constraint(equalTo: stripe.trailingAnchor, constant: Sumi.Spacing.m),
            titleLabel.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -Sumi.Spacing.l),

            descLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 2),
            descLabel.leadingAnchor.constraint(equalTo: stripe.trailingAnchor, constant: Sumi.Spacing.m),
            descLabel.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -Sumi.Spacing.l),
            descLabel.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -Sumi.Spacing.m)
        ])
        return card
    }

    /// Round 56pt avatar — single-letter monogram. Tiny source
    /// stress-test: the context menu should still anchor
    /// sensibly even though the source is barely bigger than
    /// a button.
    private func makeAvatarCircle(initial: String) -> UIView {
        let avatar = UIView()
        avatar.translatesAutoresizingMaskIntoConstraints = false
        avatar.backgroundColor = Sumi.Color.accent
        avatar.layer.cornerRadius = 28
        avatar.layer.cornerCurve = .continuous

        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = initial
        label.font = UIFont.systemFont(ofSize: 22, weight: .semibold)
        label.textColor = .white
        label.textAlignment = .center
        avatar.addSubview(label)

        NSLayoutConstraint.activate([
            avatar.widthAnchor.constraint(equalToConstant: 56),
            avatar.heightAnchor.constraint(equalToConstant: 56),
            label.centerXAnchor.constraint(equalTo: avatar.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: avatar.centerYAnchor)
        ])
        return avatar
    }

    /// Wrap a view in a row that pins it to one side of the
    /// stack — used for chat bubbles + voice notes that
    /// shouldn't span the whole row.
    private func wrapAlignedRow(view: UIView, alignment: UIStackView.Alignment) -> UIView {
        let row = UIStackView()
        row.translatesAutoresizingMaskIntoConstraints = false
        row.axis = .horizontal
        row.alignment = .center
        row.distribution = .fill
        if alignment == .trailing {
            row.addArrangedSubview(UIView())
            row.addArrangedSubview(view)
        } else {
            row.addArrangedSubview(view)
            row.addArrangedSubview(UIView())
        }
        return row
    }
}

// MARK: - Helpers

private extension Array where Element == MenuAction {
    /// Wrap a flat actions array into a single-section list —
    /// convenience for ContextMenu's `sections:` API when we
    /// don't actually need grouping.
    var asSections: [MenuSection] {
        [MenuSection(actions: self)]
    }
}

// MARK: - GradientTile

private final class GradientTile: UIView {
    private let gradient = CAGradientLayer()

    init(accentColor: UIColor) {
        super.init(frame: .zero)
        gradient.colors = [
            accentColor.withAlphaComponent(0.25).cgColor,
            accentColor.withAlphaComponent(0.05).cgColor
        ]
        gradient.locations = [0.0, 1.0]
        gradient.startPoint = CGPoint(x: 0, y: 0)
        gradient.endPoint = CGPoint(x: 1, y: 1)
        layer.insertSublayer(gradient, at: 0)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }

    override func layoutSubviews() {
        super.layoutSubviews()
        gradient.frame = bounds
    }
}
