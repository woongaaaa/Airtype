import AppKit
import AVFoundation
import Combine
import SwiftUI
import AirtypeCore

@MainActor final class AppModel: ObservableObject {
    @Published var cameraRunning = false
    @Published var cameraStarting = false
    @Published var accessibilityGranted = AXIsProcessTrusted()
    @Published var outputEnabled = false
    @Published var mode: ControlMode = .paused
    @Published var frame = HandFrame(timestamp: 0, hands: [])
    @Published var profile: CalibrationProfile?
    @Published var status = "개발 프리뷰 · 정확도 검증 전입니다. 먼저 연습 모드로 확인하세요."
    @Published var lastKey = ""
    @Published var practiceText = ""
    @Published var fps = 0.0
    @Published var latency = 0.0
    @Published var sentIntents = 0
    @Published var modifiers: Set<String> = []
    @Published var calibrating = false
    @Published var trainingIndex: Int?
    @Published var showOverlay = false
    @Published var leftHanded = false
    let engine = InputEngine()
    private let tracker = VisionTracker()
    private let dispatcher = InputDispatcher()
    private var timer: AnyCancellable?
    private var notifications: [NSObjectProtocol] = []
    private var calibrationFrames: [HandFrame] = []
    private var calibrationStarted = 0.0
    private var trainingStart = 0.0
    private var trainingOffsets: [Double] = []
    private var arrivalTimes: [Double] = []
    private var lastDisplay: Double = 0
    private var overlay: NSPanel?
    private var previousFrontmostPID: pid_t?
    private var previousDisplay = CGMainDisplayID()
    private let demo = ProcessInfo.processInfo.arguments.contains("--demo")

    var trainingSteps: [(HandSide, Finger)] { HandSide.allCases.flatMap { side in Finger.allCases.map { (side,$0) } } }
    var trainingPrompt: String? {
        guard let i = trainingIndex else { return nil }
        let (side, finger) = trainingSteps[i]
        let names: [Finger:String] = [.thumb:"엄지",.index:"검지",.middle:"중지",.ring:"약지",.little:"새끼"]
        return "\(i+1)/10 · \(side == .left ? "왼손" : "오른손") \(names[finger]!)를 3초 동안 두 번 굽혔다 펴세요."
    }
    init() {
        if let data = UserDefaults.standard.data(forKey: "calibration.v1"),
           let saved = try? JSONDecoder().decode(CalibrationProfile.self, from: data), saved.valid {
            profile = saved; engine.calibration = saved
        }
        tracker.onFrame = { [weak self] frame in self?.receive(frame) }
        tracker.onError = { [weak self] message in self?.stopCamera(); self?.status = message }
        dispatcher.onError = { [weak self] message in self?.status = message }
        timer = Timer.publish(every: 0.05, on: .main, in: .common).autoconnect().sink { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.sessionDidResignActiveNotification] {
            notifications.append(workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.stopCamera() }
            })
        }
        if demo {
            status = "시뮬레이션 미리보기 · 카메라와 OS 입력을 사용하지 않습니다."
            profile = CalibrationProfile(board: Rect(x: 0.08,y: 0.22,width: 0.84,height: 0.42), scales: ["left":0.15,"right":0.15])
        }
    }
    func requestAccessibility() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([key:true] as CFDictionary)
        NSWorkspace.shared.open(URL(string:"x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }
    func startCamera() {
        guard !demo, !cameraRunning, !cameraStarting else { return }
        cameraStarting = true
        AVCaptureDevice.requestAccess(for: .video) { [weak self] allowed in
            DispatchQueue.main.async {
                guard let self, self.cameraStarting else { return }
                self.cameraStarting = false
                guard allowed else {
                    self.status = "카메라 접근이 꺼져 있습니다. 시스템 설정 → 개인정보 보호 및 보안 → 카메라에서 Airtype을 허용하세요."; return
                }
                do {
                    try self.tracker.start(); self.cameraRunning = true
                    self.process(self.engine.setMode(.ready))
                    self.status = "양손이 화면에 보이도록 놓고 홈 위치 보정을 시작하세요."
                } catch { self.status = error.localizedDescription }
            }
        }
    }
    func stopCamera() {
        cameraStarting = false; cameraRunning = false
        setOutput(false); process(engine.setMode(.paused)); tracker.stop()
        calibrating = false; trainingIndex = nil; calibrationFrames.removeAll(); trainingOffsets.removeAll()
        frame = HandFrame(timestamp:0,hands:[]); arrivalTimes.removeAll(); fps = 0
    }
    func setOutput(_ enabled: Bool) {
        dispatcher.releaseAll()
        outputEnabled = enabled && accessibilityGranted && cameraRunning && !demo
        dispatcher.enabled = outputEnabled
        modifiers = []
        if outputEnabled { status = "실제 입력 켜짐 · 양손을 펼쳐 1.5초 유지하면 모드를 선택할 수 있습니다." }
        else { status = "연습 모드 · macOS에 입력을 보내지 않습니다." }
    }
    func selectMode(_ requested: ControlMode) {
        guard cameraRunning || requested == .paused else { return }
        if requested == .keyboard && profile == nil { status = "먼저 홈 위치를 보정하세요." }
        calibrating = false; trainingIndex = nil
        process(engine.setMode(requested))
    }
    func startCalibration() {
        guard cameraRunning else { return }
        setOutput(false); process(engine.setMode(.ready))
        calibrating = true; trainingIndex = nil; calibrationStarted = ProcessInfo.processInfo.systemUptime
        calibrationFrames.removeAll()
        status = "양손을 홈 위치에 놓고 1초 동안 유지하세요. 카메라에 모든 손끝이 보여야 합니다."
    }
    func startFingerTraining() {
        guard profile != nil, cameraRunning else { return }
        setOutput(false); process(engine.setMode(.ready)); calibrating = false
        trainingIndex = 0; trainingStart = ProcessInfo.processInfo.systemUptime; trainingOffsets.removeAll()
        status = trainingPrompt ?? ""
    }
    func resetCalibration() {
        selectMode(.ready); setOutput(false); profile = nil; engine.calibration = nil
        UserDefaults.standard.removeObject(forKey:"calibration.v1")
    }
    private func saveProfile(_ new: CalibrationProfile) {
        profile = new; engine.calibration = new
        if let data = try? JSONEncoder().encode(new) { UserDefaults.standard.set(data,forKey:"calibration.v1") }
    }
    private func receive(_ next: HandFrame) {
        guard cameraRunning else { return }
        let now = ProcessInfo.processInfo.systemUptime
        guard now-next.timestamp <= 0.25 else { process(engine.setMode(.lost)); return }
        let events = calibrating || trainingIndex != nil ? [] : engine.consume(next)
        if calibrating {
            if next.hands.count == 2 { calibrationFrames.append(next) } else { calibrationFrames.removeAll() }
            if calibrationFrames.count >= 30 {
                if let result = CalibrationProfile.make(from:Array(calibrationFrames.suffix(30))) {
                    saveProfile(result); calibrating = false
                    status = "홈 위치 보정 완료. 손가락 보정 후 실제 키보드 입력을 켤 수 있습니다."
                } else { calibrationFrames.removeFirst() }
            }
        }
        if let index = trainingIndex {
            let (side,finger) = trainingSteps[index]
            if let hand = next.hands.first(where:{$0.side == side}), let scale = hand.scale,
               let tip = hand.point(finger.tip), let base = hand.point(finger.base) {
                trainingOffsets.append((tip.y-base.y)/scale)
            }
            if now-trainingStart > 3.5 {
                let sorted = trainingOffsets.sorted()
                if sorted.count >= 30, let low = sorted.first, let high = sorted.last, high-low > 0.12,
                   var result = profile {
                    result.tapThresholds[side.rawValue+"."+finger.rawValue] = min(0.45,max(0.08,(high-low)*0.55))
                    saveProfile(result)
                    trainingIndex = index == 9 ? nil : index+1
                    status = trainingPrompt ?? "10개 손가락 보정 완료. 연습 모드에서 문자 입력을 먼저 확인하세요."
                } else { status = "움직임을 충분히 읽지 못했습니다. " + (trainingPrompt ?? "") }
                trainingStart = now; trainingOffsets.removeAll()
            }
        }
        process(events)
        arrivalTimes.append(now); arrivalTimes.removeAll { now-$0 > 1 }
        if now-lastDisplay > 1.0/20 {
            frame = next; fps = Double(arrivalTimes.count)
            latency = (ProcessInfo.processInfo.systemUptime-next.timestamp)*1000
            lastDisplay = now
        }
    }
    private func tick() {
        let trusted = AXIsProcessTrusted()
        if trusted != accessibilityGranted { accessibilityGranted = trusted; if !trusted { setOutput(false) } }
        if cameraRunning {
            process(engine.tick(at:ProcessInfo.processInfo.systemUptime))
            if calibrating && ProcessInfo.processInfo.systemUptime-calibrationStarted > 8 {
                calibrating = false; status = "보정 실패: 양손을 안정적으로 볼 수 없습니다. 손 위치와 조명을 바꾸고 다시 시도하세요."
            }
            let display = CGMainDisplayID()
            if display != previousDisplay { previousDisplay = display; selectMode(.ready); status = "화면 구성이 바뀌어 입력을 정지했습니다." }
        }
        let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier
        if previousFrontmostPID != pid { dispatcher.releaseAll(); modifiers = []; previousFrontmostPID = pid }
    }
    private func process(_ events: [InputIntent]) {
        for event in events {
            if case let .mode(next) = event {
                mode = next
                if next == .lost { status = "손 추적이 끊겨 입력을 정지했습니다. 다시 준비한 뒤 모드를 선택하세요." }
                if next == .choosing { setOverlay(true) }
            }
            if case let .key(key) = event {
                lastKey = key
                if !outputEnabled {
                    if key == "backspace" { if !practiceText.isEmpty { practiceText.removeLast() } }
                    else if key == "space" { practiceText += " " }
                    else if key == "enter" { practiceText += "\n" }
                    else if key.count == 1 { practiceText += key }
                    practiceText = String(practiceText.suffix(300))
                }
                // Home calibration alone is insufficient for real keyboard injection.
                if (profile?.tapThresholds.count ?? 0) < 10 { continue }
            }
            dispatcher.dispatch(event)
            if outputEnabled { sentIntents += 1 }
        }
        modifiers = dispatcher.modifiers
    }
    func setHand(_ left: Bool) { leftHanded = left; engine.preferredHand = left ? .left : .right; selectMode(.ready) }
    func setOverlay(_ visible: Bool) {
        showOverlay = visible
        if visible {
            if overlay == nil {
                let panel = NSPanel(contentRect:NSRect(x:0,y:0,width:850,height:350),
                                    styleMask:[.borderless,.nonactivatingPanel], backing:.buffered, defer:false)
                panel.level = .floating; panel.backgroundColor = .clear; panel.isOpaque = false
                panel.hasShadow = true; panel.ignoresMouseEvents = true
                panel.collectionBehavior = [.canJoinAllSpaces,.fullScreenAuxiliary]
                panel.contentView = NSHostingView(rootView:OverlayView(model:self))
                overlay = panel
            }
            if let screen = NSScreen.main {
                overlay?.setFrameOrigin(NSPoint(x:screen.visibleFrame.midX-425,y:screen.visibleFrame.minY+20))
            }
            overlay?.orderFrontRegardless()
        } else { overlay?.orderOut(nil) }
    }
    func exportDiagnostics() {
        let panel = NSSavePanel(); panel.nameFieldStringValue = "airtype-diagnostics.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let info: [String:Any] = ["schemaVersion":1,"appVersion":"0.1.0-dev","engine":"Vision",
            "os":ProcessInfo.processInfo.operatingSystemVersionString,"mode":mode.rawValue,
            "fps":fps,"lastFrameProcessingMs":latency,"calibrated":profile != nil,
            "trainedFingerCount":profile?.tapThresholds.count ?? 0,
            "cameraRunning":cameraRunning,"accessibilityGranted":accessibilityGranted,
            "releaseQualified":false]
        do { try JSONSerialization.data(withJSONObject:info, options:[.prettyPrinted,.sortedKeys]).write(to:url,options:.atomic) }
        catch { status = error.localizedDescription }
    }
    func shutdown() { stopCamera(); overlay?.orderOut(nil) }
}
