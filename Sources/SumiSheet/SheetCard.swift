import UIKit
import Sumi

// SheetCard — main action-list card (vertical layout).
//
// Two-card layout reinstated: the "channel strip" trick of
// folding Cancel into the same surface produced an ugly band
// across the card. Now Cancel is a separate `SheetCancelCard`
// floating below with a transparent 8pt gap — same chrome
// pattern Apple uses, two distinct shadows, but clean.
//
// What stayed from the redesign:
//   • No drag indicator pill — removed per user request,
//     swipe-down-anywhere replaces it.
//   • Cornerradius 22pt (softer, modern shape vs the previous 16pt).
//   • Tighter typography: title 15pt semibold, message 12pt
//     regular — header reads as a section header, not a
//     dominant banner.
//   • Row height 52pt (matches SumiMenu).
//   • Icon column 22pt (down from 28pt).
//   • Destructive style: danger colour only, no bold weight.

@MainActor
final class SheetCard: UIView, SheetContentCard {

    var onActionPicked: ((Int) -> Void)?

    private let actions: [SheetAction]

    init(title: String?, message: String?, actions: [SheetAction]) {
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

        // ---- Header (title + message), optional ----
        let hasTitle = (title?.isEmpty == false)
        let hasMessage = (message?.isEmpty == false)
        if hasTitle || hasMessage {
            container.addArrangedSubview(makeHeaderBlock(title: title, message: message))
            container.addArrangedSubview(makeHairline(inset: 0))
        }

        // ---- Action rows ----
        let showsIconColumn = actions.contains { $0.icon != nil }
        for (idx, action) in actions.enumerated() {
            if idx > 0 {
                container.addArrangedSubview(makeHairline(inset: Sumi.Spacing.l))
            }
            let row = SheetActionRow(action: action, showsIconColumn: showsIconColumn)
            row.onTap = { [weak self] in self?.onActionPicked?(idx) }
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

    private func makeHairline(inset: CGFloat) -> UIView {
        let wrapper = UIView()
        wrapper.translatesAutoresizingMaskIntoConstraints = false
        wrapper.heightAnchor.constraint(equalToConstant: 1.0 / UIScreen.main.scale).isActive = true
        wrapper.backgroundColor = .clear
        let line = UIView()
        line.translatesAutoresizingMaskIntoConstraints = false
        line.backgroundColor = Sumi.Color.separator
        wrapper.addSubview(line)
        NSLayoutConstraint.activate([
            line.topAnchor.constraint(equalTo: wrapper.topAnchor),
            line.bottomAnchor.constraint(equalTo: wrapper.bottomAnchor),
            line.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor, constant: inset),
            line.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor)
        ])
        return wrapper
    }
}

// MARK: - SheetCancelCard
//
// Separate floating card below the main one. Same chrome
// (22pt corners, modal shadow, surfaceElevated bg) — distinct
// view so the gap between the two cards shows the dimmer
// through. Bold semibold textPrimary centred; tap returns
// `nil` from the sheet's async API.

@MainActor
final class SheetCancelCard: UIView {

    var onTap: (() -> Void)?

    init(title: String) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        backgroundColor = Sumi.Color.surfaceElevated
        layer.cornerRadius = 22
        layer.cornerCurve = .continuous
        layer.applySumiShadow(.modal)

        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = title
        label.font = Sumi.Font.bodyEmphasised()
        label.textColor = Sumi.Color.textPrimary
        label.textAlignment = .center
        addSubview(label)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 56),
            label.centerXAnchor.constraint(equalTo: centerXAnchor),
            label.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])

        let tap = UITapGestureRecognizer(target: self, action: #selector(tapTriggered))
        addGestureRecognizer(tap)

        accessibilityLabel = title
        accessibilityTraits = .button
        isAccessibilityElement = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesBegan(touches, with: event)
        UIView.animate(withDuration: 0.06) {
            self.backgroundColor = Sumi.Color.surfaceElevated.withAlphaComponent(0.85)
        }
    }
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesEnded(touches, with: event)
        UIView.animate(withDuration: 0.18) {
            self.backgroundColor = Sumi.Color.surfaceElevated
        }
    }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesCancelled(touches, with: event)
        UIView.animate(withDuration: 0.12) {
            self.backgroundColor = Sumi.Color.surfaceElevated
        }
    }

    @objc private func tapTriggered() { onTap?() }
}

// MARK: - Shared protocol

/// Sheet content card — the variant-specific top card
/// (vertical action list, horizontal action pills, anything
/// future). Exposes a single hook the presentation controller
/// subscribes to: which index was picked.
@MainActor
protocol SheetContentCard: UIView {
    var onActionPicked: ((Int) -> Void)? { get set }
}
