import Foundation

/// Original bundled Blender meshes, never paths provided by a vault or user.
/// Validation also makes a damaged app resource fail closed to the native fallback.
struct KeychainMeshAsset: Decodable {
    struct Mesh: Decodable {
        let name: String
        let role: String
        let positions: [Float]
        let normals: [Float]
        let indices: [UInt32]
    }
    let schemaVersion: Int
    let meshes: [Mesh]

    static func decode(_ data: Data) -> KeychainMeshAsset? {
        guard data.count <= 12_000_000,
              let asset = try? JSONDecoder().decode(Self.self, from: data),
              asset.schemaVersion == 1, (1...32).contains(asset.meshes.count) else { return nil }
        var triangles = 0
        for mesh in asset.meshes {
            guard ["glass", "metal", "logo"].contains(mesh.role),
                  !mesh.positions.isEmpty, mesh.positions.count <= 180_000,
                  mesh.positions.count.isMultiple(of: 3), mesh.normals.count == mesh.positions.count,
                  mesh.positions.allSatisfy({ $0.isFinite && abs($0) <= 10 }),
                  mesh.normals.allSatisfy({ $0.isFinite && abs($0) <= 1.01 }),
                  !mesh.indices.isEmpty, mesh.indices.count.isMultiple(of: 3),
                  mesh.indices.allSatisfy({ Int($0) < mesh.positions.count / 3 }) else { return nil }
            triangles += mesh.indices.count / 3
        }
        guard triangles <= 30_000 else { return nil }
        return asset
    }

    static func isSafeName(_ name: String) -> Bool {
        !name.isEmpty && name.utf8.count < 60 && name.utf8.allSatisfy {
            (97...122).contains($0) || (48...57).contains($0) || $0 == 45
        }
    }

    private struct Manifest: Decodable {
        struct Brand: Decodable { let rgba: [Double] }
        let providers: [String: Brand]
    }
    @MainActor private static let brandColors: [String: [Double]] = {
        guard let url = Bundle.main.resourceURL?.appendingPathComponent("KeychainArt/manifest.json"),
              let data = try? Data(contentsOf: url), data.count <= 500_000,
              let manifest = try? JSONDecoder().decode(Manifest.self, from: data) else { return [:] }
        return manifest.providers.compactMapValues { brand in
            guard brand.rgba.count == 4, brand.rgba.allSatisfy({ $0.isFinite && (0...1).contains($0) }) else { return nil }
            return brand.rgba
        }
    }()
    @MainActor static func brandColor(_ name: String?) -> [Double]? {
        guard let name, isSafeName(name) else { return nil }
        return brandColors[name]
    }

    @MainActor private static var cache: [String: KeychainMeshAsset] = [:]
    @MainActor private static var missing: Set<String> = []

    @MainActor static func bundled(named name: String, brandCharm: Bool = false) -> KeychainMeshAsset? {
        guard isSafeName(name) else { return nil }
        let key = (brandCharm ? "charms/" : "") + name
        if let cached = cache[key] { return cached }
        if missing.contains(key) { return nil }
        guard let resourceRoot = Bundle.main.resourceURL,
              let data = try? Data(contentsOf: resourceRoot.appendingPathComponent("KeychainArt")
                .appendingPathComponent(key + ".mesh.json")),
              let asset = decode(data) else {
            missing.insert(key)
            return nil
        }
        cache[key] = asset
        return asset
    }
}
