import Foundation
import Algorithms
import Dispatch

/**
 Finds possible Fourtiles games by repeatedly generating random combinations of
 fourtiles until a combination is found that meets all the requirements.

 These requirements are:

 - Exactly ``numFourtilesPerGame`` fourtiles are constructible.
 - No words are constructible with more than ``numTilesPerFourtile`` tiles.
 - Each word is constructible using only one combination of tiles.
 - At least ``minWordsPerGame`` are constructible using between ``minTilesPerWord`` and ``numTilesPerFourtile`` tiles.

 Fourtiles are defined as words constructible with ``numTilesPerFourtile``
 tiles, with each tile having between ``minCharactersPerTile`` and
 ``maxCharactersPerTile`` characters. All words with sufficient characters to
 meet these criteria are candidate fourtiles.

 Games are found asynchronously when ``findGames(showProgress:)`` is called, and
 streamed to a given file handle in JSON format. The process can be interrupted
 at any point, though you will have to add the closing `]` in the output JSON.
 */
class GameFinder {
    
    /// The minimum number of characters to use when splitting a word into tiles.
    static let minCharactersPerTile = 2
    
    /// The maximum number of characters to use when splitting a word into tiles.
    static let maxCharactersPerTile = 4
    
    /// The minimum number of tiles that can be used to build a word.
    static let minTilesPerWord = 2

    /// The maximum number of tiles that can be used to build a word.
    static let numTilesPerFourtile = 4

    /// The number of words, buildable with ``numTilesPerFourtile``, used to make a board.
    static let numFourtilesPerGame = 5

    /// The minimum number of total buildable words within a board.
    static let minWordsPerGame = 10

    private static var validWordLengths: ClosedRange<Int> {
        let minLength = minCharactersPerTile * numTilesPerFourtile
        let maxLength = maxCharactersPerTile * numTilesPerFourtile
        return minLength...maxLength
    }

    private static var tileSizes: Dictionary<Int, Array<Int>> {
        validWordLengths.reduce([:]) { dict, wordLength in
            var dict = dict
            dict[wordLength] = Array(repeating: minCharactersPerTile, count: numTilesPerFourtile)
            while dict[wordLength]!.reduce(0, +) < wordLength {
                guard let index = dict[wordLength]!.firstIndex(where: { $0 < maxCharactersPerTile }) else {
                    fatalError("Couldn’t generate tileSizes")
                }
                dict[wordLength]![index] += 1
            }

            return dict
        }
    }

    private let words: Words
    private let stream: FileHandle

    /**
     Creates a new GameFinder which streams found games to a file handle.

     - Parameter words: The dictionary to use when finding games.
     - Parameter stream: The file handle to stream found games in JSON format.
     */
    init(words: Words, streamTo stream: FileHandle) {
        self.words = words
        self.stream = stream
    }

    /**
     Begins an asynchronous, stochastic process to find possible combinations
     of fourtiles.

     A stack of candidate fourtiles, pulled from the ``Words`` dictionary, is
     shuffled, and then groups of ``numFourtilesPerGame`` fourtiles are popped
     from the shuffled stack. Each group of words is then randomly split into
     tiles to make a board. The board is evaluated according to the game
     criteria, and streamed to the file handle if the board is valid. Otherwise,
     the fourtiles are added back to the stack and the stack is re-shuffled.

     This process will most likely never complete, as there will be remaining
     fourtiles that cannot be arranged and split to produce a valid board.

     - Parameter showProgress: If true, a progress bar is written to `stdout`.
       Set this to false when streaming output to `stdout`.
     */
    func findGames(showProgress: Bool = false) async throws {
        try stream.write(contentsOf: "[".data(using: .ascii)!)

        let fourtiles = await FourtileProvider(fourtiles: words.words.filter { Self.validWordLengths.contains($0.count) })

        let fourtileCount = await fourtiles.count/Self.numFourtilesPerGame
        let progress = showProgress ? ProgressActor(count: fourtileCount) : nil

        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted

        while await fourtiles.count >= Self.numFourtilesPerGame {
            try await withThrowingDiscardingTaskGroup { group in
                while let fourtilesForGame = await fourtiles.pop(count: Self.numFourtilesPerGame) {
                    group.addTask {
                        guard fourtilesForGame.count == Self.numFourtilesPerGame else { return }

                        if let game = await self.findGame(forWords: fourtilesForGame) {
                            try await MainActor.run {
                                try self.stream.write(contentsOf: encoder.encode(game))
                                try self.stream.write(contentsOf: ",\n".data(using: .ascii)!)
                            }
                            await progress?.next()
                        } else {
                            await fourtiles.push(fourtiles: fourtilesForGame)
                        }
                    }
                }
            }
        }
    }

    private func findGame(forWords fourtiles: Array<String>) async -> Game? {
        let tileSizes = fourtiles.map { Self.tileSizes[$0.count]!.shuffled() }
        guard let tiles = tilesFor(words: fourtiles, sizes: tileSizes) else { return nil }
        guard await possibleFourtiles(inTiles: tiles).count == Self.numFourtilesPerGame else { return nil }

        let otherWords = await possibleOtherWords(inTiles: tiles)
        guard otherWords.count > Self.minWordsPerGame else { return nil }
        guard otherWords.intersection(fourtiles).isEmpty else { return nil }

        return .init(tiles: tiles,
                     fourtiles: Set(fourtiles),
                     otherWords: otherWords)
    }

    private func tilesFor(words: Array<String>, sizes: Array<Array<Int>>) -> Set<String>? {
        var tiles = Set<String>()

        for (i, word) in words.enumerated() {
            var word = String(word)

            for size in sizes[i] {
                let tile = String(word.prefix(size))
                word.removeFirst(size)
                guard !tiles.contains(tile) else { return nil }
                tiles.insert(tile)
            }
        }

        return tiles
    }

    private func possibleFourtiles(inTiles tiles: Set<String>) async -> Set<String> {
        let possibleArrangements = tiles.permutations(ofCount: Self.numTilesPerFourtile).map { $0.joined() }
        return await words.words.intersection(possibleArrangements)
    }

    private func possibleOtherWords(inTiles tiles: Set<String>) async -> Set<String> {
        var otherWords = Set<String>()
        for tileCount in (Self.minTilesPerWord..<Self.numTilesPerFourtile) {
            let possibleArrangements = tiles.permutations(ofCount: tileCount).map { $0.joined() }
            await otherWords.formUnion(words.words.intersection(possibleArrangements))
        }
        return otherWords
    }

    private actor FourtileProvider {
        var fourtiles: Array<String>

        var count: Int { fourtiles.count }
        var isEmpty: Bool { fourtiles.isEmpty}

        init(fourtiles: Set<String>) {
            self.fourtiles = Array(fourtiles)
            self.fourtiles.shuffle()
        }

        func pop(count n: Int) -> Array<String>? {
            guard fourtiles.count >= n else { return nil }

            defer { fourtiles.removeFirst(n) }
            return Array(fourtiles.prefix(n))
        }

        func push(fourtiles: Array<String>) {
            self.fourtiles.append(contentsOf: fourtiles)
            self.fourtiles.shuffle()
        }
    }
}
