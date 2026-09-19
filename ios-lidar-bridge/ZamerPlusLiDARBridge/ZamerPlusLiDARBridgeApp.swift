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
        if url.scheme?.lowercased() == "zamerpluslidar" && url.host?.lowercased() == "send" {
            handleSend(url: url)
            return
        }
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

    private func isReceiverIPv4(_ ip: String, remote: Bool) -> Bool {
        let parts = ip.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return false }
        let values = parts.compactMap { part -> Int? in
            guard part.count <= 3, !part.isEmpty, part.allSatisfy({ $0.isNumber }),
                  let n = Int(part), (0...255).contains(n) else { return nil }
            return n
        }
        guard values.count == 4 else { return false }
        if remote { return values[0] == 100 && (64...127).contains(values[1]) }
        return values[0] == 10 || (values[0] == 192 && values[1] == 168) ||
            (values[0] == 172 && (16...31).contains(values[1]))
    }

    private func transferCallback(_ callback: URL, status: String) {
        var parts = URLComponents(url: callback, resolvingAgainstBaseURL: false)
        parts?.fragment = "zamerplus_transfer=\(status)"
        if let url = parts?.url { UIApplication.shared.open(url) }
    }

    private func handleSend(url: URL) {
        guard let c = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            statusText = "Некорректная ссылка передачи"; return
        }
        var params: [String: String] = [:]
        for item in c.queryItems ?? [] { params[item.name] = item.value ?? "" }
        let homeIP = params["ip"] ?? ""
        let remoteIP = params["remoteIp"] ?? ""
        let validHome = isReceiverIPv4(homeIP, remote: false)
        let validRemote = isReceiverIPv4(remoteIP, remote: true)
        guard (validHome || validRemote),
              let port = Int(params["port"] ?? ""), port == 8787,
              let token = params["token"], token.range(of: "^[0-9a-fA-F]{48}$", options: .regularExpression) != nil,
              let encoded = params["payload"], encoded.count <= 48000,
              let callbackString = params["callback"], let callback = URL(string: callbackString),
              callback.scheme == "https", callback.host == "businessmarketolog-web.github.io",
              let bytes = Data(base64Encoded: encoded.replacingOccurrences(of: "-", with: "+")
                .replacingOccurrences(of: "_", with: "/")
                + String(repeating: "=", count: (4 - encoded.count % 4) % 4)),
              bytes.count <= 512 * 1024,
              let json = try? JSONSerialization.jsonObject(with: bytes) as? [String: Any],
              ["zamerplus-sketchup", "zamerplus-project"].contains(json["format"] as? String ?? "")
        else { statusText = "Укажите домашний IP или адрес Tailscale и код сопряжения."; return }

        // Prefer only the VPN endpoint when configured; never send to a possible
        // address collision on a foreign Wi-Fi network without explicit home mode.
        var addresses: [(ip: String, isRemote: Bool)] = []
        if validRemote { addresses.append((ip: remoteIP, isRemote: true)) }
        else if validHome { addresses.append((ip: homeIP, isRemote: false)) }
        statusText = "Передаю замер на компьютер…"
        Task {
            for (index, item) in addresses.enumerated() {
                guard let endpoint = URL(string: "http://\(item.ip):\(port)/upload") else { continue }
                var request = URLRequest(url: endpoint)
                request.httpMethod = "POST"
                request.timeoutInterval = item.isRemote ? 22 : 18
                request.setValue(token.lowercased(), forHTTPHeaderField: "X-Zamer-Token")
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.httpBody = bytes
                statusText = item.isRemote ? "Передаю через защищённую сеть Tailscale…" : "Пробую домашний Wi-Fi…"
                do {
                    let (data, response) = try await URLSession.shared.data(for: request)
                    let result = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                    if let http = response as? HTTPURLResponse,
                       http.statusCode == 202, result?["accepted"] as? Bool == true {
                        statusText = "Скан получен компьютером и ожидает импорта в SketchUp."
                        transferCallback(callback, status: "accepted")
                        return
                    }
                    statusText = "Приёмник отклонил запрос. Проверьте код сопряжения."
                    transferCallback(callback, status: "rejected")
                    return
                } catch {
                    if index == addresses.count - 1 {
                        statusText = "Нет связи с компьютером. Проверьте Tailscale на iPhone и ПК, доступ к интернету и приёмник."
                        transferCallback(callback, status: "offline")
                    }
                }
            }
        }
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

                Text("LiDAR-сканирование и прямая передача на приёмник SketchUp по локальной сети. Ручной JSON/DAE доступен в Safari.")
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
