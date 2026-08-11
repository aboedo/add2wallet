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
                .package(product: "RevenueCatUI"),
                .target(name: "Add2WalletShareExtension")
            ],
            settings: .settings(
                base: [
                    "DEVELOPMENT_TEAM": "H9DPH4DQG7",
                    "CODE_SIGN_STYLE": "Automatic",
                    "ENABLE_PREVIEWS": "YES",
                    "MARKETING_VERSION": "1.0",
                    "CURRENT_PROJECT_VERSION": "50",
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
                    "CURRENT_PROJECT_VERSION": "50",
                    "SWIFT_VERSION": "5.0",
                    "APPLICATION_EXTENSION_API_ONLY": "YES"
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
    ],
    schemes: [
        .scheme(
            name: "Add2Wallet",
            shared: true,
            buildAction: .buildAction(targets: [.target("Add2Wallet")]),
            testAction: .targets([.testableTarget(target: .target("Add2WalletTests"))]),
            runAction: .runAction(
                configuration: .debug,
                options: .options(storeKitConfigurationPath: "Storekit.storekit")
            ),
            archiveAction: .archiveAction(configuration: .release)
        ),
        .scheme(
            name: "Add2Wallet Screenshots",
            shared: true,
            buildAction: .buildAction(targets: [.target("Add2Wallet")]),
            runAction: .runAction(
                configuration: .debug,
                arguments: .arguments(
                    environmentVariables: [
                        "SCREENSHOT_MODE": .environmentVariable(value: "1", isEnabled: true)
                    ]
                ),
                options: .options(storeKitConfigurationPath: "Storekit.storekit")
            ),
            archiveAction: .archiveAction(configuration: .release)
        )
    ]
)
