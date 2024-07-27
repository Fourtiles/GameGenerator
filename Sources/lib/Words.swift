import Foundation

actor Words {
    var words = Set<String>()
    
    func load(from fileURL: URL) throws {
        let fileContents = try String(contentsOf: fileURL, encoding: .utf8)
        
        // Split the file into words and add to the set
        let words = fileContents.components(separatedBy: .newlines).filter { !$0.isEmpty }
        self.words.formUnion(words)
    }
}
