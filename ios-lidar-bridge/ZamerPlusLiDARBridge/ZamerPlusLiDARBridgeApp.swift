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
            let data = try JSONSerialization.data(withJSONObject: payload, options: [])
            let encoded = data.base64URLEncodedString()

            var components = URLComponents(url: request.callback, resolvingAgainstBaseURL: false)
            components?.fragment = "zamerplus_lidar=\(encoded)"

            guard let returnURL = components?.url else {
                statusText = "Не удалось сформировать ссылку возврата."
                scanRequest = nil
                return
            }

            statusText = "Скан завершён. Возвращаю результат в Safari…"
            scanRequest = nil
            UIApplication.shared.open(returnURL)
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
