import XCTest
import CodexRouterCore

final class CDPProbeURLsTests: XCTestCase {

    func test_probeURLs_ipv4First() {
        let urls = CDPProbeURLs(port: 9222)
        XCTAssertEqual(urls.first, "http://127.0.0.1:9222/json")
    }

    func test_probeURLs_orderIsIPv4ThenLocalhostThenIPv6() {
        let urls = CDPProbeURLs(port: 9222)
        XCTAssertEqual(urls, [
            "http://127.0.0.1:9222/json",
            "http://localhost:9222/json",
            "http://[::1]:9222/json",
        ])
    }

    func test_probeURLs_customPort() {
        let urls = CDPProbeURLs(port: 9333)
        XCTAssertEqual(urls.first, "http://127.0.0.1:9333/json")
    }
}

final class CDPOriginHeaderTests: XCTestCase {

    func test_originHeader_fromIPv4WSURL() {
        let url = URL(string: "ws://127.0.0.1:9222/devtools/page/ABC")!
        XCTAssertEqual(CDPOriginHeader(for: url), "http://127.0.0.1:9222")
    }

    func test_originHeader_fromLocalhostWSURL() {
        let url = URL(string: "ws://localhost:9222/devtools/page/ABC")!
        XCTAssertEqual(CDPOriginHeader(for: url), "http://localhost:9222")
    }

    func test_originHeader_fromIPv6WSURL() {
        let url = URL(string: "ws://[::1]:9222/devtools/page/ABC")!
        XCTAssertEqual(CDPOriginHeader(for: url), "http://[::1]:9222")
    }

    func test_originHeader_nilForInvalidURL() {
        XCTAssertNil(CDPOriginHeader(for: URL(string: "not-a-url")!))
    }
}
