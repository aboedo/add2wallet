import ProjectDescription

let project = Project(
    name: "Add2Wallet",
    packages: [
        .remote(
            url: "https://github.com/RevenueCat/purchases-ios-spm.git",
            requirement: .upToNextMajor(from: "5.32.0")
        )
    ],
    targets: [
        .target(
            name: "Add2Wallet",
            destinations: .iOS,
            product: .app,
            bundleId: "com.andresboedo.add2wallet",
            deploymentTargets: .iOS("17.0"),
            infoPlist: .file(path: "Add2Wallet/Info.plist"),
            sources: [
                "Add2Wallet/**/*.swift"
            ],
            resources: [
                "Add2Wallet/Assets.xcassets",
                "Add2Wallet/Preview Content/**",
                "Add2Wallet/Resources/**"
            ],
            entitlements: "Add2Wallet/Add2Wallet.entitlements",
            dependencies: [
                .package(product: "RevenueCat"),
                .package(product: "RevenueCatUI")
            ],
            settings: .settings(
                base: [
                    "DEVELOPMENT_TEAM": "H9DPH4DQG7",
                    "CODE_SIGN_STYLE": "Automatic",
                    "ENABLE_PREVIEWS": "YES",
                    "MARKETING_VERSION": "1.0",
                    "CURRENT_PROJECT_VERSION": "1",
                    "SWIFT_VERSION": "5.0"
                ]
            )
        ),
        // Share Extension removed — using "Copy to App" (document types) only
        .target(
            name: "Add2WalletTests",
            destinations: .iOS,
            product: .unitTests,
            bundleId: "com.andresboedo.add2wallet.tests",
            deploymentTargets: .iOS("17.0"),
            infoPlist: .default,
            sources: [
                "Add2WalletTests/**/*.swift"
            ],
            resources: [
                "Add2WalletTests/Resources/**"
            ],
            dependencies: [
                .target(name: "Add2Wallet")
            ],
            settings: .settings(
                base: [
                    "DEVELOPMENT_TEAM": "H9DPH4DQG7",
                    "CODE_SIGN_STYLE": "Automatic",
                    "MARKETING_VERSION": "1.0",
                    "CURRENT_PROJECT_VERSION": "1",
                    "SWIFT_VERSION": "5.0"
                ]
            )
        )
    ]
)