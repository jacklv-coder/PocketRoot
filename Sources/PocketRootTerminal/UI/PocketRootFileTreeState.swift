import Foundation

struct PocketRootFileTreeRow: Equatable, Identifiable {
    let entry: PocketRootFileEntry
    let depth: Int

    var id: String {
        entry.path
    }
}

struct PocketRootFileTreeState: Equatable {
    private(set) var rootEntries: [PocketRootFileEntry] = []
    private(set) var childrenByDirectory: [String: [PocketRootFileEntry]] = [:]
    private(set) var expandedDirectories: Set<String> = []

    var visibleRows: [PocketRootFileTreeRow] {
        flatten(rootEntries, depth: 0)
    }

    func refreshSnapshot(
        rootEntries entries: [PocketRootFileEntry]
    ) -> Self {
        var snapshot = Self()
        snapshot.replaceRootEntries(
            entries,
            preservingExpandedDirectories: expandedDirectories
        )
        return snapshot
    }

    mutating func replaceRootEntries(
        _ entries: [PocketRootFileEntry],
        preservingExpandedDirectories: Set<String> = []
    ) {
        rootEntries = entries
        childrenByDirectory = [:]
        expandedDirectories = preservingExpandedDirectories
    }

    mutating func replaceChildren(
        _ entries: [PocketRootFileEntry],
        of directoryPath: String
    ) {
        childrenByDirectory[directoryPath] = entries
    }

    mutating func expand(_ directoryPath: String) {
        expandedDirectories.insert(directoryPath)
    }

    mutating func collapse(_ directoryPath: String) {
        expandedDirectories.remove(directoryPath)
    }

    mutating func collapse(directoriesAt paths: some Sequence<String>) {
        for path in paths {
            expandedDirectories.remove(path)
        }
    }

    func isExpanded(_ directoryPath: String) -> Bool {
        expandedDirectories.contains(directoryPath)
    }

    func hasLoadedChildren(of directoryPath: String) -> Bool {
        childrenByDirectory[directoryPath] != nil
    }

    func entry(at path: String) -> PocketRootFileEntry? {
        visibleRows.first { $0.entry.path == path }?.entry
    }

    private func flatten(
        _ entries: [PocketRootFileEntry],
        depth: Int
    ) -> [PocketRootFileTreeRow] {
        entries.flatMap { entry in
            var rows = [
                PocketRootFileTreeRow(entry: entry, depth: depth)
            ]
            if entry.kind == .directory,
               expandedDirectories.contains(entry.path),
               let children = childrenByDirectory[entry.path]
            {
                rows.append(contentsOf: flatten(children, depth: depth + 1))
            }
            return rows
        }
    }
}
