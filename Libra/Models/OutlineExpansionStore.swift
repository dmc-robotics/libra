import Foundation

/// Remembers which assemblies are open in the sidebar outline of each file, so reopening a file restores them.
/// Kept in user defaults by file path rather than in the file, so opening an assembly doesn't edit the document.
struct OutlineExpansionStore {
    /// Joins an assembly path's names into one string (the same separator the STEP importer uses).
    private static let pathSeparator = "\u{1f}"

    var defaults: UserDefaults = .standard

    func expandedAssemblies(for fileURL: URL) -> Set<[String]> {
        let saved = defaults.dictionary(forKey: Preferences.expandedAssembliesKey)?[fileURL.path] as? [String] ?? []
        return Set(saved.map { $0.components(separatedBy: Self.pathSeparator) })
    }

    func save(_ expanded: Set<[String]>, for fileURL: URL) {
        var all = defaults.dictionary(forKey: Preferences.expandedAssembliesKey) ?? [:]
        all[fileURL.path] = expanded.map { $0.joined(separator: Self.pathSeparator) }.sorted()
        defaults.set(all, forKey: Preferences.expandedAssembliesKey)
    }
}
