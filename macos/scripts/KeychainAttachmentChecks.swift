import Foundation
import Darwin

private struct AttachmentCheckFailure: Error, CustomStringConvertible {
    let description: String
}

/// Independent ray/solid checks on the actual bundled triangle meshes. No
/// renderer, window, Core vault model, network or authentication is created.
@main @MainActor private enum KeychainAttachmentChecks {
    static var assertions = 0

    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        assertions += 1
        guard condition() else { throw AttachmentCheckFailure(description: message) }
    }

    static func main() {
        do {
            guard CommandLine.arguments.count == 2 else {
                throw AttachmentCheckFailure(description: "Expected the project's Resources directory")
            }
            let directory = URL(fileURLWithPath: CommandLine.arguments[1]).appendingPathComponent("KeychainArt/charms")
            let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
                .filter { $0.lastPathComponent.hasSuffix(".mesh.json") }.sorted { $0.lastPathComponent < $1.lastPathComponent }
            try expect(files.count == 61, "Exercise every one of the 61 current brand assets")
            var referenceRing: KeychainMeshAsset.Mesh?
            for file in files {
                guard let asset = KeychainMeshAsset.decode(try Data(contentsOf: file)),
                      let attachment = asset.brandAttachment() else {
                    throw AttachmentCheckFailure(description: "No safe attachment for \(file.lastPathComponent)")
                }
                let body = asset.meshes.filter { $0.role == "logo" }
                let rings = asset.meshes.filter { $0.name.hasSuffix("-suspension-ring") }
                try expect(isInside(attachment.bodyPoint, meshes: body), "Body endpoint must penetrate actual enamel: \(file.lastPathComponent)")
                try expect(isInside(attachment.ringPoint, meshes: rings), "Ring endpoint must penetrate actual metal: \(file.lastPathComponent)")
                try expect(attachment.radius > 0 && attachment.radius < 0.05, "Connector stays slender")
                let delta = attachment.ringPoint - attachment.bodyPoint
                try expect((0..<3).allSatisfy { delta[$0].isFinite } && delta.y > 0, "Finite connector reaches upward into its ring")
                try expect(asset.brandAttachment()?.bodyPoint == attachment.bodyPoint, "Attachment selection is deterministic")
                if file.lastPathComponent == "anthropic.mesh.json" {
                    referenceRing = rings.first
                    try expect(abs(attachment.bodyPoint.x) > 0.035, "Claude must attach to a real off-center ray, not its empty top-center")
                    let top = body.flatMap { mesh in stride(from: 1, to: mesh.positions.count, by: 3).map { index in Double(mesh.positions[index]) } }.max()!
                    try expect(!isInside(SIMD3(0, top - 0.002, 0), meshes: body), "Claude regression fixture really has no solid at the bounding-box top-center")
                    print(String(format: "Claude body attachment: (%.5f, %.5f, %.5f); ring: (%.5f, %.5f, %.5f)",
                                 attachment.bodyPoint.x, attachment.bodyPoint.y, attachment.bodyPoint.z,
                                 attachment.ringPoint.x, attachment.ringPoint.y, attachment.ringPoint.z))
                }
            }
            guard let referenceRing else { throw AttachmentCheckFailure(description: "Missing Claude fixture") }
            try syntheticBoundaries(ring: referenceRing)
            print("PASS: \(assertions) attachment assertions across \(files.count) real brands and synthetic hollow/eccentric/invalid geometry; no rendering or vault access.")
        } catch {
            fputs("FAIL attachment geometry: \(error)\n", stderr)
            exit(1)
        }
    }

    /// +Z/-Z ray intersections are calculated independently of the production
    /// nearest-triangle algorithm. Odd crossings on each side prove the endpoint
    /// is in solid volume, rather than in a hole or just tangent to a boundary.
    private static func isInside(_ point: SIMD3<Double>, meshes: [KeychainMeshAsset.Mesh]) -> Bool {
        var hits: [Double] = []
        for mesh in meshes {
            for offset in stride(from: 0, to: mesh.indices.count, by: 3) {
                let vertices = (0..<3).map { n -> SIMD3<Double> in
                    let i = Int(mesh.indices[offset + n]) * 3
                    return SIMD3(Double(mesh.positions[i]), Double(mesh.positions[i + 1]), Double(mesh.positions[i + 2]))
                }
                let a = vertices[0], b = vertices[1], c = vertices[2]
                let denominator = (b.y - c.y) * (a.x - c.x) + (c.x - b.x) * (a.y - c.y)
                if abs(denominator) < 1e-12 { continue }
                let u = ((b.y - c.y) * (point.x - c.x) + (c.x - b.x) * (point.y - c.y)) / denominator
                let v = ((c.y - a.y) * (point.x - c.x) + (a.x - c.x) * (point.y - c.y)) / denominator
                if min(u, v, 1 - u - v) >= -1e-8 { hits.append(u * a.z + v * b.z + (1 - u - v) * c.z) }
            }
        }
        var unique: [Double] = []
        for value in hits.sorted() where unique.last.map({ abs(value - $0) > 1e-6 }) ?? true { unique.append(value) }
        let above = unique.filter { $0 > point.z + 1e-5 }.count
        let below = unique.filter { $0 < point.z - 1e-5 }.count
        return above % 2 == 1 && below % 2 == 1
    }

    private static func syntheticBoundaries(ring: KeychainMeshAsset.Mesh) throws {
        let left = box(x: -0.6 ... -0.25, y: 0.2 ... 0.8)
        let right = box(x: 0.25 ... 0.6, y: 0.2 ... 0.8)
        let hollow = KeychainMeshAsset(schemaVersion: 1, meshes: [left, right, ring])
        let hollowPoint = try require(hollow.brandAttachment()).bodyPoint
        try expect(abs(hollowPoint.x) > 0.25, "Hollow top-center must not be selected")
        try expect(isInside(hollowPoint, meshes: [left, right]), "Hollow fixture endpoint is inside a real arm")

        let lowRight = box(x: 0.25 ... 0.6, y: 0.0 ... 0.3)
        let eccentric = KeychainMeshAsset(schemaVersion: 1, meshes: [left, lowRight, ring])
        let eccentricPoint = try require(eccentric.brandAttachment()).bodyPoint
        try expect(eccentricPoint.x < -0.25 && eccentricPoint.y < 0.8, "Offset highest ray is selected with real inward overlap")
        try expect(isInside(eccentricPoint, meshes: [left, lowRight]), "Eccentric fixture endpoint is solid")

        try expect(KeychainMeshAsset(schemaVersion: 1, meshes: [ring]).brandAttachment() == nil, "Missing enamel fails safely")
        try expect(KeychainMeshAsset(schemaVersion: 1, meshes: [left]).brandAttachment() == nil, "Missing ring fails safely")
        let invalid = KeychainMeshAsset.Mesh(name: "bad", role: "logo", positions: [.nan, 0, 0], normals: [0, 0, 1], indices: [0, 0, 0])
        try expect(KeychainMeshAsset(schemaVersion: 1, meshes: [invalid, ring]).brandAttachment() == nil, "Nonfinite geometry is rejected")
        let flat = KeychainMeshAsset.Mesh(name: "flat", role: "logo", positions: [0, 0, 0.1, 0, 1, 0.1, 0, 2, 0.1], normals: Array(repeating: 0, count: 9), indices: [0, 1, 2])
        try expect(KeychainMeshAsset(schemaVersion: 1, meshes: [flat, ring]).brandAttachment() == nil, "Zero-thickness/degenerate geometry is rejected")
        let outOfBounds = KeychainMeshAsset.Mesh(name: "bad index", role: "logo", positions: left.positions, normals: left.normals, indices: [0, 1, 900])
        try expect(KeychainMeshAsset(schemaVersion: 1, meshes: [outOfBounds, ring]).brandAttachment() == nil, "Bad indices cannot be dereferenced")
    }

    private static func require(_ value: KeychainMeshAsset.Attachment?) throws -> KeychainMeshAsset.Attachment {
        guard let value else { throw AttachmentCheckFailure(description: "Synthetic fixture has no attachment") }
        return value
    }

    private static func box(x: ClosedRange<Float>, y: ClosedRange<Float>) -> KeychainMeshAsset.Mesh {
        let points: [Float] = [x.lowerBound,y.lowerBound,-0.11, x.upperBound,y.lowerBound,-0.11,
                              x.upperBound,y.upperBound,-0.11, x.lowerBound,y.upperBound,-0.11,
                              x.lowerBound,y.lowerBound,0.11, x.upperBound,y.lowerBound,0.11,
                              x.upperBound,y.upperBound,0.11, x.lowerBound,y.upperBound,0.11]
        return .init(name: "fixture", role: "logo", positions: points, normals: Array(repeating: 0, count: points.count),
                     indices: [0,2,1, 0,3,2, 4,5,6, 4,6,7, 0,1,5, 0,5,4, 1,2,6, 1,6,5, 2,3,7, 2,7,6, 3,0,4, 3,4,7])
    }
}
