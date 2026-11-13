load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

swift_library(
    name = "SuperGramLocalTranscription",
    module_name = "SuperGramLocalTranscription",
    srcs = glob([
        "Sources/**/*.swift",
    ]),
    copts = [
        "-warnings-as-errors",
    ],
    deps = [
        "//submodules/SSignalKit/SwiftSignalKit",
        "//submodules/Postbox",
        "//submodules/TelegramCore",
        "//submodules/Display",
        "//submodules/AccountContext",
        "//submodules/TelegramPresentationData",
        "//submodules/TelegramUIPreferences",
        "//submodules/UndoUI",
        "//submodules/Media/ConvertOpusToAAC",
        "//submodules/Media/LocalAudioTranscription",
    ],
    visibility = [
        "//visibility:public",
    ],
)
