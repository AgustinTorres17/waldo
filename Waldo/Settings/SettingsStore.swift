import Foundation

/// User preferences, persisted in UserDefaults.
@MainActor
final class SettingsStore: ObservableObject {
    private enum Key {
        static let targetLanguage = "targetLanguage"
        static let engineMode = "engineMode"
        static let llamaIdleUnloadSeconds = "llamaIdleUnloadSeconds"
        static let llamaModelID = "llamaModelID"
        static let popupEnabled = "popupEnabled"
        static let keyboardSelectionEnabled = "keyboardSelectionEnabled"
        static let excludedBundleIDs = "excludedBundleIDs"
        static let accessibleBrowserBundleIDs = "accessibleBrowserBundleIDs"
        static let customModes = "customModes"
        static let activeModeID = "activeModeID"
        static let appModeRules = "appModeRules"
        static let showChanges = "showChanges"
        static let glossary = "glossary"
        static let appTheme = "appTheme"
        static let chatLanguage = "explainLanguage" // named before Chat existed
        static let chatSearchesWeb = "explainSearchesWeb"
        static let chatThinks = "chatThinks"
        static let searchProvider = "searchProvider"
        static let searXNGURL = "searXNGURL"
    }

    private let defaults: UserDefaults

    /// Read by WaldoApp through @AppStorage to show or hide the menu bar icon.
    nonisolated static let showsMenuBarIconKey = "showsMenuBarIcon"

    /// Waldo is a Dock app; its menu bar icon is optional.
    @Published var showsMenuBarIcon: Bool {
        didSet { defaults.set(showsMenuBarIcon, forKey: Self.showsMenuBarIconKey) }
    }

    @Published var targetLanguage: TargetLanguage {
        didSet { defaults.set(targetLanguage.rawValue, forKey: Key.targetLanguage) }
    }

    /// The language Explain answers in.
    @Published var chatLanguage: TargetLanguage {
        didSet { defaults.set(chatLanguage.rawValue, forKey: Key.chatLanguage) }
    }

    /// Explain searches the web before answering (the 🌐 button in its panel).
    @Published var chatSearchesWeb: Bool {
        didSet { defaults.set(chatSearchesWeb, forKey: Key.chatSearchesWeb) }
    }

    /// Chat answers think first (the brain button in its panel).
    @Published var chatThinks: Bool {
        didSet { defaults.set(chatThinks, forKey: Key.chatThinks) }
    }

    @Published var searchProvider: SearchProvider {
        didSet { defaults.set(searchProvider.rawValue, forKey: Key.searchProvider) }
    }

    /// The user's SearXNG instance, e.g. http://localhost:8888.
    @Published var searXNGURL: String {
        didSet { defaults.set(searXNGURL, forKey: Key.searXNGURL) }
    }

    @Published var engineMode: EngineMode {
        didSet { defaults.set(engineMode.rawValue, forKey: Key.engineMode) }
    }

    /// How long a loaded llama.cpp model may stay in memory without requests.
    @Published var llamaIdleUnloadSeconds: Int {
        didSet { defaults.set(llamaIdleUnloadSeconds, forKey: Key.llamaIdleUnloadSeconds) }
    }

    /// The curated llama.cpp model to use (ModelCatalog id).
    @Published var llamaModelID: String {
        didSet { defaults.set(llamaModelID, forKey: Key.llamaModelID) }
    }

    /// Show the Translate/Correct popup when text is selected in an editable field.
    @Published var popupEnabled: Bool {
        didSet { defaults.set(popupEnabled, forKey: Key.popupEnabled) }
    }

    /// Also show the popup after Shift+arrow or ⌘A selections, not just mouse selections.
    @Published var keyboardSelectionEnabled: Bool {
        didSet { defaults.set(keyboardSelectionEnabled, forKey: Key.keyboardSelectionEnabled) }
    }

    /// Apps where the popup never appears.
    @Published var excludedBundleIDs: [String] {
        didSet { defaults.set(excludedBundleIDs, forKey: Key.excludedBundleIDs) }
    }

    /// Chromium browsers where Waldo turns on AXEnhancedUserInterface so the popup works.
    @Published var accessibleBrowserBundleIDs: [String] {
        didSet { defaults.set(accessibleBrowserBundleIDs, forKey: Key.accessibleBrowserBundleIDs) }
    }

    /// Highlight what a correction changed in the popup's result.
    @Published var showChanges: Bool {
        didSet { defaults.set(showChanges, forKey: Key.showChanges) }
    }

    /// The look of Waldo's windows and popup.
    @Published var appTheme: AppTheme {
        didSet {
            Theme.current = appTheme
            defaults.set(appTheme.rawValue, forKey: Key.appTheme)
        }
    }

    /// Terms Waldo never changes, one per line (see Glossary).
    @Published var glossaryText: String {
        didSet { defaults.set(glossaryText, forKey: Key.glossary) }
    }

    var glossary: [String] { Glossary.terms(from: glossaryText) }

    /// User-defined modes, in the order shown in menus.
    @Published var customModes: [CustomMode] {
        didSet {
            defaults.set(try? JSONEncoder().encode(customModes), forKey: Key.customModes)
            if let activeModeID, !customModes.contains(where: { $0.id == activeModeID }) {
                self.activeModeID = nil
            }
            // An app whose mode was deleted falls back to the default.
            let ids = Set(customModes.map(\.id))
            let kept = appModeRules.filter { $0.modeID.map(ids.contains) ?? true }
            if kept != appModeRules { appModeRules = kept }
        }
    }

    /// The default mode, used in apps without a rule; nil for Waldo's defaults.
    @Published var activeModeID: UUID? {
        didSet { defaults.set(activeModeID?.uuidString, forKey: Key.activeModeID) }
    }

    /// Apps that use their own mode and language instead of the defaults.
    @Published var appModeRules: [AppRule] {
        didSet { defaults.set(try? JSONEncoder().encode(appModeRules), forKey: Key.appModeRules) }
    }

    /// The mode for text in `bundleID`: its rule if it has one, else the default.
    func modeID(for bundleID: String?) -> UUID? {
        if let rule = appModeRules.first(where: { $0.bundleID == bundleID }) { return rule.modeID }
        return activeModeID
    }

    func mode(for bundleID: String?) -> CustomMode? {
        let id = modeID(for: bundleID)
        return customModes.first { $0.id == id }
    }

    /// Changes the app's rule if it has one, else the default mode.
    func setModeID(_ id: UUID?, for bundleID: String?) {
        if let index = appModeRules.firstIndex(where: { $0.bundleID == bundleID }) {
            appModeRules[index].modeID = id
        } else {
            activeModeID = id
        }
    }

    func hasRule(for bundleID: String?) -> Bool {
        appModeRules.contains { $0.bundleID == bundleID }
    }

    /// The language for text in `bundleID`: its rule's if set, else the default.
    func language(for bundleID: String?) -> TargetLanguage {
        appModeRules.first { $0.bundleID == bundleID }?.language ?? targetLanguage
    }

    /// Changes the app's rule if it has one, else the default language.
    func setLanguage(_ language: TargetLanguage, for bundleID: String?) {
        if let index = appModeRules.firstIndex(where: { $0.bundleID == bundleID }) {
            appModeRules[index].language = language
        } else {
            targetLanguage = language
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        targetLanguage = defaults.string(forKey: Key.targetLanguage).flatMap(TargetLanguage.init) ?? .english
        chatLanguage = defaults.string(forKey: Key.chatLanguage).flatMap(TargetLanguage.init)
            ?? TargetLanguage.preferred ?? .english
        chatSearchesWeb = defaults.bool(forKey: Key.chatSearchesWeb)
        chatThinks = defaults.bool(forKey: Key.chatThinks)
        showsMenuBarIcon = defaults.bool(forKey: Self.showsMenuBarIconKey)
        searchProvider = defaults.string(forKey: Key.searchProvider).flatMap(SearchProvider.init) ?? .duckDuckGo
        searXNGURL = defaults.string(forKey: Key.searXNGURL) ?? ""
        engineMode = defaults.string(forKey: Key.engineMode).flatMap(EngineMode.init) ?? .auto
        let idle = defaults.integer(forKey: Key.llamaIdleUnloadSeconds)
        llamaIdleUnloadSeconds = idle > 0 ? idle : 120
        llamaModelID = defaults.string(forKey: Key.llamaModelID)
            .flatMap(ModelCatalog.model(id:))?.id ?? ModelCatalog.recommended.id
        popupEnabled = defaults.object(forKey: Key.popupEnabled) as? Bool ?? true
        keyboardSelectionEnabled = defaults.object(forKey: Key.keyboardSelectionEnabled) as? Bool ?? true
        excludedBundleIDs = defaults.stringArray(forKey: Key.excludedBundleIDs) ?? []
        accessibleBrowserBundleIDs = defaults.stringArray(forKey: Key.accessibleBrowserBundleIDs) ?? []
        showChanges = defaults.object(forKey: Key.showChanges) as? Bool ?? true
        glossaryText = defaults.string(forKey: Key.glossary) ?? ""
        let theme = defaults.string(forKey: Key.appTheme).flatMap(AppTheme.init) ?? .glass
        appTheme = theme
        Theme.current = theme
        appModeRules = defaults.data(forKey: Key.appModeRules)
            .flatMap { try? JSONDecoder().decode([AppRule].self, from: $0) } ?? []
        // Starter modes on first launch only, so deleting them sticks.
        customModes = defaults.data(forKey: Key.customModes)
            .flatMap { try? JSONDecoder().decode([CustomMode].self, from: $0) } ?? CustomMode.starters
        activeModeID = defaults.string(forKey: Key.activeModeID).flatMap(UUID.init)
    }
}
