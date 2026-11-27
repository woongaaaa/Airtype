import Foundation
import AirtypeCore

func option(_ name: String) -> String? {
    let args = CommandLine.arguments
    guard let i = args.firstIndex(of:name), i+1 < args.count else { return nil }; return args[i+1]
}
func describe(_ event: InputIntent, time: Double) -> [String:Any] {
    var value: [String:Any] = ["timestamp":time]
    switch event {
    case let .key(key): value["type"] = "key"; value["key"] = key
    case let .move(x,y): value["type"] = "move"; value["x"] = x; value["y"] = y
    case let .button(button,down,clicks): value["type"] = "button"; value["button"] = button.rawValue; value["down"] = down; value["clicks"] = clicks
    case let .scroll(x,y): value["type"] = "scroll"; value["x"] = x; value["y"] = y
    case let .navigate(back): value["type"] = "navigate"; value["back"] = back
    case .releaseAll: value["type"] = "releaseAll"
    case let .mode(mode): value["type"] = "mode"; value["mode"] = mode.rawValue
    }
    return value
}
do {
    guard let input = option("--input"), let rawMode = option("--mode"),
          let mode = ControlMode(rawValue:rawMode), [.keyboard,.pointer].contains(mode) else {
        throw NSError(domain:"Usage: airtype-replay --input frames.jsonl --mode keyboard|pointer [--profile calibration.json]",code:2)
    }
    let decoder = JSONDecoder()
    var profile: CalibrationProfile?
    if let path = option("--profile") { profile = try decoder.decode(CalibrationProfile.self,from:Data(contentsOf:URL(fileURLWithPath:path))) }
    if mode == .keyboard && profile?.valid != true { throw NSError(domain:"Keyboard replay requires a valid --profile",code:2) }
    let engine = InputEngine(calibration:profile); engine.setMode(mode)
    let lines = try String(contentsOfFile:input,encoding:.utf8).split(separator:"\n")
    var lastTime = -Double.infinity
    for (index,line) in lines.enumerated() {
        let frame = try decoder.decode(HandFrame.self,from:Data(line.utf8))
        guard frame.valid, frame.timestamp > lastTime else { throw NSError(domain:"Invalid/non-monotonic frame at line \(index+1)",code:2) }
        lastTime = frame.timestamp
        for event in engine.consume(frame) {
            let data = try JSONSerialization.data(withJSONObject:describe(event,time:frame.timestamp),options:[.sortedKeys])
            print(String(decoding:data,as:UTF8.self))
        }
    }
    // Include the terminal watchdog release so held gestures cannot outlive a replay.
    if lastTime.isFinite {
        for event in engine.tick(at:lastTime+0.3) {
            let data = try JSONSerialization.data(withJSONObject:describe(event,time:lastTime+0.3),options:[.sortedKeys])
            print(String(decoding:data,as:UTF8.self))
        }
    }
} catch {
    FileHandle.standardError.write(Data("\(error)\n".utf8)); exit(2)
}
