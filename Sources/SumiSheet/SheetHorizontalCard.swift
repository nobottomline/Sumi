import UIKit
import Sumi

// SheetHorizontalCard — sheet variant with actions laid out
// HORIZONTALLY as icon-pills.
//
// Where you'd use this instead of the vertical sheet:
//
//   • Quick-action rows (Share, Save, Copy, Forward) where
//     each option is best recognised by its icon and labels
//     are short (≤ 1 word usually).
//   • Reaction-style picks: emoji rows, status flags, sticker
//     categories.
//   • Anywhere an iOS share sheet's top icon row would fit —
//     ours uses the same scaffold (modal sheet, dimmer,
//     pan-to-dismiss, Cancel below) but with horizontal pills.
//
// Layout:
//
//   ┌───────────────────────────────────┐
//   │   Title (optional)                │   14pt padding
//   │   Subtitle (optional)             │
//   │   ───────────────────────────     │   hairline
//   │   ┌──┐  ┌──┐  ┌──┐  ┌──┐  ┌──┐    │   horizontal scroll
//   │   │  │  │  │  │  │  │  │  │  │    │   each pill = 72×88pt
//   │   └──┘  └──┘  └──┘  └──┘  └──┘    │
//   │   Save  Copy  Sha  Forw  Del      │   12pt labels
//   └───────────────────────────────────┘
//
// Pills don't wrap to a second row — they scroll horizontally
// if total width exceeds the card's width. Empirically 4-6
// pills always fit on phone, 8+ on iPad before scroll engages.

@MainActor
final class SheetHorizontalCard: UIView, SheetContentCard {

    var onActionPicked: ((Int) -> Void)?

    private let actions: [SheetAction]
    private let scrollView = UIScrollView()
    private let stack = UIStackView()

    init(title: String?, message: String?, actions: [SheetAction], scrollable: Bool) {
        self.actions = actions
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        backgroundColor = Sumi.Color.surfaceElevated
        layer.cornerRadius = 22
        layer.cornerCurve = .continuous
        layer.applySumiShadow(.modal)
        clipsToBounds = true

        let container = UIStackView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.axis = .vertical
        container.spacing = 0
        container.alignment = .fill
        addSubview(container)
        NSLayoutConstraint.activate([
            container.topAnchor.constraint(equalTo: topAnchor),
            container.bottomAnchor.constraint(equalTo: bottomAnchor),
            container.leadingAnchor.constraint(equalTo: leadingAnchor),
            container.trailingAnchor.constraint(equalTo: trailingAnchor)
        ])

        let hasTitle = (title?.isEmpty == false)
        let hasMessage = (message?.isEmpty == false)
        if hasTitle || hasMessage {
            container.addArrangedSubview(makeHeaderBlock(title: title, message: message))
            container.addArrangedSubview(makeHairline())
        }

        // ---- Pill row ----
        // 14pt between borderless pills — more air than the
        // previous boxed design needed because there's no
        // container fill to visually separate items.
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .horizontal
        stack.spacing = 14
        stack.alignment = .center

        for (idx, action) in actions.enumerated() {
            let pill = SheetActionPill(action: action)
            pill.onTap = { [weak self] in self?.onActionPicked?(idx) }
            stack.addArrangedSubview(pill)
        }

        if scrollable {
            // ---- Scrollable variant ----
            // ScrollView wraps the pill stack so a long list
            // of actions scrolls horizontally rather than
            // truncating. `showsHorizontalScrollIndicator = false`
            // — the pills visually edge-fade at the trailing
            // edge when there's overflow (last pill clipped
            // halfway), a more elegant hint than the system bar.
            scrollView.translatesAutoresizingMaskIntoConstraints = false
            scrollView.showsHorizontalScrollIndicator = false
            scrollView.showsVerticalScrollIndicator = false
            scrollView.alwaysBounceHorizontal = false  // only bounce when content actually overflows
            scrollView.contentInsetAdjustmentBehavior = .never
            scrollView.contentInset = UIEdgeInsets(top: 0, left: Sumi.Spacing.l, bottom: 0, right: Sumi.Spacing.l)
            container.addArrangedSubview(scrollView)
            scrollView.addSubview(stack)

            NSLayoutConstraint.activate([
                stack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 14),
                stack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -14),
                stack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
                stack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
                stack.heightAnchor.constraint(equalTo: scrollView.heightAnchor, constant: -28)
            ])
        } else {
            // ---- Fixed (non-scrollable) variant ----
            //
            // Layout philosophy: bind the CARD width to a
            // phone-sized maximum so the horizontal pill
            // rhythm stays consistent on any device. Without
            // this, the sheet's outer container stretches to
            // ~500pt on iPad, `.equalSpacing` distributes the
            // 200pt+ of slack as huge gaps between pills, and
            // the row reads as "lonely icons floating in
            // void". Capping the card at 380pt means the gap
            // math always lands in a tasteful 18-30pt range
            // regardless of host device.
            //
            // 380pt was chosen empirically: 4 pills × 64pt +
            // padding fits with ~20pt gaps; 5 pills fit with
            // ~12pt gaps (still readable). Tighter than that
            // (3 pills) yields ~36pt gaps which IS too much,
            // but with 3 actions you should probably be using
            // the vertical sheet variant anyway.
            //
            // `.equalSpacing` distributes whatever slack
            // remains after the pills' natural widths claim
            // their space — first pill flush leading, last
            // pill flush trailing, gaps between equal.
            stack.distribution = .equalSpacing
            // The width cap is `required` priority so it wins
            // against the cardContainer's `.defaultHigh`
            // (priority 750) "stretch to fill window width"
            // constraint set by SheetPresentation.
            widthAnchor.constraint(lessThanOrEqualToConstant: 380).isActive = true

            let row = UIView()
            row.translatesAutoresizingMaskIntoConstraints = false
            row.addSubview(stack)
            NSLayoutConstraint.activate([
                stack.topAnchor.constraint(equalTo: row.topAnchor, constant: 14),
                stack.bottomAnchor.constraint(equalTo: row.bottomAnchor, constant: -14),
                stack.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: Sumi.Spacing.l),
                stack.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -Sumi.Spacing.l)
            ])
            container.addArrangedSubview(row)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }

    // MARK: - Building blocks

    private func makeHeaderBlock(title: String?, message: String?) -> UIView {
        let wrapper = UIView()
        wrapper.translatesAutoresizingMaskIntoConstraints = false
        let stack = UIStackView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.spacing = 3
        stack.alignment = .fill
        wrapper.addSubview(stack)

        if let title, !title.isEmpty {
            let l = UILabel()
            l.text = title
            l.font = UIFont.systemFont(ofSize: 15, weight: .semibold).sumiSized(15)
            l.adjustsFontForContentSizeCategory = true
            l.textColor = Sumi.Color.textPrimary
            l.textAlignment = .center
            l.numberOfLines = 0
            stack.addArrangedSubview(l)
        }
        if let message, !message.isEmpty {
            let l = UILabel()
            l.text = message
            l.font = UIFont.systemFont(ofSize: 12, weight: .regular).sumiSized(12)
            l.adjustsFontForContentSizeCategory = true
            l.textColor = Sumi.Color.textSecondary
            l.textAlignment = .center
            l.numberOfLines = 0
            stack.addArrangedSubview(l)
        }

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: wrapper.topAnchor, constant: 14),
            stack.bottomAnchor.constraint(equalTo: wrapper.bottomAnchor, constant: -14),
            stack.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor, constant: Sumi.Spacing.l),
            stack.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor, constant: -Sumi.Spacing.l)
        ])
        return wrapper
    }

    private func makeHairline() -> UIView {
        let v = UIView()
        v.translatesAutoresizingMaskIntoConstraints = false
        v.backgroundColor = Sumi.Color.separator
        v.heightAnchor.constraint(equalToConstant: 1.0 / UIScreen.main.scale).isActive = true
        return v
    }
}

// MARK: - SheetActionPill
//
// Borderless minimalist pill — no container background at
// rest, no outline, no chrome. SF Symbol + label, that's it.
//
// Press feedback follows iOS Share Sheet convention: a
// circular tint appears UNDER the icon on touch-down (not
// the whole pill — just the icon area), fades out on release.
// Same pattern Apple uses on UIActivityViewController and
// the iOS 14+ tab bar — proven, professional, instantly
// recognisable as "pressable affordance" without inventing a
// new motion language. Previous version added a press-dot
// indicator below the label + translated the whole pill
// down 4pt; the layered motion was busy. Stripping back to
// just the icon halo reads as cleaner intent.
//
// Total pill: 64pt × 72pt. Icon at 28pt, label at 11pt.

@MainActor
private final class SheetActionPill: UIView {

    var onTap: (() -> Void)?

    private let iconHalo = UIView()  // press-state circle behind icon
    private let iconView = UIImageView()
    private let label = UILabel()

    init(action: SheetAction) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        let isDestructive = (action.style == .destructive)
        let tint: UIColor = isDestructive ? Sumi.Color.danger : Sumi.Color.textPrimary

        // Halo — 44pt circle behind the icon. Transparent at
        // rest; fills with `pressOverlay` on touch-down. Sized
        // generously around the 28pt icon so the touch feedback
        // reads as "I touched here", not "the icon shrank".
        iconHalo.translatesAutoresizingMaskIntoConstraints = false
        iconHalo.backgroundColor = .clear
        iconHalo.layer.cornerRadius = 22
        iconHalo.layer.cornerCurve = .circular
        addSubview(iconHalo)

        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.contentMode = .scaleAspectFit
        // Semibold compensates for the missing container fill —
        // gives icons enough optical weight to read as
        // deliberate affordances against the cream surface
        // without needing a box around them.
        iconView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(
            pointSize: 24, weight: .semibold
        )
        iconView.image = action.icon
        iconView.tintColor = tint
        addSubview(iconView)

        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = action.title
        label.font = UIFont.systemFont(ofSize: 11, weight: .medium)
        label.textColor = tint
        label.textAlignment = .center
        label.numberOfLines = 2
        label.lineBreakMode = .byTruncatingTail
        addSubview(label)

        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 64),
            heightAnchor.constraint(equalToConstant: 72),

            iconHalo.topAnchor.constraint(equalTo: topAnchor, constant: 0),
            iconHalo.centerXAnchor.constraint(equalTo: centerXAnchor),
            iconHalo.widthAnchor.constraint(equalToConstant: 44),
            iconHalo.heightAnchor.constraint(equalToConstant: 44),

            iconView.centerXAnchor.constraint(equalTo: iconHalo.centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: iconHalo.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 28),
            iconView.heightAnchor.constraint(equalToConstant: 28),

            label.topAnchor.constraint(equalTo: iconHalo.bottomAnchor, constant: 6),
            label.leadingAnchor.constraint(equalTo: leadingAnchor),
            label.trailingAnchor.constraint(equalTo: trailingAnchor)
        ])

        let tap = UITapGestureRecognizer(target: self, action: #selector(tapTriggered))
        addGestureRecognizer(tap)

        accessibilityLabel = action.title
        accessibilityHint = action.subtitle
        accessibilityTraits = .button
        isAccessibilityElement = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }

    @objc private func tapTriggered() { onTap?() }

    // Halo fades in / out behind the icon. No scale, no
    // translate, no opacity-dip on icon or label — just the
    // circular tint. Same press-feedback pattern as Apple's
    // share sheet and iOS 14+ tab bar items, recognised
    // immediately as "this is tappable" without inventing a
    // bespoke motion vocabulary.
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesBegan(touches, with: event)
        UIView.animate(
            withDuration: 0.08,
            delay: 0,
            options: [.curveEaseOut, .allowUserInteraction]
        ) {
            self.iconHalo.backgroundColor = Sumi.Color.pressOverlay
        }
    }
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesEnded(touches, with: event)
        UIView.animate(withDuration: 0.18) {
            self.iconHalo.backgroundColor = .clear
        }
    }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesCancelled(touches, with: event)
        UIView.animate(withDuration: 0.14) {
            self.iconHalo.backgroundColor = .clear
        }
    }
}
