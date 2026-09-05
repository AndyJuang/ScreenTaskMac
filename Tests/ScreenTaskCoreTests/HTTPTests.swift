import Foundation
import ScreenTaskCore
final class HTTPTests {
    func request(_ path: String = "/", method: String = "GET", headers: String = "") -> HTTPRequest {
        HTTPRequest(Data("\(method) \(path) HTTP/1.1\r\nHost: localhost\r\n\(headers)\r\n".utf8))!
    }
    func testRoutesAndFrameAvailability() {
        let router = Router(html: Data("viewer".utf8))
        XCTAssertEqual(router.response(to: request(), jpeg: nil).body, Data("viewer".utf8))
        XCTAssertEqual(router.response(to: request("/ScreenTask.jpg?t=1"), jpeg: nil).status, 503)
        let jpeg = Data([0xff, 0xd8, 0xff, 0xd9])
        XCTAssertEqual(router.response(to: request("/ScreenTask.jpg"), jpeg: jpeg).body, jpeg)
        for path in ["/../etc/passwd", "/%2e%2e/secret", "/settings.json", "/missing"] {
            XCTAssertEqual(router.response(to: request(path), jpeg: jpeg).status, 404)
        }
        XCTAssertEqual(router.response(to: request(method: "POST"), jpeg: jpeg).status, 405)
    }
    func testAuthenticationProtectsEveryRoute() {
        let router = Router(html: Data(), username: "名字", password: "密碼:more")
        for path in ["/", "/index.html", "/ScreenTask.jpg", "/frame.jpg", "/unknown"] {
            for bad in ["", "Authorization: Basic !!!\r\n", "Authorization: Bearer xxx\r\n", "Authorization: Basic \(Data("名字:wrong".utf8).base64EncodedString())\r\n"] {
                let result = router.response(to: request(path, headers: bad), jpeg: Data())
                XCTAssertEqual(result.status, 401)
                XCTAssertNotNil(result.headers["WWW-Authenticate"])
            }
        }
        let valid = "aUtHoRiZaTiOn: bAsIc \(Data("名字:密碼:more".utf8).base64EncodedString())\r\n"
        XCTAssertEqual(router.response(to: request(headers: valid), jpeg: nil).status, 200)
    }
    func testMalformedRequestsAreRejected() {
        for raw in ["GET / HTTP/1.1\r\n", "GET / BAD\r\n\r\n", "GET / HTTP/1.1\r\nInvalid\r\n\r\n", "GET / HTTP/1.1\r\nAuthorization: a\r\nauthorization: b\r\n\r\n", String(repeating: "a", count: 17000) + "\r\n\r\n"] {
            XCTAssertNil(HTTPRequest(Data(raw.utf8)))
        }
    }
    func testResponseFramingAndHead() {
        let response = HTTPResponse(200, type: "image/jpeg", body: Data([1,2,3]))
        let header = String(data: response.encoded(headOnly: true), encoding: .utf8)!
        XCTAssertTrue(header.contains("Content-Length: 3\r\n"))
        XCTAssertTrue(header.contains("Cache-Control: no-store"))
        XCTAssertTrue(response.encoded().suffix(3) == Data([1,2,3]))
        XCTAssertEqual(response.encoded().count, response.encoded(headOnly: true).count + 3)
    }
    func testSubnetRestrictionAndExplicitPublicMode() {
        XCTAssertTrue(LANScope.allows(peer: "192.168.1.20", address: "192.168.1.10", mask: "255.255.255.0", publicAccess: false))
        XCTAssertFalse(LANScope.allows(peer: "192.168.2.20", address: "192.168.1.10", mask: "255.255.255.0", publicAccess: false))
        XCTAssertFalse(LANScope.allows(peer: "8.8.8.8", address: "192.168.1.10", mask: "255.255.255.0", publicAccess: false))
        XCTAssertTrue(LANScope.allows(peer: "8.8.8.8", address: "192.168.1.10", mask: "255.255.255.0", publicAccess: true))
        XCTAssertFalse(LANScope.allows(peer: "bad", address: "192.168.1.10", mask: "255.255.255.0", publicAccess: true))
        XCTAssertNil(LANScope.ipv4("999.1.2.3"))
        XCTAssertNil(LANScope.ipv4("1..2.3"))
    }
}

func XCTAssertTrue(_ value: Bool, file: StaticString = #file, line: UInt = #line) { precondition(value, "Expected true", file: file, line: line) }
func XCTAssertFalse(_ value: Bool, file: StaticString = #file, line: UInt = #line) { precondition(!value, "Expected false", file: file, line: line) }
func XCTAssertEqual<T: Equatable>(_ a: T, _ b: T, file: StaticString = #file, line: UInt = #line) { precondition(a == b, "Values differ: \(a), \(b)", file: file, line: line) }
func XCTAssertNil<T>(_ value: T?, file: StaticString = #file, line: UInt = #line) { precondition(value == nil, "Expected nil", file: file, line: line) }
func XCTAssertNotNil<T>(_ value: T?, file: StaticString = #file, line: UInt = #line) { precondition(value != nil, "Expected non-nil", file: file, line: line) }
@main enum TestRunner {
 static func main() {
  let tests = HTTPTests()
  tests.testRoutesAndFrameAvailability()
  tests.testAuthenticationProtectsEveryRoute()
  tests.testMalformedRequestsAreRejected()
  tests.testResponseFramingAndHead()
  tests.testSubnetRestrictionAndExplicitPublicMode()
  print("All tests passed: 5 regression groups")
 }
}
