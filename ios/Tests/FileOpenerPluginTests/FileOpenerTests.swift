import XCTest
import Capacitor
@testable import FileOpenerPlugin

class FileOpenerTests: XCTestCase {
    func testOpenIsRegisteredAsAPromiseMethod() {
        let plugin = FileOpenerPlugin()

        XCTAssertEqual(["open"], plugin.pluginMethods.map { $0.name })
        XCTAssertEqual([.promise], plugin.pluginMethods.map { $0.returnType })
    }

    @MainActor
    func testOpenWithoutABridgeThrows() async {
        let options: JSObject = ["filePath": "/tmp/file.pdf"]
        let call = CAPPluginCall(callbackId: "test", methodName: "open", options: options, success: { _, _ in
            XCTFail("open answers by returning or throwing")
        }, error: { _ in
            XCTFail("open answers by returning or throwing")
        })

        do {
            try await FileOpenerPlugin().open(call)
            XCTFail("open must throw without a bridge")
        } catch let error as CAPPluginError {
            // The bridge rejects the call with this message and code, as the method did before.
            XCTAssertEqual(error.message, "Internal error. Bridge not found!")
            XCTAssertEqual(error.code, "1")
        } catch {
            XCTFail("unexpected error \(error)")
        }
    }

    func testFileURLAcceptsPathsFileURLsAndPercentEncodedURLs() {
        XCTAssertEqual(FileOpenerPlugin.fileURL(from: "/tmp/a b.pdf")?.path, "/tmp/a b.pdf")
        XCTAssertEqual(FileOpenerPlugin.fileURL(from: "file:///tmp/a.pdf")?.path, "/tmp/a.pdf")
        XCTAssertEqual(FileOpenerPlugin.fileURL(from: "file:///tmp/a%20b.pdf")?.path, "/tmp/a b.pdf")
    }

    func testUTIComesFromTheContentTypeOrTheExtension() throws {
        let pdf = URL(fileURLWithPath: "/tmp/file.pdf")

        XCTAssertEqual(try FileOpenerPlugin.uti(of: pdf, contentType: nil), "com.adobe.pdf")
        XCTAssertEqual(try FileOpenerPlugin.uti(of: pdf, contentType: "image/png"), "public.png")
        let noExtension = URL(fileURLWithPath: "/tmp/file")
        XCTAssertThrowsError(try FileOpenerPlugin.uti(of: noExtension, contentType: "")) { error in
            XCTAssertEqual((error as? CAPPluginError)?.message,
                           "Failed to determine the file type because extension is missing")
            XCTAssertEqual((error as? CAPPluginError)?.code, "2")
        }
    }

    func testOnceContinuationResumesOnceAndWithItsFallbackWhenReleased() async {
        let answered = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            let once = OnceContinuation(continuation, fallback: true)
            XCTAssertTrue(once.resume(returning: false))
            XCTAssertFalse(once.resume(returning: true))
        }
        XCTAssertFalse(answered)

        let released = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            _ = OnceContinuation(continuation, fallback: true)
        }
        XCTAssertTrue(released)
    }
}
