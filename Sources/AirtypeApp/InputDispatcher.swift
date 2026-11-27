import AppKit
import Carbon
import AirtypeCore

@MainActor final class InputDispatcher {
    var enabled = false
    var onError: ((String) -> Void)?
    private(set) var modifiers: Set<String> = []
    private var buttons: Set<String> = []
    private var heldClickCounts: [String: Int] = [:]
    private var point = CGPoint.zero
    private let source = CGEventSource(stateID: .hidSystemState)

    func dispatch(_ event: InputIntent) {
        if event == .releaseAll { releaseAll(); return }
        guard enabled, AXIsProcessTrusted() else { releaseAll(); return }
        switch event {
        case let .move(x,y):
            let bounds = CGDisplayBounds(CGMainDisplayID())
            point = CGPoint(x: bounds.minX+x*(bounds.width-1), y: bounds.minY+y*(bounds.height-1))
            let type: CGEventType = buttons.contains("left") ? .leftMouseDragged : .mouseMoved
            CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: point, mouseButton: .left)?.post(tap: .cghidEventTap)
        case let .button(button,down,clicks):
            let right = button == .right
            let type: CGEventType = right ? (down ? .rightMouseDown : .rightMouseUp) : (down ? .leftMouseDown : .leftMouseUp)
            let e = CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: point, mouseButton: right ? .right : .left)
            e?.setIntegerValueField(.mouseEventClickState, value: Int64(clicks))
            e?.post(tap: .cghidEventTap)
            if down { buttons.insert(button.rawValue); heldClickCounts[button.rawValue] = clicks }
            else { buttons.remove(button.rawValue); heldClickCounts.removeValue(forKey: button.rawValue) }
        case let .scroll(x,y):
            CGEvent(scrollWheelEvent2Source: source, units: .pixel, wheelCount: 2,
                    wheel1: Int32(max(-200,min(200,y))), wheel2: Int32(max(-200,min(200,x))), wheel3: 0)?.post(tap: .cghidEventTap)
        case let .key(id):
            if Self.modifierFlags[id] != nil {
                if modifiers.contains(id) { modifiers.remove(id) } else { modifiers.insert(id) }
                return
            }
            guard NSWorkspace.shared.frontmostApplication?.bundleIdentifier != Bundle.main.bundleIdentifier else { return }
            if id == "language" { switchLanguage(); modifiers.removeAll(); return }
            guard let code = Self.keyCodes[id] else { return }
            let flags = modifiers.reduce(CGEventFlags()) { $0.union(Self.modifierFlags[$1] ?? []) }
            sendKey(code, flags: flags); modifiers.removeAll()
        case let .navigate(back):
            guard let app = NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
                  ["com.apple.Safari", "com.google.Chrome"].contains(app) else { return }
            sendKey(back ? 33 : 30, flags: .maskCommand)
        default: break
        }
    }
    private func sendKey(_ code: CGKeyCode, flags: CGEventFlags) {
        for down in [true,false] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: down)
            event?.flags = flags; event?.post(tap: .cghidEventTap)
        }
    }
    func releaseAll() {
        for button in buttons {
            let right = button == "right"
            let event = CGEvent(mouseEventSource: source, mouseType: right ? .rightMouseUp : .leftMouseUp,
                               mouseCursorPosition: point, mouseButton: right ? .right : .left)
            event?.setIntegerValueField(.mouseEventClickState, value: Int64(heldClickCounts[button] ?? 1))
            event?.post(tap: .cghidEventTap)
        }
        buttons.removeAll(); heldClickCounts.removeAll(); modifiers.removeAll()
    }
    func switchLanguage() {
        guard let current = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(),
              let rawID = TISGetInputSourceProperty(current, kTISPropertyInputSourceID) else { return }
        let currentID = Unmanaged<CFString>.fromOpaque(rawID).takeUnretainedValue() as String
        let target = currentID == "com.apple.inputmethod.Korean.2SetKorean" ? "com.apple.keylayout.ABC" : "com.apple.inputmethod.Korean.2SetKorean"
        let filter = [kTISPropertyInputSourceID as String: target] as CFDictionary
        guard let array = TISCreateInputSourceList(filter, false)?.takeRetainedValue(),
              CFArrayGetCount(array) > 0 else {
            onError?("시스템 설정 → 키보드 → 입력 소스에 ABC와 한국어 두벌식을 추가하세요."); return
        }
        let input = Unmanaged<TISInputSource>.fromOpaque(CFArrayGetValueAtIndex(array, 0)).takeUnretainedValue()
        if TISSelectInputSource(input) != noErr { onError?("입력 소스를 전환하지 못했습니다.") }
    }
    static let modifierFlags: [String: CGEventFlags] = ["command":.maskCommand,"shift":.maskShift,"option":.maskAlternate,"control":.maskControl]
    static let keyCodes: [String: CGKeyCode] = [
        "a":0,"s":1,"d":2,"f":3,"h":4,"g":5,"z":6,"x":7,"c":8,"v":9,"b":11,
        "q":12,"w":13,"e":14,"r":15,"y":16,"t":17,"1":18,"2":19,"3":20,"4":21,"6":22,"5":23,
        "=":24,"9":25,"7":26,"-":27,"8":28,"0":29,
        "]":30,"o":31,"u":32,"[":33,"i":34,"p":35,"enter":36,"l":37,"j":38,"'":39,"k":40,
        ";":41,"\\":42,",":43,"/":44,"n":45,"m":46,".":47,"tab":48,"space":49,"`":50,
        "backspace":51,"esc":53,"left":123,"right":124,"down":125,"up":126
    ]
}
