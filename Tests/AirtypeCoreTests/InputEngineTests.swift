import Testing
@testable import AirtypeCore

struct InputEngineTests {
    func hand(_ side: HandSide = .right, indexY: Double = 0.48, pinch: Bool = false) -> Hand {
        let x = side == .left ? 0.3 : 0.7
        var joints = ["wrist":Joint(x:x,y:0.8)]
        for (i,finger) in Finger.allCases.enumerated() {
            let fx = x + Double(i-1)*0.025
            joints[finger.base] = Joint(x:fx,y:0.64)
            joints[finger.middleJoint] = Joint(x:fx,y:0.55)
            joints[finger.tip] = Joint(x:fx,y:finger == .index ? indexY : 0.5)
        }
        joints["middleMCP"] = Joint(x:x,y:0.64)
        joints["thumbTip"] = Joint(x:pinch ? x+0.01 : x-0.15,y:pinch ? indexY : 0.48)
        // A curled little finger prevents the normal pointing pose from being an open palm.
        joints["littleTip"] = Joint(x:x+0.075,y:0.6)
        return Hand(side:side,joints:joints)
    }
    var profile: CalibrationProfile { CalibrationProfile(board:Rect(x:0,y:0,width:1,height:1),scales:["left":0.16,"right":0.16]) }
    func frame(_ time:Double, y:Double = 0.48) -> HandFrame {
        HandFrame(timestamp:time,hands:[hand(.left,indexY:y),hand(.right)])
    }
    @Test func testDefaultPausedCannotEmitInput() {
        let engine = InputEngine(calibration:profile)
        expectEqual(engine.consume(frame(1)),[])
        expectEqual(engine.consume(frame(1.02,y:0.54)),[])
    }
    @Test func testKeyboardRequiresValidCalibration() {
        let engine = InputEngine()
        expectEqual(engine.setMode(.keyboard),[.releaseAll,.mode(.ready)])
    }
    @Test func testSinglePressDoesNotRepeatUntilRelease() {
        let engine = InputEngine(calibration:profile); engine.setMode(.keyboard)
        expectEqual(engine.consume(frame(1)),[])
        let press = engine.consume(frame(1.03,y:0.52))
        expectEqual(press,[.key("d")])
        expectEqual(engine.consume(frame(1.06,y:0.53)),[])
        expectEqual(engine.consume(frame(1.09,y:0.53)),[])
        expectEqual(engine.consume(frame(1.12,y:0.48)),[])
        expectEqual(engine.consume(frame(1.15,y:0.52)),[.key("d")])
    }
    @Test func testStationaryHandsNeverType() {
        let engine = InputEngine(calibration:profile); engine.setMode(.keyboard)
        for i in 0..<300 { expectEqual(engine.consume(frame(1+Double(i)/30)),[]) }
    }
    @Test func testAmbiguousSimultaneousFingerMotionDoesNotChooseArbitrarily() {
        let engine = InputEngine(calibration:profile); engine.setMode(.keyboard)
        _ = engine.consume(frame(1))
        var moved = frame(1.03,y:0.52)
        moved.hands[0].joints["middleTip"]?.y += 0.04
        expectEqual(engine.consume(moved),[])
    }
    @Test func testUnorderedFramesCannotCreatePress() {
        let engine = InputEngine(calibration:profile); engine.setMode(.keyboard)
        _ = engine.consume(frame(1))
        expectEqual(engine.consume(frame(0.9,y:0.54)),[])
        expectEqual(engine.consume(frame(1,y:0.54)),[])
        expectEqual(engine.consume(frame(1.1)),[])
    }
    @Test func testCameraStallReleasesButtonsAndRequiresExplicitResume() {
        let engine = InputEngine(); engine.setMode(.pointer)
        let press = engine.consume(HandFrame(timestamp:1,hands:[hand(pinch:true)]))
        expectTrue(press.contains(.button(.left,down:true,clicks:1)))
        expectEqual(engine.tick(at:1.26),[.releaseAll,.mode(.lost)])
        for t in [1.3,1.5,1.7,1.9] { _ = engine.consume(HandFrame(timestamp:t,hands:[hand()])) }
        expectEqual(engine.mode,.ready)
    }
    @Test func testFrameGapCannotInjectStaleGesture() {
        let engine = InputEngine(); engine.setMode(.pointer)
        _ = engine.consume(HandFrame(timestamp:1,hands:[hand()]))
        expectEqual(engine.consume(HandFrame(timestamp:2,hands:[hand(pinch:true)])),[.releaseAll,.mode(.lost)])
    }
    @Test func testMissingHandInKeyboardStopsInput() {
        let engine = InputEngine(calibration:profile); engine.setMode(.keyboard)
        _ = engine.consume(frame(1))
        expectEqual(engine.consume(HandFrame(timestamp:1.03,hands:[hand(.left,indexY:0.55)])),[.releaseAll,.mode(.lost)])
    }
    @Test func testMissingFingerDoesNotBridgeOcclusion() {
        let engine = InputEngine(calibration:profile); engine.setMode(.keyboard)
        _ = engine.consume(frame(1))
        var hidden = frame(1.02); hidden.hands[0].joints.removeValue(forKey:"indexTip")
        expectEqual(engine.consume(hidden),[])
        expectEqual(engine.consume(frame(1.04,y:0.54)),[])
    }
    @Test func testDuplicateHandLabelsRejected() {
        let engine = InputEngine(); engine.setMode(.pointer)
        expectEqual(engine.consume(HandFrame(timestamp:1,hands:[hand(),hand()])),[.releaseAll,.mode(.lost)])
    }
    @Test func testPinchHysteresisAndRelease() {
        let engine = InputEngine(); engine.setMode(.pointer)
        _ = engine.consume(HandFrame(timestamp:1,hands:[hand(pinch:true)]))
        var hysteresis = hand(pinch:true)
        hysteresis.joints["thumbTip"] = Joint(x:0.75,y:0.48)
        expectEqual(engine.consume(HandFrame(timestamp:1.03,hands:[hysteresis])),[])
        let released = engine.consume(HandFrame(timestamp:1.06,hands:[hand()]))
        expectTrue(released.contains(.button(.left,down:false,clicks:1)))
    }
    @Test func testDoubleClickUsesTwoClicks() {
        let engine = InputEngine(); engine.setMode(.pointer)
        _ = engine.consume(HandFrame(timestamp:1,hands:[hand(pinch:true)]))
        _ = engine.consume(HandFrame(timestamp:1.05,hands:[hand()]))
        expectTrue(engine.consume(HandFrame(timestamp:1.15,hands:[hand(pinch:true)])).contains(.button(.left,down:true,clicks:2)))
    }
    @Test func testModeSwitchClearsHeldGesture() {
        let engine = InputEngine(); engine.setMode(.pointer)
        _ = engine.consume(HandFrame(timestamp:1,hands:[hand(pinch:true)]))
        expectEqual(engine.setMode(.paused),[.releaseAll,.mode(.paused)])
        expectEqual(engine.consume(HandFrame(timestamp:1.02,hands:[hand(pinch:true)])),[])
    }
    @Test func testPointerDoesNotSwitchToOtherHandWhenPreferredHandLost() {
        let engine = InputEngine(); engine.setMode(.pointer)
        expectEqual(engine.consume(HandFrame(timestamp:1,hands:[hand(.left)])),[.releaseAll,.mode(.lost)])
    }
    @Test func testCalibrationRejectsIncompleteAndMovingHands() {
        expectNil(CalibrationProfile.make(from:[frame(1)]))
        let stable = (0..<30).map { frame(Double($0)/30) }
        expectNotNil(CalibrationProfile.make(from:stable))
        let moving = (0..<30).map { frame(Double($0)/30,y:0.4+Double($0)*0.003) }
        expectNil(CalibrationProfile.make(from:moving))
    }
    @Test func testInvalidConfidenceIgnored() {
        var h = hand(); h.joints["indexTip"]?.confidence = 0.1
        expectNil(h.point("indexTip"))
        h.joints["indexTip"] = Joint(x:.nan,y:0.5)
        expectNil(h.point("indexTip"))
    }
    @Test func testFilterHasNoOvershootAndResetsAcrossGap() {
        var filter = OneEuroFilter()
        expectEqual(filter.update(0,at:0),0)
        let value = filter.update(1,at:0.03)
        expectGreaterThan(value,0); expectLessThan(value,1)
        expectEqual(filter.update(0.4,at:1),0.4)
    }
    @Test func testKeyboardLayoutCoversEveryKeyAndDoesNotWrapAtBoundary() {
        for key in KeyboardLayout.keys {
            let p = Joint(x:key.rect.x+key.rect.width/2,y:key.rect.y+key.rect.height/2)
            expectEqual(KeyboardLayout.key(at:p,board:profile.board),key.id)
        }
        expectNil(KeyboardLayout.key(at:Joint(x:1,y:0.5),board:profile.board))
        expectNil(KeyboardLayout.key(at:Joint(x:-0.1,y:0.5),board:profile.board))
    }
}

private func expectEqual<T: Equatable>(_ actual: T, _ expected: T, sourceLocation: SourceLocation = #_sourceLocation) {
    #expect(actual == expected, sourceLocation: sourceLocation)
}
private func expectTrue(_ value: Bool, sourceLocation: SourceLocation = #_sourceLocation) {
    #expect(value, sourceLocation: sourceLocation)
}
private func expectNil<T>(_ value: T?, sourceLocation: SourceLocation = #_sourceLocation) {
    #expect(value == nil, sourceLocation: sourceLocation)
}
private func expectNotNil<T>(_ value: T?, sourceLocation: SourceLocation = #_sourceLocation) {
    #expect(value != nil, sourceLocation: sourceLocation)
}
private func expectGreaterThan<T: Comparable>(_ value: T, _ other: T, sourceLocation: SourceLocation = #_sourceLocation) {
    #expect(value > other, sourceLocation: sourceLocation)
}
private func expectLessThan<T: Comparable>(_ value: T, _ other: T, sourceLocation: SourceLocation = #_sourceLocation) {
    #expect(value < other, sourceLocation: sourceLocation)
}
