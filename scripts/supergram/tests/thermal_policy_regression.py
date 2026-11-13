#!/usr/bin/env python3
"""Exercise production energy notifications, inline listeners, eligibility and slot budgeting.

Only UIKit surfaces, the dispatch queue, and media/decoder dependencies are doubles.
The test runs extracted Swift source on macOS; physical-device thermal/decoder QA
remains separate. No source file is modified, and no network or account is used.
"""
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[3]


def block(source, marker, start=0):
    beginning = source.index(marker, start)
    opening = source.index("{", beginning)
    depth, ending = 1, opening + 1
    while depth:
        if source[ending] == "{":
            depth += 1
        elif source[ending] == "}":
            depth -= 1
        ending += 1
    return source[beginning:ending] + "\n"


preferences = (ROOT / "submodules/TelegramUIPreferences/Sources/MediaAutoDownloadSettings.swift").read_text()
shared = (ROOT / "submodules/TelegramUI/Sources/SharedAccountContext.swift").read_text()
environment = (ROOT / "submodules/TelegramUI/Components/Chat/ChatMessageInteractiveMediaNode/Sources/SuperGramInlineMediaPlayback.swift").read_text()
media = (ROOT / "submodules/TelegramUI/Components/Chat/ChatMessageInteractiveMediaNode/Sources/ChatMessageInteractiveMediaNode.swift").read_text()
bubble = (ROOT / "submodules/TelegramUI/Components/Chat/ChatMessageMediaBubbleContentNode/Sources/ChatMessageMediaBubbleContentNode.swift").read_text()

swift = r'''
import Foundation
import Darwin

enum ProcessInfo {
    enum ThermalState: Int { case nominal, fair, serious, critical }
    final class State { var thermalState = ThermalState.nominal }
    static let processInfo = State()
    static let thermalStateDidChangeNotification = Notification.Name("ThermalStateFixture")
}
final class UIApplication {
    enum State { case active, background }
    static let shared = UIApplication()
    var applicationState = State.active
    static let didEnterBackgroundNotification = Notification.Name("BackgroundFixture")
    static let willEnterForegroundNotification = Notification.Name("ForegroundFixture")
    static let didBecomeActiveNotification = Notification.Name("ActiveFixture")
}
final class UserDefaults {
    static let standard = UserDefaults()
    static let didChangeNotification = Notification.Name("DefaultsFixture")
    var inlineAutoplayVideos = true
    func object(forKey key: String) -> Any? { inlineAutoplayVideos }
}
final class Atomic<T> {
    private var value: T
    init(value: T) { self.value = value }
    func with<R>(_ f: (T) -> R) -> R { f(value) }
    func swap(_ next: T) -> T { let previous = value; value = next; return previous }
}
final class Bag<T> {
    private var next = 0
    private var items: [Int: T] = [:]
    func add(_ item: T) -> Int { let id = next; next += 1; items[id] = item; return id }
    func remove(_ id: Int) { items.removeValue(forKey: id) }
    func copyItems() -> [T] { items.keys.sorted().map { items[$0]! } }
}
final class Queue {
    static let main = Queue()
    private var work: [() -> Void] = []
    static func mainQueue() -> Queue { main }
    func justDispatch(_ f: @escaping () -> Void) { work.append(f) }
    func after(_ delay: Double, _ f: @escaping () -> Void) { work.append(f) }
    func drain() {
        precondition(Thread.isMainThread)
        var iterations = 0
        while !work.isEmpty {
            iterations += 1; precondition(iterations < 1000, "unexpected feedback loop")
            work.removeFirst()()
        }
    }
}
func CACurrentMediaTime() -> Double { 100.0 }
func check(_ value: @autoclosure () -> Bool, _ message: String) { precondition(value(), message) }
'''
swift += block(preferences, "public extension Notification.Name {")
swift += block(preferences, "public struct EnergyUsageSettings:")
swift += block(shared, "private func superGramEffectiveEnergyUsageSettings(")
swift += r'''
struct MediaAutoDownloadSettings {
    var energyUsageSettings: EnergyUsageSettings
    var powerSaving = false
}
func automaticEnergyUsageShouldBeOnNow(settings: MediaAutoDownloadSettings) -> Bool { settings.powerSaving }
struct MediaDisplaySettings { var performanceMode = false }
final class SharedContextFixture {
    var currentAutomaticMediaDownloadSettings: MediaAutoDownloadSettings
    let currentMediaDisplaySettings = Atomic(value: MediaDisplaySettings())
'''
swift += "public private(set) var energyUsageSettings: EnergyUsageSettings\n"
swift += "init(_ settings: EnergyUsageSettings) {\n"
swift += "currentAutomaticMediaDownloadSettings = MediaAutoDownloadSettings(energyUsageSettings: settings)\n"
swift += "energyUsageSettings = superGramEffectiveEnergyUsageSettings(settings, performanceMode: false)\n"
swift += block(shared, "let _ = NotificationCenter.default.addObserver(forName: ProcessInfo.thermalStateDidChangeNotification")[:-1] + ")\n}\n"
swift += block(shared, "private func superGramUpdateEnergyUsageSettings()")
swift += r'''
    func setBase(_ settings: EnergyUsageSettings, powerSaving: Bool = false) {
        currentAutomaticMediaDownloadSettings = MediaAutoDownloadSettings(energyUsageSettings: settings, powerSaving: powerSaving)
        superGramUpdateEnergyUsageSettings()
    }
}
'''
inline_start = environment.index("private let superGramInlineAutoplayVideosKey")
swift += environment[inline_start:environment.index("final class SuperGramInlineMediaEnvironment", inline_start)]
swift += block(environment, "final class SuperGramInlineMediaEnvironment {")
swift += block(environment, "final class SuperGramInlineVideoPlaybackBudget {")
swift += r'''
struct EngineMediaResource { struct Id { let value: Int; init(_ value: Int) { self.value = value } } }
protocol Media: AnyObject { func isSemanticallyEqual(to other: Media) -> Bool }
class MediaFixture: Media { func isSemanticallyEqual(to other: Media) -> Bool { self === other } }
final class TelegramMediaFile: MediaFixture {
    struct Resource { let id: Int }
    let resource = Resource(id: 1)
    let isAnimated: Bool
    let isVideo = true
    var isVideoSticker = false
    var isInstantVideo = false
    let videoCover: Int? = nil
    init(animated: Bool) { isAnimated = animated }
}
enum TelegramExtendedMedia { case full(Media), preview }
final class TelegramMediaInvoice: MediaFixture { var extendedMedia: TelegramExtendedMedia? }
final class TelegramMediaPaidContent: MediaFixture { var extendedMedia: [TelegramExtendedMedia] = [] }
final class TelegramMediaImage: MediaFixture { var video: Int? }
final class TelegramMediaStory: MediaFixture { let storyId = 0 }
enum Stories { enum StoredItem { case item(Int) } }
struct StoryBox { func get<T>(_ type: T.Type) -> T? { nil } }
func selectStoryMedia(item: Int, preferredHighQuality: Bool) -> Media? { nil }
enum NativeVideoContent { static func isHLSVideo(file: TelegramMediaFile) -> Bool { false } }
final class ResourcesFixture {
    func completedResourcePath(id: EngineMediaResource.Id) -> String? { id.value == 1 ? "/fixture/downloaded.gif" : nil }
}
struct EngineFixture { let resources = ResourcesFixture() }
final class AccountContextFixture {
    let sharedContext: SharedContextFixture
    let engine = EngineFixture()
    init(_ shared: SharedContextFixture) { sharedContext = shared }
}
struct MessageFixture { var id = 1; var containsSecretMedia = false; var associatedStories: [Int: StoryBox] = [:] }
struct BubbleItemFixture { let context: AccountContextFixture; let message = MessageFixture() }
enum DownloadFixture { case full, none }
func productionAutomaticPlayback(item: BubbleItemFixture, telegramFile: TelegramMediaFile, automaticDownload: DownloadFixture) -> Bool {
    var automaticPlayback = false
'''
regular_file_start = bubble.index("} else if let telegramFile = media as? TelegramMediaFile {")
gif_marker = "if telegramFile.isAnimated && item.context.sharedContext.energyUsageSettings.autoplayGif {"
gif_start = bubble.index(gif_marker, regular_file_start)
swift += block(bubble, gif_marker, gif_start)
swift += block(bubble, "else if (telegramFile.isVideo && !telegramFile.isAnimated)", gif_start)
swift += r'''
    return automaticPlayback
}
final class PlayerFixture {
    var canAttachContent = false
    var hasAttachedContext = true
    var playCount = 0
    var removed = false
    var soundEnabled = false
    var status = "playing"
    func play() { playCount += 1 }
    func removeFromSupernode() { removed = true }
}
final class AnimatedStickerFixture { var visibility = false }
final class BoolPromiseFixture { func set(_ value: Bool) {} }
func productionPreserveManualVideo(automaticPlayback: Bool, currentVideoNode: PlayerFixture?, currentVideoSoundEnabled: Bool, currentMedia: Media?, media: Media, currentMessage: MessageFixture?, message: MessageFixture) -> Bool {
    var automaticPlayback = automaticPlayback
'''
swift += block(media, "if !automaticPlayback, currentVideoNode != nil, currentVideoSoundEnabled,")
swift += r'''
    return automaticPlayback
}
func productionInlineAutoplayToggle(automaticPlayback: Bool, media: Media) -> Bool {
    var automaticPlayback = automaticPlayback
    let isLivePhoto = (media as? TelegramMediaImage)?.video != nil
'''
swift += block(media, "if automaticPlayback && !isLivePhoto && !SuperGramInlineMediaEnvironment.shared.inlineAutoplayVideos {")
swift += r'''
    return automaticPlayback
}
final class ChatMessageInteractiveMediaNode {
    var context: AccountContextFixture?
    var media: Media?
    var mediaIndex: Int?
    var message: MessageFixture? = MessageFixture()
    var appliedMedia: Media?
    var appliedMessage: MessageFixture?
    var preferredStoryHighQuality = false
    var videoNode: PlayerFixture?
    var automaticPlayback: Bool?
    var playerStatus: PlayerFixture? { videoNode }
    var visibility = true
    var internallyVisible = true
    var themeAndStrings: (Int, Int, Int, Bool)?
    var animatedStickerNode: AnimatedStickerFixture?
    let visibilityPromise = BoolPromiseFixture()
    var superGramEnvironmentListenerIndex: Int?
    var superGramInlineVideoPlaybackKind = SuperGramInlineVideoPlaybackBudget.Kind.video
    var requestInlineUpdate: (() -> Void)?
    var redraws = 0
    let distance: CGFloat
    init(_ shared: SharedContextFixture, animated: Bool, distance: CGFloat = 0) {
        context = AccountContextFixture(shared)
        media = TelegramMediaFile(animated: animated)
        self.distance = distance
        superGramInlineVideoPlaybackKind = animated ? .animation : .video
        requestInlineUpdate = { [weak self] in self?.layoutFixture() }
        // didLoad registers even if the initial policy leaves no player.
        superGramEnsureEnvironmentListener()
        layoutFixture()
    }
    func superGramUpdateStallWatchdog() {}
    func superGramInlinePlaybackDistanceToWindowCenter() -> CGFloat? { distance }
'''
for marker in ["private func updateVisibility()", "private func superGramEnsureEnvironmentListener()", "private func updateInlineVideoAttachment(isVisible:", "func superGramApplyInlineVideoPlaybackGrant(", "private func superGramEffectiveFetchMedia()"]:
    swift += block(media, marker)
swift += r'''
    func layoutFixture() {
        check(Thread.isMainThread, "inline policy layout stays on main")
        redraws += 1
        guard let context, let media, let message, let file = superGramEffectiveFetchMedia() as? TelegramMediaFile else { return }
        let currentAutomaticPlayback = self.automaticPlayback
'''
sound_capture = "let currentVideoSoundEnabled = self.playerStatus?.soundEnabled ?? false"
assert sound_capture in media
swift += sound_capture + "\n"
swift += r'''
        var automaticPlayback = productionAutomaticPlayback(item: BubbleItemFixture(context: context), telegramFile: file, automaticDownload: .none)
        automaticPlayback = productionPreserveManualVideo(automaticPlayback: automaticPlayback, currentVideoNode: videoNode, currentVideoSoundEnabled: currentVideoSoundEnabled, currentMedia: appliedMedia, media: media, currentMessage: appliedMessage, message: message)
        automaticPlayback = productionInlineAutoplayToggle(automaticPlayback: automaticPlayback, media: media)
'''
updated_start = media.index("var automaticPlaybackUpdated = false")
updated_end = media.index("var statusUpdated =", updated_start)
swift += media[updated_start:updated_end]
swift += r'''
        if automaticPlaybackUpdated || currentAutomaticPlayback == nil {
            let strongSelf = self
'''
removal_start = media.index("if let currentReplaceVideoNode = replaceVideoNode {")
swift += block(media, "if let videoNode = strongSelf.videoNode {", removal_start)
swift += "let isSecretMedia = false\nlet uploading = false\n"
video_condition_start = media.index("if file.isVideo && !file.isVideoSticker && !isSecretMedia && automaticPlayback && !uploading {")
video_condition_end = media.index("{", video_condition_start)
swift += media[video_condition_start:video_condition_end] + "{ self.videoNode = PlayerFixture() }\n}\n"
swift += "self.automaticPlayback = automaticPlayback\nself.appliedMedia = media\nself.appliedMessage = message\nself.updateVisibility()\n}\n"
swift += "func refreshVisibility() { updateVisibility() }\n"
swift += "deinit {\n"
deinit_start = media.index("deinit {", media.index("private func superGramEnsureEnvironmentListener()"))
deinit_end = media.index("self.statusDisposable.dispose()", deinit_start)
swift += media[media.index("let superGramEnvironmentListenerIndex", deinit_start):deinit_end]
swift += "}\n}\n"
swift += r'''
func thermal(_ state: ProcessInfo.ThermalState) {
    ProcessInfo.processInfo.thermalState = state
    NotificationCenter.default.post(name: ProcessInfo.thermalStateDidChangeNotification, object: nil)
}
func base(gif: Bool = true, video: Bool = true, decorative: Bool = true) -> EnergyUsageSettings {
    EnergyUsageSettings(activationThreshold: 15, autoplayVideo: video, autoplayGif: gif, loopStickers: true, loopEmoji: decorative, fullTranslucency: decorative, extendBackgroundWork: true, autodownloadInBackground: true)
}
let environmentFixture = SuperGramInlineMediaEnvironment.shared
let sharedFixture = SharedContextFixture(base())
var energyEvents = 0
let eventListener = environmentFixture.addListener { event in
    if case .energyUsageSettingsChanged = event { check(Thread.isMainThread, "event delivered on main"); energyEvents += 1 }
}
var gif: ChatMessageInteractiveMediaNode? = ChatMessageInteractiveMediaNode(sharedFixture, animated: true)
check(gif!.automaticPlayback == true && gif!.videoNode!.canAttachContent, "visible downloaded GIF starts normally")
let firstPlayer = gif!.videoNode!
let initialRedraws = gif!.redraws
thermal(.serious)
check(!sharedFixture.energyUsageSettings.autoplayGif, "effective thermal policy changed")
check(gif!.redraws == initialRedraws, "policy forwarding deferred beyond setter")
Queue.main.drain()
check(gif!.automaticPlayback == false && gif!.videoNode == nil && firstPlayer.removed && !firstPlayer.canAttachContent, "idle visible GIF detached without scroll")
check(energyEvents == 1 && gif!.redraws == initialRedraws + 1, "one thermal policy refresh")
thermal(.serious); Queue.main.drain()
check(energyEvents == 2 && gif!.redraws == initialRedraws + 1, "equal cached policy does not redraw")
thermal(.nominal); Queue.main.drain()
check(gif!.automaticPlayback == true && gif!.videoNode!.canAttachContent, "cooling restores cached-false GIF without scroll")
let coalescedRedraws = gif!.redraws
thermal(.serious); thermal(.nominal); Queue.main.drain()
check(gif!.redraws == coalescedRedraws && gif!.videoNode!.canAttachContent, "same-turn thermal changes use latest matching policy without redraw")

// A battery/settings update changes the stored policy without emitting a new UI event in this scoped fix.
// A later thermal callback must still refresh a GIF whose cached autoplay has become stale.
sharedFixture.setBase(base(), powerSaving: true)
check(gif!.automaticPlayback == true && !sharedFixture.energyUsageSettings.autoplayGif, "pre-existing stale battery policy reproduced")
let staleRedraws = gif!.redraws
thermal(.serious); Queue.main.drain()
check(gif!.videoNode == nil && gif!.redraws == staleRedraws + 1, "equal effective energy still stops stale GIF on thermal callback")
sharedFixture.setBase(base()); thermal(.nominal); Queue.main.drain()
check(gif!.videoNode!.canAttachContent, "stale-policy GIF can resume on nominal")

// A GIF and a manual video share the actual parent-layout behavior: either callback lays out both nodes.
var manualNeighbour: ChatMessageInteractiveMediaNode? = ChatMessageInteractiveMediaNode(sharedFixture, animated: false)
let preservedPlayer = manualNeighbour!.videoNode!
preservedPlayer.soundEnabled = true
SuperGramInlineVideoPlaybackBudget.shared.pinPlayback(node: manualNeighbour!)
let albumUpdate: () -> Void = { [weak gifNode = gif, weak videoNode = manualNeighbour] in
    gifNode?.layoutFixture(); videoNode?.layoutFixture()
}
gif!.requestInlineUpdate = albumUpdate
manualNeighbour!.requestInlineUpdate = albumUpdate
for status in ["playing", "paused", "buffering"] {
    preservedPlayer.status = status
    sharedFixture.setBase(base(), powerSaving: true)
    thermal(.serious); Queue.main.drain()
    check(gif!.videoNode == nil && manualNeighbour!.videoNode === preservedPlayer && preservedPlayer.canAttachContent && preservedPlayer.status == status, "mixed album retains manual video in " + status)
    sharedFixture.setBase(base()); thermal(.nominal); Queue.main.drain()
    check(gif!.videoNode!.canAttachContent && manualNeighbour!.videoNode === preservedPlayer && preservedPlayer.status == status, "mixed album nominal restoration retains manual state")
}
let manualFile = manualNeighbour!.media!
let manualMessage = manualNeighbour!.message!
func manualGuard(media: Media, message: MessageFixture, sound: Bool = true, player: PlayerFixture? = preservedPlayer) -> Bool {
    productionPreserveManualVideo(automaticPlayback: false, currentVideoNode: player, currentVideoSoundEnabled: sound, currentMedia: manualFile, media: media, currentMessage: manualMessage, message: message)
}
check(!manualGuard(media: TelegramMediaFile(animated: false), message: manualMessage), "different file cannot inherit manual autoplay")
check(!manualGuard(media: manualFile, message: MessageFixture(id: 2)), "different message cannot inherit manual autoplay")
check(!manualGuard(media: manualFile, message: manualMessage, sound: false), "muted autoplay cannot inherit manual policy")
check(!manualGuard(media: manualFile, message: manualMessage, player: nil), "absent player cannot inherit manual policy")
let gifMedia = TelegramMediaFile(animated: true)
check(!productionPreserveManualVideo(automaticPlayback: false, currentVideoNode: preservedPlayer, currentVideoSoundEnabled: true, currentMedia: gifMedia, media: gifMedia, currentMessage: manualMessage, message: manualMessage), "GIF cannot bypass automatic thermal policy as manual video")
for category in ["round", "sticker"] {
    let excludedFile = TelegramMediaFile(animated: false)
    excludedFile.isInstantVideo = category == "round"
    excludedFile.isVideoSticker = category == "sticker"
    check(!productionPreserveManualVideo(automaticPlayback: false, currentVideoNode: preservedPlayer, currentVideoSoundEnabled: true, currentMedia: excludedFile, media: excludedFile, currentMessage: manualMessage, message: manualMessage), "manual guard excludes " + category)
}
UserDefaults.standard.inlineAutoplayVideos = false
NotificationCenter.default.post(name: UserDefaults.didChangeNotification, object: nil)
check(!productionInlineAutoplayToggle(automaticPlayback: manualGuard(media: manualFile, message: manualMessage), media: manualFile), "explicit inline autoplay toggle retains final precedence")
UserDefaults.standard.inlineAutoplayVideos = true
NotificationCenter.default.post(name: UserDefaults.didChangeNotification, object: nil)
gif!.requestInlineUpdate = { [weak gifNode = gif] in gifNode?.layoutFixture() }
manualNeighbour = nil; Queue.main.drain()

NotificationCenter.default.post(name: UIApplication.didEnterBackgroundNotification, object: nil)
check(!gif!.videoNode!.canAttachContent, "background detaches inline player")
thermal(.serious); Queue.main.drain(); thermal(.nominal); Queue.main.drain()
check(gif!.videoNode != nil && !gif!.videoNode!.canAttachContent, "policy restoration in background stays detached")
NotificationCenter.default.post(name: UIApplication.willEnterForegroundNotification, object: nil)
check(gif!.videoNode!.canAttachContent, "foreground restores existing attachment path")

thermal(.serious); Queue.main.drain()
var initiallyHot: ChatMessageInteractiveMediaNode? = ChatMessageInteractiveMediaNode(sharedFixture, animated: true)
check(initiallyHot!.videoNode == nil && initiallyHot!.automaticPlayback == false, "initial hot node has no player")
thermal(.nominal); Queue.main.drain()
check(initiallyHot!.videoNode!.canAttachContent, "no-player didLoad listener restores on cooling")
let unrelated = SharedContextFixture(base())
let scopedRedraws = gif!.redraws
unrelated.setBase(base(gif: false)); Queue.main.drain()
NotificationCenter.default.post(name: .superGramEnergyUsageSettingsDidChange, object: unrelated); Queue.main.drain()
check(gif!.redraws == scopedRedraws, "different shared account context does not redraw node")

weak var released = initiallyHot
initiallyHot = nil
Queue.main.drain()
check(released == nil, "environment and budget do not retain media node")
gif = nil; Queue.main.drain()

// This effective policy is equal across thermal changes. Only the independent budget observer can rerank.
let unchanged = SharedContextFixture(base(gif: false, decorative: false))
let nearVideo = ChatMessageInteractiveMediaNode(unchanged, animated: false, distance: 0)
let farVideo = ChatMessageInteractiveMediaNode(unchanged, animated: false, distance: 1000)
check(nearVideo.videoNode!.canAttachContent && farVideo.videoNode!.canAttachContent, "two regular videos granted nominal slots")
let videoRedraws = nearVideo.redraws + farVideo.redraws
SuperGramInlineVideoPlaybackBudget.shared.pinPlayback(node: farVideo)
thermal(.serious); Queue.main.drain()
check(nearVideo.redraws + farVideo.redraws == videoRedraws, "equal effective policy does not need layout for thermal budget")
check(!nearVideo.videoNode!.canAttachContent && farVideo.videoNode!.canAttachContent, "thermal budget shrinks immediately and retains manual pin")
thermal(.nominal); Queue.main.drain()
check(nearVideo.videoNode!.canAttachContent && farVideo.videoNode!.canAttachContent, "cooling expands idle regular-video budget without requests")
let manualPlayer = farVideo.videoNode!
unchanged.setBase(base(gif: false, video: false, decorative: false)); Queue.main.drain()
check(farVideo.videoNode === manualPlayer && manualPlayer.canAttachContent, "nonthermal settings update retains prior notification behavior")
NotificationCenter.default.post(name: UIApplication.didEnterBackgroundNotification, object: nil)
check(!manualPlayer.canAttachContent, "manual pin does not bypass background detachment")
NotificationCenter.default.post(name: UIApplication.willEnterForegroundNotification, object: nil)

var removedListenerCalls = 0
let removedListener = environmentFixture.addListener { _ in removedListenerCalls += 1 }
environmentFixture.removeListener(removedListener)
thermal(.serious); Queue.main.drain()
check(removedListenerCalls == 0, "removed listener cannot receive queued policy change")
environmentFixture.removeListener(eventListener)
print("PASS: extracted thermal policy notification, coalescing, GIF stop/resume, account scope, lifecycle, background, and independent pinned-video budget regressions")
'''

with tempfile.TemporaryDirectory(prefix="supergram-thermal-regression-") as temporary:
    source = Path(temporary) / "main.swift"
    executable = Path(temporary) / "regression"
    source.write_text(swift)
    subprocess.run(["xcrun", "swiftc", "-warnings-as-errors", str(source), "-o", str(executable)], check=True)
    subprocess.run([str(executable)], check=True)
