import Foundation
import UIKit
import Capacitor
/**
 * Please read the Capacitor iOS Plugin Development Guide
 * here: https://capacitorjs.com/docs/plugins/ios
 */
@objc(FileOpenerPlugin)
public class FileOpenerPlugin: CAPPlugin, UIDocumentInteractionControllerDelegate, CAPBridgedPlugin {
    public let identifier = "FileOpenerPlugin"
    public let jsName = "FileOpener"
    public let pluginMethods: [CAPPluginMethod] = [
        .async("open", FileOpenerPlugin.open)
    ]

    var documentInteractionController: UIDocumentInteractionController!
    /// Answers the `open` call whose preview is on screen when the preview ends.
    private var previewEnd: OnceContinuation<Bool>?

    /// Presents the file in a preview or an "Open in" menu, which is UIKit: the method runs on the main actor. With
    /// `openWithDefault`, the default, it returns when the preview ends; otherwise once the menu is presented.
    @MainActor
    func open(_ call: CAPPluginCall) async throws {
        guard self.bridge != nil else {
            throw CAPPluginError("Internal error. Bridge not found!", code: "1")
        }
        guard let filePath = call.options["filePath"] as? String else {
            throw CAPPluginError("Must provide a filePath", code: "2")
        }
        let contentType = call.getString("contentType")
        let openWithDefault = call.getBool("openWithDefault") ?? true

        guard let fileURL = FileOpenerPlugin.fileURL(from: filePath),
              FileManager.default.fileExists(atPath: fileURL.path) else {
            throw CAPPluginError("File does not exist", code: "9")
        }
        let uti = try FileOpenerPlugin.uti(of: fileURL, contentType: contentType)

        let controller = UIDocumentInteractionController(url: fileURL)
        controller.uti = uti
        controller.delegate = self
        self.documentInteractionController = controller

        if openWithDefault {
            try await presentPreview(with: controller)
        } else {
            let chooserPosition = call.options["chooserPosition"] as? JSObject
            try presentOpenInMenu(with: controller, for: fileURL, chooserPosition: chooserPosition)
        }
    }

    /// Presents the preview and returns when it ends, or throws when UIKit does not present it.
    @MainActor
    private func presentPreview(with controller: UIDocumentInteractionController) async throws {
        let presented = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            // Released without an answer, for example when a later preview takes its place, it resumes with true:
            // that preview can no longer report its end.
            let end = OnceContinuation(continuation, fallback: true)
            guard controller.presentPreview(animated: true) else {
                end.resume(returning: false)
                return
            }
            previewEnd = end
        }
        if !presented {
            throw CAPPluginError("Failed to open the file preview", code: "8")
        }
    }

    @MainActor
    private func presentOpenInMenu(with controller: UIDocumentInteractionController, for fileURL: URL,
                                   chooserPosition: JSObject?) throws {
        guard let view = self.bridge?.viewController?.view else {
            throw CAPPluginError("Internal error. View not found!", code: "1")
        }
        let wasOpened: Bool
        if UIDevice.current.userInterfaceIdiom == .pad {
            if let positionX = chooserPosition?["x"] as? Float, let positionY = chooserPosition?["y"] as? Float {
                let rect = CGRect(x: 0, y: 0, width: CGFloat(positionX), height: CGFloat(positionY))
                wasOpened = controller.presentOpenInMenu(from: rect, in: view, animated: true)
            } else {
                let activityViewController = UIActivityViewController(activityItems: [fileURL],
                                                                      applicationActivities: nil)
                if let popover = activityViewController.popoverPresentationController {
                    popover.permittedArrowDirections = UIPopoverArrowDirection(rawValue: 0)
                    popover.sourceView = view
                    popover.sourceRect = CGRect(x: view.frame.midX, y: view.frame.midY, width: 0, height: 0)
                }
                self.bridge?.viewController?.present(activityViewController, animated: true, completion: nil)
                wasOpened = true
            }
        } else {
            let rect = CGRect(x: 0, y: 0, width: view.frame.width, height: view.frame.height)
            wasOpened = controller.presentOpenInMenu(from: rect, in: view, animated: true)
        }
        if !wasOpened {
            throw CAPPluginError("Failed to open the file preview", code: "8")
        }
    }

    /// The URL of `filePath`: a path or a `file://` URL, or a percent-encoded URL. Nil when it is not a valid URL.
    static func fileURL(from filePath: String) -> URL? {
        if filePath == filePath.removingPercentEncoding {
            return URL(fileURLWithPath: filePath.replacingOccurrences(of: "file://", with: ""))
        }
        return URL(string: filePath)
    }

    /// The uniform type identifier of the file: the one of `contentType` when given, else the one of its extension.
    static func uti(of fileURL: URL, contentType: String?) throws -> String {
        let uti: String?
        if let mime = contentType, !mime.isEmpty {
            uti = MimeTypeConverter.mimeToUti(mime)
        } else {
            if fileURL.pathExtension.isEmpty {
                throw CAPPluginError("Failed to determine the file type because extension is missing", code: "2")
            }
            uti = MimeTypeConverter.fileExtensionToUti(fileURL.pathExtension)
        }
        guard let uti else {
            throw CAPPluginError("Failed to determine type of the file to open", code: "10")
        }
        return uti
    }

    public func documentInteractionControllerViewControllerForPreview(
        _ controller: UIDocumentInteractionController
    ) -> UIViewController {
        var presentingViewController = bridge?.viewController
        while let presented = presentingViewController?.presentedViewController {
            presentingViewController = presented
        }
        return presentingViewController!
    }

    public func documentInteractionControllerDidEndPreview(_ controller: UIDocumentInteractionController) {
        previewEnd?.resume(returning: true)
        previewEnd = nil
    }
}
