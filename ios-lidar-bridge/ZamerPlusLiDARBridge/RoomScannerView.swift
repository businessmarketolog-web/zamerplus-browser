import SwiftUI
import UIKit
import RoomPlan
import simd

struct RoomScannerView: UIViewControllerRepresentable {
    let request: ScanRequest
    let onComplete: ([String: Any]) -> Void
    let onCancel: () -> Void

    func makeUIViewController(context: Context) -> RoomScannerViewController {
        let controller = RoomScannerViewController()
        controller.requestId = request.id
        controller.onComplete = onComplete
        controller.onCancel = onCancel
        return controller
    }

    func updateUIViewController(_ uiViewController: RoomScannerViewController, context: Context) {}
}

final class RoomScannerViewController: UIViewController, RoomCaptureViewDelegate {
    var requestId = ""
    var onComplete: (([String: Any]) -> Void)?
    var onCancel: (() -> Void)?

    private var captureView: RoomCaptureView!
    private var didFinish = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black

        captureView = RoomCaptureView(frame: view.bounds)
        captureView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        captureView.delegate = self
        captureView.isModelEnabled = true
        view.addSubview(captureView)

        let topBar = UIVisualEffectView(effect: UIBlurEffect(style: .systemThinMaterialDark))
        topBar.translatesAutoresizingMaskIntoConstraints = false
        topBar.layer.cornerRadius = 20
        topBar.clipsToBounds = true
        view.addSubview(topBar)

        let label = UILabel()
        label.text = "Медленно обойдите помещение и покажите все стены, двери и окна"
        label.textColor = .white
        label.font = .systemFont(ofSize: 13, weight: .semibold)
        label.numberOfLines = 2
        label.translatesAutoresizingMaskIntoConstraints = false
        topBar.contentView.addSubview(label)

        let cancel = makeButton(title: "Отмена", color: .systemGray)
        cancel.addTarget(self, action: #selector(cancelScan), for: .touchUpInside)
        view.addSubview(cancel)

        let done = makeButton(title: "Готово", color: .systemPink)
        done.addTarget(self, action: #selector(finishScan), for: .touchUpInside)
        view.addSubview(done)

        NSLayoutConstraint.activate([
            topBar.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 14),
            topBar.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -14),
            topBar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 10),

            label.leadingAnchor.constraint(equalTo: topBar.contentView.leadingAnchor, constant: 14),
            label.trailingAnchor.constraint(equalTo: topBar.contentView.trailingAnchor, constant: -14),
            label.topAnchor.constraint(equalTo: topBar.contentView.topAnchor, constant: 10),
            label.bottomAnchor.constraint(equalTo: topBar.contentView.bottomAnchor, constant: -10),

            cancel.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
            cancel.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -14),
            cancel.widthAnchor.constraint(equalToConstant: 105),
            cancel.heightAnchor.constraint(equalToConstant: 50),

            done.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
            done.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -14),
            done.widthAnchor.constraint(equalToConstant: 115),
            done.heightAnchor.constraint(equalToConstant: 50)
        ])
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard RoomCaptureSession.isSupported else {
            showUnsupported()
            return
        }
        captureView.captureSession.run(configuration: RoomCaptureSession.Configuration())
    }

    private func makeButton(title: String, color: UIColor) -> UIButton {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setTitle(title, for: .normal)
        button.setTitleColor(.white, for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 17, weight: .bold)
        button.backgroundColor = color
        button.layer.cornerRadius = 18
        return button
    }

    private func showUnsupported() {
        let alert = UIAlertController(
            title: "LiDAR недоступен",
            message: "RoomPlan не поддерживается на этом устройстве.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Закрыть", style: .default) { [weak self] _ in
            self?.onCancel?()
        })
        present(alert, animated: true)
    }

    @objc private func finishScan() {
        guard !didFinish else { return }
        captureView.captureSession.stop()
    }

    @objc private func cancelScan() {
        guard !didFinish else { return }
        didFinish = true
        captureView.captureSession.stop()
        onCancel?()
    }

    func captureView(shouldPresent roomDataForProcessing: CapturedRoomData, error: Error?) -> Bool {
        error == nil
    }

    func captureView(didPresent room: CapturedRoom, error: Error?) {
        guard !didFinish else { return }
        didFinish = true

        if let error {
            onComplete?(["requestId": requestId, "error": error.localizedDescription])
            return
        }

        onComplete?(makePayload(room: room))
    }

    private func makePayload(room: CapturedRoom) -> [String: Any] {
        let wallMap = Dictionary(uniqueKeysWithValues: room.walls.map { ($0.identifier, $0) })

        let walls: [[String: Any]] = room.walls.map { wall in
            let center = wall.transform.columns.3
            let axis = SIMD2<Float>(wall.transform.columns.0.x, wall.transform.columns.0.z)
            let normalized = simd_length(axis) > 0.0001 ? simd_normalize(axis) : SIMD2<Float>(1, 0)
            let half = wall.dimensions.x / 2

            let x1 = center.x - normalized.x * half
            let z1 = center.z - normalized.y * half
            let x2 = center.x + normalized.x * half
            let z2 = center.z + normalized.y * half
            let heading = atan2(normalized.y, normalized.x) * 180 / Float.pi

            return [
                "id": wall.identifier.uuidString,
                "widthMm": Int((wall.dimensions.x * 1000).rounded()),
                "heightMm": Int((wall.dimensions.y * 1000).rounded()),
                "x1Mm": Int((x1 * 1000).rounded()),
                "z1Mm": Int((z1 * 1000).rounded()),
                "x2Mm": Int((x2 * 1000).rounded()),
                "z2Mm": Int((z2 * 1000).rounded()),
                "centerXMm": Int((center.x * 1000).rounded()),
                "centerZMm": Int((center.z * 1000).rounded()),
                "headingDeg": Double(heading),
                "source": "roomplan"
            ]
        }

        func surfacePayload(_ surface: CapturedRoom.Surface, type: String) -> [String: Any] {
            let center = surface.transform.columns.3
            var offset: Float = 0
            var bottom: Float = max(0, center.y - surface.dimensions.y / 2)

            if let parentId = surface.parentIdentifier, let wall = wallMap[parentId] {
                let wallCenter = wall.transform.columns.3
                let axis = SIMD2<Float>(wall.transform.columns.0.x, wall.transform.columns.0.z)
                let normalized = simd_length(axis) > 0.0001 ? simd_normalize(axis) : SIMD2<Float>(1, 0)
                let delta = SIMD2<Float>(center.x - wallCenter.x, center.z - wallCenter.z)
                offset = simd_dot(delta, normalized) + wall.dimensions.x / 2
                let wallBottom = wallCenter.y - wall.dimensions.y / 2
                bottom = max(0, (center.y - surface.dimensions.y / 2) - wallBottom)
            }

            return [
                "id": surface.identifier.uuidString,
                "type": type,
                "parentId": surface.parentIdentifier?.uuidString ?? "",
                "widthMm": Int((surface.dimensions.x * 1000).rounded()),
                "heightMm": Int((surface.dimensions.y * 1000).rounded()),
                "offsetMm": Int((offset * 1000).rounded()),
                "bottomMm": Int((bottom * 1000).rounded()),
                "source": "roomplan"
            ]
        }

        var openings: [[String: Any]] = []
        openings.append(contentsOf: room.doors.map { surfacePayload($0, type: "door") })
        openings.append(contentsOf: room.windows.map { surfacePayload($0, type: "window") })
        openings.append(contentsOf: room.openings.map { surfacePayload($0, type: "opening") })

        var floorPolygon: [[String: Any]] = []
        if let floor = room.floors.first {
            for corner in floor.polygonCorners {
                let world = floor.transform * SIMD4<Float>(corner.x, corner.y, corner.z, 1)
                floorPolygon.append([
                    "xMm": Int((world.x * 1000).rounded()),
                    "zMm": Int((world.z * 1000).rounded())
                ])
            }
        }

        let heights = room.walls.map { Int(($0.dimensions.y * 1000).rounded()) }.sorted()
        let roomHeight = heights.isEmpty ? 0 : heights[heights.count / 2]

        return [
            "version": 1,
            "requestId": requestId,
            "source": "apple_roomplan",
            "capturedAt": ISO8601DateFormatter().string(from: Date()),
            "heightMm": roomHeight,
            "walls": walls,
            "openings": openings,
            "floorPolygon": floorPolygon,
            "doorsCount": room.doors.count,
            "windowsCount": room.windows.count
        ]
    }
}
