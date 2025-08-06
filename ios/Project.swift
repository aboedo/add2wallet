import ProjectDescription

let project = Project(
    name: "Add2Wallet",
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
                "Add2Wallet/Preview Content/**"
            ],
            entitlements: "Add2Wallet/Add2Wallet.entitlements",
            dependencies: [
                .target(name: "Add2WalletShareExtension")
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
        .target(
            name: "Add2WalletShareExtension",
            destinations: .iOS,
            product: .appExtension,
            bundleId: "com.andresboedo.add2wallet.shareextension",
            deploymentTargets: .iOS("17.0"),
            infoPlist: .file(path: "Add2WalletShareExtension/Info.plist"),
            sources: [
                "Add2WalletShareExtension/**/*.swift"
            ],
            entitlements: "Add2WalletShareExtension/Add2WalletShareExtension.entitlements",
            settings: .settings(
                base: [
                    "DEVELOPMENT_TEAM": "H9DPH4DQG7",
                    "CODE_SIGN_STYLE": "Automatic",
                    "MARKETING_VERSION": "1.0",
                    "CURRENT_PROJECT_VERSION": "1",
                    "SWIFT_VERSION": "5.0",
                    "SKIP_INSTALL": "YES"
                ]
            )
        ),
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