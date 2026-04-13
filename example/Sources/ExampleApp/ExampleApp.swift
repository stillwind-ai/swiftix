import ArgumentParser
import Algorithms
import Logging

@main
struct ExampleApp: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "A demo CLI built with swiftix and Apple's Swift packages."
    )

    @Option(name: .shortAndLong, help: "Number of items to generate.")
    var count: Int = 10

    @Flag(name: .shortAndLong, help: "Show unique pairs of items.")
    var pairs: Bool = false

    mutating func run() throws {
        var logger = Logger(label: "com.example.swiftix")
        logger.logLevel = .info

        let items = Array(1...count)
        logger.info("Generated \(items.count) items")

        if pairs {
            let combos = items.combinations(ofCount: 2)
            for combo in combos.prefix(20) {
                print("(\(combo[0]), \(combo[1]))")
            }
            logger.info("Showed \(min(20, combos.count)) of \(combos.count) pairs")
        } else {
            let chunks = items.chunks(ofCount: 3)
            for chunk in chunks {
                print(chunk.map(String.init).joined(separator: ", "))
            }
            logger.info("Displayed \(chunks.count) chunks of 3")
        }
    }
}
