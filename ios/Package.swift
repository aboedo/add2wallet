// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Add2Wallet",
    platforms: [
        .iOS(.v17)
    ],
    products: [
        .library(
            name: "Add2Wallet",
            targets: ["Add2Wallet"]),
    ],
    dependencies: [],
    targets: [
        .target(
            name: "Add2Wallet",
            dependencies: [],
            path: "Add2Wallet"),
        .testTarget(
            name: "Add2WalletTests",
            dependencies: ["Add2Wallet"],
            path: "Add2WalletTests"),
    ]
)