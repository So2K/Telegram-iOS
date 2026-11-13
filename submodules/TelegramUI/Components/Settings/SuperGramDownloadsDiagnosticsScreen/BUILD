load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

swift_library(
    name = "SuperGramDownloadsDiagnosticsScreen",
    module_name = "SuperGramDownloadsDiagnosticsScreen",
    srcs = glob([
        "Sources/**/*.swift",
    ]),
    copts = [
        "-warnings-as-errors",
    ],
    deps = [
        "//submodules/Display",
        "//submodules/SSignalKit/SwiftSignalKit",
        "//submodules/Postbox",
        "//submodules/TelegramCore",
        "//submodules/TelegramPresentationData",
        "//submodules/ItemListUI",
        "//submodules/PresentationDataUtils",
        "//submodules/AccountContext",
        "//submodules/TextFormat",
        "//submodules/UndoUI",
        "//submodules/FetchManagerImpl",
        "//Swiftgram/SGSimpleSettings:SGSimpleSettings",
        "//Swiftgram/SGStrings:SGStrings",
    ],
    visibility = [
        "//visibility:public",
    ],
)
