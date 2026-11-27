import Foundation

public enum HandSide: String, Codable, CaseIterable, Sendable { case left, right }
public enum Finger: String, Codable, CaseIterable, Sendable {
    case thumb, index, middle, ring, little
    public var tip: String { rawValue + "Tip" }
    public var base: String { rawValue + "MCP" }
    public var middleJoint: String { rawValue + (self == .thumb ? "IP" : "PIP") }
}

/// Canonical coordinates: mirrored image, x rightward, y downward; [0, 1].
/// z is optional model-relative depth, never a physical contact measurement.
public struct Joint: Codable, Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var z: Double?
    public var confidence: Double?
    public init(x: Double, y: Double, z: Double? = nil, confidence: Double? = nil) {
        self.x = x; self.y = y; self.z = z; self.confidence = confidence
    }
    public var valid: Bool {
        x.isFinite && y.isFinite && (0...1).contains(x) && (0...1).contains(y)
        && (confidence.map { $0.isFinite && $0 >= 0.35 } ?? true)
    }
    public func distance(to other: Joint) -> Double { hypot(x - other.x, y - other.y) }
}

public struct Hand: Codable, Equatable, Sendable {
    public var side: HandSide
    public var joints: [String: Joint]
    public init(side: HandSide, joints: [String: Joint]) { self.side = side; self.joints = joints }
    public func point(_ name: String) -> Joint? {
        guard let point = joints[name], point.valid else { return nil }; return point
    }
    public var scale: Double? {
        guard let wrist = point("wrist"), let middle = point("middleMCP") else { return nil }
        let size = wrist.distance(to: middle)
        return size >= 0.035 ? size : nil
    }
    public var isOpenPalm: Bool {
        guard let scale, let thumb = point("thumbTip"), let index = point("indexTip"),
              thumb.distance(to: index) > scale * 0.65 else { return false }
        return [Finger.index, .middle, .ring, .little].allSatisfy {
            guard let tip = point($0.tip), let pip = point($0.middleJoint), let base = point($0.base) else { return false }
            return tip.y < pip.y - scale * 0.08 && pip.y < base.y - scale * 0.08
        }
    }
}

public struct HandFrame: Codable, Equatable, Sendable {
    public var schemaVersion: Int = 1
    public var timestamp: Double
    public var hands: [Hand]
    public init(timestamp: Double, hands: [Hand]) { self.timestamp = timestamp; self.hands = hands }
    public var valid: Bool {
        schemaVersion == 1 && timestamp.isFinite && timestamp >= 0 && hands.count <= 2
        && Set(hands.map(\.side)).count == hands.count
    }
}

public enum ControlMode: String, Codable, CaseIterable, Sendable {
    case paused, ready, choosing, keyboard, pointer, lost
}
public enum MouseButton: String, Codable, Sendable { case left, right }
public enum InputIntent: Equatable, Sendable {
    case move(x: Double, y: Double)
    case button(MouseButton, down: Bool, clicks: Int)
    case scroll(x: Double, y: Double)
    case key(String)
    case navigate(back: Bool)
    case releaseAll
    case mode(ControlMode)
}

public protocol HandTracker: AnyObject {
    var onFrame: ((HandFrame) -> Void)? { get set }
    func start() throws
    func stop()
}
