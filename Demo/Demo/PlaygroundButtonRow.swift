import UIKit
import Sumi

// PlaygroundButtonRow — reusable "tap me" row used by every
// component playground. Big tap target, accent-coloured left
// bar, multi-line title. Wrapping into one shared type means
// every playground reads identical, and visual tweaks to the
// row apply everywhere at once.

@MainActor
final class PlaygroundButtonRow: UIControl {

    var onTap: (() -> Void)?

    private let label = UILabel()
    private let accentBar = UIView()

    init(title: String, accent: UIColor) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        backgroundColor = Sumi.Color.surfaceElevated
        layer.cornerRadius = Sumi.Radius.interactive
        layer.cornerCurve = .continuous

        accentBar.translatesAutoresizingMaskIntoConstraints = false
        accentBar.backgroundColor = accent
        accentBar.layer.cornerRadius = 2
        addSubview(accentBar)

        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = title
        label.font = Sumi.Font.body()
        label.textColor = Sumi.Color.textPrimary
        label.numberOfLines = 0
        addSubview(label)

        NSLayoutConstraint.activate([
            accentBar.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Sumi.Spacing.m),
            accentBar.topAnchor.constraint(equalTo: topAnchor, constant: Sumi.Spacing.m),
            accentBar.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -Sumi.Spacing.m),
            accentBar.widthAnchor.constraint(equalToConstant: 3),

            label.leadingAnchor.constraint(equalTo: accentBar.trailingAnchor, constant: Sumi.Spacing.m),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Sumi.Spacing.l),
            label.topAnchor.constraint(equalTo: topAnchor, constant: Sumi.Spacing.m),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -Sumi.Spacing.m)
        ])
        addTarget(self, action: #selector(tapped), for: .touchUpInside)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }

    @objc private func tapped() {
        UIView.animate(withDuration: Sumi.Motion.fast, animations: {
            self.transform = CGAffineTransform(scaleX: 0.98, y: 0.98)
        }) { _ in
            UIView.animate(withDuration: Sumi.Motion.fast) {
                self.transform = .identity
            }
        }
        onTap?()
    }
}
