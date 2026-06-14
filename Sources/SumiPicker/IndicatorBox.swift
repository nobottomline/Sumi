import UIKit
import Sumi

// IndicatorBox — custom rounded-square indicator used by the
// checkbox + tri-state variants of ChoiceRowView.
//
// Replaces the previous SF-Symbol-based approach
// ("checkmark.square.fill") because:
//   • SF symbol fills look generic and slightly puffy on
//     small sizes; we want a crisp 22pt rounded square that
//     matches our 6pt-radius button language.
//   • Symbols can't animate the fill colour smoothly between
//     states; with a custom view we get a spring scale on
//     the inner checkmark + colour crossfade on the box.
//
// States:
//   • .off       — 1.5pt stroke, transparent fill, no symbol
//   • .on        — filled accent, white checkmark inside
//   • .negated   — filled danger,  white minus     inside

@MainActor
final class IndicatorBox: UIView {

    enum State {
        case off, on, negated
    }

    private(set) var state: State = .off
    private let symbolView = UIImageView()

    init() {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: 22).isActive = true
        heightAnchor.constraint(equalToConstant: 22).isActive = true

        layer.cornerRadius = 6
        layer.cornerCurve = .continuous
        layer.borderWidth = 1.5
        layer.borderColor = Sumi.Color.textSecondary.cgColor
        backgroundColor = .clear

        symbolView.translatesAutoresizingMaskIntoConstraints = false
        symbolView.tintColor = .white
        symbolView.contentMode = .center
        addSubview(symbolView)
        NSLayoutConstraint.activate([
            symbolView.centerXAnchor.constraint(equalTo: centerXAnchor),
            symbolView.centerYAnchor.constraint(equalTo: centerYAnchor),
            symbolView.widthAnchor.constraint(equalToConstant: 16),
            symbolView.heightAnchor.constraint(equalToConstant: 16)
        ])
        applyState(animated: false)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }

    func setState(_ newState: State, animated: Bool) {
        guard newState != state else { return }
        state = newState
        applyState(animated: animated)
    }

    private func applyState(animated: Bool) {
        // Resolve colours + symbol for this state.
        let bg: UIColor
        let border: UIColor
        let symbolName: String?
        switch state {
        case .off:
            bg = .clear
            border = Sumi.Color.textSecondary
            symbolName = nil
        case .on:
            bg = Sumi.Color.accent
            border = Sumi.Color.accent
            symbolName = "checkmark"
        case .negated:
            bg = Sumi.Color.danger
            border = Sumi.Color.danger
            symbolName = "minus"
        }

        let symbolImage = symbolName.flatMap {
            UIImage(systemName: $0, withConfiguration: UIImage.SymbolConfiguration(pointSize: 13, weight: .bold))
        }

        // Box colour swap + symbol scale-in spring.
        if animated {
            UIView.animate(withDuration: 0.18, animations: {
                self.backgroundColor = bg
                self.layer.borderColor = border.cgColor
            })
            if symbolImage != nil {
                symbolView.image = symbolImage
                symbolView.alpha = 0
                symbolView.transform = CGAffineTransform(scaleX: 0.4, y: 0.4)
                UIView.animate(
                    withDuration: 0.22,
                    delay: 0.04,
                    usingSpringWithDamping: 0.65,
                    initialSpringVelocity: 0.6
                ) {
                    self.symbolView.alpha = 1
                    self.symbolView.transform = .identity
                }
            } else {
                UIView.animate(
                    withDuration: 0.14,
                    animations: {
                        self.symbolView.alpha = 0
                        self.symbolView.transform = CGAffineTransform(scaleX: 0.5, y: 0.5)
                    },
                    completion: { _ in
                        self.symbolView.image = nil
                        self.symbolView.transform = .identity
                    }
                )
            }
        } else {
            backgroundColor = bg
            layer.borderColor = border.cgColor
            symbolView.image = symbolImage
            symbolView.alpha = (symbolImage != nil) ? 1 : 0
            symbolView.transform = .identity
        }
    }
}
