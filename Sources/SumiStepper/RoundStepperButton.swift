import UIKit
import Sumi

// RoundStepperButton — large (64pt) circular ± button used by
// `SumiStepperView`. Public because hero-stepper rows are
// occasionally assembled inline (e.g. inside a settings cell
// where the canonical stepper card is too heavy) and the
// caller wants the same press affordance.
//
// Visual:
//
//   • 64pt circle, label-tinted fill at 6% opacity
//   • SF Symbol glyph (passed via `symbol:`), 22pt bold weight
//   • Touch-down: fill bumps to 14% + scale 0.94, spring back
//   • Disabled: fill drops to 3%, glyph fades to 35% — visible
//     but unmistakably inert
//
// Press semantics:
//
//   • `onTap`        — single tap on press-up (target/action)
//   • `onHoldBegan`  — long-press recogniser fires at 0.32s
//   • `onHoldEnded`  — long-press ended / cancelled / failed
//
// Hold-and-tap are NOT mutually exclusive — a quick tap fires
// `onTap` and never engages the hold path; a long hold engages
// `onHoldBegan` but `onTap` won't fire on release (the
// gesture-recogniser cancels touchUpInside). The caller wires
// repeat logic in `onHoldBegan`/`onHoldEnded` and the single-
// step path in `onTap`.

@MainActor
public final class RoundStepperButton: UIControl {

    public var onTap: (() -> Void)?
    public var onHoldBegan: (() -> Void)?
    public var onHoldEnded: (() -> Void)?

    private let imageView = UIImageView()
    private let fill = UIView()
    private static let diameter: CGFloat = 64

    public override var isEnabled: Bool {
        didSet { updateAppearance(animated: true) }
    }

    public init(symbol: String) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        fill.translatesAutoresizingMaskIntoConstraints = false
        fill.backgroundColor = Sumi.Color.textPrimary.withAlphaComponent(0.06)
        fill.layer.cornerRadius = Self.diameter / 2
        fill.layer.cornerCurve = .continuous
        fill.isUserInteractionEnabled = false
        addSubview(fill)

        let symbolConfig = UIImage.SymbolConfiguration(pointSize: 22, weight: .bold)
        imageView.image = UIImage(systemName: symbol, withConfiguration: symbolConfig)
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.tintColor = Sumi.Color.textPrimary
        imageView.contentMode = .center
        imageView.isUserInteractionEnabled = false
        addSubview(imageView)

        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: Self.diameter),
            heightAnchor.constraint(equalToConstant: Self.diameter),
            fill.topAnchor.constraint(equalTo: topAnchor),
            fill.bottomAnchor.constraint(equalTo: bottomAnchor),
            fill.leadingAnchor.constraint(equalTo: leadingAnchor),
            fill.trailingAnchor.constraint(equalTo: trailingAnchor),
            imageView.centerXAnchor.constraint(equalTo: centerXAnchor),
            imageView.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])

        let longPress = UILongPressGestureRecognizer(
            target: self, action: #selector(handleLongPress(_:))
        )
        longPress.minimumPressDuration = 0.32
        addGestureRecognizer(longPress)

        addTarget(self, action: #selector(touchDown), for: .touchDown)
        addTarget(self, action: #selector(touchUpInside), for: .touchUpInside)
        addTarget(
            self,
            action: #selector(touchCancelled),
            for: [.touchUpOutside, .touchCancel]
        )
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }

    // MARK: - Touch handlers

    @objc private func touchDown() {
        UIView.animate(
            withDuration: 0.12,
            delay: 0,
            options: [.curveEaseOut, .allowUserInteraction]
        ) {
            self.fill.backgroundColor = Sumi.Color.textPrimary.withAlphaComponent(0.14)
            self.fill.transform = CGAffineTransform(scaleX: 0.94, y: 0.94)
        }
    }

    @objc private func touchUpInside() {
        restoreFill()
        onTap?()
    }

    @objc private func touchCancelled() {
        restoreFill()
        onHoldEnded?()
    }

    private func restoreFill() {
        UIView.animate(
            withDuration: 0.20,
            delay: 0,
            usingSpringWithDamping: 0.7,
            initialSpringVelocity: 0.3,
            options: [.allowUserInteraction]
        ) {
            self.fill.transform = .identity
            self.updateAppearance(animated: false)
        }
    }

    private func updateAppearance(animated: Bool) {
        let bg: UIColor = isEnabled
            ? Sumi.Color.textPrimary.withAlphaComponent(0.06)
            : Sumi.Color.textPrimary.withAlphaComponent(0.03)
        let tint: UIColor = isEnabled
            ? Sumi.Color.textPrimary
            : Sumi.Color.textPrimary.withAlphaComponent(0.35)
        let block = {
            self.fill.backgroundColor = bg
            self.imageView.tintColor = tint
        }
        if animated {
            UIView.animate(withDuration: 0.18, animations: block)
        } else {
            block()
        }
    }

    @objc private func handleLongPress(_ gr: UILongPressGestureRecognizer) {
        switch gr.state {
        case .began:
            onHoldBegan?()
        case .ended, .cancelled, .failed:
            onHoldEnded?()
        default:
            break
        }
    }
}
