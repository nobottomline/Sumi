import UIKit
import Sumi

// SheetActionRow — one tappable row inside a sheet card.
//
// Same UIView + UITapGestureRecognizer pattern used by
// `ChoiceRowView` (see SumiPicker). UIControl would start
// tracking on touchDown which interferes with the card's
// pan-to-dismiss gesture — UITapGestureRecognizer fails
// automatically on movement (~10pt tolerance), so a vertical
// drag becomes a sheet-dismiss without manual coordination.

@MainActor
final class SheetActionRow: UIView {

    let action: SheetAction
    var onTap: (() -> Void)?

    private let iconView = UIImageView()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()

    /// `showsIconColumn` is decided sheet-wide: if any action
    /// has an icon, every row reserves the 28pt leading column
    /// (empty for icon-less rows) so titles align vertically.
    init(action: SheetAction, showsIconColumn: Bool) {
        self.action = action
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(greaterThanOrEqualToConstant: 52).isActive = true

        let tintColor: UIColor = (action.style == .destructive)
            ? Sumi.Color.danger
            : Sumi.Color.textPrimary
        // Destructive used to render bold — the color is signal
        // enough now that surrounding chrome (drag handle, two
        // cards, heavy header) was stripped away. Bold here
        // shouted; regular body weight + danger tint reads as
        // "this is destructive, not louder than everything else."
        let titleFont: UIFont = Sumi.Font.body()

        // ---- Icon ----
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.contentMode = .scaleAspectFit
        iconView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 17, weight: .regular)
        iconView.image = action.icon
        iconView.tintColor = tintColor
        addSubview(iconView)

        // ---- Title ----
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.text = action.title
        titleLabel.font = titleFont
        titleLabel.textColor = tintColor
        titleLabel.numberOfLines = 1
        // When no icon column: Apple-style centered title.
        // With icon column: icon-led left-aligned title.
        titleLabel.textAlignment = showsIconColumn ? .left : .center
        addSubview(titleLabel)

        // ---- Subtitle ----
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        subtitleLabel.text = action.subtitle
        subtitleLabel.font = Sumi.Font.caption()
        subtitleLabel.textColor = Sumi.Color.textSecondary
        subtitleLabel.numberOfLines = 1
        subtitleLabel.textAlignment = showsIconColumn ? .left : .center
        subtitleLabel.isHidden = (action.subtitle == nil)
        addSubview(subtitleLabel)

        // ---- Layout ----
        var constraints: [NSLayoutConstraint] = []
        let hasSubtitle = (action.subtitle != nil)

        if showsIconColumn {
            // Icon slot tightened from 28pt → 22pt to match
            // SumiMenu's row indicator column. Smaller icons
            // give titles more breathing room and read as
            // "iOS Settings" rather than "icon-driven grid".
            constraints += [
                iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Sumi.Spacing.l),
                iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
                iconView.widthAnchor.constraint(equalToConstant: 22),
                iconView.heightAnchor.constraint(equalToConstant: 22),

                titleLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: Sumi.Spacing.m),
                titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -Sumi.Spacing.l),
                subtitleLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
                subtitleLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -Sumi.Spacing.l)
            ]
        } else {
            // Centered title, no icon shown. iconView still
            // sits in the hierarchy but with size 0 so the
            // layout doesn't have a dangling view.
            iconView.isHidden = true
            constraints += [
                iconView.widthAnchor.constraint(equalToConstant: 0),
                iconView.heightAnchor.constraint(equalToConstant: 0),
                iconView.leadingAnchor.constraint(equalTo: leadingAnchor),
                iconView.topAnchor.constraint(equalTo: topAnchor),

                titleLabel.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: Sumi.Spacing.l),
                titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -Sumi.Spacing.l),
                titleLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
                subtitleLabel.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: Sumi.Spacing.l),
                subtitleLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -Sumi.Spacing.l),
                subtitleLabel.centerXAnchor.constraint(equalTo: centerXAnchor)
            ]
        }

        if hasSubtitle {
            constraints += [
                titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 10),
                titleLabel.bottomAnchor.constraint(equalTo: subtitleLabel.topAnchor, constant: -2),
                subtitleLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10)
            ]
        } else {
            constraints += [
                titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor)
            ]
        }
        NSLayoutConstraint.activate(constraints)

        // Tap recogniser (see class-level comment about why not
        // UIControl).
        let tap = UITapGestureRecognizer(target: self, action: #selector(tapTriggered))
        addGestureRecognizer(tap)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }

    // Press feedback — fires in parallel with the tap gesture.
    // If the sheet's pan claims the touch (swipe-down dismiss),
    // touchesCancelled fires and we restore the row.
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesBegan(touches, with: event)
        UIView.animate(withDuration: 0.06) {
            self.backgroundColor = UIColor(white: 0.5, alpha: 0.10)
        }
    }
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesEnded(touches, with: event)
        UIView.animate(withDuration: 0.18) {
            self.backgroundColor = .clear
        }
    }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesCancelled(touches, with: event)
        UIView.animate(withDuration: 0.12) {
            self.backgroundColor = .clear
        }
    }

    @objc private func tapTriggered() { onTap?() }
}
