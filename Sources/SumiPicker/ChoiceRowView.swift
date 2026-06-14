import UIKit
import Sumi

// IndicatorStyle — what the leading affordance looks like.

enum IndicatorStyle {
    case radio         // single-select
    case checkbox      // multi-select
    case triState      // off / on / negated
}

// ChoiceRowView — single row inside ChoiceDialogCard.
//
// Visual layout (leading to trailing):
//
//   • Leading indicator: radio circle, checkbox, tristate
//     symbol, or — if `choice.colorSwatch` is set —
//     a 22pt filled colour circle (replaces the radio/check
//     so theme/accent pickers feel native instead of
//     "radio with a swatch next to the title").
//   • Optional preview thumbnail (28pt rounded image)
//   • Title + optional subtitle
//   • Optional trailing badge ("NEW" / count / "PRO")
//
// Indicator transition is animated:
//   • Old indicator scales 1.0 → 0.6 + alpha 1 → 0
//   • New indicator scales 0.6 → 1.0 + alpha 0 → 1 (spring)
// Creates a satisfying micro-bounce instead of an instant
// swap. Skips animation when `animated: false` so initial
// state-setting on appear doesn't pop.

@MainActor
final class ChoiceRowView: UIView {

    let choice: AnyChoice
    private let style: IndicatorStyle

    var onTap: (() -> Void)?

    private let indicatorContainer = UIView()
    private var indicatorIconView = UIImageView()   // used for radio (single) only
    private let indicatorBox = IndicatorBox()        // used for checkbox + tristate
    private let swatchView = UIView()
    private let previewView = UIImageView()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let badgeView = ChoiceBadge()

    private(set) var isCurrentlySelected: Bool = false
    private(set) var currentTriState: TriState = .off

    init(choice: AnyChoice, indicatorStyle: IndicatorStyle) {
        self.choice = choice
        self.style = indicatorStyle
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        // The whole row is the tap target, so we expose a
        // generous min height (52pt — comfortable touch).
        heightAnchor.constraint(greaterThanOrEqualToConstant: 52).isActive = true

        // ---- Indicator ----
        indicatorContainer.translatesAutoresizingMaskIntoConstraints = false
        indicatorContainer.isUserInteractionEnabled = false
        addSubview(indicatorContainer)

        // For checkbox + tri-state, use the custom IndicatorBox
        // (rounded square with filled accent state). Radio
        // (single-select) keeps an SF-symbol-based circle below.
        if indicatorStyle != .radio {
            indicatorContainer.addSubview(indicatorBox)
            NSLayoutConstraint.activate([
                indicatorBox.centerXAnchor.constraint(equalTo: indicatorContainer.centerXAnchor),
                indicatorBox.centerYAnchor.constraint(equalTo: indicatorContainer.centerYAnchor)
            ])
        }

        // ---- Color swatch (replaces indicator when used) ----
        swatchView.translatesAutoresizingMaskIntoConstraints = false
        swatchView.layer.cornerRadius = 11
        swatchView.layer.cornerCurve = .continuous
        swatchView.layer.borderWidth = 1.0 / UIScreen.main.scale
        swatchView.layer.borderColor = Sumi.Color.separator.cgColor
        swatchView.isHidden = (choice.colorSwatch == nil)
        if let swatch = choice.colorSwatch {
            swatchView.backgroundColor = swatch
        }
        addSubview(swatchView)

        // ---- Preview ----
        previewView.translatesAutoresizingMaskIntoConstraints = false
        previewView.layer.cornerRadius = 6
        previewView.layer.cornerCurve = .continuous
        previewView.clipsToBounds = true
        previewView.contentMode = .scaleAspectFill
        previewView.backgroundColor = Sumi.Color.surface
        previewView.image = choice.previewImage
        previewView.isHidden = (choice.previewImage == nil)
        addSubview(previewView)

        // ---- Title / subtitle ----
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.text = choice.title
        titleLabel.font = Sumi.Font.body()
        titleLabel.textColor = choice.isDisabled
            ? Sumi.Color.textSecondary
            : Sumi.Color.textPrimary
        titleLabel.numberOfLines = 1
        addSubview(titleLabel)

        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        subtitleLabel.text = choice.subtitle
        subtitleLabel.font = Sumi.Font.caption()
        subtitleLabel.textColor = Sumi.Color.textSecondary
        subtitleLabel.numberOfLines = 1
        subtitleLabel.isHidden = (choice.subtitle == nil)
        addSubview(subtitleLabel)

        // ---- Badge ----
        badgeView.translatesAutoresizingMaskIntoConstraints = false
        badgeView.setContentHuggingPriority(.required, for: .horizontal)
        badgeView.setContentCompressionResistancePriority(.required, for: .horizontal)
        if let badgeText = choice.badge {
            badgeView.configure(text: badgeText)
            badgeView.isHidden = false
        } else {
            badgeView.isHidden = true
        }
        addSubview(badgeView)

        // Whichever of indicator-or-swatch is shown sits at
        // x=16; the other is hidden. Determine the leading
        // anchor for the title accordingly.
        let leadingAffordance: UIView = (choice.colorSwatch != nil) ? swatchView : indicatorContainer

        NSLayoutConstraint.activate([
            leadingAffordance.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Sumi.Spacing.l),
            leadingAffordance.centerYAnchor.constraint(equalTo: centerYAnchor),
            leadingAffordance.widthAnchor.constraint(equalToConstant: 22),
            leadingAffordance.heightAnchor.constraint(equalToConstant: 22),

            indicatorContainer.centerXAnchor.constraint(equalTo: leadingAffordance.centerXAnchor),
            indicatorContainer.centerYAnchor.constraint(equalTo: leadingAffordance.centerYAnchor),
            indicatorContainer.widthAnchor.constraint(equalToConstant: 22),
            indicatorContainer.heightAnchor.constraint(equalToConstant: 22),

            swatchView.centerXAnchor.constraint(equalTo: leadingAffordance.centerXAnchor),
            swatchView.centerYAnchor.constraint(equalTo: leadingAffordance.centerYAnchor),
            swatchView.widthAnchor.constraint(equalToConstant: 22),
            swatchView.heightAnchor.constraint(equalToConstant: 22)
        ])

        // Preview sits between indicator and title when present.
        if !previewView.isHidden {
            NSLayoutConstraint.activate([
                previewView.leadingAnchor.constraint(equalTo: leadingAffordance.trailingAnchor, constant: Sumi.Spacing.m),
                previewView.centerYAnchor.constraint(equalTo: centerYAnchor),
                previewView.widthAnchor.constraint(equalToConstant: 36),
                previewView.heightAnchor.constraint(equalToConstant: 36)
            ])
        }

        let titleLeadingAnchor = previewView.isHidden
            ? leadingAffordance.trailingAnchor
            : previewView.trailingAnchor
        let titleLeadingInset: CGFloat = previewView.isHidden
            ? Sumi.Spacing.m
            : Sumi.Spacing.m

        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: titleLeadingAnchor, constant: titleLeadingInset),
            titleLabel.topAnchor.constraint(
                equalTo: topAnchor,
                constant: (choice.subtitle == nil) ? 0 : 10
            ).withPriority(.defaultHigh),
            titleLabel.bottomAnchor.constraint(
                equalTo: (choice.subtitle == nil) ? bottomAnchor : subtitleLabel.topAnchor,
                constant: (choice.subtitle == nil) ? 0 : -1
            ).withPriority(.defaultHigh),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor).withPriority(.defaultLow),

            subtitleLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            subtitleLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10),

            badgeView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Sumi.Spacing.l),
            badgeView.centerYAnchor.constraint(equalTo: centerYAnchor),

            titleLabel.trailingAnchor.constraint(
                lessThanOrEqualTo: badgeView.isHidden ? trailingAnchor : badgeView.leadingAnchor,
                constant: badgeView.isHidden ? -Sumi.Spacing.l : -Sumi.Spacing.s
            ),
            subtitleLabel.trailingAnchor.constraint(
                lessThanOrEqualTo: trailingAnchor,
                constant: -Sumi.Spacing.l
            )
        ])

        // Initial indicator (off state). IndicatorBox starts
        // at .off in its own init, so we only need to handle
        // the radio case here.
        if indicatorStyle == .radio {
            replaceIndicator(with: imageForState(isSelected: false, tri: .off), animated: false)
        }

        // Use UITapGestureRecognizer instead of UIControl
        // events. UIControl starts tracking on touchDown
        // which interferes with UIScrollView's pan-to-scroll
        // disambiguation — once UIControl is tracking, the
        // scrollView's pan can't cleanly take over even with
        // `canCancelContentTouches = true`. UITapGestureRecognizer
        // fails automatically when the touch moves (its
        // built-in movement tolerance is ~10pt), so a vertical
        // drag becomes a scroll without any extra coordination.
        let tap = UITapGestureRecognizer(target: self, action: #selector(tapTriggered))
        addGestureRecognizer(tap)

        if choice.isDisabled {
            isUserInteractionEnabled = false
            indicatorContainer.alpha = 0.4
            swatchView.alpha = 0.4
            previewView.alpha = 0.4
        }
    }

    // Visual press feedback via touch events. These fire in
    // parallel with the tap gesture recogniser. When user
    // releases without panning → tap fires + we briefly
    // showed highlight. When user pans → touchesCancelled
    // fires (scrollView claims the touch) + tap fails.
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

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }

    // MARK: - State setters

    func setSelected(_ selected: Bool, animated: Bool) {
        guard !choice.isDisabled else { return }
        isCurrentlySelected = selected
        if style == .checkbox {
            // Custom rounded-square indicator.
            indicatorBox.setState(selected ? .on : .off, animated: animated)
        } else {
            // Single-select uses an SF-symbol radio circle.
            replaceIndicator(with: imageForState(isSelected: selected, tri: .off), animated: animated)
        }
    }

    func setTriState(_ state: TriState, animated: Bool) {
        guard !choice.isDisabled else { return }
        currentTriState = state
        let boxState: IndicatorBox.State
        switch state {
        case .off:     boxState = .off
        case .on:      boxState = .on
        case .negated: boxState = .negated
        }
        indicatorBox.setState(boxState, animated: animated)
    }

    // MARK: - Indicator art

    private func imageForState(isSelected: Bool, tri: TriState) -> (image: UIImage?, color: UIColor) {
        // Color-swatch rows don't draw their own indicator —
        // selection is shown via a thin accent ring instead
        // (applied separately via `swatchView.layer.borderColor`).
        if choice.colorSwatch != nil {
            applySwatchSelection(isSelected: isSelected || tri == .on)
            return (nil, .clear)
        }
        switch style {
        case .radio:
            if isSelected {
                return (UIImage(systemName: "largecircle.fill.circle"), Sumi.Color.accent)
            } else {
                return (UIImage(systemName: "circle"), Sumi.Color.textSecondary)
            }
        case .checkbox:
            if isSelected {
                return (UIImage(systemName: "checkmark.square.fill"), Sumi.Color.accent)
            } else {
                return (UIImage(systemName: "square"), Sumi.Color.textSecondary)
            }
        case .triState:
            switch tri {
            case .off:
                return (UIImage(systemName: "square"), Sumi.Color.textSecondary)
            case .on:
                return (UIImage(systemName: "checkmark.square.fill"), Sumi.Color.accent)
            case .negated:
                return (UIImage(systemName: "minus.square.fill"), Sumi.Color.danger)
            }
        }
    }

    private func applySwatchSelection(isSelected: Bool) {
        if isSelected {
            swatchView.layer.borderWidth = 3
            swatchView.layer.borderColor = Sumi.Color.accent.cgColor
        } else {
            swatchView.layer.borderWidth = 1.0 / UIScreen.main.scale
            swatchView.layer.borderColor = Sumi.Color.separator.cgColor
        }
    }

    /// Crossfade-with-spring indicator transition. The old
    /// imageView scales 1.0→0.6 + alpha 1→0; the new one
    /// scales 0.6→1.0 + alpha 0→1 with a soft spring. Skips
    /// the animation when `animated == false` so initial
    /// state-application on appear doesn't pop.
    private func replaceIndicator(with state: (image: UIImage?, color: UIColor), animated: Bool) {
        // For colour-swatch rows: nothing to replace; the
        // swatch's own border updates instead.
        if choice.colorSwatch != nil { return }

        let new = UIImageView(image: state.image)
        new.translatesAutoresizingMaskIntoConstraints = false
        new.tintColor = state.color
        new.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 21, weight: .regular)
        new.contentMode = .scaleAspectFit
        indicatorContainer.addSubview(new)
        NSLayoutConstraint.activate([
            new.centerXAnchor.constraint(equalTo: indicatorContainer.centerXAnchor),
            new.centerYAnchor.constraint(equalTo: indicatorContainer.centerYAnchor),
            new.widthAnchor.constraint(equalToConstant: 22),
            new.heightAnchor.constraint(equalToConstant: 22)
        ])

        let outgoing = indicatorIconView
        indicatorIconView = new

        guard animated else {
            outgoing.removeFromSuperview()
            return
        }

        new.transform = CGAffineTransform(scaleX: 0.6, y: 0.6)
        new.alpha = 0
        UIView.animate(
            withDuration: 0.22,
            delay: 0,
            usingSpringWithDamping: 0.7,
            initialSpringVelocity: 0.6,
            options: [.allowUserInteraction]
        ) {
            new.transform = .identity
            new.alpha = 1
            outgoing.transform = CGAffineTransform(scaleX: 0.6, y: 0.6)
            outgoing.alpha = 0
        } completion: { _ in
            outgoing.removeFromSuperview()
        }
    }

    @objc private func tapTriggered() { onTap?() }
}

// MARK: - Badge

@MainActor
final class ChoiceBadge: UIView {
    private let label = UILabel()

    init() {
        super.init(frame: .zero)
        backgroundColor = Sumi.Color.accent
        layer.cornerRadius = 8
        layer.cornerCurve = .continuous

        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = UIFont.systemFont(ofSize: 11, weight: .bold)
        label.textColor = .white
        label.textAlignment = .center
        addSubview(label)
        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: topAnchor, constant: 2),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -2),
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 7),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -7),
            heightAnchor.constraint(greaterThanOrEqualToConstant: 18)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }

    func configure(text: String) { label.text = text }
}

private extension NSLayoutConstraint {
    func withPriority(_ priority: UILayoutPriority) -> NSLayoutConstraint {
        self.priority = priority
        return self
    }
}
