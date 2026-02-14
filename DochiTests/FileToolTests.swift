import XCTest
@testable import Dochi

@MainActor
final class FileToolTests: XCTestCase {

    private var tempDir: String!

    override func setUp() {
        super.setUp()
        // Must be inside home directory (path validation blocks outside ~/)
        tempDir = NSHomeDirectory() + "/.DochiFileToolTests_\(UUID().uuidString)"
        try? FileManager.default.createDirectory(atPath: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(atPath: tempDir)
        super.tearDown()
    }

    // MARK: - Tool Properties

    func testToolNames() {
        XCTAssertEqual(FileReadTool().name, "file.read")
        XCTAssertEqual(FileWriteTool().name, "file.write")
        XCTAssertEqual(FileListTool().name, "file.list")
        XCTAssertEqual(FileSearchTool().name, "file.search")
        XCTAssertEqual(FileMoveTool().name, "file.move")
        XCTAssertEqual(FileCopyTool().name, "file.copy")
        XCTAssertEqual(FileDeleteTool().name, "file.delete")
    }

    func testToolCategories() {
        XCTAssertEqual(FileReadTool().category, .safe)
        XCTAssertEqual(FileWriteTool().category, .sensitive)
        XCTAssertEqual(FileListTool().category, .safe)
        XCTAssertEqual(FileSearchTool().category, .safe)
        XCTAssertEqual(FileMoveTool().category, .sensitive)
        XCTAssertEqual(FileCopyTool().category, .sensitive)
        XCTAssertEqual(FileDeleteTool().category, .restricted)
    }

    func testAllToolsAreNonBaseline() {
        XCTAssertFalse(FileReadTool().isBaseline)
        XCTAssertFalse(FileWriteTool().isBaseline)
        XCTAssertFalse(FileListTool().isBaseline)
        XCTAssertFalse(FileSearchTool().isBaseline)
        XCTAssertFalse(FileMoveTool().isBaseline)
        XCTAssertFalse(FileCopyTool().isBaseline)
        XCTAssertFalse(FileDeleteTool().isBaseline)
    }

    // MARK: - file.read

    func testReadMissingPath() async {
        let result = await FileReadTool().execute(arguments: [:])
        XCTAssertTrue(result.isError)
    }

    func testReadNonexistentFile() async {
        let result = await FileReadTool().execute(arguments: ["path": tempDir + "/nonexistent.txt"])
        XCTAssertTrue(result.isError)
        XCTAssertTrue(result.content.contains("찾을 수 없습니다"))
    }

    func testReadTextFile() async {
        let filePath = tempDir + "/test.txt"
        try! "안녕하세요".write(toFile: filePath, atomically: true, encoding: .utf8)

        let result = await FileReadTool().execute(arguments: ["path": filePath])
        XCTAssertFalse(result.isError)
        XCTAssertTrue(result.content.contains("안녕하세요"))
    }

    // MARK: - file.write

    func testWriteMissingPath() async {
        let result = await FileWriteTool().execute(arguments: ["content": "test"])
        XCTAssertTrue(result.isError)
    }

    func testWriteMissingContent() async {
        let result = await FileWriteTool().execute(arguments: ["path": tempDir + "/out.txt"])
        XCTAssertTrue(result.isError)
    }

    func testWriteCreatesFile() async {
        let filePath = tempDir + "/new_file.txt"
        let result = await FileWriteTool().execute(arguments: ["path": filePath, "content": "테스트 내용"])
        XCTAssertFalse(result.isError)
        XCTAssertTrue(FileManager.default.fileExists(atPath: filePath))

        let content = try! String(contentsOfFile: filePath, encoding: .utf8)
        XCTAssertEqual(content, "테스트 내용")
    }

    func testWriteCreatesParentDirectories() async {
        let filePath = tempDir + "/sub/dir/file.txt"
        let result = await FileWriteTool().execute(arguments: ["path": filePath, "content": "nested"])
        XCTAssertFalse(result.isError)
        XCTAssertTrue(FileManager.default.fileExists(atPath: filePath))
    }

    // MARK: - file.list

    func testListMissingPath() async {
        let result = await FileListTool().execute(arguments: [:])
        XCTAssertTrue(result.isError)
    }

    func testListNonexistentDir() async {
        let result = await FileListTool().execute(arguments: ["path": tempDir + "/nonexistent"])
        XCTAssertTrue(result.isError)
    }

    func testListDirectory() async {
        try! "a".write(toFile: tempDir + "/file_a.txt", atomically: true, encoding: .utf8)
        try! "b".write(toFile: tempDir + "/file_b.txt", atomically: true, encoding: .utf8)
        try! FileManager.default.createDirectory(atPath: tempDir + "/subdir", withIntermediateDirectories: true)

        let result = await FileListTool().execute(arguments: ["path": tempDir])
        XCTAssertFalse(result.isError)
        XCTAssertTrue(result.content.contains("file_a.txt"))
        XCTAssertTrue(result.content.contains("file_b.txt"))
        XCTAssertTrue(result.content.contains("subdir/"))
        XCTAssertTrue(result.content.contains("3개"))
    }

    func testListHiddenFiles() async {
        try! "hidden".write(toFile: tempDir + "/.hidden", atomically: true, encoding: .utf8)
        try! "visible".write(toFile: tempDir + "/visible.txt", atomically: true, encoding: .utf8)

        // Without show_hidden
        let result1 = await FileListTool().execute(arguments: ["path": tempDir])
        XCTAssertFalse(result1.content.contains(".hidden"))
        XCTAssertTrue(result1.content.contains("visible.txt"))

        // With show_hidden
        let result2 = await FileListTool().execute(arguments: ["path": tempDir, "show_hidden": true])
        XCTAssertTrue(result2.content.contains(".hidden"))
    }

    // MARK: - file.search

    func testSearchMissingPattern() async {
        let result = await FileSearchTool().execute(arguments: ["path": tempDir])
        XCTAssertTrue(result.isError)
    }

    func testSearchFindsFiles() async {
        try! "a".write(toFile: tempDir + "/report.txt", atomically: true, encoding: .utf8)
        try! "b".write(toFile: tempDir + "/report.csv", atomically: true, encoding: .utf8)
        try! "c".write(toFile: tempDir + "/other.txt", atomically: true, encoding: .utf8)

        let result = await FileSearchTool().execute(arguments: ["path": tempDir, "pattern": "report*"])
        XCTAssertFalse(result.isError)
        XCTAssertTrue(result.content.contains("report.txt"))
        XCTAssertTrue(result.content.contains("report.csv"))
        XCTAssertFalse(result.content.contains("other.txt"))
    }

    func testSearchNoMatches() async {
        try! "a".write(toFile: tempDir + "/test.txt", atomically: true, encoding: .utf8)

        let result = await FileSearchTool().execute(arguments: ["path": tempDir, "pattern": "*.pdf"])
        XCTAssertFalse(result.isError)
        XCTAssertTrue(result.content.contains("일치하는 파일이 없습니다"))
    }

    // MARK: - file.move

    func testMoveMissingSource() async {
        let result = await FileMoveTool().execute(arguments: ["destination": tempDir + "/dst.txt"])
        XCTAssertTrue(result.isError)
    }

    func testMoveFile() async {
        let src = tempDir + "/move_src.txt"
        let dst = tempDir + "/move_dst.txt"
        try! "move me".write(toFile: src, atomically: true, encoding: .utf8)

        let result = await FileMoveTool().execute(arguments: ["source": src, "destination": dst])
        XCTAssertFalse(result.isError)
        XCTAssertFalse(FileManager.default.fileExists(atPath: src))
        XCTAssertTrue(FileManager.default.fileExists(atPath: dst))
    }

    func testMoveNonexistentSource() async {
        let result = await FileMoveTool().execute(arguments: [
            "source": tempDir + "/nonexistent.txt",
            "destination": tempDir + "/dst.txt",
        ])
        XCTAssertTrue(result.isError)
    }

    // MARK: - file.copy

    func testCopyFile() async {
        let src = tempDir + "/copy_src.txt"
        let dst = tempDir + "/copy_dst.txt"
        try! "copy me".write(toFile: src, atomically: true, encoding: .utf8)

        let result = await FileCopyTool().execute(arguments: ["source": src, "destination": dst])
        XCTAssertFalse(result.isError)
        XCTAssertTrue(FileManager.default.fileExists(atPath: src))
        XCTAssertTrue(FileManager.default.fileExists(atPath: dst))

        let content = try! String(contentsOfFile: dst, encoding: .utf8)
        XCTAssertEqual(content, "copy me")
    }

    func testCopyNonexistentSource() async {
        let result = await FileCopyTool().execute(arguments: [
            "source": tempDir + "/nonexistent.txt",
            "destination": tempDir + "/dst.txt",
        ])
        XCTAssertTrue(result.isError)
    }

    // MARK: - file.delete

    func testDeleteMissingPath() async {
        let result = await FileDeleteTool().execute(arguments: [:])
        XCTAssertTrue(result.isError)
    }

    func testDeleteFile() async {
        let filePath = tempDir + "/delete_me.txt"
        try! "bye".write(toFile: filePath, atomically: true, encoding: .utf8)

        let result = await FileDeleteTool().execute(arguments: ["path": filePath])
        XCTAssertFalse(result.isError)
        XCTAssertFalse(FileManager.default.fileExists(atPath: filePath))
    }

    func testDeleteNonexistentFile() async {
        let result = await FileDeleteTool().execute(arguments: ["path": tempDir + "/nonexistent.txt"])
        XCTAssertTrue(result.isError)
    }

    func testDeleteHomeDirectoryBlocked() async {
        let result = await FileDeleteTool().execute(arguments: ["path": NSHomeDirectory()])
        XCTAssertTrue(result.isError)
        XCTAssertTrue(result.content.contains("홈 디렉토리"))
    }

    // MARK: - Path Traversal Prevention

    func testReadOutsideHomeBlocked() async {
        let result = await FileReadTool().execute(arguments: ["path": "/etc/passwd"])
        XCTAssertTrue(result.isError)
        XCTAssertTrue(result.content.contains("홈 디렉토리 밖"))
    }

    func testWriteOutsideHomeBlocked() async {
        let result = await FileWriteTool().execute(arguments: ["path": "/tmp/evil.txt", "content": "hack"])
        XCTAssertTrue(result.isError)
        XCTAssertTrue(result.content.contains("홈 디렉토리 밖"))
    }

    func testDeleteOutsideHomeBlocked() async {
        let result = await FileDeleteTool().execute(arguments: ["path": "/etc/hosts"])
        XCTAssertTrue(result.isError)
        XCTAssertTrue(result.content.contains("홈 디렉토리 밖"))
    }

    // MARK: - Registry Integration

    func testFileToolsAreNonBaseline() {
        let registry = ToolRegistry()
        registry.register(FileReadTool())
        registry.register(FileWriteTool())
        registry.register(FileDeleteTool())

        XCTAssertTrue(registry.baselineTools.isEmpty)
    }

    func testFileToolsAvailableAfterEnable() {
        let registry = ToolRegistry()
        registry.register(FileReadTool())
        registry.register(FileWriteTool())
        registry.register(FileDeleteTool())

        registry.enable(names: ["file.read", "file.write", "file.delete"])
        let available = registry.availableTools(for: ["safe", "sensitive", "restricted"])
        XCTAssertEqual(available.count, 3)
    }
}
