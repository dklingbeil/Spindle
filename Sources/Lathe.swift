import SceneKit

/// Builds turned parts (platter, knobs, feet, lamp) by spinning a profile around the y axis,
/// which gives them the rounded edges that plain cylinders lack.
enum Lathe {
    typealias Point = (r: CGFloat, y: CGFloat)

    /// `profile` runs up the outside of the part and then in towards the axis.
    static func geometry(_ profile: [Point], segments: Int = 96) -> SCNGeometry {
        var vertices: [SCNVector3] = []
        var normals: [SCNVector3] = []
        var uvs: [CGPoint] = []
        var indices: [Int32] = []

        let total = zip(profile, profile.dropFirst()).reduce(CGFloat(0)) { $0 + hypot($1.1.r - $1.0.r, $1.1.y - $1.0.y) }
        var travelled: CGFloat = 0

        // Each band gets its own vertices so edges between bands stay crisp.
        for (a, b) in zip(profile, profile.dropFirst()) {
            let length = hypot(b.r - a.r, b.y - a.y)
            guard length > 0 else { continue }
            let normal = (r: (b.y - a.y) / length, y: -(b.r - a.r) / length)
            let base = Int32(vertices.count)
            for step in 0...segments {
                let turn = CGFloat(step) / CGFloat(segments)
                let (sine, cosine) = (sin(turn * 2 * .pi), cos(turn * 2 * .pi))
                for (point, along) in [(a, travelled), (b, travelled + length)] {
                    vertices.append(SCNVector3(point.r * cosine, point.y, point.r * sine))
                    normals.append(SCNVector3(normal.r * cosine, normal.y, normal.r * sine))
                    uvs.append(CGPoint(x: turn, y: along / total))
                }
            }
            for step in 0..<Int32(segments) {
                let a0 = base + step * 2
                indices += [a0, a0 + 1, a0 + 2, a0 + 2, a0 + 1, a0 + 3]
            }
            travelled += length
        }
        return SCNGeometry(
            sources: [SCNGeometrySource(vertices: vertices), SCNGeometrySource(normals: normals),
                      SCNGeometrySource(textureCoordinates: uvs)],
            elements: [SCNGeometryElement(indices: indices, primitiveType: .triangles)]
        )
    }

    /// The profile of a solid disc standing on `bottom`, with its top edge rounded over.
    static func disc(radius: CGFloat, bottom: CGFloat, top: CGFloat, bevel: CGFloat) -> [Point] {
        var profile: [Point] = [(radius - bevel * 0.6, bottom), (radius, bottom + bevel * 0.6)]
        for step in 0...6 {
            let angle = CGFloat(step) / 6 * .pi / 2
            profile.append((radius - bevel + bevel * cos(angle), top - bevel + bevel * sin(angle)))
        }
        profile.append((0, top))
        return profile
    }
}
