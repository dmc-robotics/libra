// swift-tools-version: 6.2
import PackageDescription

// OpenCASCADE comes from Homebrew (`brew install opencascade`, pinned). It's only used by StepBridge.
let openCascade = "/opt/homebrew/opt/opencascade"
let openCascadeLibraries = [
    "TKDESTEP", "TKDE", "TKXCAF", "TKCAF", "TKLCAF", "TKVCAF", "TKXSBase", "TKMesh", "TKShHealing",
    "TKTopAlgo", "TKGeomAlgo", "TKBRep", "TKGeomBase", "TKG3d", "TKG2d", "TKMath", "TKernel"
]

let package = Package(
    name: "LibraKit",
    platforms: [.macOS("27.0")],
    products: [
        .library(name: "LibraKit", targets: ["LibraKit"]),
        .library(name: "StepImport", targets: ["StepImport"])
    ],
    targets: [
        .target(name: "LibraKit"),
        .target(
            name: "StepBridge",
            cxxSettings: [
                .unsafeFlags(["-isystem", "\(openCascade)/include/opencascade", "-Wno-deprecated-declarations"])
            ],
            linkerSettings: [.unsafeFlags(["-L\(openCascade)/lib"])]
                + openCascadeLibraries.map { .linkedLibrary($0) }
        ),
        .target(name: "StepImport", dependencies: ["LibraKit", "StepBridge"]),
        .testTarget(name: "LibraKitTests", dependencies: ["LibraKit"]),
        .testTarget(
            name: "StepImportTests",
            dependencies: ["StepImport", "LibraKit"],
            resources: [.copy("Fixtures")]
        )
    ],
    cxxLanguageStandard: .cxx17
)
