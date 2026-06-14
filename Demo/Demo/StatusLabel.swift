import UIKit
import Sumi

// StatusLabel — inline "last picked: X" readout for playgrounds.
//
// Earlier versions used Toast for action feedback, but that
// bled the Toast component into every other playground —
// confusing when testing a component in isolation. A sticky
// inline label keeps each playground self-contained.

@MainActor
final class StatusLabel: UIView {

    private let label = UILabel()
    private let icon = UIImageView()

    var status: String = "" {
        didSet { update() }
    }

    init() {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        backgroundColor = Sumi.Color.surfaceElevated
        layer.cornerRadius = Sumi.Radius.interactive
        layer.cornerCurve = .continuous

        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.image = UIImage(systemName: "arrow.right.circle.fill")
        icon.tintColor = Sumi.Color.accent
        icon.preferredSymbolConfiguration = .init(textStyle: .footnote)
        icon.setContentHuggingPriority(.required, for: .horizontal)

        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = "(no action yet)"
        label.font = Sumi.Font.caption()
        label.textColor = Sumi.Color.textSecondary
        label.numberOfLines = 1

        addSubview(icon)
        addSubview(label)
        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Sumi.Spacing.m),
            icon.centerYAnchor.constraint(equalTo: centerYAnchor),
            label.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: Sumi.Spacing.s),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Sumi.Spacing.m),
            label.topAnchor.constraint(equalTo: topAnchor, constant: Sumi.Spacing.s),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -Sumi.Spacing.s)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }

    private func update() {
        if status.isEmpty {
            label.text = "(no action yet)"
            label.textColor = Sumi.Color.textSecondary
        } else {
            label.text = "Last picked: \(status)"
            label.textColor = Sumi.Color.textPrimary
        }
        // Quick pulse so the label visibly changes — important
        // because the eye is on the menu, not on this readout.
        UIView.animate(withDuration: 0.12, animations: {
            self.transform = CGAffineTransform(scaleX: 1.03, y: 1.03)
        }) { _ in
            UIView.animate(withDuration: 0.18) {
                self.transform = .identity
            }
        }
    }
}
