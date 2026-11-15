import Foundation

struct ReverbParameters: Sendable, Equatable {
    var presetID: String
    var decaySeconds: Float
    var size: Float
    var preDelayMs: Float
    var tone: Float
    var width: Float
    var modulation: Float
    var early: Float

    struct Preset: Sendable, Identifiable {
        let id: String
        let name: String
        let parameters: ReverbParameters
    }

    private static func preset(_ id: String, _ name: String, _ decay: Float, _ room: Float,
                               _ predelay: Float, _ tone: Float, _ width: Float,
                               _ modulation: Float, _ early: Float) -> Preset {
        Preset(id: id, name: name, parameters: ReverbParameters(presetID: id,
            decaySeconds: decay, size: (room - 10) / 150, preDelayMs: predelay,
            tone: tone, width: width, modulation: modulation, early: early))
    }

    static let presets: [Preset] = [
        preset("room", "Комната", 0.8, 25, 5, 0.45, 0.7, 0.1, 1.5),
        preset("chamber", "Камерный зал", 2.2, 60, 18, 0.5, 1, 0.2, 1.2),
        preset("concert", "Концертный зал", 3.5, 110, 25, 0.6, 1, 0.3, 1),
        preset("warm", "Тёплый", 2.8, 80, 15, 0.15, 0.9, 0.25, 1.1),
        preset("airy", "Воздушный", 4.5, 110, 30, 0.9, 1, 0.4, 0.8),
        preset("ambient", "Эмбиент", 12, 150, 40, 0.4, 1, 0.85, 0.55)
    ]
    static let `default` = presets[1].parameters

    static func parameters(for id: String) -> ReverbParameters {
        presets.first { $0.id == id }?.parameters ?? .default
    }

    var isModified: Bool { self != Self.parameters(for: presetID) }

    func sanitized() -> ReverbParameters {
        var result = self
        let fallback = Self.parameters(for: presetID)
        result.presetID = fallback.presetID
        func bounded(_ value: Float, _ range: ClosedRange<Float>, _ fallback: Float) -> Float {
            value.isFinite ? min(range.upperBound, max(range.lowerBound, value)) : fallback
        }
        result.decaySeconds = bounded(decaySeconds, 0.3...20, fallback.decaySeconds)
        result.size = bounded(size, 0...1, fallback.size)
        result.preDelayMs = bounded(preDelayMs, 0...100, fallback.preDelayMs)
        result.tone = bounded(tone, 0...1, fallback.tone)
        result.width = bounded(width, 0...1, fallback.width)
        result.modulation = bounded(modulation, 0...1, fallback.modulation)
        result.early = fallback.early
        return result
    }
}
