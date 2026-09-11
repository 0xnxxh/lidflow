import Foundation

public struct EffectSettings: Equatable {
    public var perspective:Double
    public var blur:Double
    public var shadow:Double
    public init(perspective:Double,blur:Double,shadow:Double) {
        self.perspective=perspective;self.blur=blur;self.shadow=shadow
    }
    public static func preset(_ style:Int)->Self {
        switch style {
        case 1:return Self(perspective:0.9,blur:0.35,shadow:0.65)
        case 2:return Self(perspective:0.85,blur:1,shadow:0.3)
        case 3:return Self(perspective:0.6,blur:0.7,shadow:0.55)
        default:return Self(perspective:1,blur:0.65,shadow:0.45)
        }
    }
}

/// Each material owns its settings. Migrate the old global values once, only
/// into the material they belonged to; never overwrite an existing profile.
public final class EffectSettingsStore {
    private let defaults:UserDefaults
    private func key(_ style:Int)->String {"effect.\(style)"}
    public init(defaults:UserDefaults) {
        self.defaults=defaults
        let selected=selectedStyle
        if !defaults.bool(forKey:"effectSettingsMigrated"), defaults.dictionary(forKey:key(selected)) == nil,
           defaults.object(forKey:"perspective") != nil || defaults.object(forKey:"blur") != nil || defaults.object(forKey:"shadow") != nil {
            let preset=EffectSettings.preset(selected)
            save(EffectSettings(perspective:defaults.object(forKey:"perspective") as? Double ?? preset.perspective,
                                blur:defaults.object(forKey:"blur") as? Double ?? preset.blur,
                                shadow:defaults.object(forKey:"shadow") as? Double ?? preset.shadow),for:selected)
        }
        defaults.set(true,forKey:"effectSettingsMigrated")
    }
    public var selectedStyle:Int {
        get {let value=defaults.integer(forKey:"style");return (0...3).contains(value) ? value : 0}
        set {defaults.set((0...3).contains(newValue) ? newValue : 0,forKey:"style")}
    }
    public func settings(for style:Int)->EffectSettings {
        let preset=EffectSettings.preset(style),stored=defaults.dictionary(forKey:key(style)) ?? [:]
        func read(_ key:String,_ fallback:Double)->Double {
            guard let value=stored[key] as? Double,value.isFinite else{return fallback}
            return min(1,max(0,value))
        }
        return EffectSettings(perspective:read("perspective",preset.perspective),blur:read("blur",preset.blur),shadow:read("shadow",preset.shadow))
    }
    public func save(_ value:EffectSettings,for style:Int) {
        defaults.set(["perspective":value.perspective,"blur":value.blur,"shadow":value.shadow],forKey:key(style))
    }
    public func reset(_ style:Int) {save(.preset(style),for:style)}
}
