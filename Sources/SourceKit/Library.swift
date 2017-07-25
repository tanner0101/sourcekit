import CSourceKit
import Foundation

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
        return try File(data)
    }
}

struct Syntax {
    var kind: String
    var offset: Int
    var length: Int
}

struct SyntaxMap {
    let items: [Syntax]
    let data: Data

    init(_ data: Data, _ items: [Syntax]) {
        self.data = data
        self.items = items
    }
}

extension SyntaxMap {
    func comment(beforeOffset: Int) -> Comment? {
        guard let index = items.index(where: { syntax in
            return syntax.offset == beforeOffset
        }) else {
            return nil
        }

        var lines: [String] = []

        for i in (0..<index).reversed() {
            let test = items[i]
            if test.kind.hasSuffix("comment") {
                let chunk = Data(data[test.offset..<(test.offset + test.length)])
                var line = String(data: chunk, encoding: .utf8) ?? ""
                if line.hasPrefix("///") {
                    line = String(line.characters.dropFirst(3))
                } else if line.hasPrefix("//") {
                    line = String(line.characters.dropFirst(2))
                } else if line.hasPrefix("/*") {
                    line = String(line.characters.dropFirst(2))
                } else if line.hasPrefix("*/") {
                    line = String(line.characters.dropLast(2))
                }
                if line.hasSuffix("\n") {
                    line = String(line.characters.dropLast())
                }
                lines.append(line)
            } else {
                break
            }
        }

        if lines.count == 0 {
            return nil
        }

        return Comment(lines: lines)
    }
}

extension String: Error {}

public struct File {
    let syntaxMap: SyntaxMap
    let declarations: [Declaration]

    init(_ contents: Data) throws {
        guard let string = String(data: contents, encoding: .utf8) else {
            throw "Could not create string from contents"
        }

        let dict: [sourcekitd_uid_t: sourcekitd_object_t?] = [
            sourcekitd_uid_get_from_cstr("key.request"): sourcekitd_request_uid_create(sourcekitd_uid_get_from_cstr("source.request.editor.open")),
            sourcekitd_uid_get_from_cstr("key.name"): sourcekitd_request_string_create(String(string.hash)),
            sourcekitd_uid_get_from_cstr("key.sourcetext"): sourcekitd_request_string_create(string),
        ]

        var keys = Array(dict.keys.map({ $0 as sourcekitd_uid_t? }))
        var values = Array(dict.values)
        let req = sourcekitd_request_dictionary_create(&keys, &values, dict.count)

        let response = sourcekitd_send_request_sync(req!)
        defer {
            sourcekitd_response_dispose(response!)
        }

        let value = sourcekitd_response_get_value(response!)
        let variant = Variant(value)!

        print(variant.formatted())

        let syntax = variant.parseSyntaxMap() ?? []
        let syntaxMap = SyntaxMap(contents, syntax)
        declarations = variant.parseSubDeclarations(syntaxMap) ?? []
        self.syntaxMap = syntaxMap
    }
}

extension File {
    public var classes: [Entity] {
        return declarations.flatMap { decl in
            return decl.class
        }
    }

    public var entities: [Entity] {
        return declarations.flatMap { decl in
            return decl.entity
        }
    }

    public var structs: [Entity] {
        return declarations.flatMap { decl in
            return decl.struct
        }
    }
}

enum Swift {
    case declarations([Declaration])
}

public struct Entity {
    public var name: String
    var declarations: [Declaration]
    public var inheritedTypes: [String]

    init(
        name: String,
        _ declarations: [Declaration],
        inheritedTypes: [String]
    ) {
        self.name = name
        self.declarations = declarations
        self.inheritedTypes = inheritedTypes
    }

    public var properties: [Instance] {
        return declarations.flatMap { decl in
            return decl.instance
        }
    }
}

public struct Instance {
    public var name: String
    public var typeName: String
    public var comment: Comment?

    init(name: String, typeName: String, comment: Comment?) {
        self.name = name
        self.typeName = typeName
        self.comment = comment
    }
}

public struct Comment {
    public var lines: [String]

    public var attributes: [String: [String]] {
        var attributes: [String: [String]] = [:]

        for line in lines {
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("- ") {
                let content = line.characters.dropFirst(2)

                let array = content.split(separator: ":", maxSplits: 1)
                guard array.count == 2 else {
                    continue
                }

                let key = String(array[0]).trimmingCharacters(in: .whitespaces)
                let values = array[1].split(
                    separator: " ",
                    omittingEmptySubsequences: true
                ).map(String.init)

                attributes[key] = values
            }
        }

        return attributes
    }
}

enum Declaration {
    case `class`(Entity)
    case `struct`(Entity)
    case instance(Instance)
}

extension Declaration {
    public var `class`: Entity? {
        switch self {
        case .`class`(let c):
            return c
        default:
            return nil
        }
    }

    public var `struct`: Entity? {
        switch self {
        case .`struct`(let s):
            return s
        default:
            return nil
        }
    }

    public var entity: Entity? {
        switch self {
        case .`struct`(let s):
            return s
        case .`class`(let c):
            return c
        default:
            return nil
        }
    }

    public var instance: Instance? {
        switch self {
        case .instance(let i):
            return i
        default:
            return nil
        }
    }
}

enum Variant {
    case array([Variant])
    case dictionary([String: Variant])
    case string(String)
    case integer(Int)
    case bool(Bool)

    init?(_ raw: sourcekitd_variant_t) {
        let type = sourcekitd_variant_get_type(raw)
        let variant: Variant

        switch type {
        case SOURCEKITD_VARIANT_TYPE_ARRAY:
            var array: [Variant] = []
            _ = withUnsafeMutablePointer(to: &array) { arrayPtr in
                sourcekitd_variant_array_apply_f(raw, { index, value, context in
                    if let value = Variant(value), let context = context {
                        let localArray = context.assumingMemoryBound(to: [Variant].self)
                        localArray.pointee.insert(value, at: Int(index))
                    }
                    return true
                }, arrayPtr)
            }
            variant = .array(array)
        case SOURCEKITD_VARIANT_TYPE_DICTIONARY:
            var dict: [String: Variant] = [:]
            _ = withUnsafeMutablePointer(to: &dict) { dictPtr in
                sourcekitd_variant_dictionary_apply_f(raw, { key, value, context in

                    if
                        let key = String(sourceKitUID: key!),
                        let value = Variant(value),
                        let context = context
                    {
                        let localDict = context.assumingMemoryBound(to: [String: Variant].self)
                        localDict.pointee[key] = value
                    }
                    return true
                }, dictPtr)
            }
            variant = .dictionary(dict)
        case SOURCEKITD_VARIANT_TYPE_STRING:
            let string = String(
                bytes: sourcekitd_variant_string_get_ptr(raw),
                length: sourcekitd_variant_string_get_length(raw)
            )
            variant = .string(string!)
        case SOURCEKITD_VARIANT_TYPE_INT64:
            variant = .integer(Int(sourcekitd_variant_int64_get_value(raw)))
        case SOURCEKITD_VARIANT_TYPE_BOOL:
            variant = .bool(sourcekitd_variant_bool_get_value(raw))
        case SOURCEKITD_VARIANT_TYPE_UID:
            variant = .string(String(sourceKitUID: sourcekitd_variant_uid_get_value(raw))!)
        default:
            return nil
        }

        self = variant
    }

    var dictionary: [String: Variant]? {
        switch self {
        case .dictionary(let dict):
            return dict
        default:
            return nil
        }
    }

    var array: [Variant]? {
        switch self {
        case .array(let array):
            return array
        default:
            return nil
        }
    }

    var string: String? {
        switch self {
        case .string(let string):
            return string
        default:
            return nil
        }
    }

    var integer: Int? {
        switch self {
        case .integer(let int):
            return int
        default:
            return nil
        }
    }

    func parseSyntaxMap() -> [Syntax]? {
        guard let mapped = dictionary?["key.syntaxmap"]?.array?.flatMap({ variant in
            return variant.parseSyntax()
        }) else {
            return nil
        }

        return mapped
    }

    func parseSyntax() -> Syntax? {
        guard let dict = dictionary else {
            return nil
        }

        guard let kind = dict["key.kind"]?.string else {
            return nil
        }

        guard let offset = dict["key.offset"]?.integer else {
            return nil
        }

        guard let length = dict["key.length"]?.integer else {
            return nil
        }

        return Syntax(kind: kind, offset: offset, length: length)
    }

    func parseSubDeclarations(_ syntaxMap: SyntaxMap) -> [Declaration]? {
        guard let mapped = dictionary?["key.substructure"]?.array?.flatMap({ variant in
            return variant.parseDeclaration(syntaxMap)
        }) else {
            return nil
        }
        return mapped
    }

    func parseDeclaration(_ syntaxMap: SyntaxMap) -> Declaration? {
        guard let dict = dictionary else {
            return nil
        }

        guard let kind = dict["key.kind"]?.string else {
            return nil
        }

        let decl: Declaration

        switch kind {
        case "source.lang.swift.decl.struct", "source.lang.swift.decl.class":
            guard let name = dict["key.name"]?.string else {
                return nil
            }

            let sub = parseSubDeclarations(syntaxMap) ?? []

            let inheritedTypes = dict["key.inheritedtypes"]?.array?.flatMap({ variant in
                variant.dictionary?["key.name"]?.string
            }) ?? []

            let e = Entity(name: name, sub, inheritedTypes: inheritedTypes)
            if kind.hasSuffix("struct") {
                decl = .struct(e)
            } else {
                decl = .class(e)
            }
        case "source.lang.swift.decl.var.instance":
            guard let name = dict["key.name"]?.string else {
                return nil
            }

            guard let typeName = dict["key.typename"]?.string else {
                return nil
            }

            guard let offset = dict["key.offset"]?.integer else {
                return nil
            }

            let comment = syntaxMap.comment(beforeOffset: offset)

            let instance = Instance(
                name: name,
                typeName: typeName,
                comment: comment
            )
            decl = .instance(instance)
        default:
            print("Unsupported kind: \(kind)")
            return nil
        }

        return decl
    }

    func formatted(level: Int = 0) -> String {
        let indent = String(repeating: "    ", count: level)
        switch self {
        case .array(let array):
            return array.map({ v in
                return "\n" + indent + v.formatted(level: level + 1)
            }).joined(separator: "") + "\n"
        case .dictionary(let dict):
            var string = ""

            for (key, val) in dict {
                string += "\n" + indent + key + ": " + val.formatted(level: level + 1)
            }

            return string
        case .integer(let int):
            return int.description
        case .string(let string):
            return string
        case .bool(let bool):
            return bool ? "true" : "false"
        }
    }
}

extension String {
    /**
     Cache SourceKit requests for strings from UIDs
     - returns: Cached UID string if available, nil otherwise.
     */
    init?(sourceKitUID: sourcekitd_uid_t) {
        let length = sourcekitd_uid_get_length(sourceKitUID)
        let bytes = sourcekitd_uid_get_string_ptr(sourceKitUID)
        if let uidString = String(bytes: bytes!, length: length) {
            /*
             `String` created by `String(UTF8String:)` is based on `NSString`.
             `NSString` base `String` has performance penalty on getting `hashValue`.
             Everytime on getting `hashValue`, it calls `decomposedStringWithCanonicalMapping` for
             "Unicode Normalization Form D" and creates autoreleased `CFString (mutable)` and
             `CFString (store)`. Those `CFString` are created every time on using `hashValue`, such as
             using `String` for Dictionary's key or adding to Set.
             For avoiding those penalty, replaces with enum's rawValue String if defined in SourceKitten.
             That does not cause calling `decomposedStringWithCanonicalMapping`.
             */

            self = uidString
            return
        }
        return nil
    }

    init?(bytes: UnsafePointer<Int8>, length: Int) {
        let pointer = UnsafeMutablePointer<Int8>(mutating: bytes)
        // It seems SourceKitService returns string in other than NSUTF8StringEncoding.
        // We'll try another encodings if fail.
        for encoding in [String.Encoding.utf8, .nextstep, .ascii] {
            if let string = String(bytesNoCopy: pointer, length: length, encoding: encoding,
                                   freeWhenDone: false) {
                self = "\(string)"
                return
            }
        }
        return nil
    }
}
