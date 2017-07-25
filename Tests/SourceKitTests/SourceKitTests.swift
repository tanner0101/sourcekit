import XCTest
import SourceKit

class SourceKitTests: XCTestCase {
    func testExample() throws {
        let file = try Library.shared.parseFile(at: "/Users/tanner/dev/tanner0101/sourcekit/Sources/SourceKit/Test.swift")

        for c in file.classes {
            print("Class: \(c.name)")
            print(c.inheritedTypes)
            for prop in c.properties {
                print(prop.name)
                print(prop.comment?.attributes)
                print()
            }
        }
    }

    static var allTests = [
        ("testExample", testExample),
    ]
}
