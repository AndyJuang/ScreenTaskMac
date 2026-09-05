// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import Security
import Darwin

struct Settings: Codable, Equatable {
    var address = ""
    var displayID: UInt32 = 0
    var port = 7070
    var interval = 150
    var quality = 75.0
    var maxWidth = 1920
    var cursor = true
    var privateSession = false
    var username = "viewer"
    var autoStart = false
    var startMinimized = false
    var publicAccess = false
    static func load() -> Settings {
        guard let data = UserDefaults.standard.data(forKey: "settings"), let value = try? JSONDecoder().decode(Settings.self, from: data) else { return Settings() }
        return value
    }
    func save() { if let data = try? JSONEncoder().encode(self) { UserDefaults.standard.set(data, forKey: "settings") } }
}

enum PasswordStore {
    static let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "io.github.AndyJuang.ScreenTaskMac", kSecAttrAccount as String: "session"]
    static func load() -> String {
        var request = query; request[kSecReturnData as String] = true
        var result: CFTypeRef?
        guard SecItemCopyMatching(request as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }
    static func save(_ password: String) throws {
        let data = Data(password.utf8)
        var status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var item = query; item[kSecValueData as String] = data
            item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            status = SecItemAdd(item as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(status)) }
    }
}

struct NetworkAddress: Identifiable, Equatable {
    let name: String
    let address: String
    let mask: String
    var id: String { address }
    static func list() -> [NetworkAddress] {
        var pointer: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&pointer) == 0 else { return [] }
        defer { freeifaddrs(pointer) }
        var result: [NetworkAddress] = []
        var cursor = pointer
        while let current = cursor {
            defer { cursor = current.pointee.ifa_next }
            let item = current.pointee
            guard item.ifa_flags & UInt32(IFF_UP) != 0,
                  let address = item.ifa_addr, address.pointee.sa_family == UInt8(AF_INET), let mask = item.ifa_netmask else { continue }
            func string(_ pointer: UnsafeMutablePointer<sockaddr>) -> String {
                var buffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                guard getnameinfo(pointer, socklen_t(pointer.pointee.sa_len), &buffer, socklen_t(buffer.count), nil, 0, NI_NUMERICHOST) == 0 else { return "" }
                return String(cString: buffer)
            }
            result.append(NetworkAddress(name: String(cString: item.ifa_name), address: string(address), mask: string(mask)))
        }
        return result.sorted { ($0.address.hasPrefix("127.") ? 1 : 0, $0.name, $0.address) < ($1.address.hasPrefix("127.") ? 1 : 0, $1.name, $1.address) }
    }
}
