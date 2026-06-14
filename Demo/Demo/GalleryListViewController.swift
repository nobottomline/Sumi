import UIKit
import Sumi

// GalleryListViewController — top-level catalog list.
//
// Single source of registration is `entries:` passed in by the
// App. Backed by `UITableView` (`.insetGrouped`) for an iOS 13
// floor — the previous implementation used
// `UICollectionLayoutListConfiguration` + `CellRegistration` +
// `defaultContentConfiguration()` (all iOS 14+) which would
// silently degrade if a teammate dropped the deployment target.
// UITableView is uglier to set up but has none of those guards.
//
// Each row pushes the component's playground onto the
// navigation stack. No tab bar — components are categorically
// equal, sorting / grouping comes from the caller's entries
// order.

@MainActor
public final class GalleryListViewController: UIViewController {

    private let entries: [GalleryEntry]
    private let tableView = UITableView(frame: .zero, style: .insetGrouped)
    private static let cellReuseIdentifier = "GalleryEntryCell"

    public init(entries: [GalleryEntry]) {
        self.entries = entries
        super.init(nibName: nil, bundle: nil)
        self.title = "Sumi"
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }

    public override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Sumi.Color.surface
        navigationController?.navigationBar.prefersLargeTitles = true
        navigationItem.largeTitleDisplayMode = .always

        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.backgroundColor = Sumi.Color.surface
        tableView.dataSource = self
        tableView.delegate = self
        // Subtitle style gives us a built-in two-line cell with
        // text + secondaryText. iOS 13 had no
        // `defaultContentConfiguration()`; cells expose `.textLabel`
        // and `.detailTextLabel` directly.
        tableView.register(GalleryEntryCell.self, forCellReuseIdentifier: Self.cellReuseIdentifier)
        tableView.estimatedRowHeight = 60
        tableView.rowHeight = UITableView.automaticDimension
        view.addSubview(tableView)

        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
    }
}

// MARK: - UITableViewDataSource

extension GalleryListViewController: UITableViewDataSource {

    public func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        entries.count
    }

    public func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: Self.cellReuseIdentifier, for: indexPath)
        let entry = entries[indexPath.row]

        cell.textLabel?.text = entry.title
        cell.textLabel?.font = Sumi.Font.bodyEmphasised()
        cell.textLabel?.textColor = Sumi.Color.textPrimary

        cell.detailTextLabel?.text = entry.subtitle
        cell.detailTextLabel?.font = Sumi.Font.caption()
        cell.detailTextLabel?.textColor = Sumi.Color.textSecondary
        cell.detailTextLabel?.numberOfLines = 0

        let symbolConfig = UIImage.SymbolConfiguration(textStyle: .title2)
        let symbol = UIImage(systemName: entry.symbol, withConfiguration: symbolConfig)
        cell.imageView?.image = symbol
        cell.imageView?.tintColor = Sumi.Color.accent

        cell.accessoryType = .disclosureIndicator
        cell.backgroundColor = Sumi.Color.surfaceElevated
        return cell
    }
}

// MARK: - UITableViewDelegate

extension GalleryListViewController: UITableViewDelegate {

    public func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard indexPath.row < entries.count else { return }
        let entry = entries[indexPath.row]
        let vc = entry.make()
        vc.title = entry.title
        navigationController?.pushViewController(vc, animated: true)
    }
}

// MARK: - Cell
//
// UITableViewCell subclass with `style: .subtitle` baked in.
// iOS 13 doesn't support setting the style at dequeue-time on
// a default cell — the `.subtitle` style must come from the
// init, hence a tiny subclass.

private final class GalleryEntryCell: UITableViewCell {
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: .subtitle, reuseIdentifier: reuseIdentifier)
    }
    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }
}
