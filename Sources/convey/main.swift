import AppKit
import ConveyCore

let usage = """
convey <command>

  list                        show detected clipboard flavors + valid targets
  html2md | html2txt          convert clipboard HTML
  md2html                     convert clipboard Markdown to HTML
  rtf2md                      convert clipboard RTF to Markdown
  img2b64                     convert clipboard image to a base64 data-URI
  mmd2svg | mmd2png           render clipboard Mermaid text
  rec [file.cast]             record this terminal (text + colors) as asciicast v2
  play <file.cast>            replay a recording in the terminal

Control the running Convey.app (needs Preferences › Allow command-line control):
  windows [--json] [--all]    list windows: id, app, title, x,y,w,h (--all: other Spaces too)
  shot   <target> [-o f.png]  screenshot; prints the file path
  record <target> [-o f.mp4] [--duration secs]
                              record video; without --duration, run `convey stop`
  stop | status               finish the recording (prints path) / show state
  <target>: screen [N] | window <id|app or title text> | area x,y,w,h (points, top-left)
  version | --version | -v    print the convey version

Reads the clipboard, converts, writes the result back to the clipboard.
For text edges, piped stdin is used as input and stdout receives the result.
"""

@MainActor
func run() async -> Int32 {
    let args = Array(CommandLine.arguments.dropFirst())
    let command = parseCommand(args)

    switch command {
    case .usage:
        print(usage)
        return 2

    case .version:
        print(conveyVersion)
        return 0

    case let .rec(path):
        return recordTerminal(to: path)

    case let .play(path):
        return playCast(path)

    case let .control(args):
        return control(args)

    case .list:
        let sources = PasteboardReader().sources(from: SystemPasteboard())
        let targets = Convey().graph.validTargets(from: sources)
        print("sources: " + sources.map(\.rawValue).joined(separator: ", "))
        print("targets: " + targets.map(\.rawValue).joined(separator: ", "))
        return 0

    case let .convert(from, to):
        let reader = PasteboardReader()
        let snapshot = SystemPasteboard()

        // Text edges accept piped stdin; otherwise read from the clipboard.
        let stdinData = from == .image ? nil : readPipedStdin()
        let input: Payload?
        if let stdinData {
            if from == .rtf {
                input = .bytes(stdinData)
            } else {
                guard let text = String(data: stdinData, encoding: .utf8) else {
                    FileHandle.standardError.write(Data("convey: stdin must be UTF-8 text\n".utf8))
                    return 1
                }
                input = .text(text)
            }
        } else {
            input = reader.payload(for: from, from: snapshot)
        }
        guard let input else {
            FileHandle.standardError.write(Data("convey: no \(from.rawValue) content on clipboard\n".utf8))
            return 1
        }

        do {
            let result = try await Convey().convert(input, from: from, to: to)
            // Route by whether stdin was actually USED as input, not merely present:
            // img2b64 reads the image from the clipboard even if stdin is piped, so
            // stdin-presence alone would misroute its data-URI to stdout.
            if stdinData != nil {
                switch result {
                case let .text(out): print(out)
                case let .bytes(out): FileHandle.standardOutput.write(out)
                }
            } else {
                PasteboardWriter().write(result, as: to, to: .general)
                FileHandle.standardError.write(Data("convey: wrote \(to.rawValue) to clipboard\n".utf8))
            }
            return 0
        } catch {
            FileHandle.standardError.write(Data("convey: \(error)\n".utf8))
            return 1
        }
    }
}

func readPipedStdin() -> Data? {
    guard isatty(fileno(stdin)) == 0 else { return nil }
    let data = FileHandle.standardInput.readDataToEndOfFile()
    guard !data.isEmpty else { return nil }
    return data
}

let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
app.finishLaunching()

Task { @MainActor in
    let code = await run()
    exit(code)
}

app.run()
