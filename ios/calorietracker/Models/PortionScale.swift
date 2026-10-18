import CoreGraphics
import Foundation
import simd
import UIKit

/// Real-world scale for a food photo, measured with the AR camera from the table
/// the food sits on (#601). The AI gets the table area the photo covers, so it can
/// size plates, bowls and portions from real dimensions instead of guessing.
nonisolated struct PortionScale: Equatable, Sendable {
    /// Camera height above the table plane.
    let cameraHeightCm: Double
    /// Angle between the camera's view direction and straight down.
    let tiltDegrees: Double
    /// Table area the whole upright photo covers around its centre.
    let photoWidthCm: Double
    let photoHeightCm: Double

    static let maxTiltDegrees: Double = 30
    static let minHeightCm: Double = 10
    static let maxHeightCm: Double = 100

    enum Readiness: Equatable, Sendable {
        case tooClose
        case tooFar
        case tooTilted
        case ready
    }

    /// Only a near-overhead photo has an even scale across the frame, so steeper
    /// angles and out-of-range heights are not sent to the AI.
    var readiness: Readiness {
        if cameraHeightCm < Self.minHeightCm { return .tooClose }
        if cameraHeightCm > Self.maxHeightCm { return .tooFar }
        if tiltDegrees > Self.maxTiltDegrees { return .tooTilted }
        return .ready
    }

    /// - Parameters:
    ///   - cameraTransform: `ARCamera.transform`; the camera looks down its -Z axis.
    ///   - planePoint: where the ray through the image centre meets the table.
    ///   - planeNormal: the table's up direction.
    ///   - intrinsics: `ARCamera.intrinsics`, in pixels of `imageResolution`.
    ///   - imageResolution: the landscape sensor image the intrinsics describe.
    static func measure(
        cameraTransform: simd_float4x4,
        planePoint: SIMD3<Float>,
        planeNormal: SIMD3<Float>,
        intrinsics: simd_float3x3,
        imageResolution: CGSize
    ) -> PortionScale? {
        let camera = SIMD3<Float>(cameraTransform.columns.3.x, cameraTransform.columns.3.y, cameraTransform.columns.3.z)
        let back = SIMD3<Float>(cameraTransform.columns.2.x, cameraTransform.columns.2.y, cameraTransform.columns.2.z)
        guard simd_length(back) > 0, simd_length(planeNormal) > 0 else { return nil }
        let forward = -simd_normalize(back)
        let up = simd_normalize(planeNormal)

        let height = Double(simd_dot(camera - planePoint, up))
        let distance = Double(simd_length(camera - planePoint))
        let fx = Double(intrinsics.columns.0.x)
        let fy = Double(intrinsics.columns.1.y)
        guard height > 0, distance > 0, fx > 0, fy > 0,
              imageResolution.width > 0, imageResolution.height > 0 else { return nil }

        let cosine = min(1, max(-1, Double(simd_dot(forward, -up))))
        let tilt = acos(cosine) * 180 / .pi
        // Pinhole size at the centre depth. The sensor image is landscape, so the
        // upright portrait photo swaps its width and height.
        let sensorWidthCm = Double(imageResolution.width) / fx * distance * 100
        let sensorHeightCm = Double(imageResolution.height) / fy * distance * 100
        return PortionScale(
            cameraHeightCm: height * 100,
            tiltDegrees: tilt,
            photoWidthCm: sensorHeightCm,
            photoHeightCm: sensorWidthCm
        )
    }

    /// AI-facing English, like the rest of the analysis prompt. Photos without a
    /// usable measurement are skipped; nil when none has one.
    static func promptSection(for scales: [PortionScale?]) -> String? {
        let lines = scales.enumerated().compactMap { index, scale -> String? in
            guard let scale, scale.readiness == .ready else { return nil }
            let angle = scale.tiltDegrees < 10 ? "straight down" : "nearly straight down"
            return "- Photo \(index + 1): taken from about \(Self.wholeCm(scale.cameraHeightCm)) cm above the table, looking \(angle). "
                + "The whole photo covers about \(Self.wholeCm(scale.photoWidthCm)) × \(Self.wholeCm(scale.photoHeightCm)) cm of the table (width × height)."
        }
        guard !lines.isEmpty else { return nil }
        return """
        REAL-WORLD SCALE (measured with the phone's AR camera)
        \(lines.joined(separator: "\n"))
        Use these measurements to judge the real size of plates, bowls, cutlery and food instead of assuming typical sizes. Estimate each food's volume from its real footprint and visible height, then its weight from typical density. Visible kitchen-scale readings and nutrition labels still take priority.
        """
    }

    private static func wholeCm(_ value: Double) -> String {
        String(Int(value.rounded()))
    }
}

/// Keeps each AR photo's measurement with the image until analysis, so capture,
/// multi-photo and retry paths need no extra plumbing. Entries go with the image.
enum PortionScaleRegistry {
    private final class Box {
        let scale: PortionScale
        init(_ scale: PortionScale) { self.scale = scale }
    }

    private static let table = NSMapTable<UIImage, Box>.weakToStrongObjects()

    static func attach(_ scale: PortionScale, to image: UIImage) {
        table.setObject(Box(scale), forKey: image)
    }

    static func scale(for image: UIImage) -> PortionScale? {
        table.object(forKey: image)?.scale
    }
}
