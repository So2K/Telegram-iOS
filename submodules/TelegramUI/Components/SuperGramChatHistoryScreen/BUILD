load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

swift_library(
    name = "SuperGramChatHistoryScreen",
    module_name = "SuperGramChatHistoryScreen",
    srcs = glob([
        "Sources/**/*.swift",
    ]),
    copts = [
        "-warnings-as-errors",
    ],
    deps = [
        "//submodules/SSignalKit/SwiftSignalKit:SwiftSignalKit",
        "//submodules/Display:Display",
        "//submodules/TelegramCore:TelegramCore",
        "//submodules/TelegramPresentationData:TelegramPresentationData",
        "//submodules/TelegramUIPreferences:TelegramUIPreferences",
        "//submodules/AccountContext:AccountContext",
        "//submodules/ItemListUI:ItemListUI",
        "//submodules/ItemListPeerItem:ItemListPeerItem",
        "//submodules/PresentationDataUtils:PresentationDataUtils",
        "//Swiftgram/SGStrings:SGStrings",
    ],
    visibility = [
        "//visibility:public",
    ],
)
