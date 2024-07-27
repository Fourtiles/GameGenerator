import Foundation
import Algorithms
import Dispatch

class GameFinder {
    static let minCharactersPerTile = 2
    static let maxCharactersPerTile = 4
    static let minTilesPerWord = 2
    static let numFourtilesPerGame = 5
    static let numTilesPerFourtile = 4
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

    let words: Words
    let stream: FileHandle

    init(words: Words, streamTo stream: FileHandle) {
        self.words = words
        self.stream = stream
    }

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
