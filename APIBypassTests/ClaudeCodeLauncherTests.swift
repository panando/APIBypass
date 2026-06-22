import XCTest
@testable import APIBypass

final class ClaudeCodeLauncherTests: XCTestCase {

    // MARK: - Fake FileSystem

    private struct FakeFileSystem: FileSystem {
        let existingPaths: Set<String>
        let directoryContents: [String: [String]]

        func fileExists(atPath path: String) -> Bool {
            existingPaths.contains(path)
        }

        func contentsOfDirectory(atPath path: String) throws -> [String] {
            guard let contents = directoryContents[path] else {
                throw NSError(domain: NSCocoaErrorDomain, code: NSFileReadNoSuchFileError)
            }
            return contents
        }
    }

    private let home = "/Users/test"

    // MARK: - Native Install (~/.local/bin/claude)

    func testFindsClaudeViaNativeInstall() {
        let fs = FakeFileSystem(
            existingPaths: ["\(home)/.local/bin/claude"],
            directoryContents: [:]
        )
        let result = ClaudeCodeLauncher.findClaudeInCommonLocations(fs: fs, home: home)
        XCTAssertEqual(result, "\(home)/.local/bin/claude")
    }

    // MARK: - Homebrew

    func testFindsClaudeViaHomebrewAppleSilicon() {
        let fs = FakeFileSystem(
            existingPaths: ["/opt/homebrew/bin/claude"],
            directoryContents: [:]
        )
        let result = ClaudeCodeLauncher.findClaudeInCommonLocations(fs: fs, home: home)
        XCTAssertEqual(result, "/opt/homebrew/bin/claude")
    }

    func testFindsClaudeViaHomebrewIntel() {
        let fs = FakeFileSystem(
            existingPaths: ["/usr/local/bin/claude"],
            directoryContents: [:]
        )
        let result = ClaudeCodeLauncher.findClaudeInCommonLocations(fs: fs, home: home)
        XCTAssertEqual(result, "/usr/local/bin/claude")
    }

    // MARK: - nvm (npm install)

    func testFindsClaudeViaNvm() {
        let fs = FakeFileSystem(
            existingPaths: ["\(home)/.nvm/versions/node/v22.1.0/bin/claude"],
            directoryContents: ["\(home)/.nvm/versions/node": ["v22.1.0", "v20.10.0"]]
        )
        let result = ClaudeCodeLauncher.findClaudeInCommonLocations(fs: fs, home: home)
        XCTAssertEqual(result, "\(home)/.nvm/versions/node/v22.1.0/bin/claude")
    }

    // MARK: - fnm (npm install)

    func testFindsClaudeViaFnm() {
        let fs = FakeFileSystem(
            existingPaths: ["\(home)/Library/Application Support/fnm/node-versions/v22.1.0/installation/bin/claude"],
            directoryContents: [
                "\(home)/Library/Application Support/fnm/node-versions": ["v22.1.0"]
            ]
        )
        let result = ClaudeCodeLauncher.findClaudeInCommonLocations(fs: fs, home: home)
        XCTAssertEqual(result, "\(home)/Library/Application Support/fnm/node-versions/v22.1.0/installation/bin/claude")
    }

    // MARK: - Volta (npm install)

    func testFindsClaudeViaVolta() {
        let fs = FakeFileSystem(
            existingPaths: ["\(home)/.volta/bin/claude"],
            directoryContents: [:]
        )
        let result = ClaudeCodeLauncher.findClaudeInCommonLocations(fs: fs, home: home)
        XCTAssertEqual(result, "\(home)/.volta/bin/claude")
    }

    // MARK: - Homebrew Cask (Claude.app)

    func testFindsClaudeViaHomebrewCask() {
        let fs = FakeFileSystem(
            existingPaths: [],
            directoryContents: ["/Applications/Claude.app/Contents/MacOS": ["claude"]]
        )
        let result = ClaudeCodeLauncher.findClaudeInCommonLocations(fs: fs, home: home)
        XCTAssertEqual(result, "/Applications/Claude.app/Contents/MacOS/claude")
    }

    func testFindsClaudeViaHomebrewCaskInUserApplications() {
        let fs = FakeFileSystem(
            existingPaths: [],
            directoryContents: ["\(home)/Applications/Claude.app/Contents/MacOS": ["claude"]]
        )
        let result = ClaudeCodeLauncher.findClaudeInCommonLocations(fs: fs, home: home)
        XCTAssertEqual(result, "\(home)/Applications/Claude.app/Contents/MacOS/claude")
    }

    // MARK: - Not Found

    func testReturnsNilWhenClaudeNotFound() {
        let fs = FakeFileSystem(existingPaths: [], directoryContents: [:])
        let result = ClaudeCodeLauncher.findClaudeInCommonLocations(fs: fs, home: home)
        XCTAssertNil(result)
    }

    // MARK: - Priority

    func testNativeInstallTakesPriorityOverHomebrew() {
        let fs = FakeFileSystem(
            existingPaths: [
                "\(home)/.local/bin/claude",
                "/opt/homebrew/bin/claude"
            ],
            directoryContents: [:]
        )
        let result = ClaudeCodeLauncher.findClaudeInCommonLocations(fs: fs, home: home)
        XCTAssertEqual(result, "\(home)/.local/bin/claude")
    }

    // MARK: - ~/.claude/bin (auto-updater / desktop app CLI)

    func testFindsClaudeViaClaudeBinDir() {
        let fs = FakeFileSystem(
            existingPaths: ["\(home)/.claude/bin/claude"],
            directoryContents: [:]
        )
        let result = ClaudeCodeLauncher.findClaudeInCommonLocations(fs: fs, home: home)
        XCTAssertEqual(result, "\(home)/.claude/bin/claude")
    }
}
