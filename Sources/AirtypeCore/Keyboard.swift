import Foundation

public struct Rect: Codable, Equatable, Sendable {
    public var x: Double, y: Double, width: Double, height: Double
    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x; self.y = y; self.width = width; self.height = height
    }
    public func contains(_ p: Joint) -> Bool {
        p.x >= x && p.x < x + width && p.y >= y && p.y < y + height
    }
}
public struct KeyRegion: Equatable, Sendable {
    public let id: String
    public let rect: Rect
}

public enum KeyboardLayout {
    public static let rows: [[String]] = [
        ["esc", "`", "1", "2", "3", "4", "5", "6", "7", "8", "9", "0", "-", "=", "backspace"],
        ["tab", "q", "w", "e", "r", "t", "y", "u", "i", "o", "p", "[", "]", "\\"],
        ["control", "a", "s", "d", "f", "g", "h", "j", "k", "l", ";", "'", "enter"],
        ["shift", "z", "x", "c", "v", "b", "n", "m", ",", ".", "/", "up", "shift"],
        ["option", "command", "language", "space", "command", "left", "down", "right"]
    ]
    public static let labels: [String: String] = [
        "esc":"esc", "backspace":"⌫", "tab":"⇥", "control":"⌃", "enter":"↩",
        "shift":"⇧", "option":"⌥", "command":"⌘", "language":"한/영", "space":"space",
        "left":"←", "right":"→", "up":"↑", "down":"↓"
    ]
    public static let hangul: [String: String] = Dictionary(uniqueKeysWithValues:
        zip(Array("qwertyuiopasdfghjklzxcvbnm").map(String.init),
            Array("ㅂㅈㄷㄱㅅㅛㅕㅑㅐㅔㅁㄴㅇㄹㅎㅗㅓㅏㅣㅋㅌㅊㅍㅠㅜㅡ").map(String.init)))
    public static let keys: [KeyRegion] = rows.enumerated().flatMap { row, keys in
        let units = keys.map { $0 == "space" ? 5.0 : 1.0 }
        let total = units.reduce(0, +)
        var x = 0.0
        return zip(keys, units).map { id, units in
            defer { x += units / total }
            return KeyRegion(id: id, rect: Rect(x: x, y: Double(row) / 5, width: units / total, height: 0.2))
        }
    }
    public static func key(at point: Joint, board: Rect) -> String? {
        guard board.width > 0, board.height > 0, board.contains(point) else { return nil }
        let local = Joint(x: (point.x-board.x)/board.width, y: (point.y-board.y)/board.height)
        return keys.first { $0.rect.contains(local) }?.id
    }
}

public struct CalibrationProfile: Codable, Equatable, Sendable {
    public var version: Int = 1
    public var board: Rect
    public var scales: [String: Double]
    public var pressThreshold: Double = 0.16
    public var tapThresholds: [String: Double] = [:]
    public init(board: Rect, scales: [String: Double]) { self.board = board; self.scales = scales }
    public var valid: Bool {
        version == 1 && [board.x, board.y, board.width, board.height, pressThreshold].allSatisfy(\.isFinite)
        && board.width >= 0.2 && board.height >= 0.12 && board.x >= 0 && board.y >= 0
        && board.x + board.width <= 1.001 && board.y + board.height <= 1.001
        && (0.05...0.5).contains(pressThreshold)
        && tapThresholds.values.allSatisfy { $0.isFinite && (0.05...0.5).contains($0) }
        && HandSide.allCases.allSatisfy { (scales[$0.rawValue] ?? 0) >= 0.035 }
    }
    /// Home-row calibration only. Real per-finger tap tuning is an explicit research gate.
    public static func make(from frames: [HandFrame]) -> CalibrationProfile? {
        guard frames.count >= 20 else { return nil }
        var tips: [Joint] = [], scales: [String: [Double]] = [:]
        for frame in frames {
            guard frame.valid, frame.hands.count == 2 else { return nil }
            for hand in frame.hands {
                guard let scale = hand.scale else { return nil }
                scales[hand.side.rawValue, default: []].append(scale)
                for finger in [Finger.index, .middle, .ring, .little] {
                    guard let tip = hand.point(finger.tip), hand.point(finger.base) != nil else { return nil }
                    tips.append(tip)
                }
            }
        }
        // Reject motion during calibration instead of silently creating an unstable board.
        for side in HandSide.allCases {
            let points = frames.compactMap { $0.hands.first { $0.side == side }?.point("indexTip") }
            guard let first = points.first, points.allSatisfy({ $0.distance(to: first) < 0.035 }) else { return nil }
        }
        let minX = tips.map(\.x).min()!, maxX = tips.map(\.x).max()!
        let width = min(0.9, max(0.45, (maxX-minX) * 1.3))
        let height = min(0.5, width * 0.5)
        let centerY = tips.map(\.y).reduce(0,+) / Double(tips.count)
        let board = Rect(x: max(0, min(1-width, (minX+maxX-width)/2)),
                         y: max(0, min(1-height, centerY-height*0.5)), width: width, height: height)
        let profile = CalibrationProfile(board: board, scales: scales.mapValues { $0.reduce(0,+)/Double($0.count) })
        return profile.valid ? profile : nil
    }
}
