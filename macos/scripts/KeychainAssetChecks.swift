import Foundation
import CryptoKit
import Darwin

private struct AssetCheckFailure: Error, CustomStringConvertible {
    let description: String
}

/// Checks real, bundled artwork through the production decoder. This executable
/// never creates AppModel, a renderer, a window, or an authentication context.
@main private enum KeychainAssetChecks {
    private struct Manifest: Decodable {
        struct Palette: Decodable { let color: String }
        struct Brand: Decodable {
            struct Extraction: Decodable {
                let method: String
                let sourceOpaqueCoverage: Double
                let silhouetteBoundingBoxCoverage: Double
            }
            let charm: String
            let charmTriangles: Int
            let rgba: [Double]
            let contours: Int
            let extraction: Extraction
            let source: String
            let sourceSHA256: String
        }
        let schemaVersion: Int
        let model: String
        let baseTriangles: Int
        let palettes: [String: Palette]
        let providers: [String: Brand]
    }

    static func main() {
        do {
            guard CommandLine.arguments.count == 3 else {
                throw AssetCheckFailure(description: "Usage: keynest-keychain-asset-checks <Resources directory> <source Resources directory>")
            }
            let target = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true).standardizedFileURL
            let reference = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true).standardizedFileURL
            let compareSource = target.resolvingSymlinksInPath() != reference.resolvingSymlinksInPath()
            var assertions = 0
            func expect(_ condition: Bool, _ message: String) throws {
                assertions += 1
                guard condition else { throw AssetCheckFailure(description: message) }
            }
            let presets = ProviderPreset.all
            let providerIDs = Set(presets.map(\.id))
            try expect(!providerIDs.isEmpty && providerIDs.count == presets.count, "Provider catalog IDs must be nonempty and unique")
            try expect(providerIDs.allSatisfy(KeychainMeshAsset.isSafeName), "Provider IDs must be safe bundled asset names")
            try requireDirectory(target)
            let art = target.appendingPathComponent("KeychainArt", isDirectory: true)
            let charms = art.appendingPathComponent("charms", isDirectory: true)
            try requireDirectory(art)
            try requireDirectory(charms)
            let manifestData = try readFile(art.appendingPathComponent("manifest.json"), limit: 500_000)
            let manifest: Manifest
            do { manifest = try JSONDecoder().decode(Manifest.self, from: manifestData) }
            catch { throw AssetCheckFailure(description: "KeychainArt/manifest.json is malformed or lacks required fields") }
            try expect(manifest.schemaVersion == 1, "Manifest schema version must be supported")
            try expect(Set(manifest.providers.keys) == providerIDs, "Manifest provider IDs differ from the production catalog")
            let filenames = try FileManager.default.contentsOfDirectory(atPath: charms.path)
                .filter { $0.hasSuffix(".mesh.json") }
            try expect(Set(filenames) == Set(providerIDs.map { "\($0).mesh.json" }), "Charm filenames differ from the production catalog (missing or unexpected mesh)")
            try expect(Set(manifest.palettes.keys) == Set(KeychainCharmColor.allCases.map(\.rawValue)), "Manifest must contain the six supported generic colors")
            try expect(manifest.palettes.values.allSatisfy { isHex($0.color, count: 6) }, "Generic palette colors must be six-digit RGB values")
            try expect(manifest.model == "glass-key-v1.mesh.json", "Generic model path must match the production loader")

            func compare(_ relativePath: String, data: Data) throws {
                guard compareSource else { return }
                let source = try readFile(reference.appendingPathComponent(relativePath), limit: 12_000_000)
                try expect(SHA256.hash(data: data) == SHA256.hash(data: source), "Packaged file differs from source: \(relativePath)")
            }
            try compare("KeychainArt/manifest.json", data: manifestData)
            let genericData = try readFile(art.appendingPathComponent(manifest.model), limit: 12_000_000)
            guard let generic = KeychainMeshAsset.decode(genericData) else {
                throw AssetCheckFailure(description: "Production decoder rejected the generic glass key")
            }
            let genericTriangles = triangles(in: generic)
            try expect(genericTriangles > 0 && genericTriangles <= 11_000, "Generic key exceeds the 11,000 triangle budget")
            try expect(genericTriangles == manifest.baseTriangles, "Generic key triangle count differs from manifest")
            try expect(generic.meshes.contains { $0.role == "glass" }, "Generic key must contain its glass body")
            try compare("KeychainArt/\(manifest.model)", data: genericData)

            var highestCharmTriangles = 0
            for preset in presets {
                guard let brand = manifest.providers[preset.id] else {
                    throw AssetCheckFailure(description: "Missing manifest brand: \(preset.id)")
                }
                let charmPath = "charms/\(preset.id).mesh.json"
                try expect(brand.charm == charmPath, "Manifest charm path does not match the production loader: \(preset.id)")
                try expect(brand.rgba.count == 4 && brand.rgba.allSatisfy { $0.isFinite && (0...1).contains($0) }, "Invalid brand RGBA: \(preset.id)")
                try expect(brand.contours > 0, "Brand must have at least one extracted contour: \(preset.id)")
                try expect(!brand.extraction.method.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, "Brand silhouette extraction method is missing: \(preset.id)")
                let sourceCoverage = brand.extraction.sourceOpaqueCoverage
                let silhouetteCoverage = brand.extraction.silhouetteBoundingBoxCoverage
                try expect(sourceCoverage.isFinite && sourceCoverage > 0 && sourceCoverage <= 1, "Invalid source opacity coverage: \(preset.id)")
                try expect(silhouetteCoverage.isFinite && silhouetteCoverage > 0 && silhouetteCoverage <= 0.94, "Brand silhouette must not be an opaque rectangular plate: \(preset.id)")
                if preset.id == "cartesia" {
                    try expect(brand.extraction.method != "alpha", "Cartesia must extract the symbol from its colored background")
                }
                let data = try readFile(art.appendingPathComponent(charmPath), limit: 12_000_000)
                guard let asset = KeychainMeshAsset.decode(data) else {
                    throw AssetCheckFailure(description: "Production decoder rejected brand charm: \(preset.id)")
                }
                let triangleCount = triangles(in: asset)
                try expect(triangleCount > 0 && triangleCount < 15_000, "Brand charm exceeds the 15,000 triangle budget: \(preset.id)")
                try expect(triangleCount == brand.charmTriangles, "Charm triangle count differs from manifest: \(preset.id)")
                try expect(asset.meshes.contains { $0.role == "logo" }, "Brand charm has no brand geometry: \(preset.id)")
                highestCharmTriangles = max(highestCharmTriangles, triangleCount)
                try compare("KeychainArt/\(charmPath)", data: data)

                // An asset may only cite the bundled icon for its exact catalog ID.
                // Never resolve arbitrary relative paths from manifest contents.
                try expect(brand.source == "../ProviderIcons/\(preset.iconFilename)", "Unexpected brand icon source path: \(preset.id)")
                try expect(isHex(brand.sourceSHA256, count: 64), "Invalid source checksum: \(preset.id)")
                let iconPath = "ProviderIcons/\(preset.iconFilename)"
                let icon = try readFile(target.appendingPathComponent(iconPath), limit: 12_000_000)
                try expect(hexDigest(icon) == brand.sourceSHA256.lowercased(), "Brand mesh was generated from a different icon: \(preset.id)")
                try compare(iconPath, data: icon)
            }
            print("PASS Keychain assets: \(providerIDs.count) brand charms + generic key; \(assertions) assertions; generic \(genericTriangles) triangles, largest charm \(highestCharmTriangles).")
            print(compareSource ? "Packaged artwork and provider icons match source SHA-256; no renderer, window, network or vault access." : "Source artwork checked with the production decoder; no renderer, window, network or vault access.")
        } catch let error as AssetCheckFailure {
            fputs("FAIL Keychain assets: \(error.description)\n", stderr)
            exit(1)
        } catch {
            fputs("FAIL Keychain assets: resource inspection failed (\(error.localizedDescription))\n", stderr)
            exit(1)
        }
    }

    private static func requireDirectory(_ url: URL) throws {
        let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard values.isDirectory == true, values.isSymbolicLink != true else {
            throw AssetCheckFailure(description: "Resource directory is absent, invalid or a symbolic link: \(url.lastPathComponent)")
        }
    }

    private static func readFile(_ url: URL, limit: Int) throws -> Data {
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true,
              let size = values.fileSize, (1...limit).contains(size) else {
            throw AssetCheckFailure(description: "Resource must be a bounded regular file: \(url.lastPathComponent)")
        }
        let data = try Data(contentsOf: url)
        guard data.count == size else { throw AssetCheckFailure(description: "Resource changed during verification: \(url.lastPathComponent)") }
        return data
    }

    private static func triangles(in asset: KeychainMeshAsset) -> Int {
        asset.meshes.reduce(0) { $0 + $1.indices.count / 3 }
    }

    private static func isHex(_ text: String, count: Int) -> Bool {
        text.utf8.count == count && text.utf8.allSatisfy {
            (48...57).contains($0) || (65...70).contains($0) || (97...102).contains($0)
        }
    }

    private static func hexDigest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
