import XCTest
@testable import FoldCore

final class EffectSettingsTests:XCTestCase {
    private func withDefaults(_ body:(UserDefaults)->Void) {
        let name="LidFlowTests.\(UUID().uuidString)"
        let isolated=UserDefaults(suiteName:name)!
        defer {isolated.removePersistentDomain(forName:name)}
        body(isolated)
    }
    func testEachStyleSurvivesSwitchAndStoreRecreation() {
        withDefaults { defaults in
            let store=EffectSettingsStore(defaults:defaults)
            let silk=EffectSettings(perspective:0.3,blur:0.8,shadow:0.2)
            let ash=EffectSettings(perspective:0.2,blur:0.4,shadow:0.9)
            store.save(silk,for:0);store.save(ash,for:3);store.selectedStyle=3
            let reopened=EffectSettingsStore(defaults:defaults)
            XCTAssertEqual(reopened.settings(for:0),silk)
            XCTAssertEqual(reopened.settings(for:3),ash)
            XCTAssertEqual(reopened.settings(for:1),.preset(1))
            XCTAssertEqual(reopened.selectedStyle,3)
        }
    }
    func testResetOnlyCurrentEffect() {
        withDefaults { defaults in
            let store=EffectSettingsStore(defaults:defaults)
            let custom=EffectSettings(perspective:0.2,blur:0.6,shadow:0.1)
            store.save(custom,for:0);store.save(custom,for:2);store.selectedStyle=2
            defaults.set(123,forKey:"clearAngle");store.reset(2)
            XCTAssertEqual(store.settings(for:2),.preset(2))
            XCTAssertEqual(store.settings(for:0),custom)
            XCTAssertEqual(store.selectedStyle,2)
            XCTAssertEqual(defaults.integer(forKey:"clearAngle"),123)
        }
    }
    func testLegacyGlobalValuesMigrateOnlyToPreviouslySelectedStyle() {
        withDefaults { defaults in
            defaults.set(1,forKey:"style");defaults.set(0.23,forKey:"perspective")
            defaults.set(0.42,forKey:"blur");defaults.set(0.87,forKey:"shadow")
            let store=EffectSettingsStore(defaults:defaults)
            XCTAssertEqual(store.settings(for:1),EffectSettings(perspective:0.23,blur:0.42,shadow:0.87))
            XCTAssertEqual(store.settings(for:0),.preset(0))
            store.selectedStyle=3
            XCTAssertEqual(EffectSettingsStore(defaults:defaults).settings(for:3),.preset(3))
            store.reset(1)
            XCTAssertEqual(EffectSettingsStore(defaults:defaults).settings(for:1),.preset(1))
        }
    }
}
