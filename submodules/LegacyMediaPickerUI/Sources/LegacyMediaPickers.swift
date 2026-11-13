// MARK: Swiftgram
import SGSimpleSettings
import Foundation
import UIKit
import LegacyComponents
import SwiftSignalKit
import TelegramCore
import SSignalKit
import Display
import TelegramPresentationData
import DeviceAccess
import AccountContext
import ImageCompression
import MimeTypes
import LocalMediaResources
import LegacyUI
import TextFormat
import Photos

public func guessMimeTypeByFileExtension(_ ext: String) -> String {
    return TGMimeTypeMap.mimeType(forExtension: ext) ?? "application/binary"
}

public func configureLegacyAssetPicker(_ controller: TGMediaAssetsController, context: AccountContext, peer: EngineRawPeer, chatLocation: ChatLocation, captionsEnabled: Bool = true, storeCreatedAssets: Bool = true, showFileTooltip: Bool = false, initialCaption: NSAttributedString, hasSchedule: Bool, presentWebSearch: (() -> Void)?, presentSelectionLimitExceeded: @escaping () -> Void, presentSchedulePicker: @escaping (Bool, @escaping (Int32, Bool) -> Void) -> Void, presentTimerPicker: @escaping (@escaping (Int32) -> Void) -> Void, getCaptionPanelView: @escaping () -> TGCaptionPanelView?) {
    let paintStickersContext = LegacyPaintStickersContext(context: context)
    paintStickersContext.presentMediaPickerSendActionMenu = makeLegacyMediaPickerSendActionMenuPresenter(context: context)
    paintStickersContext.captionPanelView = {
        return getCaptionPanelView()
    }
    
    controller.captionsEnabled = captionsEnabled
    controller.inhibitDocumentCaptions = false
    controller.stickersContext = paintStickersContext
    if peer.id != context.account.peerId {
        if peer is TelegramUser {
            controller.hasTimer = hasSchedule
        }
        controller.hasSilentPosting = true
    }
    controller.hasSchedule = hasSchedule
    controller.reminder = peer.id == context.account.peerId
    if let channel = peer as? TelegramChannel, case .broadcast = channel.info {
        controller.hasCoverButton = true
    } else if peer.id == context.account.peerId {
        controller.hasCoverButton = true
    }
    controller.presentScheduleController = { media, done in
        presentSchedulePicker(media, { time, silentPosting in
            done?(time, silentPosting)
        })
    }
    controller.presentTimerController = { done in
        presentTimerPicker { time in
            done?(time)
        }
    }
    controller.selectionLimitExceeded = {
        presentSelectionLimitExceeded()
    }
    controller.localMediaCacheEnabled = false
    controller.shouldStoreAssets = storeCreatedAssets
    controller.shouldShowFileTipIfNeeded = showFileTooltip
    controller.requestSearchController = presentWebSearch
    
    if !initialCaption.string.isEmpty {
        controller.editingContext.setForcedCaption(initialCaption)
    }
}

public func legacyAssetPicker(context: AccountContext, presentationData: PresentationData, editingMedia: Bool, fileMode: Bool, peer: EngineRawPeer?, threadTitle: String?, saveEditedPhotos: Bool, allowGrouping: Bool, selectionLimit: Int) -> Signal<(LegacyComponentsContext) -> TGMediaAssetsController, Void> {
    let isSecretChat = (peer?.id.namespace._internalGetInt32Value() ?? 0) == Namespaces.Peer.SecretChat._internalGetInt32Value()
    
    let recipientName: String?
    if let threadTitle {
        recipientName = threadTitle
    } else {
        if peer?.id == context.account.peerId {
            recipientName = presentationData.strings.DialogList_SavedMessages
        } else {
            recipientName = peer.flatMap(EnginePeer.init)?.displayTitle(strings: presentationData.strings, displayOrder: presentationData.nameDisplayOrder)
        }
    }
    
    return Signal { subscriber in
        let intent = fileMode ? TGMediaAssetsControllerSendFileIntent : TGMediaAssetsControllerSendMediaIntent
        let defaultVideoPreset = defaultVideoPresetForContext(context)
        UserDefaults.standard.set(defaultVideoPreset.rawValue as NSNumber, forKey: "TG_preferredVideoPreset_v0")
        
        DeviceAccess.authorizeAccess(to: .mediaLibrary(.send), presentationData: presentationData, present: context.sharedContext.presentGlobalController, openSettings: context.sharedContext.applicationBindings.openSettings, { value in
            if !value {
                subscriber.putError(Void())
                return
            }
    
            if TGMediaAssetsLibrary.authorizationStatus() == TGMediaLibraryAuthorizationStatusNotDetermined {
                TGMediaAssetsLibrary.requestAuthorization(for: TGMediaAssetAnyType, completion: { (status, group) in
                    if !LegacyComponentsGlobals.provider().accessChecker().checkPhotoAuthorizationStatus(for: TGPhotoAccessIntentRead, alertDismissCompletion: nil) {
                        subscriber.putError(Void())
                    } else {
                        Queue.mainQueue().async {
                            subscriber.putNext({ context in
                                let controller = TGMediaAssetsController(context: context, assetGroup: group, intent: intent, recipientName: recipientName, saveEditedPhotos: !isSecretChat && saveEditedPhotos, allowGrouping: allowGrouping, inhibitSelection: editingMedia, selectionLimit: Int32(selectionLimit))
                                return controller!
                            })
                            subscriber.putCompletion()
                        }
                    }
                })
            } else {
                subscriber.putNext({ context in
                    let controller = TGMediaAssetsController(context: context, assetGroup: nil, intent: intent, recipientName: recipientName, saveEditedPhotos: !isSecretChat && saveEditedPhotos, allowGrouping: allowGrouping, inhibitSelection: editingMedia, selectionLimit: Int32(selectionLimit))
                    return controller!
                })
                subscriber.putCompletion()
            }  
        })
        
        return ActionDisposable {
            
        }
    }
}

private enum LegacyAssetImageData {
    case image(UIImage)
    case asset(PHAsset)
    case tempFile(String)
}

private enum LegacyAssetVideoData {
    case asset(TGMediaAsset)
    case tempFile(path: String, dimensions: CGSize, duration: Double)
}

private enum LegacyAssetItem {
    case image(data: LegacyAssetImageData, thumbnail: UIImage?, caption: NSAttributedString?, stickers: [FileMediaReference], video: LegacyAssetVideoData?, adjustments: TGVideoEditAdjustments?)
    case file(data: LegacyAssetImageData, thumbnail: UIImage?, mimeType: String, name: String, caption: NSAttributedString?)
    case video(data: LegacyAssetVideoData, thumbnail: UIImage?, cover: UIImage?, adjustments: TGVideoEditAdjustments?, caption: NSAttributedString?, asFile: Bool, asAnimation: Bool, stickers: [FileMediaReference])
}

private final class LegacyAssetItemWrapper: NSObject {
    let item: LegacyAssetItem
    let timer: Int?
    let spoiler: Bool?
    let price: Int64?
    let forceHd: Bool
    let groupedId: Int64?
    let uniqueId: String?
    
    init(item: LegacyAssetItem, timer: Int?, spoiler: Bool?, price: Int64?, forceHd: Bool = false, groupedId: Int64?, uniqueId: String?) {
        self.item = item
        self.timer = timer
        self.spoiler = spoiler
        self.price = price
        self.forceHd = forceHd
        self.groupedId = groupedId
        self.uniqueId = uniqueId
        
        super.init()
    }
}

private func legacyPickerCGSize(_ value: Any?) -> CGSize? {
    if let value = value as? NSValue {
        return value.cgSizeValue
    } else if let value = value as? CGSize {
        return value
    } else {
        return nil
    }
}

private func legacyPickerDouble(_ value: Any?) -> Double? {
    if let value = value as? NSNumber {
        return value.doubleValue
    } else if let value = value as? Double {
        return value
    } else {
        return nil
    }
}

private func legacyPickerString(_ value: Any?) -> String? {
    if let value = value as? String {
        return value
    } else if let value = value as? NSString {
        return value as String
    } else {
        return nil
    }
}

private func legacyPickerPath(_ value: Any?) -> String? {
    if let value = value as? URL {
        return value.path
    } else {
        return legacyPickerString(value)
    }
}

// SuperGram: center square crop for round video ("Telescope") placeholders
private func legacyAssetPickerSquareCroppedImage(_ image: UIImage) -> UIImage {
    guard let cgImage = image.cgImage else {
        return image
    }
    let width = CGFloat(cgImage.width)
    let height = CGFloat(cgImage.height)
    if abs(width - height) < 1.0 {
        return image
    }
    let side = min(width, height)
    let rect = CGRect(x: floor((width - side) / 2.0), y: floor((height - side) / 2.0), width: side, height: side)
    guard let croppedImage = cgImage.cropping(to: rect) else {
        return image
    }
    return UIImage(cgImage: croppedImage, scale: image.scale, orientation: image.imageOrientation)
}

public func legacyAssetPickerItemGenerator() -> ((Any?, NSAttributedString?, String?, String?) -> [AnyHashable : Any]?) {
    return { anyDict, caption, hash, uniqueId in
        guard let dict = anyDict as? NSDictionary, let type = legacyPickerString(dict["type"]) else {
            return nil
        }
        let stickers = (dict["stickers"] as? [Data])?.compactMap { data -> FileMediaReference? in
            let decoder = EnginePostboxDecoder(buffer: EngineMemoryBuffer(data: data))
            if let file = decoder.decodeRootObject() as? TelegramMediaFile {
                return FileMediaReference.standalone(media: file)
            } else {
                return nil
            }
        } ?? []
        
        let price = dict["price"] as? Int64
        
        if type == "editedPhoto" || type == "capturedPhoto" {
            guard let image = dict["image"] as? UIImage else {
                return nil
            }
            let thumbnail = dict["previewImage"] as? UIImage
            let cover = dict["coverImage"] as? UIImage
            let forceHd = (dict["hd"] as? NSNumber)?.boolValue ?? false
            
            var result: [AnyHashable : Any] = [:]
            if let isAnimation = dict["isAnimation"] as? NSNumber, isAnimation.boolValue {
                let url: String? = (dict["url"] as? String) ?? (dict["url"] as? URL)?.path
                if let url = url {
                    let dimensions = image.size
                    result["item" as NSString] = LegacyAssetItemWrapper(item: .video(data: .tempFile(path: url, dimensions: dimensions, duration: 4.0), thumbnail: thumbnail, cover: cover, adjustments: dict["adjustments"] as? TGVideoEditAdjustments, caption: caption, asFile: false, asAnimation: true, stickers: stickers), timer: (dict["timer"] as? NSNumber)?.intValue, spoiler: (dict["spoiler"] as? NSNumber)?.boolValue, price: price, groupedId: (dict["groupedId"] as? NSNumber)?.int64Value, uniqueId: uniqueId)
                } else {
                    return nil
                }
            } else {
                result["item" as NSString] = LegacyAssetItemWrapper(item: .image(data: .image(image), thumbnail: thumbnail, caption: caption, stickers: stickers, video: nil, adjustments: nil), timer: (dict["timer"] as? NSNumber)?.intValue, spoiler: (dict["spoiler"] as? NSNumber)?.boolValue, price: price, forceHd: forceHd, groupedId: (dict["groupedId"] as? NSNumber)?.int64Value, uniqueId: uniqueId)
            }
            return result
        } else if type == "cloudPhoto" {
            guard let asset = dict["asset"] as? TGMediaAsset else {
                return nil
            }
            let thumbnail = dict["previewImage"] as? UIImage
            var asFile = false
            if let document = dict["document"] as? NSNumber, document.boolValue {
                asFile = true
            }
            var result: [AnyHashable: Any] = [:]
            if asFile {
                var mimeType = "image/jpeg"
                if let customMimeType = dict["mimeType"] as? String {
                    mimeType = customMimeType
                }
                var name = "image.jpg"
                if let customName = dict["fileName"] as? String {
                    name = customName
                }
                result["item" as NSString] = LegacyAssetItemWrapper(item: .file(data: .asset(asset.backingAsset), thumbnail: thumbnail, mimeType: mimeType, name: name, caption: caption), timer: nil, spoiler: nil, price: price, groupedId: (dict["groupedId"] as? NSNumber)?.int64Value, uniqueId: uniqueId)
            } else {
                let forceHd = (dict["hd"] as? NSNumber)?.boolValue ?? false
                result["item" as NSString] = LegacyAssetItemWrapper(item: .image(data: .asset(asset.backingAsset), thumbnail: thumbnail, caption: caption, stickers: [], video: nil, adjustments: nil), timer: (dict["timer"] as? NSNumber)?.intValue, spoiler: (dict["spoiler"] as? NSNumber)?.boolValue, price: price, forceHd: forceHd, groupedId: (dict["groupedId"] as? NSNumber)?.int64Value, uniqueId: uniqueId)
            }
            return result
        } else if type == "file" {
            if let tempFileUrl = dict["tempFileUrl"] as? URL {
                let thumbnail = dict["previewImage"] as? UIImage
                var mimeType = "application/binary"
                if let customMimeType = dict["mimeType"] as? String {
                    mimeType = customMimeType
                }
                var name = "file"
                if let customName = dict["fileName"] as? String {
                    name = customName
                }
                
                if let isAnimation = dict["isAnimation"] as? NSNumber, isAnimation.boolValue, mimeType == "video/mp4" {
                    var result: [AnyHashable: Any] = [:]
                    
                    if let dimensions = legacyPickerCGSize(dict["dimensions"]), let duration = legacyPickerDouble(dict["duration"]) {
                        result["item" as NSString] = LegacyAssetItemWrapper(item: .video(data: .tempFile(path: tempFileUrl.path, dimensions: dimensions, duration: duration), thumbnail: thumbnail, cover: nil, adjustments: nil, caption: caption, asFile: false, asAnimation: true, stickers: []), timer: (dict["timer"] as? NSNumber)?.intValue, spoiler: (dict["spoiler"] as? NSNumber)?.boolValue, price: price, groupedId: (dict["groupedId"] as? NSNumber)?.int64Value, uniqueId: uniqueId)
                        return result
                    }
                }
                
                var result: [AnyHashable: Any] = [:]
                result["item" as NSString] = LegacyAssetItemWrapper(item: .file(data: .tempFile(tempFileUrl.path), thumbnail: thumbnail, mimeType: mimeType, name: name, caption: caption), timer: (dict["timer"] as? NSNumber)?.intValue, spoiler: (dict["spoiler"] as? NSNumber)?.boolValue, price: price, groupedId: (dict["groupedId"] as? NSNumber)?.int64Value, uniqueId: uniqueId)
                return result
            }
        } else if type == "video" {
            let thumbnail = dict["previewImage"] as? UIImage
            let cover = dict["coverImage"] as? UIImage
            var asFile = false
            if let document = dict["document"] as? NSNumber, document.boolValue {
                asFile = true
            }
            
            if let asset = dict["asset"] as? TGMediaAsset {
                var result: [AnyHashable: Any] = [:]
                result["item" as NSString] = LegacyAssetItemWrapper(item: .video(data: .asset(asset), thumbnail: thumbnail, cover: cover, adjustments: dict["adjustments"] as? TGVideoEditAdjustments, caption: caption, asFile: asFile, asAnimation: false, stickers: stickers), timer: (dict["timer"] as? NSNumber)?.intValue, spoiler: (dict["spoiler"] as? NSNumber)?.boolValue, price: price, groupedId: (dict["groupedId"] as? NSNumber)?.int64Value, uniqueId: uniqueId)
                return result
            } else if let url = (dict["url"] as? String) ?? (dict["url"] as? URL)?.absoluteString {
                guard let dimensions = legacyPickerCGSize(dict["dimensions"]), let duration = legacyPickerDouble(dict["duration"]) else {
                    return nil
                }
                var result: [AnyHashable: Any] = [:]
                result["item" as NSString] = LegacyAssetItemWrapper(item: .video(data: .tempFile(path: url, dimensions: dimensions, duration: duration), thumbnail: thumbnail, cover: cover, adjustments: dict["adjustments"] as? TGVideoEditAdjustments, caption: caption, asFile: asFile, asAnimation: false, stickers: stickers), timer: (dict["timer"] as? NSNumber)?.intValue, spoiler: (dict["spoiler"] as? NSNumber)?.boolValue, price: price, groupedId: (dict["groupedId"] as? NSNumber)?.int64Value, uniqueId: uniqueId)
                return result
            }
        } else if type == "cameraVideo" {
            let thumbnail = dict["previewImage"] as? UIImage
            let cover = dict["coverImage"] as? UIImage
            var asFile = false
            if let document = dict["document"] as? NSNumber, document.boolValue {
                asFile = true
            }
            
            var isLivePhoto = false
            if let value = dict["livePhoto"] as? Bool {
                isLivePhoto = value
            }
                 
            let url: String? = legacyPickerPath(dict["url"])
            
            if let url = url, let previewImage = dict["previewImage"] as? UIImage {
                let dimensions = previewImage.pixelSize()
                guard let duration = legacyPickerDouble(dict["duration"]) else {
                    return nil
                }
                
                var result: [AnyHashable: Any] = [:]
                if isLivePhoto, let cover {
                    result["item" as NSString] = LegacyAssetItemWrapper(
                        item: .image(
                            data: .image(cover),
                            thumbnail: thumbnail,
                            caption: caption,
                            stickers: stickers,
                            video: .tempFile(path: url, dimensions: dimensions, duration: duration),
                            adjustments: dict["adjustments"] as? TGVideoEditAdjustments
                        ),
                        timer: (dict["timer"] as? NSNumber)?.intValue,
                        spoiler: (dict["spoiler"] as? NSNumber)?.boolValue,
                        price: price,
                        groupedId: (dict["groupedId"] as? NSNumber)?.int64Value,
                        uniqueId: uniqueId
                    )
                } else {
                    result["item" as NSString] = LegacyAssetItemWrapper(
                        item: .video(
                            data: .tempFile(path: url, dimensions: dimensions, duration: duration),
                            thumbnail: thumbnail,
                            cover: cover,
                            adjustments: dict["adjustments"] as? TGVideoEditAdjustments,
                            caption: caption,
                            asFile: asFile,
                            asAnimation: false,
                            stickers: stickers
                        ),
                        timer: (dict["timer"] as? NSNumber)?.intValue,
                        spoiler: (dict["spoiler"] as? NSNumber)?.boolValue,
                        price: price,
                        groupedId: (dict["groupedId"] as? NSNumber)?.int64Value,
                        uniqueId: uniqueId
                    )
                }
                return result
            }
        }
        return nil
    }
}

public func legacyEnqueueGifMessage(account: Account, data: Data, correlationId: Int64? = nil) -> Signal<EnqueueMessage, Void> {
    return Signal { subscriber in
        if let previewImage = UIImage(data: data) {
            let dimensions = previewImage.size
            var previewRepresentations: [TelegramMediaImageRepresentation] = []
            
            let thumbnailSize = dimensions.aspectFitted(CGSize(width: 320.0, height: 320.0))
            if let thumbnailImage = TGScaleImageToPixelSize(previewImage, thumbnailSize), let thumbnailData = thumbnailImage.jpegData(compressionQuality: 0.4) {
                let resource = LocalFileMediaResource(fileId: Int64.random(in: Int64.min ... Int64.max))
                account.postbox.mediaBox.storeResourceData(resource.id, data: thumbnailData)
                previewRepresentations.append(TelegramMediaImageRepresentation(dimensions: PixelDimensions(thumbnailSize), resource: resource, progressiveSizes: [], immediateThumbnailData: nil, hasVideo: false, isPersonal: false))
            }
            
            var randomId: Int64 = 0
            arc4random_buf(&randomId, 8)
            let tempFilePath = NSTemporaryDirectory() + "\(randomId).gif"
            
            let _ = try? FileManager.default.removeItem(atPath: tempFilePath)
            let _ = try? data.write(to: URL(fileURLWithPath: tempFilePath), options: [.atomic])
        
            let resource = LocalFileGifMediaResource(randomId: Int64.random(in: Int64.min ... Int64.max), path: tempFilePath)
            let fileName: String = "video.mp4"
            
            let finalDimensions = TGMediaVideoConverter.dimensions(for: dimensions, adjustments: nil, preset: TGMediaVideoConversionPresetAnimation)
            
            var fileAttributes: [TelegramMediaFileAttribute] = []
            fileAttributes.append(.Video(duration: 0.0, size: PixelDimensions(finalDimensions), flags: [.supportsStreaming], preloadSize: nil, coverTime: nil, videoCodec: nil))
            fileAttributes.append(.FileName(fileName: fileName))
            fileAttributes.append(.Animated)
            
            let media = TelegramMediaFile(fileId: EngineMedia.Id(namespace: Namespaces.Media.LocalFile, id: Int64.random(in: Int64.min ... Int64.max)), partialReference: nil, resource: resource, previewRepresentations: previewRepresentations, videoThumbnails: [], immediateThumbnailData: nil, mimeType: "video/mp4", size: nil, attributes: fileAttributes, alternativeRepresentations: [])
            subscriber.putNext(.message(text: "", attributes: [], inlineStickers: [:], mediaReference: .standalone(media: media), threadId: nil, replyToMessageId: nil, replyToStoryId: nil, localGroupingKey: nil, correlationId: correlationId, bubbleUpEmojiOrStickersets: []))
            subscriber.putCompletion()
        } else {
            subscriber.putError(Void())
        }
        
        return EmptyDisposable
    } |> runOn(Queue.concurrentDefaultQueue())
}

public struct LegacyAssetPickerEnqueueMessage {
    public var message: EnqueueMessage
    public var uniqueId: String?
    public var isFile: Bool
}

public func legacyAssetPickerEnqueueMessages(
    context: AccountContext,
    account: Account,
    signals: [Any],
    originalMediaReference: AnyMediaReference? = nil
) -> Signal<[LegacyAssetPickerEnqueueMessage], Void> {
    return Signal { subscriber in
        let disposable = SSignal.combineSignals(signals).start(next: { anyValues in
            var messages: [LegacyAssetPickerEnqueueMessage] = []
                    
            struct EnqueuePaidMessage {
                var price: Int64
                var text: String
                var entities: [MessageTextEntity]
                var media: [EngineRawMedia]
            }
            
            var paidMessage: EnqueuePaidMessage?
            
            guard let itemValues = anyValues as? [Any] else {
                subscriber.putError(Void())
                return
            }
            outer: for item in itemValues {
                if let item = (item as? NSDictionary)?.object(forKey: "item") as? LegacyAssetItemWrapper {
                    switch item.item {
                        case let .image(data, thumbnail, caption, stickers, video, adjustments):
                            var representations: [TelegramMediaImageRepresentation] = []
                            if let thumbnail = thumbnail {
                                let resource = LocalFileMediaResource(fileId: Int64.random(in: Int64.min ... Int64.max))
                                let thumbnailSize = thumbnail.size.aspectFitted(CGSize(width: 320.0, height: 320.0))
                                if let thumbnailImage = TGScaleImageToPixelSize(thumbnail, thumbnailSize), let thumbnailData = thumbnailImage.jpegData(compressionQuality: 0.4) {
                                    account.postbox.mediaBox.storeResourceData(resource.id, data: thumbnailData)
                                    representations.append(TelegramMediaImageRepresentation(dimensions: PixelDimensions(thumbnailSize), resource: resource, progressiveSizes: [], immediateThumbnailData: nil, hasVideo: false, isPersonal: false))
                                }
                            }
                            switch data {
                                case let .image(image):
                                    var randomId: Int64 = 0
                                    arc4random_buf(&randomId, 8)
                                    let tempFilePath = NSTemporaryDirectory() + "\(randomId).jpeg"
                                    let maxSize = item.forceHd ? CGSize(width: 2560.0, height: 2560.0) : CGSize(width: 1280.0, height: 1280.0)
                                    let scaledSize = image.size.aspectFittedOrSmaller(maxSize)
                                
                                    if let scaledImage = TGScaleImageToPixelSize(image, scaledSize) {
                                        let tempFile = EngineTempBox.shared.tempFile(fileName: "file")
                                        defer {
                                            EngineTempBox.shared.dispose(tempFile)
                                        }
                                        // MARK: Swiftgram
                                        // SuperGram (SGM-F5): outgoing JPEG quality is user-controlled. The default of
                                        // 70 is slightly above the 0.6 stock Telegram used here.
                                        if let scaledImageData = compressImageToJPEG(scaledImage, quality: SGSimpleSettings.shared.outgoingPhotoQualityFactor, tempFilePath: tempFile.path) {
                                            let _ = try? scaledImageData.write(to: URL(fileURLWithPath: tempFilePath))

                                            let resource = LocalFileReferenceMediaResource(localFilePath: tempFilePath, randomId: randomId)
                                            representations.append(TelegramMediaImageRepresentation(dimensions: PixelDimensions(scaledSize), resource: resource, progressiveSizes: [], immediateThumbnailData: nil, hasVideo: false, isPersonal: false))
                                            
                                            var imageFlags: TelegramMediaImageFlags = []
                                                                                        
                                            var attributes: [EngineMessage.Attribute] = []
                                            
                                            var stickerFiles: [TelegramMediaFile] = []
                                            if !stickers.isEmpty {
                                                for fileReference in stickers {
                                                    stickerFiles.append(fileReference.media)
                                                }
                                            }
                                            if !stickerFiles.isEmpty {
                                                attributes.append(EmbeddedMediaStickersMessageAttribute(files: stickerFiles))
                                                imageFlags.insert(.hasStickers)
                                            }

                                            var videoFile: TelegramMediaFile?
                                            if let video, case let .tempFile(path, dimensions, duration) = video {
                                                var finalDimensions: CGSize = dimensions
                                                var finalDuration: Double = duration
 
                                                let preset: TGMediaVideoConversionPreset = TGMediaVideoConversionPresetCompressedMedium
                                                finalDimensions = TGMediaVideoConverter.dimensions(for: finalDimensions, adjustments: adjustments, preset: preset)
                                                
                                                var resourceAdjustments: VideoMediaResourceAdjustments?
                                                if let adjustments = adjustments {
                                                    if adjustments.trimApplied() {
                                                        finalDuration = adjustments.trimEndValue - adjustments.trimStartValue
                                                    }
                                                    
                                                    if let dict = adjustments.dictionary(), let data = try? NSKeyedArchiver.archivedData(withRootObject: dict, requiringSecureCoding: false) {
                                                        let adjustmentsData = EngineMemoryBuffer(data: data)
                                                        let digest = EngineMemoryBuffer(data: adjustmentsData.md5Digest())
                                                        resourceAdjustments = VideoMediaResourceAdjustments(data: adjustmentsData, digest: digest, isStory: false)
                                                    }
                                                }
                                                
                                                let resource = LocalFileVideoMediaResource(randomId: Int64.random(in: Int64.min ... Int64.max), path: path, adjustments: resourceAdjustments)
                                                let estimatedSize = TGMediaVideoConverter.estimatedSize(for: preset, duration: finalDuration, hasAudio: true)
                                                
                                                var fileAttributes: [TelegramMediaFileAttribute] = []
                                                fileAttributes.append(.Video(duration: finalDuration, size: PixelDimensions(finalDimensions), flags: [], preloadSize: nil, coverTime: nil, videoCodec: nil))
                                                if estimatedSize > 10 * 1024 * 1024 {
                                                    fileAttributes.append(.hintFileIsLarge)
                                                }
                                                videoFile = TelegramMediaFile(fileId: EngineMedia.Id(namespace: Namespaces.Media.LocalFile, id: Int64.random(in: Int64.min ... Int64.max)), partialReference: nil, resource: resource, previewRepresentations: [], videoThumbnails: [], videoCover: nil, immediateThumbnailData: nil, mimeType: "video/mp4", size: nil, attributes: fileAttributes, alternativeRepresentations: [])
                                                imageFlags.insert(.isLivePhoto)
                                            }
                                            
                                            let media = TelegramMediaImage(imageId: EngineMedia.Id(namespace: Namespaces.Media.LocalImage, id: randomId), representations: representations, immediateThumbnailData: nil, reference: nil, partialReference: nil, flags: imageFlags, video: videoFile)
                                            if let timer = item.timer, timer > 0 && (timer <= 60 || timer == viewOnceTimeout) {
                                                attributes.append(AutoremoveTimeoutMessageAttribute(timeout: Int32(timer), countdownBeginTime: nil))
                                            }
                                            if let spoiler = item.spoiler, spoiler {
                                                attributes.append(MediaSpoilerMessageAttribute())
                                            }
                                                                                        
                                            let text = trimChatInputText(convertMarkdownToAttributes(caption ?? NSAttributedString()))
                                            let entities = generateTextEntities(text.string, enabledTypes: .all, currentEntities: generateChatInputTextEntities(text))
                                            if !entities.isEmpty {
                                                attributes.append(TextEntitiesMessageAttribute(entities: entities))
                                            }
                                            var bubbleUpEmojiOrStickersetsById: [Int64: EngineItemCollectionId] = [:]
                                            text.enumerateAttribute(ChatTextInputAttributes.customEmoji, in: NSRange(location: 0, length: text.length), using: { value, _, _ in
                                                if let value = value as? ChatTextInputTextCustomEmojiAttribute {
                                                    if let file = value.file {
                                                        if let packId = value.interactivelySelectedFromPackId {
                                                            bubbleUpEmojiOrStickersetsById[file.fileId.id] = packId
                                                        }
                                                    }
                                                }
                                            })
                                            var bubbleUpEmojiOrStickersets: [EngineItemCollectionId] = []
                                            for entity in entities {
                                                if case let .CustomEmoji(_, fileId) = entity.type {
                                                    if let packId = bubbleUpEmojiOrStickersetsById[fileId] {
                                                        if !bubbleUpEmojiOrStickersets.contains(packId) {
                                                            bubbleUpEmojiOrStickersets.append(packId)
                                                        }
                                                    }
                                                }
                                            }
                                            
                                            if let price = item.price {
                                                if var current = paidMessage {
                                                    if current.text.isEmpty && !text.string.isEmpty {
                                                        current.text = text.string
                                                        current.entities = entities
                                                    }
                                                    current.media.append(media)
                                                    paidMessage = current
                                                } else {
                                                    paidMessage = EnqueuePaidMessage(
                                                        price: price,
                                                        text: text.string,
                                                        entities: entities,
                                                        media: [media]
                                                    )
                                                }
                                            } else {
                                                messages.append(LegacyAssetPickerEnqueueMessage(message: .message(text: text.string, attributes: attributes, inlineStickers: [:], mediaReference: .standalone(media: media), threadId: nil, replyToMessageId: nil, replyToStoryId: nil, localGroupingKey: item.groupedId, correlationId: nil, bubbleUpEmojiOrStickersets: bubbleUpEmojiOrStickersets), uniqueId: item.uniqueId, isFile: false))
                                            }
                                        }
                                    }
                                case let .asset(asset):
                                    if context.sharedContext.immediateExperimentalUISettings.storiesJpegExperiment {
                                        let sizes: [Int32] = [2048, 1280]
                                        let formats: [MediaImageFormat] = [.jxl, .jpeg]
                                        let qualities: [Int32: [Int32]] = [
                                            MediaImageFormat.jxl.rawValue: [
                                                50,
                                                75
                                            ],
                                            MediaImageFormat.jpeg.rawValue: [
                                                75
                                            ]
                                        ]
                                        for sizeSide in sizes {
                                            for format in formats {
                                                for quality in qualities[format.rawValue]! {
                                                    var randomId: Int64 = 0
                                                    arc4random_buf(&randomId, 8)
                                                    let resource = PhotoLibraryMediaResource(
                                                        localIdentifier: asset.localIdentifier,
                                                        uniqueId: Int64.random(in: Int64.min ... Int64.max),
                                                        width: sizeSide,
                                                        height: sizeSide,
                                                        format: format,
                                                        quality: quality
                                                    )
                                                    
                                                    let size = CGSize(width: CGFloat(asset.pixelWidth), height: CGFloat(asset.pixelHeight))
                                                    let scaledSize = size.aspectFittedOrSmaller(CGSize(width: CGFloat(sizeSide), height: CGFloat(sizeSide)))
                                                    
                                                    let media: EngineRawMedia
                                                    media = TelegramMediaFile(fileId: EngineMedia.Id(namespace: Namespaces.Media.LocalFile, id: Int64.random(in: Int64.min ... Int64.max)), partialReference: nil, resource: resource, previewRepresentations: [], videoThumbnails: [], immediateThumbnailData: nil, mimeType: format == .jxl ? "image/jxl" : "image/jpeg", size: nil, attributes: [
                                                        .FileName(fileName: format == .jxl ? "image\(sizeSide)-q\(quality).jxl" : "image\(sizeSide)-q\(quality).jpg"),
                                                        .ImageSize(size: PixelDimensions(scaledSize))
                                                    ], alternativeRepresentations: [])
                                                    
                                                    var attributes: [EngineMessage.Attribute] = []
                                                    if let timer = item.timer, timer > 0 && (timer <= 60 || timer == viewOnceTimeout) {
                                                        attributes.append(AutoremoveTimeoutMessageAttribute(timeout: Int32(timer), countdownBeginTime: nil))
                                                    }
                                                    if let spoiler = item.spoiler, spoiler {
                                                        attributes.append(MediaSpoilerMessageAttribute())
                                                    }
                                                    
                                                    let text = trimChatInputText(convertMarkdownToAttributes(caption ?? NSAttributedString()))
                                                    let entities = generateTextEntities(text.string, enabledTypes: .all, currentEntities: generateChatInputTextEntities(text))
                                                    if !entities.isEmpty {
                                                        attributes.append(TextEntitiesMessageAttribute(entities: entities))
                                                    }
                                                    
                                                    var bubbleUpEmojiOrStickersetsById: [Int64: EngineItemCollectionId] = [:]
                                                    text.enumerateAttribute(ChatTextInputAttributes.customEmoji, in: NSRange(location: 0, length: text.length), using: { value, _, _ in
                                                        if let value = value as? ChatTextInputTextCustomEmojiAttribute {
                                                            if let file = value.file {
                                                                if let packId = value.interactivelySelectedFromPackId {
                                                                    bubbleUpEmojiOrStickersetsById[file.fileId.id] = packId
                                                                }
                                                            }
                                                        }
                                                    })
                                                    var bubbleUpEmojiOrStickersets: [EngineItemCollectionId] = []
                                                    for entity in entities {
                                                        if case let .CustomEmoji(_, fileId) = entity.type {
                                                            if let packId = bubbleUpEmojiOrStickersetsById[fileId] {
                                                                if !bubbleUpEmojiOrStickersets.contains(packId) {
                                                                    bubbleUpEmojiOrStickersets.append(packId)
                                                                }
                                                            }
                                                        }
                                                    }
                                                    
                                                    if let price = item.price {
                                                        if var current = paidMessage {
                                                            if current.text.isEmpty && !text.string.isEmpty {
                                                                current.text = text.string
                                                                current.entities = entities
                                                            }
                                                            current.media.append(media)
                                                            paidMessage = current
                                                        } else {
                                                            paidMessage = EnqueuePaidMessage(
                                                                price: price,
                                                                text: text.string,
                                                                entities: entities,
                                                                media: [media]
                                                            )
                                                        }
                                                    } else {
                                                        messages.append(LegacyAssetPickerEnqueueMessage(message: .message(text: text.string, attributes: attributes, inlineStickers: [:], mediaReference: .standalone(media: media), threadId: nil, replyToMessageId: nil, replyToStoryId: nil, localGroupingKey: item.groupedId, correlationId: nil, bubbleUpEmojiOrStickersets: bubbleUpEmojiOrStickersets), uniqueId: item.uniqueId, isFile: false))
                                                    }
                                                }
                                            }
                                        }
                                    } else {
                                        var randomId: Int64 = 0
                                        arc4random_buf(&randomId, 8)
                                        let size = CGSize(width: CGFloat(asset.pixelWidth), height: CGFloat(asset.pixelHeight))
                                        let scaledSize = size.aspectFittedOrSmaller(CGSize(width: 1280.0, height: 1280.0))
                                        let resource = PhotoLibraryMediaResource(localIdentifier: asset.localIdentifier, uniqueId: Int64.random(in: Int64.min ... Int64.max), forceHd: item.forceHd)
                                    
                                        let media: EngineRawMedia
                                        representations.append(TelegramMediaImageRepresentation(dimensions: PixelDimensions(scaledSize), resource: resource, progressiveSizes: [], immediateThumbnailData: nil, hasVideo: false, isPersonal: false))
                                        media = TelegramMediaImage(imageId: EngineMedia.Id(namespace: Namespaces.Media.LocalImage, id: randomId), representations: representations, immediateThumbnailData: nil, reference: nil, partialReference: nil, flags: [])
                                    
                                        var attributes: [EngineMessage.Attribute] = []
                                        if let timer = item.timer, timer > 0 && (timer <= 60 || timer == viewOnceTimeout) {
                                            attributes.append(AutoremoveTimeoutMessageAttribute(timeout: Int32(timer), countdownBeginTime: nil))
                                        }
                                        if let spoiler = item.spoiler, spoiler {
                                            attributes.append(MediaSpoilerMessageAttribute())
                                        }
                                    
                                        let text = trimChatInputText(convertMarkdownToAttributes(caption ?? NSAttributedString()))
                                        let entities = generateTextEntities(text.string, enabledTypes: .all, currentEntities: generateChatInputTextEntities(text))
                                        if !entities.isEmpty {
                                            attributes.append(TextEntitiesMessageAttribute(entities: entities))
                                        }
                                    
                                        var bubbleUpEmojiOrStickersetsById: [Int64: EngineItemCollectionId] = [:]
                                        text.enumerateAttribute(ChatTextInputAttributes.customEmoji, in: NSRange(location: 0, length: text.length), using: { value, _, _ in
                                            if let value = value as? ChatTextInputTextCustomEmojiAttribute {
                                                if let file = value.file {
                                                    if let packId = value.interactivelySelectedFromPackId {
                                                        bubbleUpEmojiOrStickersetsById[file.fileId.id] = packId
                                                    }
                                                }
                                            }
                                        })
                                        var bubbleUpEmojiOrStickersets: [EngineItemCollectionId] = []
                                        for entity in entities {
                                            if case let .CustomEmoji(_, fileId) = entity.type {
                                                if let packId = bubbleUpEmojiOrStickersetsById[fileId] {
                                                    if !bubbleUpEmojiOrStickersets.contains(packId) {
                                                        bubbleUpEmojiOrStickersets.append(packId)
                                                    }
                                                }
                                            }
                                        }
                                        
                                        if let price = item.price {
                                            if var current = paidMessage {
                                                if current.text.isEmpty && !text.string.isEmpty {
                                                    current.text = text.string
                                                    current.entities = entities
                                                }
                                                current.media.append(media)
                                                paidMessage = current
                                            } else {
                                                paidMessage = EnqueuePaidMessage(
                                                    price: price,
                                                    text: text.string,
                                                    entities: entities,
                                                    media: [media]
                                                )
                                            }
                                        } else {
                                            messages.append(LegacyAssetPickerEnqueueMessage(message: .message(text: text.string, attributes: attributes, inlineStickers: [:], mediaReference: .standalone(media: media), threadId: nil, replyToMessageId: nil, replyToStoryId: nil, localGroupingKey: item.groupedId, correlationId: nil, bubbleUpEmojiOrStickersets: bubbleUpEmojiOrStickersets), uniqueId: item.uniqueId, isFile: false))
                                        }
                                    }
                                case .tempFile:
                                    break
                            }
                        case let .file(data, thumbnail, mimeType, name, caption):
                            switch data {
                                case let .tempFile(path):
                                    var previewRepresentations: [TelegramMediaImageRepresentation] = []
                                    if let thumbnail = thumbnail {
                                        let resource = LocalFileMediaResource(fileId: Int64.random(in: Int64.min ... Int64.max))
                                        let thumbnailSize = thumbnail.size.aspectFitted(CGSize(width: 320.0, height: 320.0))
                                        if let thumbnailImage = TGScaleImageToPixelSize(thumbnail, thumbnailSize), let thumbnailData = thumbnailImage.jpegData(compressionQuality: 0.4) {
                                            account.postbox.mediaBox.storeResourceData(resource.id, data: thumbnailData)
                                            previewRepresentations.append(TelegramMediaImageRepresentation(dimensions: PixelDimensions(thumbnailSize), resource: resource, progressiveSizes: [], immediateThumbnailData: nil, hasVideo: false, isPersonal: false))
                                        }
                                    }
                                    
                                    var randomId: Int64 = 0
                                    arc4random_buf(&randomId, 8)
                                    let resource = LocalFileReferenceMediaResource(localFilePath: path, randomId: randomId)
                                    let media = TelegramMediaFile(fileId: EngineMedia.Id(namespace: Namespaces.Media.LocalFile, id: randomId), partialReference: nil, resource: resource, previewRepresentations: previewRepresentations, videoThumbnails: [], immediateThumbnailData: nil, mimeType: mimeType, size: engineFileSize(path), attributes: [.FileName(fileName: name)], alternativeRepresentations: [])
                                    
                                    var attributes: [EngineMessage.Attribute] = []
                                    let text = trimChatInputText(convertMarkdownToAttributes(caption ?? NSAttributedString()))
                                    let entities = generateTextEntities(text.string, enabledTypes: .all, currentEntities: generateChatInputTextEntities(text))
                                    if !entities.isEmpty {
                                        attributes.append(TextEntitiesMessageAttribute(entities: entities))
                                    }
                                
                                    var bubbleUpEmojiOrStickersetsById: [Int64: EngineItemCollectionId] = [:]
                                    text.enumerateAttribute(ChatTextInputAttributes.customEmoji, in: NSRange(location: 0, length: text.length), using: { value, _, _ in
                                        if let value = value as? ChatTextInputTextCustomEmojiAttribute {
                                            if let file = value.file {
                                                if let packId = value.interactivelySelectedFromPackId {
                                                    bubbleUpEmojiOrStickersetsById[file.fileId.id] = packId
                                                }
                                            }
                                        }
                                    })
                                    var bubbleUpEmojiOrStickersets: [EngineItemCollectionId] = []
                                    for entity in entities {
                                        if case let .CustomEmoji(_, fileId) = entity.type {
                                            if let packId = bubbleUpEmojiOrStickersetsById[fileId] {
                                                if !bubbleUpEmojiOrStickersets.contains(packId) {
                                                    bubbleUpEmojiOrStickersets.append(packId)
                                                }
                                            }
                                        }
                                    }
                                    
                                    if let price = item.price {
                                        if var current = paidMessage {
                                            if current.text.isEmpty && !text.string.isEmpty {
                                                current.text = text.string
                                                current.entities = entities
                                            }
                                            current.media.append(media)
                                            paidMessage = current
                                        } else {
                                            paidMessage = EnqueuePaidMessage(
                                                price: price,
                                                text: text.string,
                                                entities: entities,
                                                media: [media]
                                            )
                                        }
                                    } else {
                                        messages.append(LegacyAssetPickerEnqueueMessage(message: .message(text: text.string, attributes: attributes, inlineStickers: [:], mediaReference: .standalone(media: media), threadId: nil, replyToMessageId: nil, replyToStoryId: nil, localGroupingKey: item.groupedId, correlationId: nil, bubbleUpEmojiOrStickersets: bubbleUpEmojiOrStickersets), uniqueId: item.uniqueId, isFile: true))
                                    }
                                case let .asset(asset):
                                    var randomId: Int64 = 0
                                    arc4random_buf(&randomId, 8)
                                    let resource = PhotoLibraryMediaResource(localIdentifier: asset.localIdentifier, uniqueId: Int64.random(in: Int64.min ... Int64.max))
                                    let media = TelegramMediaFile(fileId: EngineMedia.Id(namespace: Namespaces.Media.LocalFile, id: randomId), partialReference: nil, resource: resource, previewRepresentations: [], videoThumbnails: [], immediateThumbnailData: nil, mimeType: mimeType, size: nil, attributes: [.FileName(fileName: name)], alternativeRepresentations: [])
                                    
                                    var attributes: [EngineMessage.Attribute] = []
                                    let text = trimChatInputText(convertMarkdownToAttributes(caption ?? NSAttributedString()))
                                    let entities = generateTextEntities(text.string, enabledTypes: .all, currentEntities: generateChatInputTextEntities(text))
                                    if !entities.isEmpty {
                                        attributes.append(TextEntitiesMessageAttribute(entities: entities))
                                    }
                                
                                    var bubbleUpEmojiOrStickersetsById: [Int64: EngineItemCollectionId] = [:]
                                    text.enumerateAttribute(ChatTextInputAttributes.customEmoji, in: NSRange(location: 0, length: text.length), using: { value, _, _ in
                                        if let value = value as? ChatTextInputTextCustomEmojiAttribute {
                                            if let file = value.file {
                                                if let packId = value.interactivelySelectedFromPackId {
                                                    bubbleUpEmojiOrStickersetsById[file.fileId.id] = packId
                                                }
                                            }
                                        }
                                    })
                                    var bubbleUpEmojiOrStickersets: [EngineItemCollectionId] = []
                                    for entity in entities {
                                        if case let .CustomEmoji(_, fileId) = entity.type {
                                            if let packId = bubbleUpEmojiOrStickersetsById[fileId] {
                                                if !bubbleUpEmojiOrStickersets.contains(packId) {
                                                    bubbleUpEmojiOrStickersets.append(packId)
                                                }
                                            }
                                        }
                                    }
                                    
                                    if let price = item.price {
                                        if var current = paidMessage {
                                            if current.text.isEmpty && !text.string.isEmpty {
                                                current.text = text.string
                                                current.entities = entities
                                            }
                                            current.media.append(media)
                                            paidMessage = current
                                        } else {
                                            paidMessage = EnqueuePaidMessage(
                                                price: price,
                                                text: text.string,
                                                entities: entities,
                                                media: [media]
                                            )
                                        }
                                    } else {
                                        messages.append(LegacyAssetPickerEnqueueMessage(message: .message(text: text.string, attributes: attributes, inlineStickers: [:], mediaReference: .standalone(media: media), threadId: nil, replyToMessageId: nil, replyToStoryId: nil, localGroupingKey: item.groupedId, correlationId: nil, bubbleUpEmojiOrStickersets: bubbleUpEmojiOrStickersets), uniqueId: item.uniqueId, isFile: true))
                                    }
                                default:
                                    break
                            }
                        case let .video(data, thumbnail, cover, adjustments, caption, asFile, asAnimation, stickers):
                            // MARK: Swiftgram
                            var adjustments = adjustments
                            // SuperGram: files, animations and paid media are never converted into round videos
                            var asTelescope = adjustments?.sendAsTelescope == true && !asFile && !asAnimation && item.price == nil

                            var finalDimensions: CGSize
                            var finalDuration: Double
                            switch data {
                                case let .asset(asset):
                                    if let adjustments = adjustments {
                                        if adjustments.cropApplied(forAvatar: false) {
                                            finalDimensions = adjustments.cropRect.size
                                            if adjustments.cropOrientation == .left || adjustments.cropOrientation == .right {
                                                finalDimensions = CGSize(width: finalDimensions.height, height: finalDimensions.width)
                                            }
                                        } else {
                                            finalDimensions = asset.dimensions
                                        }
                                        if adjustments.trimEndValue > 0.0 {
                                            finalDuration = adjustments.trimEndValue - adjustments.trimStartValue
                                        } else {
                                            finalDuration = asset.videoDuration
                                        }
                                    } else {
                                        finalDimensions = asset.dimensions
                                        finalDuration = asset.videoDuration
                                    }
                                case let .tempFile(_, dimensions, duration):
                                    finalDimensions = dimensions
                                    finalDuration = duration
                            }
                            
                            /*if !asAnimation {
                                finalDimensions = TGFitSize(finalDimensions, CGSize(width: 848.0, height: 848.0))
                            }*/
                            
                            var previewRepresentations: [TelegramMediaImageRepresentation] = []
                            if var thumbnail = thumbnail {
                                let resource = LocalFileMediaResource(fileId: Int64.random(in: Int64.min ... Int64.max))
                                var thumbnailSize = finalDimensions.aspectFitted(CGSize(width: 320.0, height: 320.0))
                                // MARK: Swiftgram
                                if asTelescope {
                                    // SuperGram: round video placeholders are square
                                    thumbnail = legacyAssetPickerSquareCroppedImage(thumbnail)
                                    thumbnailSize = CGSize(width: 320.0, height: 320.0)
                                }
                                if let thumbnailImage = TGScaleImageToPixelSize(thumbnail, thumbnailSize), let thumbnailData = thumbnailImage.jpegData(compressionQuality: 0.4) {
                                    account.postbox.mediaBox.storeResourceData(resource.id, data: thumbnailData)
                                    previewRepresentations.append(TelegramMediaImageRepresentation(dimensions: PixelDimensions(thumbnailSize), resource: resource, progressiveSizes: [], immediateThumbnailData: nil, hasVideo: false, isPersonal: false))
                                }
                            }
                            
                            var videoCover: TelegramMediaImage?
                            // SuperGram: round videos have no cover
                            if let cover, !asTelescope {
                                let resource = LocalFileMediaResource(fileId: Int64.random(in: Int64.min ... Int64.max))
                                let maxSide: CGFloat = 1280.0
                                let coverSize = cover.size.aspectFitted(CGSize(width: maxSide, height: maxSide))
                                if let coverImage = TGScaleImageToPixelSize(cover, coverSize), let coverData = coverImage.jpegData(compressionQuality: 0.87) {
                                    account.postbox.mediaBox.storeResourceData(resource.id, data: coverData)
                                    videoCover = TelegramMediaImage(
                                        imageId: EngineMedia.Id(namespace: 0, id: 0),
                                        representations: [
                                            TelegramMediaImageRepresentation(dimensions: PixelDimensions(coverSize), resource: resource, progressiveSizes: [], immediateThumbnailData: nil, hasVideo: false, isPersonal: false)
                                        ],
                                        immediateThumbnailData: nil,
                                        reference: nil,
                                        partialReference: nil,
                                        flags: []
                                    )
                                }
                            }
                        
                            let defaultPreset = TGMediaVideoConversionPreset(rawValue: UInt32(UserDefaults.standard.integer(forKey: "TG_preferredVideoPreset_v0")))
                            var preset: TGMediaVideoConversionPreset = TGMediaVideoConversionPresetCompressedMedium
                            if let selectedPreset = adjustments?.preset {
                                preset = selectedPreset
                            } else if preset == TGMediaVideoConversionPresetCompressedDefault && defaultPreset != TGMediaVideoConversionPresetCompressedDefault {
                                preset = defaultPreset
                            }
                            if asAnimation {
                                preset = TGMediaVideoConversionPresetAnimation
                            }
                            // MARK: Swiftgram
                            if asTelescope, let strongAdjustments = adjustments {
                                // Final size
                                let size = CGSize(width: finalDimensions.width, height: finalDimensions.height)

                                // Respecting user's crop
                                let originalSize: CGSize
                                let baseCropRect: CGRect
                                if strongAdjustments.cropApplied(forAvatar: false) {
                                    originalSize = strongAdjustments.originalSize
                                    baseCropRect = strongAdjustments.cropRect
                                } else {
                                    // It's a hack, video is resized according to the quality preset
                                    // To prevent this resize we must set original size the same as the after-resized video
                                    originalSize = size
                                    baseCropRect = CGRect(origin: CGPoint(), size: size)
                                }

                                // Need to make a square (centered inside the crop rect, in its own coordinate space).
                                // SuperGram: cropLockedAspectRatio 1.0 keeps cropApplied() true, so Swiftgram's inset hack for already square sources is not needed
                                let shortestSide = min(baseCropRect.width, baseCropRect.height)
                                let cropRect = CGRect(x: baseCropRect.minX + (baseCropRect.width - shortestSide) / 2.0, y: baseCropRect.minY + (baseCropRect.height - shortestSide) / 2.0, width: shortestSide, height: shortestSide)

                                // SuperGram: an untrimmed video has trimEndValue == 0, cap the real range instead of subtracting from zero
                                let maxDuration: Double = TGVideoEditMaximumTelescopeDuration
                                let trimStartValue = strongAdjustments.trimStartValue
                                var trimEndValue = strongAdjustments.trimEndValue
                                if trimEndValue <= trimStartValue {
                                    trimEndValue = max(trimStartValue, finalDuration)
                                }
                                let trimEndValueLimited = min(trimEndValue, trimStartValue + maxDuration)
                                let estimatedDuration = trimEndValueLimited - trimStartValue

                                // Dynamically calculate size with different presets and use the best one
                                // SuperGram: estimate with the capped duration; VideoMessage if nothing fits
                                var telescopePreset = TGMediaVideoConversionPresetVideoMessage
                                for presetTest in [TGMediaVideoConversionPresetVideoMessageHD, TGMediaVideoConversionPresetVideoMessage, TGMediaVideoConversionPresetCompressedLow] {
                                    let estimatedVideoMessageSize = TGMediaVideoConverter.estimatedSize(for: presetTest, duration: estimatedDuration, hasAudio: true)
                                    if estimatedVideoMessageSize < 8 * 1024 * 1024 {
                                        telescopePreset = presetTest
                                        break
                                    }
                                }

                                if let telescopeAdjustments = TGVideoEditAdjustments(originalSize: originalSize, cropRect: cropRect, cropOrientation: strongAdjustments.cropOrientation, cropRotation: strongAdjustments.cropRotation, cropLockedAspectRatio: 1.0, cropMirrored: strongAdjustments.cropMirrored, trimStartValue: trimStartValue, trimEndValue: trimEndValueLimited, toolValues: strongAdjustments.toolValues, paintingData: strongAdjustments.paintingData, sendAsGif: false, sendAsTelescope: true, preset: telescopePreset) {
                                    adjustments = telescopeAdjustments
                                    // SuperGram: the encoded file is the capped range, so the `.Video(duration:)` attribute must be too.
                                    // The generic `trimApplied()` branch below already recomputes this to the same value, but only as long
                                    // as `trimEndValueLimited > 0` keeps `trimApplied()` true — state it explicitly so the 60 s cap and the
                                    // advertised duration cannot drift apart.
                                    finalDuration = estimatedDuration
                                    preset = telescopePreset
                                    finalDimensions = TGMediaVideoConverter.dimensions(for: finalDimensions, adjustments: telescopeAdjustments, preset: telescopePreset)
                                } else {
                                    asTelescope = false
                                    finalDimensions = TGMediaVideoConverter.dimensions(for: finalDimensions, adjustments: adjustments, preset: TGMediaVideoConversionPresetCompressedMedium)
                                }
                            } else if !asAnimation {
                                finalDimensions = TGMediaVideoConverter.dimensions(for: finalDimensions, adjustments: adjustments, preset: TGMediaVideoConversionPresetCompressedMedium)
                            }
                            
                            var resourceAdjustments: VideoMediaResourceAdjustments?
                            if let adjustments = adjustments {
                                if adjustments.trimApplied() {
                                    finalDuration = adjustments.trimEndValue - adjustments.trimStartValue
                                }
                                
                                if let dict = adjustments.dictionary(), let data = try? NSKeyedArchiver.archivedData(withRootObject: dict, requiringSecureCoding: false) {
                                    let adjustmentsData = EngineMemoryBuffer(data: data)
                                    let digest = EngineMemoryBuffer(data: adjustmentsData.md5Digest())
                                    resourceAdjustments = VideoMediaResourceAdjustments(data: adjustmentsData, digest: digest, isStory: false)
                                }
                            }
                            
                            let resource: TelegramMediaResource
                            var fileName: String = "video.mp4"
                            switch data {
                                case let .asset(asset):
                                    if let assetFileName = asset.fileName, !assetFileName.isEmpty {
                                        fileName = (assetFileName as NSString).lastPathComponent
                                    }
                                    resource = VideoLibraryMediaResource(localIdentifier: asset.backingAsset.localIdentifier, conversion: asFile ? .passthrough : .compress(resourceAdjustments))
                                case let .tempFile(path, _, _):
                                    if asFile || (asAnimation && !path.contains(".jpg")) {
                                        if let size = engineFileSize(path) {
                                            resource = LocalFileMediaResource(fileId: Int64.random(in: Int64.min ... Int64.max), size: size)
                                            account.postbox.mediaBox.moveResourceData(resource.id, fromTempPath: path)
                                        } else {
                                            continue outer
                                        }
                                    } else {
                                        resource = LocalFileVideoMediaResource(randomId: Int64.random(in: Int64.min ... Int64.max), path: path, adjustments: resourceAdjustments)
                                    }
                            }
                            
                            let estimatedSize = TGMediaVideoConverter.estimatedSize(for: preset, duration: finalDuration, hasAudio: !asAnimation)
                            
                            var fileAttributes: [TelegramMediaFileAttribute] = []
                            fileAttributes.append(.FileName(fileName: fileName))
                            if asAnimation {
                                fileAttributes.append(.Animated)
                            }
                            if !asFile {
                                let flags: TelegramMediaVideoFlags = [.supportsStreaming]
                                fileAttributes.append(.Video(duration: finalDuration, size: PixelDimensions(finalDimensions), flags: flags, preloadSize: nil, coverTime: nil, videoCodec: nil))
                                if let adjustments = adjustments {
                                    if adjustments.sendAsGif {
                                        fileAttributes.append(.Animated)
                                    }
                                }
                                
                                if estimatedSize > 10 * 1024 * 1024 {
                                    fileAttributes.append(.hintFileIsLarge)
                                }
                            } else {
                                if case let .asset(asset) = data, let phAsset = asset.backingAsset, let resource = PHAssetResource.assetResources(for: phAsset).last, let sizeValue = resource.value(forKey: "fileSize") as? CLong, sizeValue > 0 {
                                    let size = Int64(bitPattern: UInt64(sizeValue))
                                    
                                    if size > 10 * 1024 * 1024 {
                                        fileAttributes.append(.hintFileIsLarge)
                                    }
                                }
                            }
                            
                            var attributes: [EngineMessage.Attribute] = []
                            
                            var stickerFiles: [TelegramMediaFile] = []
                            if !stickers.isEmpty {
                                for fileReference in stickers {
                                    stickerFiles.append(fileReference.media)
                                }
                            }
                            if !stickerFiles.isEmpty {
                                attributes.append(EmbeddedMediaStickersMessageAttribute(files: stickerFiles))
                                fileAttributes.append(.HasLinkedStickers)
                            }
                            // MARK: Swiftgram
                            if asTelescope {
                                fileAttributes = [.FileName(fileName: "video.mp4"), .Video(duration: finalDuration, size: PixelDimensions(finalDimensions), flags: [.instantRoundVideo], preloadSize: nil, coverTime: nil, videoCodec: nil)]
                            }

                            let media: EngineRawMedia
                            let mediaReference: AnyMediaReference
                            if let adjustments, adjustments.isDefaultValuesForGif(), let originalMediaReference {
                                media = originalMediaReference.media
                                mediaReference = originalMediaReference
                            } else {
                                media = TelegramMediaFile(fileId: EngineMedia.Id(namespace: Namespaces.Media.LocalFile, id: Int64.random(in: Int64.min ... Int64.max)), partialReference: nil, resource: resource, previewRepresentations: previewRepresentations, videoThumbnails: [], videoCover: videoCover, immediateThumbnailData: nil, mimeType: "video/mp4", size: nil, attributes: fileAttributes, alternativeRepresentations: [])
                                mediaReference = .standalone(media: media)
                            }
                            
                            if let timer = item.timer, timer > 0 && (timer <= 60 || timer == viewOnceTimeout) {
                                attributes.append(AutoremoveTimeoutMessageAttribute(timeout: Int32(timer), countdownBeginTime: nil))
                            }
                            if let spoiler = item.spoiler, spoiler {
                                attributes.append(MediaSpoilerMessageAttribute())
                            }
                            
                            let text = trimChatInputText(convertMarkdownToAttributes(caption ?? NSAttributedString()))
                            let entities = generateTextEntities(text.string, enabledTypes: .all, currentEntities: generateChatInputTextEntities(text))
                            if !entities.isEmpty {
                                attributes.append(TextEntitiesMessageAttribute(entities: entities))
                            }
                        
                            var bubbleUpEmojiOrStickersetsById: [Int64: EngineItemCollectionId] = [:]
                            text.enumerateAttribute(ChatTextInputAttributes.customEmoji, in: NSRange(location: 0, length: text.length), using: { value, _, _ in
                                if let value = value as? ChatTextInputTextCustomEmojiAttribute {
                                    if let file = value.file {
                                        if let packId = value.interactivelySelectedFromPackId {
                                            bubbleUpEmojiOrStickersetsById[file.fileId.id] = packId
                                        }
                                    }
                                }
                            })
                            var bubbleUpEmojiOrStickersets: [EngineItemCollectionId] = []
                            for entity in entities {
                                if case let .CustomEmoji(_, fileId) = entity.type {
                                    if let packId = bubbleUpEmojiOrStickersetsById[fileId] {
                                        if !bubbleUpEmojiOrStickersets.contains(packId) {
                                            bubbleUpEmojiOrStickersets.append(packId)
                                        }
                                    }
                                }
                            }
                            
                            if let price = item.price {
                                if var current = paidMessage {
                                    if current.text.isEmpty && !text.string.isEmpty {
                                        current.text = text.string
                                        current.entities = entities
                                    }
                                    current.media.append(media)
                                    paidMessage = current
                                } else {
                                    paidMessage = EnqueuePaidMessage(
                                        price: price,
                                        text: text.string,
                                        entities: entities,
                                        media: [media]
                                    )
                                }
                            } else {
                                // SuperGram: a round video is never part of an album. The picker already clears grouping for the whole
                                // batch as soon as one item is telescope (TGMediaAssetsController / TGMediaPickerGalleryInterfaceView),
                                // but that lives three layers away in the ObjC UI — enforce it at the send site too.
                                messages.append(LegacyAssetPickerEnqueueMessage(message: .message(text: text.string, attributes: attributes, inlineStickers: [:], mediaReference: mediaReference, threadId: nil, replyToMessageId: nil, replyToStoryId: nil, localGroupingKey: asTelescope ? nil : item.groupedId, correlationId: nil, bubbleUpEmojiOrStickersets: bubbleUpEmojiOrStickersets), uniqueId: item.uniqueId, isFile: asFile))
                            }
                    }
                }
            }
            
            if let paidMessage {
                var attributes: [EngineMessage.Attribute] = []
                if !paidMessage.entities.isEmpty {
                    attributes.append(TextEntitiesMessageAttribute(entities: paidMessage.entities))
                }
                messages.append(
                    LegacyAssetPickerEnqueueMessage(
                        message: .message(
                            text: paidMessage.text,
                            attributes: attributes,
                            inlineStickers: [:],
                            mediaReference: .standalone(
                                media: TelegramMediaPaidContent(
                                    amount: paidMessage.price,
                                    extendedMedia: paidMessage.media.map { .full(media: $0) }
                                )),
                            threadId: nil,
                            replyToMessageId: nil,
                            replyToStoryId: nil,
                            localGroupingKey: nil,
                            correlationId: nil,
                            bubbleUpEmojiOrStickersets: []
                        ),
                        uniqueId: nil,
                        isFile: false
                    )
                )
            }
            
            subscriber.putNext(messages)
            subscriber.putCompletion()
        }, error: { _ in
            subscriber.putError(Void())
        }, completed: nil)
        
        return ActionDisposable {
            disposable?.dispose()
        }
    }
}
