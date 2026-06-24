import XCTest
@testable import APIBypass

final class CDPDiagnosticsTests: XCTestCase {

    // MARK: - formatDiagnosticLogLine

    func test_formatDiagnosticLogLine_basicEventWithDetail() {
        let line = CodexRequestHandler.formatDiagnosticLogLine(
            event: "statsig_patch_installed",
            detail: ["clientCount": 1]
        )
        XCTAssertEqual(line, #"[CDP] statsig_patch_installed {"clientCount":1}"#)
    }

    func test_formatDiagnosticLogLine_emptyDetail() {
        let line = CodexRequestHandler.formatDiagnosticLogLine(
            event: "script_loaded",
            detail: [:]
        )
        XCTAssertEqual(line, #"[CDP] script_loaded {}"#)
    }

    func test_formatDiagnosticLogLine_multipleDetailKeys() {
        let line = CodexRequestHandler.formatDiagnosticLogLine(
            event: "appserver_request_patch_not_found",
            detail: ["exportCount": 0, "candidateCount": 0]
        )
        // JSONSerialization sorts keys alphabetically
        XCTAssertEqual(line, #"[CDP] appserver_request_patch_not_found {"candidateCount":0,"exportCount":0}"#)
    }

    func test_formatDiagnosticLogLine_stringDetailValue() {
        let line = CodexRequestHandler.formatDiagnosticLogLine(
            event: "catalog_failed",
            detail: ["error": "network timeout"]
        )
        XCTAssertEqual(line, #"[CDP] catalog_failed {"error":"network timeout"}"#)
    }

    func test_formatDiagnosticLogLine_nonSerializableDetail_fallsBackToEmptyBraces() {
        // JSONSerialization rejects Date objects by default
        let line = CodexRequestHandler.formatDiagnosticLogLine(
            event: "weird_event",
            detail: ["bad": Date()]
        )
        XCTAssertEqual(line, #"[CDP] weird_event {}"#)
    }

    // MARK: - diagnosticLogLevel

    func test_diagnosticLogLevel_failedSuffix_returnsError() {
        XCTAssertEqual(CodexRequestHandler.diagnosticLogLevel(for: "catalog_failed"), .error)
        XCTAssertEqual(CodexRequestHandler.diagnosticLogLevel(for: "statsig_patch_failed"), .error)
        XCTAssertEqual(CodexRequestHandler.diagnosticLogLevel(for: "appserver_request_patch_failed"), .error)
    }

    func test_diagnosticLogLevel_notFoundSuffix_returnsInfo() {
        XCTAssertEqual(CodexRequestHandler.diagnosticLogLevel(for: "appserver_request_patch_not_found"), .info)
    }

    func test_diagnosticLogLevel_installedSuffix_returnsInfo() {
        XCTAssertEqual(CodexRequestHandler.diagnosticLogLevel(for: "statsig_patch_installed"), .info)
        XCTAssertEqual(CodexRequestHandler.diagnosticLogLevel(for: "script_loaded"), .info)
        XCTAssertEqual(CodexRequestHandler.diagnosticLogLevel(for: "model_whitelist_refresh_scheduled"), .info)
    }
}
