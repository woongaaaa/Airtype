import Foundation
import AVFoundation
import Vision
import AirtypeCore

@main struct VisionExporter {
    static func main() async {
        do {
            guard CommandLine.arguments.count == 3 else { throw ExportError.message("Usage: vision-export input.mp4 output.jsonl") }
            let input = URL(fileURLWithPath:CommandLine.arguments[1]).standardizedFileURL
            let outputURL = URL(fileURLWithPath:CommandLine.arguments[2]).standardizedFileURL
            guard input != outputURL, !FileManager.default.fileExists(atPath:outputURL.path) else {
                throw ExportError.message("Output must be a new file, distinct from input")
            }
            let asset = AVURLAsset(url:input)
            guard let track = try await asset.loadTracks(withMediaType:.video).first else { throw ExportError.message("No video track") }
            let transform = try await track.load(.preferredTransform)
            guard transform == .identity else { throw ExportError.message("Normalize video rotation before comparing engines") }
            let reader = try AVAssetReader(asset:asset)
            let output = AVAssetReaderTrackOutput(track:track,outputSettings:[kCVPixelBufferPixelFormatTypeKey as String:kCVPixelFormatType_32BGRA])
            guard reader.canAdd(output) else { throw ExportError.message("Unsupported video") }
            reader.add(output)
            guard reader.startReading() else { throw reader.error ?? ExportError.message("Cannot read video") }
            FileManager.default.createFile(atPath:outputURL.path,contents:nil)
            let file = try FileHandle(forWritingTo:outputURL); defer { try? file.close() }
            let request = VNDetectHumanHandPoseRequest(); request.maximumHandCount = 2
            let names: [VNHumanHandPoseObservation.JointName:String] = [
                .wrist:"wrist",.thumbCMC:"thumbCMC",.thumbMP:"thumbMCP",.thumbIP:"thumbIP",.thumbTip:"thumbTip",
                .indexMCP:"indexMCP",.indexPIP:"indexPIP",.indexDIP:"indexDIP",.indexTip:"indexTip",
                .middleMCP:"middleMCP",.middlePIP:"middlePIP",.middleDIP:"middleDIP",.middleTip:"middleTip",
                .ringMCP:"ringMCP",.ringPIP:"ringPIP",.ringDIP:"ringDIP",.ringTip:"ringTip",
                .littleMCP:"littleMCP",.littlePIP:"littlePIP",.littleDIP:"littleDIP",.littleTip:"littleTip"]
            let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
            while let buffer = output.copyNextSampleBuffer() {
                try VNImageRequestHandler(cmSampleBuffer:buffer,orientation:.up).perform([request])
                let hands = try (request.results ?? []).map { observation in
                    var joints: [String:AirtypeCore.Joint] = [:]
                    for (name,point) in try observation.recognizedPoints(.all) {
                        guard let key = names[name] else { continue }
                        joints[key] = AirtypeCore.Joint(x:1-Double(point.location.x),y:1-Double(point.location.y),confidence:Double(point.confidence))
                    }
                    return Hand(side:observation.chirality == .left ? .left : .right,joints:joints)
                }
                let frame = HandFrame(timestamp:CMSampleBufferGetPresentationTimeStamp(buffer).seconds,hands:hands)
                try file.write(contentsOf:encoder.encode(frame)); try file.write(contentsOf:Data([10]))
            }
            if reader.status == .failed { throw reader.error ?? ExportError.message("Video decoding failed") }
        } catch { FileHandle.standardError.write(Data("\(error)\n".utf8)); exit(2) }
    }
    enum ExportError: Error { case message(String) }
}
