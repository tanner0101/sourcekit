import CSourceKit
import Foundation
import Bits

public final class Library {
    public static var shared = Library()

    let sourcekitd: DynamicLinkLibrary

    init() {
        sourcekitd = toolchainLoader.loadSourcekitd()
        sourcekitd_initialize()
    }

    public func parseFile(at path: String) throws -> File {
        let url = URL(fileURLWithPath: path)
        let data = try Data(contentsOf: url)
        let bytes = data.makeBytes()
        return try File(bytes)
    }

    public func parseFile(_ bytes: Bytes) throws -> File {
        return try File(bytes)
    }
}

extension String: Error {}
