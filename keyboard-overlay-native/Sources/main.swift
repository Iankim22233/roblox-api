import AppKit
import ApplicationServices
import WebKit
import IOKit.hid

let overlayWidth: CGFloat = 620
let overlayHeight: CGFloat = 300

// Neither print() nor NSLog reliably showed up in `log stream` for a
// Finder-launched process, for reasons still unclear — so write straight
// to a plain file instead, which sidesteps logging-system ambiguity
// entirely. Check with: cat ~/keyboard-overlay-debug.log
let debugLogPath = NSHomeDirectory() + "/keyboard-overlay-debug.log"

func debugLog(_ message: String) {
  print(message)
  let line = "\(Date()) \(message)\n"
  guard let data = line.data(using: .utf8) else { return }
  if FileManager.default.fileExists(atPath: debugLogPath) {
    if let handle = FileHandle(forWritingAtPath: debugLogPath) {
      handle.seekToEndOfFile()
      handle.write(data)
      try? handle.close()
    }
  } else {
    try? data.write(to: URL(fileURLWithPath: debugLogPath))
  }
}

// macOS virtual keycodes (Carbon HIToolbox), mapped to the same key names
// used by data-key attributes in Resources/index.html.
let keyCodeToName: [UInt16: String] = [
  0x00: "A", 0x01: "S", 0x02: "D", 0x03: "F", 0x05: "G",
  0x06: "Z", 0x07: "X", 0x08: "C", 0x09: "V", 0x0B: "B",
  0x0C: "Q", 0x0D: "W", 0x0E: "E", 0x0F: "R", 0x11: "T",
  0x12: "1", 0x13: "2", 0x14: "3", 0x15: "4", 0x17: "5",
  0x30: "Tab", 0x31: "Space", 0x32: "Backquote",
  0x38: "Shift", 0x3C: "Shift",
  0x3A: "Alt", 0x3D: "Alt",
  0x3B: "Ctrl", 0x3E: "Ctrl",
]

let controlBarWidth: CGFloat = 108
let controlBarHeight: CGFloat = 26

let defaultAccentColor = NSColor(red: 199.0 / 255, green: 201.0 / 255, blue: 52.0 / 255, alpha: 1)

extension NSColor {
  convenience init?(hex: String) {
    var hexString = hex.trimmingCharacters(in: .whitespacesAndNewlines)
    if hexString.hasPrefix("#") { hexString.removeFirst() }
    guard hexString.count == 6, let value = UInt32(hexString, radix: 16) else { return nil }
    self.init(
      red: CGFloat((value >> 16) & 0xFF) / 255,
      green: CGFloat((value >> 8) & 0xFF) / 255,
      blue: CGFloat(value & 0xFF) / 255,
      alpha: 1
    )
  }
}

// Purely decorative background for the control bar (rounded rect + three
// drag dots, centered between the real macOS close button on the left and
// the settings gear button on the right). Deliberately has NO event-
// handling code — dragging is handled entirely by the window's own
// isMovableByWindowBackground, the standard AppKit mechanism for this.
final class ControlBarView: NSView {
  override func draw(_ dirtyRect: NSRect) {
    let background = NSBezierPath(roundedRect: bounds, xRadius: 6, yRadius: 6)
    NSColor.black.withAlphaComponent(0.55).setFill()
    background.fill()
    NSColor.white.withAlphaComponent(0.5).setStroke()
    background.lineWidth = 1
    background.stroke()

    NSColor.white.withAlphaComponent(0.8).setFill()
    let dotSize: CGFloat = 3
    let y = bounds.midY - dotSize / 2
    let startX = bounds.midX - (dotSize * 3 + 3 * 2) / 2
    for i in 0..<3 {
      let dotRect = NSRect(x: startX + CGFloat(i) * (dotSize + 3), y: y, width: dotSize, height: dotSize)
      NSBezierPath(ovalIn: dotRect).fill()
    }
  }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, WKNavigationDelegate {
  var window: NSWindow!
  var webView: WKWebView!
  var controlBarWindow: NSWindow!
  var statusItem: NSStatusItem!
  var globalMonitor: Any?
  var keyPressCount = 0
  var movable = false
  var accentColor = defaultAccentColor

  func applicationDidFinishLaunching(_ notification: Notification) {
    NSApp.setActivationPolicy(.accessory) // no Dock icon, no app-switcher entry

    if let hex = UserDefaults.standard.string(forKey: "accentColorHex"), let stored = NSColor(hex: hex) {
      accentColor = stored
    }

    setUpWindow()
    setUpControlBar()
    setUpStatusItem()
    requestAccessibilityAccess()
    requestInputMonitoringAccess()
    startGlobalMonitor()
  }

  func setUpWindow() {
    let screenFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
    let origin = NSPoint(
      x: screenFrame.midX - overlayWidth / 2,
      y: screenFrame.minY + 40
    )
    let frame = NSRect(origin: origin, size: NSSize(width: overlayWidth, height: overlayHeight))

    // .nonactivatingPanel keeps this window from ever becoming key/focused
    // or activating the app, so keyboard focus always stays on whatever
    // app is underneath — global key monitoring should never need it to.
    window = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    window.isOpaque = false
    window.backgroundColor = .clear
    window.hasShadow = false
    window.level = .screenSaver
    window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
    window.ignoresMouseEvents = true
    window.isMovableByWindowBackground = false

    let config = WKWebViewConfiguration()
    webView = WKWebView(frame: NSRect(origin: .zero, size: frame.size), configuration: config)
    webView.setValue(false, forKey: "drawsBackground")
    webView.autoresizingMask = [.width, .height]
    webView.navigationDelegate = self

    window.contentView = webView

    let resourceDir = Bundle.main.resourceURL!
    let indexURL = resourceDir.appendingPathComponent("index.html")
    webView.loadFileURL(indexURL, allowingReadAccessTo: resourceDir)

    window.orderFrontRegardless()
  }

  // Re-applies the persisted/current accent color once the page's JS
  // (window.setAccentColor) actually exists — evaluateJavaScript before
  // this fires would silently do nothing.
  func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
    applyAccentColor(accentColor)
  }

  // A small always-interactive window docked at the overlay's top-left
  // corner: drag anywhere on it to move the whole overlay, click the red
  // circle to quit. Kept as a separate window (rather than baked into the
  // click-through main window) since ignoresMouseEvents is all-or-nothing
  // per window on macOS.
  //
  // Rebuilt from scratch after several failed attempts (custom mouseDown
  // dragging, NSPanel + .nonactivatingPanel, .screenSaver level) using only
  // plain, standard AppKit: a normal NSWindow (not a panel) with
  // isMovableByWindowBackground for dragging, and a real NSButton (not a
  // custom NSView) for the quit control — these are the exact mechanisms
  // essentially every Mac utility/HUD app uses, so they're the most likely
  // to just work rather than hit an obscure edge case. Trade-off: clicking
  // this bar can briefly activate the app (bring it to the foreground),
  // since it's no longer a non-activating panel.
  func setUpControlBar() {
    let origin = NSPoint(
      x: window.frame.minX + 6,
      y: window.frame.maxY - controlBarHeight - 6
    )
    let frame = NSRect(origin: origin, size: NSSize(width: controlBarWidth, height: controlBarHeight))

    // .titled + .closable gets us the REAL system close button (proper
    // hover/press states, guaranteed-correct hit testing) instead of a
    // hand-drawn one. .fullSizeContentView + transparent/hidden titlebar
    // hides all the normal title-bar chrome so it still looks like a plain
    // small floating bar, not a window.
    // .nonactivatingPanel is essential here: without it, the first click
    // while our (backgrounded, .accessory) app isn't active just activates
    // the app instead of being delivered to the button/drag as a real
    // click — confirmed by video showing our own global mouse monitor
    // (which only ever sees clicks sent to OTHER apps) lighting up in
    // response to a click that was visibly on top of the close button.
    controlBarWindow = NSPanel(
      contentRect: frame,
      styleMask: [.titled, .closable, .fullSizeContentView, .nonactivatingPanel],
      backing: .buffered,
      defer: false
    )
    controlBarWindow.titlebarAppearsTransparent = true
    controlBarWindow.titleVisibility = .hidden
    controlBarWindow.isOpaque = false
    controlBarWindow.backgroundColor = .clear
    controlBarWindow.hasShadow = true
    controlBarWindow.level = .floating
    controlBarWindow.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
    controlBarWindow.ignoresMouseEvents = false
    controlBarWindow.isMovableByWindowBackground = true
    controlBarWindow.delegate = self

    let barView = ControlBarView(frame: NSRect(origin: .zero, size: frame.size))

    let gearSize: CGFloat = 16
    let gearButton = NSButton(
      frame: NSRect(x: controlBarWidth - gearSize - 6, y: (controlBarHeight - gearSize) / 2, width: gearSize, height: gearSize)
    )
    gearButton.isBordered = false
    gearButton.imagePosition = .imageOnly
    gearButton.image = NSImage(systemSymbolName: "gearshape.fill", accessibilityDescription: "Settings")
    gearButton.contentTintColor = NSColor.white.withAlphaComponent(0.85)
    gearButton.target = self
    gearButton.action = #selector(settingsButtonClicked(_:))
    barView.addSubview(gearButton)

    controlBarWindow.contentView = barView

    // Moving this (parent) window natively/efficiently moves the main
    // overlay (child) along with it at the window-server level, in lockstep
    // with the drag — much cheaper than our previous approach of manually
    // repositioning the WKWebView-hosting main window on every mouse-move
    // notification, which was visibly laggy since that window is expensive
    // to reposition at high frequency. (addChildWindow was removed earlier
    // while chasing a click-delivery bug; that bug turned out to be the
    // local event monitor swallowing clicks, unrelated to this, so it's
    // safe to bring back.)
    controlBarWindow.addChildWindow(window, ordered: .below)
    controlBarWindow.orderFrontRegardless()
  }

  // The real close button (wired automatically by AppKit) closes this
  // window, which fires this delegate method — used to quit the whole app.
  func windowWillClose(_ notification: Notification) {
    guard notification.object as? NSWindow === controlBarWindow else { return }
    debugLog("[keyboard-overlay] control bar closed, quitting")
    NSApp.terminate(nil)
  }

  @objc func settingsButtonClicked(_ sender: NSButton) {
    let menu = NSMenu()
    let colorItem = NSMenuItem(title: "Highlight Color…", action: #selector(showColorPicker), keyEquivalent: "")
    colorItem.target = self
    menu.addItem(colorItem)
    menu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.height), in: sender)
  }

  @objc func showColorPicker() {
    // Our app is .accessory (no Dock icon) and normally never becomes the
    // frontmost app, so a plain orderFront can leave the panel sitting
    // behind whatever app currently has focus — activate first so it
    // actually comes to the front and becomes interactive.
    NSApp.activate(ignoringOtherApps: true)
    let panel = NSColorPanel.shared
    panel.setTarget(self)
    panel.setAction(#selector(colorPickerChanged(_:)))
    panel.isContinuous = true
    panel.color = accentColor
    panel.makeKeyAndOrderFront(nil)
  }

  @objc func colorPickerChanged(_ sender: NSColorPanel) {
    applyAccentColor(sender.color)
  }

  // Pushes the chosen highlight color into the page's CSS variables (both
  // the hex fill and an unitless "r, g, b" triplet used for rgba() glows),
  // and persists it so it survives relaunch.
  func applyAccentColor(_ color: NSColor) {
    guard let rgb = color.usingColorSpace(.deviceRGB) else { return }
    let r = Int(round(rgb.redComponent * 255))
    let g = Int(round(rgb.greenComponent * 255))
    let b = Int(round(rgb.blueComponent * 255))
    let hex = String(format: "#%02X%02X%02X", r, g, b)

    accentColor = rgb
    UserDefaults.standard.set(hex, forKey: "accentColorHex")
    webView.evaluateJavaScript("window.setAccentColor && window.setAccentColor('\(hex)', \(r), \(g), \(b))") { _, error in
      if let error {
        debugLog("[keyboard-overlay] setAccentColor JS error: \(error)")
      }
    }
  }

  func setUpStatusItem() {
    statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    statusItem.button?.title = "⌨"

    let menu = NSMenu()

    let moveItem = NSMenuItem(title: "Move / Resize Overlay", action: #selector(toggleMovable), keyEquivalent: "")
    moveItem.target = self
    menu.addItem(moveItem)

    let resetItem = NSMenuItem(title: "Reset Position", action: #selector(resetPosition), keyEquivalent: "")
    resetItem.target = self
    menu.addItem(resetItem)

    menu.addItem(.separator())
    menu.addItem(withTitle: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

    statusItem.menu = menu
  }

  @objc func toggleMovable(_ sender: NSMenuItem) {
    movable.toggle()
    sender.state = movable ? .on : .off
    window.ignoresMouseEvents = !movable
    window.isMovableByWindowBackground = movable
    webView.evaluateJavaScript("window.setMovable(\(movable))")
  }

  @objc func resetPosition() {
    guard let screenFrame = NSScreen.main?.visibleFrame else { return }
    let origin = NSPoint(x: screenFrame.midX - overlayWidth / 2, y: screenFrame.minY + 40)
    // window (child) follows controlBarWindow (parent) automatically.
    controlBarWindow.setFrameOrigin(NSPoint(
      x: origin.x + 6,
      y: origin.y + overlayHeight - controlBarHeight - 6
    ))
  }

  func requestAccessibilityAccess() {
    // NSEvent's global key monitor (below) is gated by Accessibility trust,
    // not Input Monitoring — this is what was actually missing before.
    // Prompts the system "trust this app" dialog on first launch.
    let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
    let trusted = AXIsProcessTrustedWithOptions(options as CFDictionary)
    debugLog("[keyboard-overlay] Accessibility trusted=\(trusted)")
  }

  func requestInputMonitoringAccess() {
    // Triggers the system "Input Monitoring" consent prompt on first launch.
    let granted = IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
    debugLog("[keyboard-overlay] IOHIDRequestAccess(listenEvent) granted=\(granted)")
  }

  func startGlobalMonitor() {
    let mask: NSEvent.EventTypeMask = [
      .keyDown, .keyUp, .flagsChanged,
      .leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp,
    ]

    globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] event in
      self?.handle(event)
    }
    debugLog("[keyboard-overlay] global monitor registered=\(globalMonitor != nil)")

    // Safety net in case our app ever does end up focused despite
    // .nonactivatingPanel (e.g. Cmd-Tabbed to explicitly) — swallow keyDown/
    // keyUp specifically (return nil) so they don't fall through the empty
    // responder chain and trigger the system beep. Everything else
    // (flagsChanged, and crucially the mouse events) must pass through
    // unmodified — returning nil for those silently ate every click on our
    // own controls (the close button, drag bar), regardless of how they
    // were implemented, which is why past attempts all failed identically.
    NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
      self?.handle(event)
      switch event.type {
      case .keyDown, .keyUp:
        return nil
      default:
        return event
      }
    }
  }

  // Modifier keys (Shift/Control/Option/Command) never generate keyDown/
  // keyUp — only flagsChanged, carrying the current overall modifier state
  // plus which physical key just changed via keyCode.
  func modifierFamily(for keyCode: UInt16) -> NSEvent.ModifierFlags? {
    switch keyCode {
    case 0x38, 0x3C: return .shift
    case 0x3B, 0x3E: return .control
    case 0x3A, 0x3D: return .option
    case 0x37, 0x36: return .command
    default: return nil
    }
  }

  func handle(_ event: NSEvent) {
    switch event.type {
    case .keyDown, .keyUp:
      let name = keyCodeToName[event.keyCode]
      debugLog("[keyboard-overlay] key keyCode=\(event.keyCode) mapped=\(name ?? "unmapped") state=\(event.type == .keyDown ? "down" : "up")")
      if event.type == .keyDown { recordKeyPress() }
      guard let name else { return }
      dispatch(kind: "key", state: event.type == .keyDown ? "down" : "up", value: name)
    case .flagsChanged:
      guard let name = keyCodeToName[event.keyCode], let family = modifierFamily(for: event.keyCode) else { return }
      let isDown = event.modifierFlags.contains(family)
      debugLog("[keyboard-overlay] modifier keyCode=\(event.keyCode) mapped=\(name) state=\(isDown ? "down" : "up")")
      if isDown { recordKeyPress() }
      dispatch(kind: "key", state: isDown ? "down" : "up", value: name)
    case .leftMouseDown, .leftMouseUp:
      dispatch(kind: "mouse", state: event.type == .leftMouseDown ? "down" : "up", value: "left")
    case .rightMouseDown, .rightMouseUp:
      dispatch(kind: "mouse", state: event.type == .rightMouseDown ? "down" : "up", value: "right")
    default:
      break
    }
  }

  // Keeps ~/keyboard-overlay-debug.log from growing forever: every 1000
  // key presses (keyDown / modifier-down — not releases, not mouse), wipe
  // it and start over.
  func recordKeyPress() {
    keyPressCount += 1
    guard keyPressCount >= 1000 else { return }
    keyPressCount = 0
    try? "".write(toFile: debugLogPath, atomically: true, encoding: .utf8)
    debugLog("[keyboard-overlay] log rotated after 1000 key presses")
  }

  func dispatch(kind: String, state: String, value: String) {
    let js = "window.handleInputEvent && window.handleInputEvent('\(kind)', '\(state)', '\(value)')"
    DispatchQueue.main.async { [weak self] in
      self?.webView.evaluateJavaScript(js) { _, error in
        if let error {
          debugLog("[keyboard-overlay] evaluateJavaScript error: \(error)")
        }
      }
    }
  }

  func applicationWillTerminate(_ notification: Notification) {
    if let globalMonitor {
      NSEvent.removeMonitor(globalMonitor)
    }
  }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
