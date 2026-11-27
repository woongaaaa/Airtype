import AVFoundation
import Vision
import AirtypeCore

final class VisionTracker: NSObject, HandTracker, AVCaptureVideoDataOutputSampleBufferDelegate {
    var onFrame: ((HandFrame) -> Void)?
    var onError: ((String) -> Void)?
    private let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "app.airtype.camera", qos: .userInitiated)
    private let request: VNDetectHumanHandPoseRequest = {
        let request = VNDetectHumanHandPoseRequest(); request.maximumHandCount = 2; return request
    }()
    private var configured = false
    private var observers: [NSObjectProtocol] = []

    override init() {
        super.init()
        for name in [AVCaptureSession.runtimeErrorNotification, AVCaptureSession.wasInterruptedNotification] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: session, queue: .main) { [weak self] _ in
                self?.onError?("카메라가 중단되었습니다. 권한과 다른 앱의 카메라 사용을 확인한 뒤 다시 시작하세요.")
            })
        }
    }
    deinit { observers.forEach(NotificationCenter.default.removeObserver) }
    func start() throws {
        queue.async { [weak self] in
            guard let self else { return }
            do {
                if !self.configured { try self.configure() }
                self.session.startRunning()
            } catch { DispatchQueue.main.async { self.onError?(error.localizedDescription) } }
        }
    }
    func stop() { queue.async { [weak self] in self?.session.stopRunning() } }
    private func configure() throws {
        // Intentionally restrict v0.1 to the built-in camera; never silently select an iPhone.
        let devices = AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInWideAngleCamera], mediaType: .video, position: .unspecified).devices
        guard let device = devices.first else { throw CameraError.noCamera }
        let input = try AVCaptureDeviceInput(device: device)
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        session.sessionPreset = .vga640x480
        let output = AVCaptureVideoDataOutput()
        output.alwaysDiscardsLateVideoFrames = true
        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        output.setSampleBufferDelegate(self, queue: queue)
        guard session.canAddInput(input), session.canAddOutput(output) else { throw CameraError.configuration }
        session.addInput(input); session.addOutput(output)
        configured = true
    }
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        let timestamp = ProcessInfo.processInfo.systemUptime
        do {
            try VNImageRequestHandler(cmSampleBuffer: sampleBuffer, orientation: .up).perform([request])
            let hands = try (request.results ?? []).map { observation -> Hand in
                var joints: [String: AirtypeCore.Joint] = [:]
                for (name, point) in try observation.recognizedPoints(.all) {
                    let key = Self.names[name] ?? name.rawValue.rawValue
                    joints[key] = AirtypeCore.Joint(x: 1-Double(point.location.x), y: 1-Double(point.location.y), confidence: Double(point.confidence))
                }
                return Hand(side: observation.chirality == .left ? .left : .right, joints: joints)
            }
            let frame = HandFrame(timestamp: timestamp, hands: hands)
            DispatchQueue.main.async { [weak self] in self?.onFrame?(frame) }
        } catch {
            DispatchQueue.main.async { [weak self] in self?.onError?("Vision 처리 실패: \(error.localizedDescription)") }
        }
    }
    static let names: [VNHumanHandPoseObservation.JointName: String] = [
        .wrist:"wrist", .thumbCMC:"thumbCMC", .thumbMP:"thumbMCP", .thumbIP:"thumbIP", .thumbTip:"thumbTip",
        .indexMCP:"indexMCP", .indexPIP:"indexPIP", .indexDIP:"indexDIP", .indexTip:"indexTip",
        .middleMCP:"middleMCP", .middlePIP:"middlePIP", .middleDIP:"middleDIP", .middleTip:"middleTip",
        .ringMCP:"ringMCP", .ringPIP:"ringPIP", .ringDIP:"ringDIP", .ringTip:"ringTip",
        .littleMCP:"littleMCP", .littlePIP:"littlePIP", .littleDIP:"littleDIP", .littleTip:"littleTip"
    ]
    enum CameraError: LocalizedError {
        case noCamera, configuration
        var errorDescription: String? { self == .noCamera ? "내장 카메라를 찾지 못했습니다." : "카메라 세션을 구성하지 못했습니다." }
    }
}
