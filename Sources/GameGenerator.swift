import ArgumentParser
import Foundation

/// Entry point for the command-line tool.
@main
struct GameGenerator: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Finds Fourtile games and streams the output as JSON, for use in the Fourtile web game.",
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
        version: "1.0.0")

    @Option(name: .shortAndLong,
            help: "The text file containing dictionary words.",
            completion: .file(extensions: ["txt"]),
            transform: { URL(filePath: $0, directoryHint: .notDirectory) })
    var dictionary: URL

    @Option(name: .shortAndLong,
            help: "The JSON file to write game data to.",
            transform: { URL(filePath: $0, directoryHint: .notDirectory) })
    var output: URL?

    /// Entry point for the command line tool.
    mutating func run() async throws {
        let words = Words()
        try await words.load(from: dictionary)

        if let output { FileManager.default.createFile(atPath: output.path(), contents: nil) }
        let outputStream = output == nil ? FileHandle.standardOutput : try FileHandle(forWritingTo: output!)

        let signalSource = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
        signal(SIGINT, SIG_IGN) // Ignore default SIGINT behavior
        signalSource.setEventHandler {
            // Flush the buffer when the script is aborted
            // swiftlint:disable force_try
            try! outputStream.synchronize()
            try! outputStream.write(contentsOf: "]".data(using: .ascii)!)
            try! outputStream.close()
            // swiftlint:enable force_try
            Self.exit()
        }
        signalSource.resume()

        let gameFinder = GameFinder(words: words, streamTo: outputStream)
        try await gameFinder.findGames(showProgress: output != nil)
    }
}
