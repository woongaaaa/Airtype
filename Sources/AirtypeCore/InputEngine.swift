import Foundation

/// Deterministic, hardware-free state machine. All calls must use one serial executor.
public final class InputEngine {
    public private(set) var mode: ControlMode = .paused
    public var calibration: CalibrationProfile?
    public var preferredHand: HandSide = .right
    private var lastTime: Double?
    private var validSince: Double?
    private var lastTypingHands = Set<HandSide>()
    private var taps: [String: TapState] = [:]
    private var xFilter = OneEuroFilter(), yFilter = OneEuroFilter()
    private var held: MouseButton?
    private var heldClicks = 1
    private var lastClickTime: Double = -.infinity
    private var lastClickPoint: Joint?
    private var pinchPoint: Joint?
    private var dragStarted = false
    private var scrollY: Double?
    private var palmStart: (time: Double, x: Double)?
    private var palmCooldown: Double = -.infinity
    private var bothOpenSince: Double?
    private var menuLatched = false
    private var selection: (mode: ControlMode, time: Double)?

    public init(calibration: CalibrationProfile? = nil) { self.calibration = calibration }

    @discardableResult public func setMode(_ requested: ControlMode) -> [InputIntent] {
        let next: ControlMode = requested == .keyboard && calibration?.valid != true ? .ready : requested
        resetMotion()
        mode = next
        validSince = nil
        return [.releaseAll, .mode(next)]
    }

    /// Also called by the app's watchdog when camera callbacks stop entirely.
    public func tick(at time: Double) -> [InputIntent] {
        guard [.keyboard, .pointer, .choosing].contains(mode), let lastTime,
              time-lastTime > 0.25 else { return [] }
        return setMode(.lost)
    }

    public func consume(_ frame: HandFrame) -> [InputIntent] {
        guard frame.valid else { return setMode(.lost) }
        if let lastTime, frame.timestamp <= lastTime { return [] }
        let gap = lastTime.map { frame.timestamp-$0 > 0.25 } ?? false
        lastTime = frame.timestamp
        if gap && [.keyboard, .pointer, .choosing].contains(mode) { return setMode(.lost) }
        let usable = frame.hands.filter { $0.scale != nil }
        if usable.isEmpty {
            bothOpenSince = nil; menuLatched = false
            return [.keyboard, .pointer, .choosing].contains(mode) ? setMode(.lost) : []
        }
        if mode == .lost {
            if validSince == nil { validSince = frame.timestamp }
            if frame.timestamp-validSince! >= 0.5 { return setMode(.ready) }
            return []
        }
        // Both palms held for 1.5s opens a mode menu. A release is required to rearm.
        if usable.count == 2 && usable.allSatisfy(\.isOpenPalm) {
            if bothOpenSince == nil { bothOpenSince = frame.timestamp }
            if !menuLatched && frame.timestamp-bothOpenSince! >= 1.5 {
                menuLatched = true
                return setMode(.choosing)
            }
        } else { bothOpenSince = nil; menuLatched = false }
        switch mode {
        case .choosing:
            guard let hand = usable.first(where: { $0.side == preferredHand }), let tip = hand.point("indexTip"),
                  (0.25...0.75).contains(tip.y), !hand.isOpenPalm else { selection = nil; return [] }
            let target: ControlMode = tip.x < 0.33 ? .paused : tip.x < 0.66 ? .keyboard : .pointer
            if selection?.mode != target { selection = (target, frame.timestamp) }
            if frame.timestamp-selection!.time >= 1 { return setMode(target) }
            return []
        case .keyboard: return type(usable, at: frame.timestamp)
        case .pointer:
            guard let hand = usable.first(where: { $0.side == preferredHand }) else { return setMode(.lost) }
            return point(hand, at: frame.timestamp)
        default: return []
        }
    }

    private func resetMotion() {
        taps.removeAll(); lastTypingHands.removeAll(); held = nil; pinchPoint = nil
        dragStarted = false; scrollY = nil; palmStart = nil; selection = nil
        lastClickTime = -.infinity; lastClickPoint = nil
        xFilter.reset(); yFilter.reset()
    }

    private struct TapState {
        var last: Joint
        var offset: Double
        var time: Double
        var start: (offset: Double, point: Joint, time: Double)?
        var pressed = false
        var peak = 0.0
        var rest = 0.0
    }

    private func type(_ hands: [Hand], at time: Double) -> [InputIntent] {
        guard let calibration, calibration.valid, hands.count == 2 else { return setMode(.lost) }
        let sides = Set(hands.map(\.side))
        if !lastTypingHands.isEmpty && sides != lastTypingHands { return setMode(.lost) }
        lastTypingHands = sides
        var events: [InputIntent] = []
        var candidates: [(id: String, strength: Double)] = []
        for hand in hands {
            guard let scale = hand.scale else { continue }
            for finger in Finger.allCases {
                let id = hand.side.rawValue + "." + finger.rawValue
                guard let tip = hand.point(finger.tip), let base = hand.point(finger.base) else {
                    // Clear an occluded finger's trajectory; never bridge a tracking hole.
                    taps.removeValue(forKey: id); continue
                }
                let offset = (tip.y-base.y)/scale
                guard var state = taps[id], time-state.time < 0.2,
                      tip.distance(to: state.last) < scale * 0.9 else {
                    taps[id] = TapState(last: tip, offset: offset, time: time); continue
                }
                let dt = max(0.001, time-state.time)
                let velocity = (offset-state.offset)/dt
                let threshold = calibration.tapThresholds[id] ?? calibration.pressThreshold
                if state.pressed {
                    state.peak = max(state.peak, offset)
                    // Release only after returning close to the pre-press pose.
                    if offset < state.rest + threshold*0.4 { state.pressed = false; state.start = nil }
                } else {
                    if state.start == nil && velocity > 0.5 {
                        state.start = (state.offset, state.last, state.time)
                    }
                    if let start = state.start {
                        let excursion = offset-start.offset
                        if time-start.time > 0.3 || excursion < -0.05 { state.start = nil }
                        else if excursion >= threshold && velocity > 0 {
                            state.pressed = true; state.peak = offset; state.rest = start.offset
                            if let key = KeyboardLayout.key(at: start.point, board: calibration.board) {
                                candidates.append((finger == .thumb ? "space" : key, excursion/threshold))
                            }
                            state.start = nil
                        }
                    }
                }
                state.last = tip; state.offset = offset; state.time = time; taps[id] = state
            }
        }
        // A physical typing stroke often moves adjacent fingers too. Admit one winner per frame.
        let ranked = candidates.sorted { $0.strength > $1.strength }
        if let winner = ranked.first, ranked.count == 1 || winner.strength > ranked[1].strength * 1.15 {
            events.append(.key(winner.id))
        }
        return events
    }

    private func point(_ hand: Hand, at time: Double) -> [InputIntent] {
        guard let scale = hand.scale, let tip = hand.point("indexTip"), let thumb = hand.point("thumbTip"),
              let middle = hand.point("middleTip") else { return setMode(.lost) }
        let pointer = Joint(x: min(1,max(0,(tip.x-0.15)/0.7)), y: min(1,max(0,(tip.y-0.15)/0.7)))
        let leftDistance = tip.distance(to: thumb)/scale
        let rightDistance = middle.distance(to: thumb)/scale
        let leftPinch = leftDistance < (held == .left ? 0.42 : 0.27)
        let rightPinch = rightDistance < (held == .right ? 0.42 : 0.27)
        var events: [InputIntent] = []
        if let current = held {
            let stillHeld = current == .left ? leftPinch : rightPinch
            if !stillHeld {
                events.append(.button(current, down: false, clicks: heldClicks))
                if current == .left { lastClickTime = heldClicks == 2 ? -.infinity : time; lastClickPoint = pinchPoint }
                held = nil; pinchPoint = nil; dragStarted = false
                xFilter.reset(); yFilter.reset()
            } else if current == .left {
                if let pinchPoint, pointer.distance(to: pinchPoint) > 0.035 { dragStarted = true }
                if dragStarted { events.append(.move(x: xFilter.update(pointer.x, at: time), y: yFilter.update(pointer.y, at: time))) }
                return events
            } else { return [] }
        } else if leftPinch || rightPinch {
            let button: MouseButton = leftPinch ? .left : .right
            heldClicks = button == .left && time-lastClickTime < 0.4
                && (lastClickPoint?.distance(to: pointer) ?? 1) < 0.04 ? 2 : 1
            if heldClicks == 2 { lastClickTime = -.infinity }
            held = button; pinchPoint = pointer; scrollY = nil; palmStart = nil
            // Move once before pressing; suppress pinch-induced cursor motion while held.
            events += [.move(x: pointer.x, y: pointer.y), .button(button, down: true, clicks: heldClicks)]
            return events
        }
        if hand.isOpenPalm {
            scrollY = nil
            if palmStart == nil { palmStart = (time, tip.x) }
            if let start = palmStart, time-start.time > 0.15, time-start.time < 0.7,
               abs(tip.x-start.x) > 0.18, time-palmCooldown > 0.9 {
                events.append(.navigate(back: tip.x < start.x)); palmCooldown = time; palmStart = nil
            } else if let start = palmStart, time-start.time > 0.7 { palmStart = (time,tip.x) }
            return events
        }
        palmStart = nil
        if let ring = hand.point("ringTip"), let ringPIP = hand.point("ringPIP"),
           let indexPIP = hand.point("indexPIP"), let middlePIP = hand.point("middlePIP"),
           tip.y < indexPIP.y, middle.y < middlePIP.y, ring.y > ringPIP.y {
            if let previous = scrollY { events.append(.scroll(x: 0, y: (previous-middle.y)*900)) }
            scrollY = middle.y
            return events
        }
        scrollY = nil
        events.append(.move(x: xFilter.update(pointer.x, at: time), y: yFilter.update(pointer.y, at: time)))
        return events
    }
}
