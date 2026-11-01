import Foundation
import Testing

func fixtureData(_ name: String, _ ext: String) throws -> Data {
    let url = try #require(Bundle.module.url(forResource: name, withExtension: ext, subdirectory: "Fixtures"))
    return try Data(contentsOf: url)
}

func fixturePlist(_ name: String) throws -> Any {
    try PropertyListSerialization.propertyList(from: fixtureData(name, "plist"), format: nil)
}
