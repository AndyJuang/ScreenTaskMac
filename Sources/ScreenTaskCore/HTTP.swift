// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

public struct HTTPRequest {
    public let method: String
    public let path: String
    public let headers: [String: String]
    public init?(_ data: Data) {
        guard data.count <= 16384, let text = String(data: data, encoding: .utf8), text.hasSuffix("\r\n\r\n") else { return nil }
        let lines = text.components(separatedBy: "\r\n")
        let first = lines[0].split(separator: " ")
        guard first.count == 3, first[2] == "HTTP/1.1" || first[2] == "HTTP/1.0", first[1].hasPrefix("/") else { return nil }
        method = String(first[0])
        path = String(first[1].split(separator: "?", maxSplits: 1)[0])
        var result: [String: String] = [:]
        for line in lines.dropFirst() where !line.isEmpty {
            guard let colon = line.firstIndex(of: ":") else { return nil }
            let key = line[..<colon].lowercased()
            guard !key.isEmpty, result[key] == nil else { return nil }
            result[key] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }
        headers = result
    }
}

public struct HTTPResponse {
    public let status: Int
    public let type: String
    public let body: Data
    public var headers: [String: String] = [:]
    /// A multipart/x-mixed-replace response carries no Content-Length: the body is the frames
    /// written afterwards, and the response ends when the connection closes.
    public var streaming = false
    public init(_ status: Int, type: String = "text/plain; charset=utf-8", body: Data = Data()) {
        self.status = status; self.type = type; self.body = body
    }
    public func encoded(headOnly: Bool = false, keepAlive: Bool = false) -> Data {
        let reasons = [200: "OK", 400: "Bad Request", 401: "Unauthorized", 403: "Forbidden", 404: "Not Found", 405: "Method Not Allowed", 431: "Request Header Fields Too Large", 503: "Service Unavailable"]
        var text = "HTTP/1.1 \(status) \(reasons[status] ?? "Error")\r\nContent-Type: \(type)\r\n"
        if !streaming { text += "Content-Length: \(body.count)\r\n" }
        text += "Connection: \(keepAlive ? "keep-alive" : "close")\r\n"
        text += "Cache-Control: no-store, max-age=0\r\nX-Content-Type-Options: nosniff\r\nReferrer-Policy: no-referrer\r\nX-Frame-Options: DENY\r\n"
        for (key, value) in headers { text += "\(key): \(value)\r\n" }
        text += "\r\n"
        var data = Data(text.utf8)
        if !headOnly && !streaming { data.append(body) }
        return data
    }
}

/// One persistent connection per viewer instead of one connection per frame. Viewers that poll
/// still work, but they now reuse a kept-alive connection.
public enum MJPEG {
    public static let boundary = "screentaskframe"
    public static let contentType = "multipart/x-mixed-replace; boundary=screentaskframe"
    public static func part(_ jpeg: Data) -> Data {
        var data = Data("--\(boundary)\r\nContent-Type: image/jpeg\r\nContent-Length: \(jpeg.count)\r\n\r\n".utf8)
        data.append(jpeg)
        data.append(Data("\r\n".utf8))
        return data
    }
}

public struct Router {
    public var username: String?
    public var password: String?
    public var html: Data
    public init(html: Data, username: String? = nil, password: String? = nil) {
        self.html = html; self.username = username; self.password = password
    }
    public func response(to request: HTTPRequest, jpeg: Data?) -> HTTPResponse {
        if let username, let password {
            let expected = Data("\(username):\(password)".utf8)
            let parts = request.headers["authorization"]?.split(separator: " ", maxSplits: 1)
            let supplied = parts?.count == 2 && parts?[0].lowercased() == "basic" ? Data(base64Encoded: String(parts![1])) : nil
            guard let supplied, constantTimeEqual(supplied, expected) else {
                var response = HTTPResponse(401, body: Data("Authentication required".utf8))
                response.headers["WWW-Authenticate"] = "Basic realm=\"ScreenTask Mac\", charset=\"UTF-8\""
                return response
            }
        }
        guard request.method == "GET" || request.method == "HEAD" else {
            var response = HTTPResponse(405); response.headers["Allow"] = "GET, HEAD"; return response
        }
        switch request.path {
        case "/", "/index.html": return HTTPResponse(200, type: "text/html; charset=utf-8", body: html)
        case "/stream.mjpg":
            var response = HTTPResponse(200, type: MJPEG.contentType)
            response.streaming = true
            return response
        case "/ScreenTask.jpg", "/frame.jpg":
            guard let jpeg else { return HTTPResponse(503, body: Data("Waiting for screen capture".utf8)) }
            return HTTPResponse(200, type: "image/jpeg", body: jpeg)
        default: return HTTPResponse(404)
        }
    }
}

private func constantTimeEqual(_ a: Data, _ b: Data) -> Bool {
    guard a.count == b.count else { return false }
    var diff: UInt8 = 0
    for (x,y) in zip(a,b) { diff |= x ^ y }
    return diff == 0
}

/// IPv4 subnet comparison, used with the selected interface's real netmask.
public enum LANScope {
    public static func ipv4(_ value: String) -> UInt32? {
        let parts = value.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return nil }
        var number: UInt32 = 0
        for part in parts {
            guard !part.isEmpty, part.allSatisfy({ $0.isASCII && $0.isNumber }), let byte = UInt8(part) else { return nil }
            number = number << 8 | UInt32(byte)
        }
        return number
    }
    public static func allows(peer: String, address: String, mask: String, publicAccess: Bool) -> Bool {
        guard let peer = ipv4(peer), let address = ipv4(address), let mask = ipv4(mask) else { return false }
        return publicAccess || (peer & mask) == (address & mask)
    }
}
