// swift-tools-version: 6.0

import PackageDescription

var products: [Product] = [
    .library(name: "HollyCore", targets: ["HollyCore"]),
    .executable(name: "HollyCoreChecks", targets: ["HollyCoreChecks"])
]

var dependencies: [Package.Dependency] = []

var targets: [Target] = [
    .target(name: "HollyCore"),
    .executableTarget(
        name: "HollyCoreChecks",
        dependencies: ["HollyCore"],
        path: "Tests/HollyCoreChecks"
    )
]

#if os(macOS)
products.append(.executable(name: "HollyCorretor", targets: ["HollyCorretor"]))
dependencies.append(
    .package(
        url: "https://github.com/sindresorhus/KeyboardShortcuts",
        exact: "1.15.0"
    )
)
targets.append(
    .executableTarget(
        name: "HollyCorretor",
        dependencies: [
            "HollyCore",
            .product(name: "KeyboardShortcuts", package: "KeyboardShortcuts")
        ],
        linkerSettings: [
            .linkedFramework("AppKit"),
            .linkedFramework("ApplicationServices"),
            .linkedFramework("Carbon"),
            .linkedFramework("ServiceManagement")
        ]
    )
)
#endif

let package = Package(
    name: "HollyCorretor",
    platforms: [
        .macOS("26.0")
    ],
    products: products,
    dependencies: dependencies,
    targets: targets
)
