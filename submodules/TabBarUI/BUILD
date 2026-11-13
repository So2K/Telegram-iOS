load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

# MARK: Swiftgram
sgdeps = [
    "//Swiftgram/SGSimpleSettings:SGSimpleSettings",
]

swift_library(
    name = "TabBarUI",
    module_name = "TabBarUI",
    srcs = glob([
		"Sources/**/*.swift",
    ]),
    copts = [
        "-warnings-as-errors",
    ],
    deps = sgdeps + [
        "//submodules/AsyncDisplayKit",
        "//submodules/Display",
    	"//submodules/SSignalKit/SwiftSignalKit",
        "//submodules/AnimatedStickerNode",
        "//submodules/TelegramAnimatedStickerNode",
        "//submodules/TelegramPresentationData",
        "//submodules/ComponentFlow",
        "//submodules/Components/ComponentDisplayAdapters",
        "//submodules/TelegramUI/Components/TabBarComponent",
        "//submodules/TelegramUI/Components/GlassControls",
    ],
    visibility = [
        "//visibility:public",
    ],
)
