import Foundation

struct Game: Codable {
    let tiles: Set<String>
    let fourtiles: Set<String>
    let otherWords: Set<String>
    
    var words: Set<String> {
        fourtiles.union(otherWords)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try container.encode(tiles.shuffled(), forKey: .tiles)
        try container.encode(fourtiles.sorted(), forKey: .fourtiles)
        try container.encode(otherWords.sorted(), forKey: .otherWords)
    }
}
