import ARKit
import CoreImage
import SwiftUI
import UIKit

/// The food camera, running ARKit in the background so a photo can carry the
/// real-world scale of the table under the food (#601). It looks and works like
/// the standard camera; nothing about AR is shown. A photo is measured only when
/// tracking is solid and a table plane is under the centre of the frame;
/// otherwise it is a normal photo.
struct ARPortionCameraView: UIViewControllerRepresentable {
    @Binding var image: UIImage?
    let title: String?
    let onCancel: (() -> Void)?
    /// ARKit couldn't run (camera access, hardware); the caller shows the standard camera.
    let onSessionFailed: () -> Void
    @Environment(\.dismiss) private var dismiss

    static var isSupported: Bool { ARWorldTrackingConfiguration.isSupported }

    func makeUIViewController(context: Context) -> ARPortionCameraController {
        let controller = ARPortionCameraController(title: title)
        controller.onCapture = { image, scale in
            if let scale {
                PortionScaleRegistry.attach(scale, to: image)
            }
            self.image = image
            dismiss()
        }
        controller.onCancel = {
            onCancel?()
            dismiss()
        }
        controller.onSessionFailed = onSessionFailed
        return controller
    }

    func updateUIViewController(_ uiViewController: ARPortionCameraController, context: Context) {}
}

final class ARPortionCameraController: UIViewController, ARSessionDelegate {
    var onCapture: ((UIImage, PortionScale?) -> Void)?
    var onCancel: (() -> Void)?
    var onSessionFailed: (() -> Void)?

    private let sceneView = ARSCNView()
    private let titleText: String?
    private let ciContext = CIContext()
    private var isCapturing = false
    /// Set when the user leaves this camera, so a still that arrives afterwards is dropped.
    private var hasLeft = false
    private var sessionFailed = false

    init(title: String?) {
        titleText = title
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .fullScreen
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        sceneView.session.delegate = self
        sceneView.automaticallyUpdatesLighting = false
        sceneView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(sceneView)

        // Same layout as the standard camera: the full 4:3 frame, letterboxed
        // above the bottom bar, so the preview matches the saved photo.
        let screenSize = UIScreen.main.bounds.size
        let previewHeight = screenSize.width * 4.0 / 3.0
        let bottomBarHeight: CGFloat = 140
        let availablePreviewHeight = max(0, screenSize.height - bottomBarHeight)
        let previewOffset = max(0, (availablePreviewHeight - previewHeight) / 2)

        let bottomBar = UIView()
        bottomBar.backgroundColor = UIColor.black.withAlphaComponent(0.6)
        bottomBar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(bottomBar)

        let shutterOuter = UIView()
        shutterOuter.backgroundColor = .white
        shutterOuter.layer.cornerRadius = 37
        shutterOuter.isUserInteractionEnabled = false
        shutterOuter.translatesAutoresizingMaskIntoConstraints = false
        bottomBar.addSubview(shutterOuter)

        let shutterInner = UIView()
        shutterInner.backgroundColor = .white
        shutterInner.layer.cornerRadius = 32
        shutterInner.layer.borderWidth = 2
        shutterInner.layer.borderColor = UIColor.black.withAlphaComponent(0.15).cgColor
        shutterInner.isUserInteractionEnabled = false
        shutterInner.translatesAutoresizingMaskIntoConstraints = false
        shutterOuter.addSubview(shutterInner)

        let shutterButton = UIButton(type: .system)
        shutterButton.accessibilityLabel = String(localized: "Take photo")
        shutterButton.translatesAutoresizingMaskIntoConstraints = false
        shutterButton.addTarget(self, action: #selector(capture), for: .touchUpInside)
        bottomBar.addSubview(shutterButton)

        let cancelButton = UIButton(type: .system)
        cancelButton.setTitle(String(localized: "Cancel"), for: .normal)
        cancelButton.setTitleColor(.white, for: .normal)
        cancelButton.titleLabel?.font = .systemFont(ofSize: 17)
        cancelButton.translatesAutoresizingMaskIntoConstraints = false
        cancelButton.addTarget(self, action: #selector(cancel), for: .touchUpInside)
        bottomBar.addSubview(cancelButton)

        NSLayoutConstraint.activate([
            sceneView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            sceneView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            sceneView.topAnchor.constraint(equalTo: view.topAnchor, constant: previewOffset),
            sceneView.heightAnchor.constraint(equalToConstant: previewHeight),

            bottomBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            bottomBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            bottomBar.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            bottomBar.heightAnchor.constraint(equalToConstant: bottomBarHeight),

            shutterOuter.centerXAnchor.constraint(equalTo: bottomBar.centerXAnchor),
            shutterOuter.centerYAnchor.constraint(equalTo: bottomBar.topAnchor, constant: 50),
            shutterOuter.widthAnchor.constraint(equalToConstant: 74),
            shutterOuter.heightAnchor.constraint(equalToConstant: 74),
            shutterInner.centerXAnchor.constraint(equalTo: shutterOuter.centerXAnchor),
            shutterInner.centerYAnchor.constraint(equalTo: shutterOuter.centerYAnchor),
            shutterInner.widthAnchor.constraint(equalToConstant: 64),
            shutterInner.heightAnchor.constraint(equalToConstant: 64),
            shutterButton.leadingAnchor.constraint(equalTo: shutterOuter.leadingAnchor),
            shutterButton.trailingAnchor.constraint(equalTo: shutterOuter.trailingAnchor),
            shutterButton.topAnchor.constraint(equalTo: shutterOuter.topAnchor),
            shutterButton.bottomAnchor.constraint(equalTo: shutterOuter.bottomAnchor),

            cancelButton.leadingAnchor.constraint(equalTo: bottomBar.leadingAnchor, constant: 20),
            cancelButton.centerYAnchor.constraint(equalTo: shutterOuter.centerYAnchor),
        ])

        if let titleText {
            let label = UILabel()
            label.text = titleText
            label.textColor = .white
            label.font = .systemFont(ofSize: 17, weight: .semibold)
            label.translatesAutoresizingMaskIntoConstraints = false
            bottomBar.addSubview(label)
            NSLayoutConstraint.activate([
                label.centerXAnchor.constraint(equalTo: bottomBar.centerXAnchor),
                label.topAnchor.constraint(equalTo: shutterOuter.bottomAnchor, constant: 14),
            ])
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        let configuration = ARWorldTrackingConfiguration()
        configuration.planeDetection = [.horizontal]
        // A full-resolution still for the AI instead of a video frame.
        if let format = ARWorldTrackingConfiguration.recommendedVideoFormatForHighResolutionFrameCapturing {
            configuration.videoFormat = format
        }
        sceneView.session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        hasLeft = true
        sceneView.session.pause()
    }

    // MARK: - ARSessionDelegate

    func session(_ session: ARSession, didFailWithError error: Error) {
        guard !sessionFailed, !hasLeft else { return }
        sessionFailed = true
        onSessionFailed?()
    }

    // MARK: - Measuring

    private var sceneOrientation: UIInterfaceOrientation {
        view.window?.windowScene?.effectiveGeometry.interfaceOrientation ?? .portrait
    }

    /// No measurement unless tracking is normal and a detected table plane, not
    /// the floor, is under the centre of the frame.
    private func measure(_ frame: ARFrame, orientation: UIInterfaceOrientation) -> PortionScale? {
        guard !sessionFailed, case .normal = frame.camera.trackingState else { return nil }
        let center = CGPoint(x: 0.5, y: 0.5)
        // The food can hide the table under the centre, so extend the detected
        // plane beneath it when the ray misses the plane's mapped area.
        for target in [ARRaycastQuery.Target.existingPlaneGeometry, .existingPlaneInfinite] {
            let results = sceneView.session.raycast(
                frame.raycastQuery(from: center, allowing: target, alignment: .horizontal)
            )
            if let hit = results.first(where: { !Self.isFloor($0) }) {
                let transform = hit.worldTransform
                return PortionScale.measure(
                    cameraTransform: frame.camera.transform,
                    planePoint: SIMD3(transform.columns.3.x, transform.columns.3.y, transform.columns.3.z),
                    planeNormal: SIMD3(transform.columns.1.x, transform.columns.1.y, transform.columns.1.z),
                    intrinsics: frame.camera.intrinsics,
                    imageResolution: frame.camera.imageResolution,
                    portrait: orientation.isPortrait || orientation == .unknown
                )
            }
        }
        return nil
    }

    private static func isFloor(_ result: ARRaycastResult) -> Bool {
        guard let plane = result.anchor as? ARPlaneAnchor else { return false }
        if case .floor = plane.classification { return true }
        return false
    }

    // MARK: - Capture

    @objc private func capture() {
        guard !isCapturing, !hasLeft, let frame = sceneView.session.currentFrame else { return }
        isCapturing = true
        let orientation = sceneOrientation
        let fallbackScale = measure(frame, orientation: orientation)
        sceneView.session.captureHighResolutionFrame { [weak self] highResolutionFrame, _ in
            let finish: () -> Void = {
                self?.finishCapture(
                    highResolutionFrame,
                    fallbackFrame: frame,
                    fallbackScale: fallbackScale,
                    orientation: orientation
                )
            }
            if Thread.isMainThread {
                finish()
            } else {
                DispatchQueue.main.async(execute: finish)
            }
        }
    }

    private func finishCapture(
        _ highResolutionFrame: ARFrame?,
        fallbackFrame: ARFrame,
        fallbackScale: PortionScale?,
        orientation: UIInterfaceOrientation
    ) {
        guard !hasLeft else { return }
        let photoFrame = highResolutionFrame ?? fallbackFrame
        // The high-resolution still has its own intrinsics for its size.
        let scale = (highResolutionFrame.flatMap { measure($0, orientation: orientation) } ?? fallbackScale)
            .flatMap { $0.readiness == .ready ? $0 : nil }
        guard let image = uprightImage(from: photoFrame.capturedImage, orientation: orientation) else {
            isCapturing = false
            return
        }
        hasLeft = true
        onCapture?(image, scale)
    }

    private func uprightImage(from pixelBuffer: CVPixelBuffer, orientation: UIInterfaceOrientation) -> UIImage? {
        // The sensor buffer is landscape-right; draw it upright so every provider
        // sees the photo the right way up, with or without EXIF support.
        let rotation: CGImagePropertyOrientation
        switch orientation {
        case .portraitUpsideDown: rotation = .left
        case .landscapeRight: rotation = .up
        case .landscapeLeft: rotation = .down
        default: rotation = .right
        }
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer).oriented(rotation)
        guard let cgImage = ciContext.createCGImage(ciImage, from: ciImage.extent) else { return nil }
        return UIImage(cgImage: cgImage, scale: 1, orientation: .up)
    }

    @objc private func cancel() {
        hasLeft = true
        onCancel?()
    }
}
