import SwiftUI
import AppKit
import AirtypeCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var model: AppModel?
    func applicationWillTerminate(_ notification: Notification) { MainActor.assumeIsolated { model?.shutdown() } }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}

@main struct AirtypeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var model = AppModel()
    @Environment(\.openWindow) private var openWindow
    var body: some Scene {
        Window("Airtype", id: "main") {
            MainView(model:model).onAppear { delegate.model = model }
                .frame(minWidth:900,minHeight:750)
        }.defaultSize(width:1000,height:820)
        MenuBarExtra("Airtype", systemImage: model.outputEnabled ? "hand.point.up.left.fill" : "hand.raised") {
            Text(model.outputEnabled ? "실제 입력 켜짐" : "연습 모드")
            Button("설정 창 열기") {
                NSApp.activate(ignoringOtherApps:true)
                openWindow(id:"main")
            }
            Button("일시정지") { model.selectMode(.paused) }
            Button("카메라 중지") { model.stopCamera() }
            Divider()
            Button("Airtype 종료") { model.shutdown(); NSApp.terminate(nil) }
        }
    }
}

struct MainView: View {
    @ObservedObject var model: AppModel
    private let accent = Color(red:0.31,green:0.79,blue:0.68)
    var body: some View {
        ScrollView {
            VStack(alignment:.leading,spacing:22) {
                HStack(alignment:.top) {
                    VStack(alignment:.leading,spacing:6) {
                        Text("Airtype").font(.system(size:34,weight:.semibold,design:.rounded))
                        Text("손끝으로 여는 새로운 입력").font(.title3).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("개발 프리뷰 · 출시 검증 전").font(.caption.weight(.medium))
                        .padding(9).background(.orange.opacity(0.15),in:Capsule())
                }
                HStack(spacing:12) {
                    stat("카메라",model.cameraRunning ? "켜짐" : "꺼짐")
                    stat("모드",model.mode.korean)
                    stat("처리",String(format:"%.0f fps",model.fps))
                    stat("최근 프레임",String(format:"%.0f ms",model.latency))
                }
                Text(model.status).font(.callout).frame(maxWidth:.infinity,alignment:.leading)
                    .padding(14).background(accent.opacity(0.09),in:RoundedRectangle(cornerRadius:12))
                HStack(alignment:.top,spacing:16) {
                    GroupBox("1 · 카메라와 권한") {
                        VStack(alignment:.leading,spacing:12) {
                            Text("영상은 저장하거나 전송하지 않습니다. 내장 카메라에서 손 관절만 추정합니다.")
                                .font(.caption).foregroundStyle(.secondary)
                            Button(model.cameraRunning ? "카메라 중지" : "카메라 시작") {
                                if model.cameraRunning { model.stopCamera() } else { model.startCamera() }
                            }.disabled(model.cameraStarting)
                            Button(model.accessibilityGranted ? "손쉬운 사용 허용됨" : "손쉬운 사용 설정 열기") { model.requestAccessibility() }
                            Toggle("macOS에 실제 입력 보내기",isOn:Binding(get:{model.outputEnabled},set:model.setOutput))
                                .disabled(!model.cameraRunning || !model.accessibilityGranted)
                        }.padding(8).frame(maxWidth:.infinity,alignment:.leading)
                    }
                    GroupBox("2 · 손 위치 보정") {
                        VStack(alignment:.leading,spacing:12) {
                            Text("카메라에서 40~80cm. 손끝을 모두 보이게 하고 평소 홈 위치를 잡으세요.")
                                .font(.caption).foregroundStyle(.secondary)
                            HStack {
                                Button(model.calibrating ? "홈 위치 측정 중…" : "홈 위치 보정") { model.startCalibration() }
                                    .disabled(!model.cameraRunning || model.calibrating)
                                Button("초기화") { model.resetCalibration() }
                            }
                            Button("손가락 보정 (\(model.profile?.tapThresholds.count ?? 0)/10)") { model.startFingerTraining() }
                                .disabled(model.profile == nil || !model.cameraRunning || model.trainingIndex != nil)
                            Toggle("포인터에 왼손 사용",isOn:Binding(get:{model.leftHanded},set:model.setHand))
                        }.padding(8).frame(maxWidth:.infinity,alignment:.leading)
                    }
                }
                if let prompt = model.trainingPrompt {
                    HStack { ProgressView().controlSize(.small); Text(prompt); Spacer(); Button("취소") { model.selectMode(.ready) } }
                        .padding().background(.orange.opacity(0.1),in:RoundedRectangle(cornerRadius:12))
                }
                HStack {
                    Text("3 · 연습하고 활성화").font(.headline)
                    Spacer()
                    ForEach([ControlMode.paused,.keyboard,.pointer],id:\.self) { mode in
                        Button(mode.korean) { model.selectMode(mode) }
                            .tint(model.mode == mode ? accent : .gray)
                    }
                    Toggle("오버레이",isOn:Binding(get:{model.showOverlay},set:model.setOverlay)).toggleStyle(.switch)
                }
                TrackingBoard(model:model).frame(height:280)
                HStack {
                    Text("연습 입력 · 영문 키 위치 확인용").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("비우기") { model.practiceText = "" }
                }
                Text(model.practiceText.isEmpty ? "실제 입력을 끈 채 키보드 모드에서 손가락을 움직여 보세요." : model.practiceText)
                    .font(.system(.body,design:.monospaced)).textSelection(.enabled)
                    .frame(maxWidth:.infinity,minHeight:40,alignment:.leading)
                    .padding(12).background(.quaternary,in:RoundedRectangle(cornerRadius:10))
                HStack(alignment:.top,spacing:24) {
                    Text("모드 선택\n양손을 펼쳐 1.5초 유지 → 검지로 영역을 1초 가리키기")
                    Text("포인터\n검지 이동 · 엄지/검지 핀치 클릭 · 유지 후 이동 드래그")
                    Text("탐색\n두 손가락 스크롤 · 펼친 손 좌우 이동으로 브라우저 탐색")
                }.font(.caption).foregroundStyle(.secondary)
                HStack {
                    Text("한글 입력: 시스템에 ABC·한국어 두벌식을 추가하세요. 조합키는 다음 키에 한 번 적용됩니다.")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("진단 내보내기") { model.exportDiagnostics() }
                }
            }.padding(28)
        }.background(Color(nsColor:.windowBackgroundColor))
    }
    func stat(_ label:String,_ value:String) -> some View {
        VStack(alignment:.leading,spacing:5) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.headline.monospacedDigit())
        }.frame(maxWidth:.infinity,alignment:.leading).padding(12).background(.quaternary,in:RoundedRectangle(cornerRadius:12))
    }
}

struct TrackingBoard: View {
    @ObservedObject var model: AppModel
    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            ZStack {
                RoundedRectangle(cornerRadius:14).fill(Color(red:0.07,green:0.10,blue:0.13))
                if model.mode == .choosing {
                    HStack {
                        ForEach([ControlMode.paused,.keyboard,.pointer],id:\.self) { mode in
                            VStack { Image(systemName:mode == .paused ? "pause.circle" : mode == .keyboard ? "keyboard" : "cursorarrow").font(.largeTitle); Text(mode.korean); Text("검지로 1초 가리키기").font(.caption) }
                                .frame(maxWidth:.infinity,maxHeight:.infinity).background(.white.opacity(0.08),in:RoundedRectangle(cornerRadius:12))
                        }
                    }.padding(24).foregroundStyle(.white)
                } else if let profile = model.profile {
                    ForEach(Array(KeyboardLayout.keys.enumerated()),id:\.offset) { _, key in
                        let r = key.rect, board = profile.board
                        HStack(spacing:3) {
                            Text(KeyboardLayout.labels[key.id] ?? key.id.uppercased()).font(.system(size:11,weight:.medium))
                            if let korean = KeyboardLayout.hangul[key.id] { Text(korean).font(.system(size:10)).foregroundStyle(.white.opacity(0.65)) }
                        }
                        .frame(width:max(12,r.width*board.width*size.width-3),height:max(15,r.height*board.height*size.height-3))
                        .background(model.modifiers.contains(key.id) ? Color.orange.opacity(0.7) : .white.opacity(0.12),in:RoundedRectangle(cornerRadius:4))
                        .foregroundStyle(.white)
                        .position(x:(board.x+(r.x+r.width/2)*board.width)*size.width,
                                  y:(board.y+(r.y+r.height/2)*board.height)*size.height)
                    }
                } else {
                    Text("카메라를 켜고 홈 위치를 보정하면\n손 관절과 가상 키 영역이 표시됩니다.")
                        .font(.callout).multilineTextAlignment(.center).foregroundStyle(.white.opacity(0.55))
                }
                Canvas { context, canvas in
                    for hand in model.frame.hands {
                        let color: Color = hand.side == .left ? .cyan : .mint
                        for finger in Finger.allCases {
                            let names = finger == .thumb ? ["wrist","thumbCMC","thumbMCP","thumbIP","thumbTip"] : ["wrist",finger.base,finger.middleJoint,finger.rawValue+"DIP",finger.tip]
                            var path = Path(); var started = false
                            for name in names {
                                guard let joint = hand.point(name) else { started = false; continue }
                                let p = CGPoint(x:joint.x*canvas.width,y:joint.y*canvas.height)
                                if started { path.addLine(to:p) } else { path.move(to:p); started = true }
                                context.fill(Path(ellipseIn:CGRect(x:p.x-3,y:p.y-3,width:6,height:6)),with:.color(color))
                            }
                            context.stroke(path,with:.color(color.opacity(0.7)),lineWidth:1.5)
                        }
                    }
                }.allowsHitTesting(false)
                VStack { Spacer(); HStack { Text(model.mode.korean); Spacer(); Text(model.outputEnabled ? "OS 입력 켜짐" : "연습 전용") }.font(.caption).foregroundStyle(.white.opacity(0.6)) }.padding(12)
            }
        }
    }
}

struct OverlayView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        VStack(spacing:4) {
            Text("Airtype · \(model.mode.korean) · \(model.outputEnabled ? "실제 입력" : "연습")").font(.caption)
            TrackingBoard(model:model)
        }.padding(10).background(.ultraThinMaterial,in:RoundedRectangle(cornerRadius:16))
    }
}

extension ControlMode {
    var korean: String {
        switch self { case .paused:"일시정지"; case .ready:"준비"; case .choosing:"모드 선택"; case .keyboard:"키보드"; case .pointer:"포인터"; case .lost:"추적 상실" }
    }
}
