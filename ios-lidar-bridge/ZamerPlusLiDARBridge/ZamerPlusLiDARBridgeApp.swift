import SwiftUI

@main
struct ZamerPlusLiDARBridgeApp: App {
    @StateObject private var coordinator = BridgeCoordinator()

    var body: some Scene {
        WindowGroup {
            BridgeHomeView()
                .environmentObject(coordinator)
                .onOpenURL { url in
                    coordinator.handle(url: url)
                }
        }
    }
}

struct ScanRequest: Identifiable, Equatable {
    let id: String
    let callback: URL
}

@MainActor
final class BridgeCoordinator: ObservableObject {
    @Published var scanRequest: ScanRequest?
    @Published var statusText = "Откройте Замер+ в Safari и нажмите «Сканировать LiDAR»."

    func handle(url: URL) {
        guard url.scheme?.lowercased() == "zamerpluslidar",
              url.host?.lowercased() == "scan",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let requestId = components.queryItems?.first(where: { $0.name == "requestId" })?.value,
              let callbackString = components.queryItems?.first(where: { $0.name == "callback" })?.value,
              let callback = URL(string: callbackString)
        else {
            statusText = "Некорректный запрос Safari."
            return
        }

        statusText = "Запуск RoomPlan…"
        scanRequest = ScanRequest(id: requestId, callback: callback)
    }

    func complete(request: ScanRequest, payload: [String: Any]) {
        do {
            let fullData = try JSONSerialization.data(withJSONObject: payload, options: [])
            UIPasteboard.general.string = "ZAMERPLUS_LIDAR_V2:\(fullData.base64URLEncodedString())"

            func keep(_ source: [String: Any], _ keys: [String]) -> [String: Any] {
                var out: [String: Any] = [:]
                for key in keys {
                    if let value = source[key] { out[key] = value }
                }
                return out
            }

            var compact: [String: Any] = [:]
            for key in ["version","requestId","source","capturedAt","heightMm","doorsCount","windowsCount"] {
                if let value = payload[key] { compact[key] = value }
            }

            let walls = (payload["walls"] as? [[String: Any]] ?? []).map {
                keep($0, ["id","widthMm","heightMm","x1Mm","z1Mm","x2Mm","z2Mm","centerXMm","centerZMm","headingDeg"])
            }
            let openings = (payload["openings"] as? [[String: Any]] ?? []).map {
                keep($0, ["id","type","parentId","widthMm","heightMm","offsetMm","bottomMm"])
            }
            let floorPolygon = payload["floorPolygon"] as? [[String: Any]] ?? []
            let objects = (payload["objects"] as? [[String: Any]] ?? []).map {
                keep($0, ["id","category","widthMm","heightMm","depthMm","centerXMm","centerYMm","centerZMm","headingDeg"])
            }

            compact["walls"] = walls
            compact["openings"] = openings
            compact["floorPolygon"] = floorPolygon
            compact["objects"] = objects

            var compactData = try JSONSerialization.data(withJSONObject: compact, options: [])
            if compactData.count > 7000 {
                compact["objects"] = []
                compactData = try JSONSerialization.data(withJSONObject: compact, options: [])
            }

            let encoded = compactData.base64URLEncodedString()
            var components = URLComponents(url: request.callback, resolvingAgainstBaseURL: false)
            components?.fragment = "zamerplus_lidar_auto=\(encoded)&requestId=\(request.id)"

            guard let returnURL = components?.url else {
                statusText = "Не удалось сформировать ссылку возврата."
                scanRequest = nil
                return
            }

            statusText = "Скан завершён. Передаю геометрию в Safari…"
            scanRequest = nil
            UIApplication.shared.open(returnURL, options: [:]) { [weak self] opened in
                if !opened {
                    self?.statusText = "Скан сохранён. Вернитесь в Safari — резервная копия находится в буфере обмена."
                }
            }
        } catch {
            statusText = "Ошибка упаковки LiDAR: \(error.localizedDescription)"
            scanRequest = nil
        }
    }

    func cancel(request: ScanRequest) {
        scanRequest = nil
        statusText = "Сканирование отменено."
        var components = URLComponents(url: request.callback, resolvingAgainstBaseURL: false)
        components?.fragment = "zamerplus_lidar_cancelled=1"
        if let url = components?.url {
            UIApplication.shared.open(url)
        }
    }
}

struct BridgeHomeView: View {
    @EnvironmentObject var coordinator: BridgeCoordinator

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                Spacer()

                Image(systemName: "viewfinder.circle.fill")
                    .font(.system(size: 74))
                    .symbolRenderingMode(.hierarchical)

                Text("Замер+ LiDAR Bridge")
                    .font(.title.bold())

                Text(coordinator.statusText)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 28)

                Button {
                    if let url = URL(string: "https://businessmarketolog-web.github.io/zamerplus-browser/") {
                        UIApplication.shared.open(url)
                    }
                } label: {
                    Text("Открыть Замер+ в Safari")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .buttonStyle(.borderedProminent)
                .padding(.horizontal, 28)

                Text("Helper нужен только для RoomPlan/LiDAR. Основной интерфейс, объекты, Bosch и экспорт остаются в Safari.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 30)

                Spacer()
            }
            .fullScreenCover(item: $coordinator.scanRequest) { request in
                RoomScannerView(
                    request: request,
                    onComplete: { payload in coordinator.complete(request: request, payload: payload) },
                    onCancel: { coordinator.cancel(request: request) }
                )
                .ignoresSafeArea()
            }
        }
    }
}

private extension Data {
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
