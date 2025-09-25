import Foundation

/// Represents a valid game board.
struct Game: Codable {

  /// The set of tiles (word fragments) on the board.
  let tiles: Set<String>

  /// The set of fourtiles that were split to generate the tiles.
  let fourtiles: Set<String>

  /// All other words that can be formed by combinations of the tiles.
  let otherWords: Set<String>

  /// The ``fourtiles`` and ``otherWords`` combined.
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
