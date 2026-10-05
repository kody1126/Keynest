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

    struct Attachment: Sendable {
        /// Coordinates remain in the baked model space (anchor is still y=1).
        let bodyPoint: SIMD3<Double>
        let ringPoint: SIMD3<Double>
        let radius: Double
    }

    /// Find real enamel under the connector, including eccentric tips and
    /// hollow logos. A bounding-box top/center can be empty space. Choosing an
    /// interior point of an actual front-cap triangle avoids that assumption.
    func brandAttachment() -> Attachment? {
        guard let ring = meshes.first(where: { $0.role == "metal" && $0.name.hasSuffix("-suspension-ring") }),
              let ringBounds = Self.bounds(of: ring) else { return nil }
        let ringCenter = (ringBounds.low + ringBounds.high) / 2
        // The authored ring lies in XY. Its Z half-thickness is its tube
        // radius; the lower tube center is solid metal, unlike the ring hole.
        let tubeRadius = (ringBounds.high.z - ringBounds.low.z) / 2
        guard tubeRadius > 0.000_1, tubeRadius < 0.1 else { return nil }
        let ringPoint = SIMD3(ringCenter.x, ringBounds.low.y + tubeRadius, ringCenter.z)
        let target = SIMD2(ringPoint.x, ringPoint.y)
        var best: (point: SIMD3<Double>, distance: Double)?
        for mesh in meshes where mesh.role == "logo" {
            guard let bounds = Self.bounds(of: mesh), bounds.high.z - bounds.low.z > 0.001,
                  mesh.indices.count.isMultiple(of: 3) else { continue }
            let frontZ = bounds.high.z
            for offset in stride(from: 0, to: mesh.indices.count, by: 3) {
                let indices = (0..<3).map { Int(mesh.indices[offset + $0]) }
                guard indices.allSatisfy({ $0 < mesh.positions.count / 3 }) else { return nil }
                let points = indices.map { index in
                    SIMD3(Double(mesh.positions[index * 3]), Double(mesh.positions[index * 3 + 1]),
                          Double(mesh.positions[index * 3 + 2]))
                }
                // Exclude side/bevel triangles. An interior point of this
                // planar cap also lies inside the extruded solid at mid-depth.
                guard points.allSatisfy({ abs($0.z - frontZ) < 0.000_01 }) else { continue }
                let a = SIMD2(points[0].x, points[0].y), b = SIMD2(points[1].x, points[1].y)
                let c = SIMD2(points[2].x, points[2].y)
                guard abs(Self.cross(b - a, c - a)) > 0.000_000_01 else { continue }
                let nearest = Self.closestPoint(target, in: (a, b, c))
                let ab = Self.length(b - a), bc = Self.length(c - b), ca = Self.length(a - c)
                let inside = (a * bc + b * ca + c * ab) / (ab + bc + ca)
                let delta = inside - nearest
                let distanceInside = Self.length(delta)
                // Penetrate the body instead of merely touching a sharp tip.
                // An incenter works even for slender triangular logo strokes.
                let amount = distanceInside > 0 ? min(0.85, 0.018 / distanceInside) : 0
                let point = nearest + delta * amount
                let distance = Self.squaredLength(point - target)
                if best == nil || distance < best!.distance {
                    best = (SIMD3(point.x, point.y, (bounds.low.z + bounds.high.z) / 2), distance)
                }
            }
        }
        guard let best, best.distance.isFinite, best.distance > 0.000_001 else { return nil }
        return Attachment(bodyPoint: best.point, ringPoint: ringPoint, radius: 0.024)
    }

    private static func bounds(of mesh: Mesh) -> (low: SIMD3<Double>, high: SIMD3<Double>)? {
        guard !mesh.positions.isEmpty, mesh.positions.count.isMultiple(of: 3),
              mesh.positions.allSatisfy({ $0.isFinite && abs($0) <= 10 }) else { return nil }
        var low = SIMD3<Double>(repeating: .infinity), high = SIMD3<Double>(repeating: -.infinity)
        for offset in stride(from: 0, to: mesh.positions.count, by: 3) {
            for axis in 0..<3 {
                let value = Double(mesh.positions[offset + axis])
                low[axis] = min(low[axis], value); high[axis] = max(high[axis], value)
            }
        }
        return (low, high)
    }

    private static func closestPoint(_ point: SIMD2<Double>, in triangle: (SIMD2<Double>, SIMD2<Double>, SIMD2<Double>)) -> SIMD2<Double> {
        let (a, b, c) = triangle
        let area = cross(b - a, c - a)
        let u = cross(b - point, c - point) / area
        let v = cross(c - point, a - point) / area
        if u >= 0, v >= 0, u + v <= 1 { return point }
        func onSegment(_ start: SIMD2<Double>, _ end: SIMD2<Double>) -> SIMD2<Double> {
            let delta = end - start, denominator = squaredLength(delta)
            guard denominator > 0 else { return start }
            let t = min(1, max(0, ((point - start).x * delta.x + (point - start).y * delta.y) / denominator))
            return start + delta * t
        }
        return [onSegment(a, b), onSegment(b, c), onSegment(c, a)].min {
            squaredLength($0 - point) < squaredLength($1 - point)
        }!
    }

    private static func cross(_ a: SIMD2<Double>, _ b: SIMD2<Double>) -> Double { a.x * b.y - a.y * b.x }
    private static func squaredLength(_ value: SIMD2<Double>) -> Double { value.x * value.x + value.y * value.y }
    private static func length(_ value: SIMD2<Double>) -> Double { sqrt(squaredLength(value)) }

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
