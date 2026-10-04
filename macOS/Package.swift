// swift-tools-version: 6.1
import PackageDescription
let package = Package(
    name: "SimpleReaderMac",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "SimpleReader", targets: ["SimpleReader"])],
    targets: [
        .target(name: "Zstd", path: "Vendor/Zstd", exclude: ["LICENSE", "COPYING"], sources: ["common", "compress", "decompress", "dictBuilder"], publicHeadersPath: "include", cSettings: [.headerSearchPath("."), .headerSearchPath("common"), .define("ZSTD_DISABLE_ASM"), .define("ZSTD_STATIC_LINKING_ONLY", to: ""), .define("ZDICT_STATIC_LINKING_ONLY", to: "")]),
        .target(name: "CHoshiDicts", dependencies: ["Zstd"], path: "Vendor/HoshiDicts", sources: ["src", "external/libdeflate/lib", "external/utf8proc/utf8proc.c"], publicHeadersPath: "include", cxxSettings: [.headerSearchPath("include"), .headerSearchPath("external/libdeflate"), .headerSearchPath("external/libdeflate/lib"), .headerSearchPath("external/utfcpp/source"), .headerSearchPath("external/glaze/include"), .headerSearchPath("external/xxHash"), .headerSearchPath("external/unordered_dense/include"), .headerSearchPath("external/utf8proc"), .unsafeFlags(["-Wno-missing-braces"]) ]),
        .target(name: "ZIPFoundation", path: "Vendor/ZIPFoundation", exclude: ["LICENSE"]),
        .executableTarget(name: "SimpleReader", dependencies: ["CHoshiDicts", "ZIPFoundation"], resources: [.copy("Resources")]),
        .testTarget(name: "SimpleReaderTests", dependencies: ["SimpleReader", "ZIPFoundation"])
    ],
    swiftLanguageModes: [.v5],
    cxxLanguageStandard: .cxx2b
)
