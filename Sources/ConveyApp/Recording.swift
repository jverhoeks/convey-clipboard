import AppKit
import AVFoundation
import ScreenCaptureKit

/// The six capture actions, shared by the picker header and the menu-bar right-click menu.
struct CaptureAction: Identifiable {
    let id: Int, title: String, symbol: String, hotKey: String, record: Bool, mode: Screenshot.Mode

    static let all: [CaptureAction] = [
        .init(id: 0, title: "Capture Area", symbol: "rectangle.dashed", hotKey: "hotkey.area", record: false, mode: .area),
        .init(id: 1, title: "Capture Window", symbol: "macwindow", hotKey: "hotkey.window", record: false, mode: .window),
        .init(id: 2, title: "Capture Screen", symbol: "display", hotKey: "hotkey.screen", record: false, mode: .screen),
        .init(id: 3, title: "Record Area", symbol: "rectangle.dashed", hotKey: "hotkey.recordArea", record: true, mode: .area),
        .init(id: 4, title: "Record Window", symbol: "macwindow", hotKey: "hotkey.recordWindow", record: true, mode: .window),
        .init(id: 5, title: "Record Screen", symbol: "display", hotKey: "hotkey.recordScreen", record: true, mode: .screen),
    ]

    var help: String { title + (Prefs.hotKey(hotKey).map { "  \($0.label)" } ?? "") }

    /// Runs after a short delay so the menu or popover is gone before the overlay or framebuffer read.
    @MainActor func perform() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            record ? Recorder.toggle(mode) : Screenshot.capture(mode)
        }
    }
}

/// Screen, area, or window video recording to MP4 (ScreenCaptureKit + AVAssetWriter, macOS 13+).
/// Any recording hotkey, or clicking the menu-bar item, stops it.
@MainActor
enum Recorder {
    private static var session: RecordingSession?
    private static var starting = false
    private static var border: NSWindow?
    /// Start date while recording, nil when idle. Drives the menu-bar stop button + timer.
    static var onChange: ((Date?) -> Void)?
    static var isRecording: Bool { session != nil }
    static private(set) var startedAt: Date?
    static var file: URL? { session?.url }

    static func toggle(_ mode: Screenshot.Mode) {
        if session != nil { stop(); return }
        guard !starting, Screenshot.ensurePermission() else { return }
        switch mode {
        case .screen:
            guard let screen = Screenshot.screenUnderMouse else { NSSound.beep(); return }
            Task { await reporting { try await start(screen: screen, rect: screen.frame) } }
        case .area:
            AreaSelector.begin { screen, rect in Task { await reporting { try await start(screen: screen, rect: rect) } } }
        case .window:
            Task { await WindowSelector.begin { window, scale in
                Task { await reporting { try await start(window: window, scale: scale) } } } }
        }
    }

    private static func reporting(_ start: () async throws -> Void) async {
        do { try await start() } catch { Screenshot.alert("Could not start recording", error) }
    }

    static func stop() {
        Task {
            do { if let url = try await finish() { deliver(url) } }
            catch { Screenshot.alert("Could not save recording", error) }
        }
    }

    /// Stops and returns the finished file, nil when idle. No clipboard or Finder side effects.
    static func finish() async throws -> URL? {
        guard let current = session else { return nil }
        session = nil
        startedAt = nil
        border?.orderOut(nil); border = nil
        onChange?(nil)
        return try await current.stop()
    }

    /// `rect` in global Cocoa coordinates. `output` nil = the screenshot folder's next name.
    static func start(screen: NSScreen, rect: NSRect, output: URL? = nil) async throws {
        guard let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
        else { throw RecordingError.noDisplay }
        try await begin(border: rect == screen.frame ? nil : rect, output: output) {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            guard let display = content.displays.first(where: { $0.displayID == id }) else { throw RecordingError.noDisplay }
            // Leave Convey's own windows (the recording frame, the picker) out of the video.
            let me = content.applications.filter { $0.processID == getpid() }
            let source = SelectionGeometry.captureRect(rect, screenFrame: screen.frame, scale: screen.backingScaleFactor, even: true)
            let cfg = config(size: source.size, scale: screen.backingScaleFactor)
            cfg.sourceRect = source
            return (SCContentFilter(display: display, excludingApplications: me, exceptingWindows: []), cfg)
        }
    }

    static func start(window: SCWindow, scale: CGFloat, output: URL? = nil) async throws {
        try await begin(border: nil, output: output) {
            (SCContentFilter(desktopIndependentWindow: window), config(size: window.frame.size, scale: scale))
        }
    }

    private static func config(size: CGSize, scale: CGFloat) -> SCStreamConfiguration {
        let cfg = SCStreamConfiguration()
        // Video encoders need even dimensions.
        cfg.width = max(2, Int((size.width * scale).rounded()) & ~1)
        cfg.height = max(2, Int((size.height * scale).rounded()) & ~1)
        cfg.minimumFrameInterval = CMTime(value: 1, timescale: 30)
        cfg.pixelFormat = kCVPixelFormatType_32BGRA
        cfg.queueDepth = 6
        cfg.showsCursor = true
        return cfg
    }

    private static func begin(border rect: NSRect?, output: URL?,
                              _ make: () async throws -> (SCContentFilter, SCStreamConfiguration)) async throws {
        guard !starting, session == nil else { throw RecordingError.busy }
        starting = true
        defer { starting = false }
        let (filter, cfg) = try await make()
        let url = try output ?? Screenshot.outputURL(extension: "mp4")
        try? FileManager.default.removeItem(at: url)  // AVAssetWriter refuses to overwrite
        let recording = try RecordingSession(filter: filter, config: cfg, url: url)
        recording.onFailure = { error in
            Task { @MainActor in
                guard session === recording else { return }
                stop()
                Screenshot.alert("Recording stopped", error)
            }
        }
        try await recording.start()
        session = recording
        startedAt = Date()
        if let rect { border = RecordingBorder(around: rect) }
        onChange?(Date())
    }

    private static func deliver(_ url: URL) {
        let d = Prefs.store
        if d.bool(forKey: "screenshotCopy") {
            // A file URL pastes as the video itself in Finder, Mail, Slack, Messages, …
            NSPasteboard.general.clearContents()
            NSPasteboard.general.writeObjects([url as NSURL])
        }
        if d.bool(forKey: "screenshotSave") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
    }
}

/// Owns one SCStream and the writer it feeds. Sample buffers arrive on `queue`; writer state is only touched there.
final class RecordingSession: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    let url: URL
    var onFailure: ((Error) -> Void)?
    private var stream: SCStream!
    private let writer: AVAssetWriter
    private let input: AVAssetWriterInput
    private let queue = DispatchQueue(label: "convey.recording")
    private var started = false, finished = false

    init(filter: SCContentFilter, config: SCStreamConfiguration, url: URL) throws {
        self.url = url
        writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        // H.264 plays everywhere; hardware H.264 tops out at 4096 px, so bigger captures (5K/6K) use HEVC.
        let codec: AVVideoCodecType = max(config.width, config.height) > 4096 ? .hevc : .h264
        input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: codec, AVVideoWidthKey: config.width, AVVideoHeightKey: config.height,
        ])
        input.expectsMediaDataInRealTime = true
        guard writer.canAdd(input) else { throw RecordingError.encoder }
        writer.add(input)
        super.init()
        stream = SCStream(filter: filter, configuration: config, delegate: self)
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)
    }

    func start() async throws {
        guard writer.startWriting() else { throw writer.error ?? RecordingError.encoder }
        do { try await stream.startCapture() } catch { writer.cancelWriting(); throw error }
    }

    func stop() async throws -> URL {
        try? await stream.stopCapture()
        return try await withCheckedThrowingContinuation { done in
            queue.async { [self] in
                finished = true
                guard started else {
                    writer.cancelWriting()
                    return done.resume(throwing: RecordingError.noFrames)
                }
                // ScreenCaptureKit only sends frames when something changes; end at "now" so a
                // still tail isn't cut off.
                writer.endSession(atSourceTime: CMClockGetTime(CMClockGetHostTimeClock()))
                input.markAsFinished()
                writer.finishWriting { [self] in
                    if writer.status == .completed { done.resume(returning: url) }
                    else { done.resume(throwing: writer.error ?? RecordingError.encoder) }
                }
            }
        }
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer buffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, !finished, buffer.isValid,
              let info = CMSampleBufferGetSampleAttachmentsArray(buffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let raw = info.first?[.status] as? Int, SCFrameStatus(rawValue: raw) == .complete else { return }
        if !started { writer.startSession(atSourceTime: buffer.presentationTimeStamp); started = true }
        if input.isReadyForMoreMediaData { input.append(buffer) }
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) { onFailure?(error) }
}

enum RecordingError: LocalizedError {
    case noDisplay, encoder, noFrames, busy
    var errorDescription: String? {
        switch self {
        case .busy: return "A recording is already running."
        case .noDisplay: return "The display is no longer available."
        case .encoder: return "The video encoder could not be set up."
        case .noFrames: return "Nothing was recorded."
        }
    }
}

/// Dashed red frame just outside the recorded area. Click-through; excluded from the video.
private final class RecordingBorder: NSWindow {
    init(around rect: NSRect) {
        super.init(contentRect: rect.insetBy(dx: -4, dy: -4), styleMask: .borderless, backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        contentView = Frame()
        orderFrontRegardless()
    }

    private final class Frame: NSView {
        override func draw(_ dirty: NSRect) {
            let path = NSBezierPath(rect: bounds.insetBy(dx: 1.5, dy: 1.5))
            path.lineWidth = 2
            path.setLineDash([6, 4], count: 2, phase: 0)
            NSColor.systemRed.setStroke()
            path.stroke()
        }
    }
}
