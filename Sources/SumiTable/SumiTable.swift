import UIKit
import Sumi

// SumiTableView — compact key → value table for embedding
// inside an Alert / Dialog content slot.
//
// Use cases:
//
//   • Series summary: "Format: Manga / Chapters: 24 /
//     Language: English / Last updated: 2 days ago"
//   • Chapter download status: "Chapter 47 / Size: 8.2 MB /
//     Pages: 22 / Quality: 1200px"
//   • Source info: "Name: Example / Version: 1.2.3 /
//     Status: Active"
//
// Visual:
//
//   ┌────────────────────────────────────┐
//   │ Source              Inkwell        │
//   │ ──────────────────────────────────  │
//   │ Pages               24             │
//   │ ──────────────────────────────────  │
//   │ Language            English        │
//   │ ──────────────────────────────────  │
//   │ Last updated        2 days ago     │
//   └────────────────────────────────────┘
//
// Label left, value right, hairline separator between rows
// (last row has no separator). Wrapped in a `surfaceSubtle`
// rounded card so it visually nests inside the parent alert
// card without competing for attention.
//
// Each value supports `Sumi.RichText` — so values can include
// inline **bold**, links, and `code` snippets without ever
// touching `NSAttributedString` directly.

@MainActor
public final class SumiTableView: UIView {

    /// One label → value row. Optional leading icon sits
    /// before the label.
    public struct Row: Sendable {
        public let label: String
        public let value: Sumi.RichText
        public let icon: UIImage?

        public init(label: String, value: Sumi.RichText, icon: UIImage? = nil) {
            self.label = label
            self.value = value
            self.icon = icon
        }
    }

    /// Tap handler for any link rendered inside a value
    /// `.markdown(...)`. Single handler for the whole table —
    /// callers route by URL inside the closure (e.g. open in
    /// browser vs deep-link into the app).
    public var onLinkTap: ((URL) -> Void)?

    private let cardView = UIView()
    private let stack = UIStackView()

    public init(rows: [Row]) {
        super.init(frame: .zero)
        setUp()
        update(rows: rows)
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }

    private func setUp() {
        translatesAutoresizingMaskIntoConstraints = false

        cardView.translatesAutoresizingMaskIntoConstraints = false
        cardView.backgroundColor = Sumi.Color.surfaceSubtle
        cardView.layer.cornerRadius = 12
        cardView.layer.cornerCurve = .continuous
        cardView.clipsToBounds = true
        addSubview(cardView)

        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.spacing = 0
        stack.alignment = .fill
        cardView.addSubview(stack)

        NSLayoutConstraint.activate([
            cardView.topAnchor.constraint(equalTo: topAnchor),
            cardView.bottomAnchor.constraint(equalTo: bottomAnchor),
            cardView.leadingAnchor.constraint(equalTo: leadingAnchor),
            cardView.trailingAnchor.constraint(equalTo: trailingAnchor),

            stack.topAnchor.constraint(equalTo: cardView.topAnchor),
            stack.bottomAnchor.constraint(equalTo: cardView.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: cardView.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: cardView.trailingAnchor)
        ])
    }

    /// Replace the table's contents. Cheap to call — clears
    /// the stack and re-builds rows from scratch. We don't
    /// diff because the surface is small (4-10 rows typical)
    /// and tables in alerts/dialogs aren't expected to mutate
    /// after first display.
    public func update(rows: [Row]) {
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for (index, row) in rows.enumerated() {
            let rowView = makeRow(row)
            stack.addArrangedSubview(rowView)
            if index < rows.count - 1 {
                stack.addArrangedSubview(makeSeparator())
            }
        }
        sumi_enableDynamicType()
    }

    private func makeRow(_ row: Row) -> UIView {
        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false

        let iconView = UIImageView()
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.contentMode = .scaleAspectFit
        iconView.tintColor = Sumi.Color.textSecondary
        iconView.image = row.icon
        iconView.isHidden = (row.icon == nil)
        container.addSubview(iconView)

        let labelView = UILabel()
        labelView.translatesAutoresizingMaskIntoConstraints = false
        labelView.text = row.label
        labelView.font = Sumi.Font.body().sumiSized(14)
        labelView.textColor = Sumi.Color.textSecondary
        labelView.numberOfLines = 1
        labelView.setContentHuggingPriority(.required, for: .horizontal)
        // Compression: if value is too long, label gets cut
        // first (its content is typically a short noun like
        // "Pages"; value is the variable-length data).
        labelView.setContentCompressionResistancePriority(.required, for: .horizontal)
        container.addSubview(labelView)

        let valueLabel = LinkAwareLabel()
        valueLabel.translatesAutoresizingMaskIntoConstraints = false
        valueLabel.attributedText = Sumi.render(
            row.value,
            context: Sumi.RichTextContext(
                baseFont: Sumi.Font.bodyEmphasised().sumiSized(14),
                textColor: Sumi.Color.textPrimary,
                accent: Sumi.Color.accent,
                codeBackgroundColor: Sumi.Color.surfaceElevated,
                alignment: .right
            )
        )
        valueLabel.numberOfLines = 2
        valueLabel.textAlignment = .right
        valueLabel.lineBreakMode = .byTruncatingTail
        valueLabel.onLinkTap = { [weak self] url in
            self?.onLinkTap?(url)
        }
        container.addSubview(valueLabel)

        let iconLeading = iconView.leadingAnchor.constraint(
            equalTo: container.leadingAnchor, constant: 14
        )
        let iconWidth = iconView.widthAnchor.constraint(
            equalToConstant: row.icon == nil ? 0 : 16
        )
        let labelLeading = labelView.leadingAnchor.constraint(
            equalTo: iconView.trailingAnchor, constant: row.icon == nil ? 14 : 8
        )

        NSLayoutConstraint.activate([
            container.heightAnchor.constraint(greaterThanOrEqualToConstant: 36),

            iconLeading,
            iconView.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            iconView.heightAnchor.constraint(equalToConstant: 16),
            iconWidth,

            labelLeading,
            labelView.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            labelView.topAnchor.constraint(greaterThanOrEqualTo: container.topAnchor, constant: 10),
            labelView.bottomAnchor.constraint(lessThanOrEqualTo: container.bottomAnchor, constant: -10),

            valueLabel.leadingAnchor.constraint(greaterThanOrEqualTo: labelView.trailingAnchor, constant: 12),
            valueLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -14),
            valueLabel.topAnchor.constraint(greaterThanOrEqualTo: container.topAnchor, constant: 10),
            valueLabel.bottomAnchor.constraint(lessThanOrEqualTo: container.bottomAnchor, constant: -10),
            valueLabel.centerYAnchor.constraint(equalTo: container.centerYAnchor)
        ])
        return container
    }

    private func makeSeparator() -> UIView {
        let separator = UIView()
        separator.translatesAutoresizingMaskIntoConstraints = false
        separator.backgroundColor = Sumi.Color.separator
        NSLayoutConstraint.activate([
            separator.heightAnchor.constraint(equalToConstant: 1.0 / UIScreen.main.scale)
        ])
        // Inset the separator so it doesn't run edge-to-edge —
        // matches the row inset and reads as "row break" not
        // "card divider".
        let wrapper = UIView()
        wrapper.translatesAutoresizingMaskIntoConstraints = false
        wrapper.addSubview(separator)
        NSLayoutConstraint.activate([
            separator.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor, constant: 14),
            separator.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor, constant: -14),
            separator.topAnchor.constraint(equalTo: wrapper.topAnchor),
            separator.bottomAnchor.constraint(equalTo: wrapper.bottomAnchor)
        ])
        return wrapper
    }
}
