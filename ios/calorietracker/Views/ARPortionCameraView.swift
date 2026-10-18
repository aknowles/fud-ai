import ARKit
import CoreImage
import SwiftUI
import UIKit

/// Food camera that also measures the table under the food with ARKit, so photo
/// analysis gets real-world scale (#601). A photo taken before the table is found,
/// or from a steep angle, is still logged; it just carries no measurement.
struct ARPortionCameraView: UIViewControllerRepresentable {
    @Binding var image: UIImage?
    let title: String?
    let onCancel: (() -> Void)?
    let onUseStandardCamera: () -> Void
    @Environment(\.dismiss) private var dismiss

    static var isSupported: Bool { ARWorldTrackingConfiguration.isSupported }
    static let preferenceKey = "foodCameraUsesARMeasure"

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
        controller.onUseStandardCamera = onUseStandardCamera
        return controller
    }

    func updateUIViewController(_ uiViewController: ARPortionCameraController, context: Context) {}
}

final class ARPortionCameraController: UIViewController, ARSessionDelegate {
    var onCapture: ((UIImage, PortionScale?) -> Void)?
    var onCancel: (() -> Void)?
    var onUseStandardCamera: (() -> Void)?

    private let sceneView = ARSCNView()
    private let statusLabel = UILabel()
    private let statusBackground = UIView()
    private let reticle = UIView()
    private let shutterButton = UIButton(type: .system)
    private let titleText: String?
    private let ciContext = CIContext()
    private var lastStatusUpdate: TimeInterval = 0
    private var isCapturing = false
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

        reticle.layer.cornerRadius = 18
        reticle.layer.borderWidth = 2
        reticle.layer.borderColor = UIColor.white.withAlphaComponent(0.8).cgColor
        reticle.isUserInteractionEnabled = false
        reticle.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(reticle)

        statusBackground.backgroundColor = UIColor.black.withAlphaComponent(0.6)
        statusBackground.layer.cornerRadius = 16
        statusBackground.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(statusBackground)

        statusLabel.textColor = .white
        statusLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        statusLabel.numberOfLines = 0
        statusLabel.textAlignment = .center
        statusLabel.text = String(localized: "Move your phone slowly to find the table")
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        statusBackground.addSubview(statusLabel)

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

        var standardConfig = UIButton.Configuration.plain()
        standardConfig.image = UIImage(systemName: "camera")
        standardConfig.title = String(localized: "Camera")
        standardConfig.imagePlacement = .top
        standardConfig.imagePadding = 4
        standardConfig.baseForegroundColor = .white
        let standardButton = UIButton(configuration: standardConfig)
        standardButton.accessibilityLabel = String(localized: "Standard camera")
        standardButton.translatesAutoresizingMaskIntoConstraints = false
        standardButton.addTarget(self, action: #selector(useStandardCamera), for: .touchUpInside)
        bottomBar.addSubview(standardButton)

        NSLayoutConstraint.activate([
            sceneView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            sceneView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            sceneView.topAnchor.constraint(equalTo: view.topAnchor),
            sceneView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            reticle.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            reticle.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            reticle.widthAnchor.constraint(equalToConstant: 36),
            reticle.heightAnchor.constraint(equalToConstant: 36),

            statusBackground.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            statusBackground.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            statusBackground.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 20),
            statusLabel.topAnchor.constraint(equalTo: statusBackground.topAnchor, constant: 10),
            statusLabel.bottomAnchor.constraint(equalTo: statusBackground.bottomAnchor, constant: -10),
            statusLabel.leadingAnchor.constraint(equalTo: statusBackground.leadingAnchor, constant: 16),
            statusLabel.trailingAnchor.constraint(equalTo: statusBackground.trailingAnchor, constant: -16),

            bottomBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            bottomBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            bottomBar.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            bottomBar.heightAnchor.constraint(equalToConstant: 140),

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
            standardButton.trailingAnchor.constraint(equalTo: bottomBar.trailingAnchor, constant: -12),
            standardButton.centerYAnchor.constraint(equalTo: shutterOuter.centerYAnchor),
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
        sceneView.session.pause()
    }

    // MARK: - ARSessionDelegate

    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        guard !sessionFailed, frame.timestamp - lastStatusUpdate > 0.2 else { return }
        lastStatusUpdate = frame.timestamp
        let tracking: Bool
        if case .normal = frame.camera.trackingState { tracking = true } else { tracking = false }
        updateStatus(for: tracking ? measure(frame) : nil)
    }

    func session(_ session: ARSession, didFailWithError error: Error) {
        sessionFailed = true
        setStatus(String(localized: "AR measuring isn't available right now"), ready: false)
    }

    // MARK: - Measuring

    private func measure(_ frame: ARFrame) -> PortionScale? {
        let center = CGPoint(x: 0.5, y: 0.5)
        // The food covers the table under the centre, so extend the detected
        // table plane beneath it before falling back to an estimate.
        var results = sceneView.session.raycast(
            frame.raycastQuery(from: center, allowing: .existingPlaneInfinite, alignment: .horizontal)
        )
        if results.isEmpty {
            results = sceneView.session.raycast(
                frame.raycastQuery(from: center, allowing: .estimatedPlane, alignment: .horizontal)
            )
        }
        guard let hit = results.first else { return nil }
        let transform = hit.worldTransform
        return PortionScale.measure(
            cameraTransform: frame.camera.transform,
            planePoint: SIMD3(transform.columns.3.x, transform.columns.3.y, transform.columns.3.z),
            planeNormal: SIMD3(transform.columns.1.x, transform.columns.1.y, transform.columns.1.z),
            intrinsics: frame.camera.intrinsics,
            imageResolution: frame.camera.imageResolution
        )
    }

    private func updateStatus(for scale: PortionScale?) {
        guard let scale else {
            setStatus(String(localized: "Move your phone slowly to find the table"), ready: false)
            return
        }
        switch scale.readiness {
        case .tooClose:
            setStatus(String(localized: "Move your phone a little higher"), ready: false)
        case .tooFar:
            setStatus(String(localized: "Move your phone closer to the food"), ready: false)
        case .tooTilted:
            setStatus(String(localized: "Hold your phone flat above the food"), ready: false)
        case .ready:
            let distance = Self.formattedHeight(cm: scale.cameraHeightCm)
            setStatus(String(localized: "Ready · \(distance) above the table"), ready: true)
        }
    }

    private func setStatus(_ text: String, ready: Bool) {
        if statusLabel.text != text {
            statusLabel.text = text
            UIAccessibility.post(notification: .announcement, argument: text)
        }
        reticle.layer.borderColor = (ready ? UIColor.systemGreen : UIColor.white.withAlphaComponent(0.8)).cgColor
    }

    private static func formattedHeight(cm: Double) -> String {
        let measurement: Measurement<UnitLength> = HeightUnit.current == .cm
            ? Measurement(value: cm.rounded(), unit: .centimeters)
            : Measurement(value: (cm / 2.54).rounded(), unit: .inches)
        return measurement.formatted(.measurement(
            width: .abbreviated,
            usage: .asProvided,
            numberFormatStyle: .number.precision(.fractionLength(0))
        ))
    }

    // MARK: - Capture

    @objc private func capture() {
        guard !isCapturing, let frame = sceneView.session.currentFrame else { return }
        isCapturing = true
        let orientation = view.window?.windowScene?.effectiveGeometry.interfaceOrientation ?? .portrait
        let fallbackScale = measure(frame)
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
        let photoFrame = highResolutionFrame ?? fallbackFrame
        // The high-resolution still has its own intrinsics for its size.
        let scale = (highResolutionFrame.flatMap { measure($0) } ?? fallbackScale)
            .flatMap { $0.readiness == .ready ? $0 : nil }
        guard let image = uprightImage(from: photoFrame.capturedImage, orientation: orientation) else {
            isCapturing = false
            return
        }
        onCapture?(image, scale)
    }

    private func uprightImage(from pixelBuffer: CVPixelBuffer, orientation: UIInterfaceOrientation) -> UIImage? {
        // The sensor buffer is landscape; draw it upright so every provider sees
        // the photo the right way up, with or without EXIF support.
        let rotation: CGImagePropertyOrientation = orientation == .portraitUpsideDown ? .left : .right
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer).oriented(rotation)
        guard let cgImage = ciContext.createCGImage(ciImage, from: ciImage.extent) else { return nil }
        return UIImage(cgImage: cgImage, scale: 1, orientation: .up)
    }

    @objc private func cancel() {
        onCancel?()
    }

    @objc private func useStandardCamera() {
        onUseStandardCamera?()
    }
}
