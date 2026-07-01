import Foundation
import AVFoundation
import Display
import SwiftSignalKit
import TelegramCore
import AccountContext
import OverlayStatusController
import LegacyMediaPickerUI
import SaveToCameraRoll
import PresentationDataUtils

private func sanitizedExportFileNameComponent(_ value: String) -> String {
    var result = ""
    for scalar in value.trimmingCharacters(in: .whitespacesAndNewlines).unicodeScalars {
        switch scalar.value {
        case 0, 47, 58, 92:
            result.append("_")
        default:
            result.append(String(scalar))
        }
    }
    if result == "." || result == ".." {
        return "_"
    } else if result.hasPrefix("..") {
        result = "__" + String(result.dropFirst(2))
    }
    if result.count > 120 {
        result = String(result.prefix(120))
    }
    return result.isEmpty ? "_" : result
}

private func linkExportFile(sourcePath: String, targetPath: String) -> Bool {
    try? FileManager.default.removeItem(atPath: targetPath)
    do {
        try FileManager.default.linkItem(atPath: sourcePath, toPath: targetPath)
        return true
    } catch {
        return false
    }
}

func saveMediaToFiles(context: AccountContext, fileReference: FileMediaReference, present: @escaping (ViewController, Any?) -> Void) -> Disposable {
    var title: String?
    var performer: String?
    for attribute in fileReference.media.attributes {
        if case let .Audio(_, _, titleValue, performerValue, _) = attribute {
            if let titleValue, !titleValue.isEmpty {
                title = titleValue
            }
            if let performerValue, !performerValue.isEmpty {
                performer = performerValue
            }
        }
    }
    
    var signal = fetchMediaData(context: context, userLocation: .other, mediaReference: fileReference.abstract)
    
    var cancelImpl: (() -> Void)?
    let presentationData = context.sharedContext.currentPresentationData.with { $0 }
    let progressSignal = Signal<Never, NoError> { subscriber in
        let controller = OverlayStatusController(theme: presentationData.theme, type: .loading(cancelled: {
            cancelImpl?()
        }))
        present(controller, ViewControllerPresentationArguments(presentationAnimation: .modalSheet))
        return ActionDisposable { [weak controller] in
            Queue.mainQueue().async() {
                controller?.dismiss()
            }
        }
    }
    |> runOn(Queue.mainQueue())
    |> delay(0.15, queue: Queue.mainQueue())
    
    let progressDisposable = progressSignal.startStrict()
    
    let disposable = MetaDisposable()
    signal = signal
    |> afterDisposed {
        Queue.mainQueue().async {
            progressDisposable.dispose()
        }
    }
    cancelImpl = { [weak disposable] in
        disposable?.set(nil)
    }
    disposable.set((signal
    |> deliverOnMainQueue).startStrict(next: { state, _ in
        switch state {
        case .progress:
            break
        case let .data(data):
            if data.isComplete {
                var symlinkPath = data.path + ".mp3"
                if !linkExportFile(sourcePath: data.path, targetPath: symlinkPath) {
                    symlinkPath = data.path
                }
                
                let audioUrl = URL(fileURLWithPath: symlinkPath)
                let audioAsset = AVURLAsset(url: audioUrl)
                
                var fileExtension = "mp3"
                if let filename = fileReference.media.fileName {
                    if let dotIndex = filename.lastIndex(of: ".") {
                        fileExtension = String(filename[filename.index(after: dotIndex)...])
                    }
                }
                
                var nameComponents: [String] = []
                if let title {
                    if let performer {
                        nameComponents.append(performer)
                    }
                    nameComponents.append(title)
                } else {
                    var artist: String?
                    var title: String?
                    for data in audioAsset.commonMetadata {
                        if data.commonKey == .commonKeyArtist {
                            artist = data.stringValue
                        }
                        if data.commonKey == .commonKeyTitle {
                            title = data.stringValue
                        }
                    }
                    if let artist, !artist.isEmpty {
                        nameComponents.append(artist)
                    }
                    if let title, !title.isEmpty {
                        nameComponents.append(title)
                    }
                    if nameComponents.isEmpty, var filename = fileReference.media.fileName {
                        if let dotIndex = filename.lastIndex(of: ".") {
                            filename = String(filename[..<dotIndex])
                        }
                        nameComponents.append(filename)
                    }
                }
                if !nameComponents.isEmpty {
                    let sanitizedNameComponents = nameComponents.map(sanitizedExportFileNameComponent)
                    let sanitizedExtension = sanitizedExportFileNameComponent(fileExtension)
                    let fileName = "\(sanitizedNameComponents.joined(separator: " – ")).\(sanitizedExtension)"
                    let updatedSymlinkPath = audioUrl.deletingLastPathComponent().appendingPathComponent(fileName).path
                    if updatedSymlinkPath != symlinkPath && linkExportFile(sourcePath: data.path, targetPath: updatedSymlinkPath) {
                        symlinkPath = updatedSymlinkPath
                    }
                }
                
                let url = URL(fileURLWithPath: symlinkPath)
                let controller = legacyICloudFilePicker(theme: presentationData.theme, mode: .export, url: url, documentTypes: [], forceDarkTheme: false, dismissed: {}, completion: { _ in
                    
                })
                present(controller, nil)
            }
        }
    }))
    
    return disposable
}
