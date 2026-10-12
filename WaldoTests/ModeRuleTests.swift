import Foundation
import Testing
@testable import Waldo

@MainActor
struct ModeRuleTests {
    private func store() -> SettingsStore {
        SettingsStore(defaults: UserDefaults(suiteName: "mode-rules-\(UUID())")!)
    }

    @Test func appRuleWinsOverDefault() {
        let settings = store()
        let (work, friends) = (settings.customModes[0], settings.customModes[1])
        settings.activeModeID = work.id
        settings.appModeRules = [AppRule(bundleID: "net.whatsapp.WhatsApp", modeID: friends.id),
                                 AppRule(bundleID: "com.apple.mail", modeID: nil)]
        #expect(settings.mode(for: "net.whatsapp.WhatsApp") == friends)
        #expect(settings.mode(for: "com.apple.mail") == nil)
        #expect(settings.mode(for: "com.tinyspeck.slackmacgap") == work)
        #expect(settings.mode(for: nil) == work)
    }

    @Test func pickerChangesTheRuleOrTheDefault() {
        let settings = store()
        let (work, friends) = (settings.customModes[0], settings.customModes[1])
        settings.appModeRules = [AppRule(bundleID: "net.whatsapp.WhatsApp", modeID: friends.id)]
        settings.setModeID(nil, for: "net.whatsapp.WhatsApp")
        #expect(settings.appModeRules == [AppRule(bundleID: "net.whatsapp.WhatsApp", modeID: nil)])
        #expect(settings.activeModeID == nil)
        settings.setModeID(work.id, for: "com.apple.mail")
        #expect(settings.activeModeID == work.id)
        #expect(settings.appModeRules.count == 1)
    }

    @Test func deletingAModeDropsItsRules() {
        let settings = store()
        let friends = settings.customModes[1]
        settings.appModeRules = [AppRule(bundleID: "a", modeID: friends.id), AppRule(bundleID: "b", modeID: nil)]
        settings.customModes.removeAll { $0.id == friends.id }
        #expect(settings.appModeRules == [AppRule(bundleID: "b", modeID: nil)])
    }

    @Test func appRuleLanguageWinsOverDefault() {
        let settings = store()
        settings.targetLanguage = .english
        settings.appModeRules = [AppRule(bundleID: "net.whatsapp.WhatsApp", modeID: nil, language: .spanish),
                                 AppRule(bundleID: "com.apple.mail", modeID: nil)]
        #expect(settings.language(for: "net.whatsapp.WhatsApp") == .spanish)
        #expect(settings.language(for: "com.apple.mail") == .english)
        #expect(settings.language(for: nil) == .english)

        settings.setLanguage(.portuguese, for: "net.whatsapp.WhatsApp")
        #expect(settings.appModeRules[0].language == .portuguese)
        #expect(settings.targetLanguage == .english)
        settings.setLanguage(.french, for: "com.tinyspeck.slackmacgap")
        #expect(settings.targetLanguage == .french)
    }

    @Test func rulesSavedWithoutLanguageStillLoad() throws {
        let id = UUID()
        let old = #"[{"bundleID":"a","modeID":"\#(id.uuidString)"}]"#
        let rules = try JSONDecoder().decode([AppRule].self, from: Data(old.utf8))
        #expect(rules == [AppRule(bundleID: "a", modeID: id, language: nil)])
    }

    @Test func rulesPersist() {
        let defaults = UserDefaults(suiteName: "mode-rules-\(UUID())")!
        let settings = SettingsStore(defaults: defaults)
        let rule = AppRule(bundleID: "a", modeID: settings.customModes[0].id)
        settings.appModeRules = [rule]
        #expect(SettingsStore(defaults: defaults).appModeRules == [rule])
    }
}
