import ArgumentParser
import Foundation

/// Entry point for the command-line tool.
@main
struct GameGenerator: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    abstract:
      "Finds Fourtile games and streams the output as JSON, for use in the Fourtile web game.",
    discussion: """
      This game attempts to find as many Fourtile games as possible. Games are
      streamed in JSON format to stdout or a file. Games are found using a randomized
      heuristic, so there is no guarantee that every possible game will be found. This
      is why games are streamed to stdout as they are found: Finding each next game
      becomes computationally more expensive as more randomizations are required.

      It is the intention that the user will abort this script when the time to find
      the next game becomes unreasonable, and the user is satisfied with the number
      of games found. The only required step is then to clean up the end of the JSON
      file.

      When writing games to a file, stdout is used to show a progress indicator, which
      is normalized to the theoretical maximum number of possible games.
      """,
    version: "1.0.0"
  )

  private static let jsonArrayTerminator = Data("]".utf8)

  @Option(
    name: .shortAndLong,
    help: "The text file containing dictionary words.",
    completion: .file(extensions: ["txt"]),
    transform: { URL(filePath: $0, directoryHint: .notDirectory) }
  )
  var dictionary: URL

  @Option(
    name: .shortAndLong,
    help: "The JSON file to write game data to.",
    transform: { URL(filePath: $0, directoryHint: .notDirectory) }
  )
  var output: URL?

  // Bridges SIGINT into an async stream that emits once per interrupt. There is
  // no native Swift-concurrency signal API, so a DispatchSource signal source
  // remains the underlying primitive; the default terminate-on-SIGINT behavior
  // is suppressed so the search can shut down gracefully and leave well-formed
  // JSON behind.
  private static func interruptSignals() -> AsyncStream<Void> {
    AsyncStream { continuation in
      let source = DispatchSource.makeSignalSource(signal: SIGINT)
      signal(SIGINT, SIG_IGN)
      source.setEventHandler { continuation.yield() }
      continuation.onTermination = { _ in source.cancel() }
      source.resume()
    }
  }

  /// Entry point for the command line tool.
  mutating func run() async throws {
    let words = Words()
    try await words.load(from: dictionary)

    if let output { FileManager.default.createFile(atPath: output.path(), contents: nil) }
    let outputStream =
      output == nil ? FileHandle.standardOutput : try FileHandle(forWritingTo: output!)

    let gameFinder = GameFinder(words: words, streamTo: outputStream)
    try await search(with: gameFinder, showingProgress: output != nil)
    finalize(outputStream)
  }

  // Runs the search alongside an interrupt watcher; the first to finish cancels
  // the other. Cancelling the search lets in-flight games finish streaming
  // before this returns, so the output is complete before it is closed.
  private func search(with gameFinder: GameFinder, showingProgress showProgress: Bool) async throws
  {
    let interrupts = Self.interruptSignals()
    try await withThrowingTaskGroup(of: Void.self) { group in
      group.addTask { try await gameFinder.findGames(showProgress: showProgress) }
      group.addTask { for await _ in interrupts { return } }

      for try await _ in group { group.cancelAll() }
    }
  }

  private func finalize(_ stream: FileHandle) {
    try? stream.synchronize()
    try? stream.write(contentsOf: Self.jsonArrayTerminator)
    try? stream.close()
  }
}
