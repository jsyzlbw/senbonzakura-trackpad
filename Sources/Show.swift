import AVFoundation
import AppKit
import CoreMedia
import Darwin
import UniformTypeIdentifiers

enum ScoreSelection {
  static func choose(in resources: URL, testing: Bool) throws -> URL? {
    let files = FileManager.default
    let directory = try files.url(
      for: .applicationSupportDirectory, in: .userDomainMask,
      appropriateFor: nil, create: false
    )
    .appendingPathComponent("SenbonzakuraTrackpad", isDirectory: true)
    let cached = directory.appendingPathComponent("Performance.mid")
    let bundled = resources.appendingPathComponent("Performance.mid")
    if testing || !NSEvent.modifierFlags.contains(.option) {
      let choices = testing ? [bundled, cached] : [cached, bundled]
      if let score = choices.first(where: { files.isReadableFile(atPath: $0.path) }) {
        return score
      }
    }
    if testing {
      throw NSError(
        domain: "Performance", code: 1,
        userInfo: [
          NSLocalizedDescriptionKey:
            "同步检查需要先导入曲谱，或使用构建时内置曲谱的版本。"
        ])
    }

    let panel = NSOpenPanel()
    panel.title = "选择《千本樱》MIDI 曲谱"
    panel.message = "画面按约 155 BPM、4 分 11 秒的编曲制作。选好后会记住曲谱，下次可直接开演。"
    panel.allowedContentTypes = [.midi]
    panel.prompt = "导入并开演"
    NSApp.activate(ignoringOtherApps: true)
    guard panel.runModal() == .OK, let source = panel.url else { return nil }

    try files.createDirectory(at: directory, withIntermediateDirectories: true)
    let temporary = directory.appendingPathComponent("import-" + UUID().uuidString + ".mid")
    defer { try? files.removeItem(at: temporary) }
    let process = Process()
    let errors = Pipe()
    process.executableURL = Bundle.main.bundleURL.appendingPathComponent(
      "Contents/Helpers/PrepareScore")
    process.arguments = [source.path, temporary.path]
    process.standardError = errors
    try process.run()
    let detail = errors.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
      throw NSError(
        domain: "Performance", code: 2,
        userInfo: [
          NSLocalizedDescriptionKey:
            "导入曲谱失败。\n" + String(decoding: detail, as: UTF8.self)
        ])
    }
    // Both paths are in the same directory. Other launches see the old or the complete new score.
    guard rename(temporary.path, cached.path) == 0 else {
      throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
    }
    return cached
  }
}

final class Stage: NSWindow {
  override var canBecomeKey: Bool { true }
  override var canBecomeMain: Bool { true }
}

final class Performance: NSObject, NSApplicationDelegate {
  let test = CommandLine.arguments.contains("--check-sync")
  let player = AVPlayer()
  let helper = Process()
  let commands = Pipe(), reports = Pipe(), errors = Pipe()
  let countdown = NSTextField(labelWithString: "准备中")
  var stage: Stage!
  var videoLayer: AVPlayerLayer!
  var cover: NSView!
  var item: AVPlayerItem!
  var timer: Timer?
  var keyMonitor: Any?
  var signals: [DispatchSourceSignal] = []
  var launched = false, hapticReady = false, priming = false, videoReady = false, stopping = false
  var textReceived = ""
  var target: CMTime?
  var started = ProcessInfo.processInfo.systemUptime
  var activity: NSObjectProtocol?
  func log(_ text: String) { FileHandle.standardError.write(Data((text + "\n").utf8)) }

  func applicationDidFinishLaunching(_ notification: Notification) {
    guard let dir = Bundle.main.resourceURL else {
      fail("找不到应用资源。")
      return
    }
    let movie = dir.appendingPathComponent("Senbonzakura.mp4")
    guard FileManager.default.isReadableFile(atPath: movie.path) else {
      fail("缺少 MV 文件 Senbonzakura.mp4，请重新构建或解压完整应用。")
      return
    }
    let score: URL
    do {
      guard let selected = try ScoreSelection.choose(in: dir, testing: test) else {
        finish()
        return
      }
      score = selected
    } catch {
      fail(error.localizedDescription)
      return
    }
    guard
      let screen = NSScreen.screens.first(where: { screen in
        guard
          let n = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
        else { return false }
        return CGDisplayIsBuiltin(n.uint32Value) != 0
      }) ?? NSScreen.main
    else {
      fail("找不到演出屏幕。")
      return
    }
    activity = ProcessInfo.processInfo.beginActivity(
      options: [.userInitiated, .idleDisplaySleepDisabled], reason: "千本樱声画同步演出")
    let frame =
      test
      ? NSRect(x: screen.frame.minX + 50, y: screen.frame.minY + 50, width: 640, height: 360)
      : screen.frame
    stage = Stage(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
    stage.isReleasedWhenClosed = false
    stage.backgroundColor = .black
    stage.level = test ? .normal : .screenSaver
    stage.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    let root = NSView(frame: NSRect(origin: .zero, size: frame.size))
    root.wantsLayer = true
    stage.contentView = root
    videoLayer = AVPlayerLayer(player: player)
    videoLayer.frame = root.bounds
    videoLayer.videoGravity = .resizeAspect
    root.layer?.addSublayer(videoLayer)
    cover = NSView(frame: root.bounds)
    cover.wantsLayer = true
    cover.layer?.backgroundColor = NSColor.black.cgColor
    root.addSubview(cover)
    countdown.font = .systemFont(ofSize: test ? 28 : 64, weight: .light)
    countdown.textColor = .white
    countdown.alignment = .center
    countdown.frame = NSRect(x: 0, y: (frame.height - 100) / 2, width: frame.width, height: 100)
    cover.addSubview(countdown)
    if !test {
      NSApp.presentationOptions = [.hideDock, .hideMenuBar]
      NSCursor.hide()
    }
    NSApp.activate(ignoringOtherApps: true)
    stage.makeKeyAndOrderFront(nil)
    keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
      if e.keyCode == 53 || e.charactersIgnoringModifiers == "q" {
        self?.finish()
        return nil
      }
      return e
    }
    for sig in [SIGINT, SIGTERM, SIGHUP] {
      signal(sig, SIG_IGN)
      let handler = DispatchSource.makeSignalSource(signal: sig, queue: .main)
      handler.setEventHandler { [weak self] in self?.finish() }
      handler.resume()
      signals.append(handler)
    }
    item = AVPlayerItem(url: movie)
    player.automaticallyWaitsToMinimizeStalling = false
    player.isMuted = true
    player.actionAtItemEnd = .pause
    player.replaceCurrentItem(with: item)
    NotificationCenter.default.addObserver(
      self, selector: #selector(videoEnded), name: .AVPlayerItemDidPlayToEndTime, object: item)
    NotificationCenter.default.addObserver(
      self, selector: #selector(videoFailed), name: .AVPlayerItemFailedToPlayToEndTime, object: item
    )
    helper.executableURL = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/Haptic")
    helper.arguments = ["--plain", "--music", score.path]
    helper.standardInput = commands
    helper.standardOutput = reports
    helper.standardError = errors
    reports.fileHandleForReading.readabilityHandler = { [weak self] fd in
      let data = fd.availableData
      if data.isEmpty {
        fd.readabilityHandler = nil
        return
      }
      let part = String(decoding: data, as: UTF8.self)
      DispatchQueue.main.async {
        guard let self else { return }
        self.textReceived += part
        if self.textReceived.contains("HAPTIC_READY\n") { self.hapticReady = true }
      }
    }
    helper.terminationHandler = { [weak self] child in
      DispatchQueue.main.async {
        guard let self, !self.stopping else { return }
        if child.terminationStatus != 0 || self.target == nil {
          let info = String(
            decoding: self.errors.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
          self.fail("触控板播放器未能完成演奏。\n" + info)
        }
      }
    }
    do {
      try helper.run()
      launched = true
    } catch {
      fail(error.localizedDescription)
      return
    }
    started = ProcessInfo.processInfo.systemUptime
    timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
      self?.update()
    }
  }
  func update() {
    guard !stopping else { return }
    if item.status == .failed {
      fail(item.error?.localizedDescription ?? "无法读取视频。")
      return
    }
    if !priming && item.status == .readyToPlay && player.status == .readyToPlay {
      priming = true
      player.preroll(atRate: 1) { ok in
        DispatchQueue.main.async {
          if ok { self.videoReady = true } else if !self.stopping { self.fail("视频预加载失败。") }
        }
      }
    }
    let clock = CMClockGetHostTimeClock()
    let now = CMClockGetTime(clock)
    if target == nil {
      guard videoReady && hapticReady && videoLayer.isReadyForDisplay else {
        if ProcessInfo.processInfo.systemUptime - started > 15 { fail("视频或触控板未能在 15 秒内就绪。") }
        return
      }
      let date = CMTimeAdd(now, CMTime(value: 3, timescale: 1))
      let ticks = CMClockConvertHostTimeToSystemUnits(date)
      do { try commands.fileHandleForWriting.write(contentsOf: Data("\(ticks)\n".utf8)) } catch {
        fail("无法通知触控板开始。")
        return
      }
      target = date
      player.setRate(1, time: .zero, atHostTime: date)
    }
    guard let target else { return }
    let elapsed = CMTimeSubtract(now, target).seconds
    if elapsed < 0 {
      countdown.stringValue = String(max(1, Int(ceil(-elapsed))))
      return
    }
    cover.isHidden = true
    if test && elapsed > 2.5 {
      let video = player.currentTime().seconds
      log(
        String(
          format:
            "sync validation — video %.3f s, shared clock %.3f s, delta %.3f s, helper running %d",
          video, elapsed, video - elapsed, helper.isRunning ? 1 : 0))
      guard
        let event = textReceived.split(separator: "\n").first(where: {
          $0.hasPrefix("FIRST_ACTUATION ")
        }),
        let ticks = UInt64(event.dropFirst("FIRST_ACTUATION ".count))
      else {
        fail("没有收到触控板驱动记录。")
        return
      }
      let offset = CMTimeSubtract(CMClockMakeHostTimeFromSystemUnits(ticks), target).seconds
      log(String(format: "first haptic dispatch relative to shared start: %.4f s", offset))
      if abs(video - elapsed) > 0.12 || abs(offset) > 0.10 || !helper.isRunning {
        fail("同步检查失败。")
        return
      }
      finish()
    } else if item.duration.isNumeric && elapsed > item.duration.seconds + 2 {
      fail("视频未能按时播放完毕。")
    }
  }
  @objc func videoEnded() { finish() }
  @objc func videoFailed() { fail(item.error?.localizedDescription ?? "播放视频时发生错误。") }
  func fail(_ message: String) {
    guard !stopping else { return }
    log(message)
    stop()
    if test { exit(EXIT_FAILURE) }
    let alert = NSAlert()
    alert.messageText = "千本樱 · 播放提示"
    alert.informativeText = message
    alert.runModal()
    NSApp.terminate(nil)
  }
  func finish() {
    guard !stopping else { return }
    stop()
    NSApp.terminate(nil)
  }
  func stop() {
    guard !stopping else { return }
    stopping = true
    timer?.invalidate()
    player.pause()
    try? commands.fileHandleForWriting.close()
    if launched && helper.isRunning {
      helper.terminate()
      helper.waitUntilExit()
    }
    reports.fileHandleForReading.readabilityHandler = nil
    if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
    if !test && stage != nil {
      NSCursor.unhide()
      NSApp.presentationOptions = []
    }
    stage?.orderOut(nil)
    if let activity { ProcessInfo.processInfo.endActivity(activity) }
  }
  func applicationWillTerminate(_ notification: Notification) { stop() }
}

let app = NSApplication.shared
app.setActivationPolicy(.regular)
let performance = Performance()
app.delegate = performance
app.run()
