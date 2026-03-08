# App Store Screenshots — Maestro Suite

## Requirements
- Maestro 2.2.0+
- Java 21+
- iOS Simulator running (iPhone 16 Pro Max for 6.9" screenshots)

## Setup
```bash
export PATH="/opt/homebrew/opt/openjdk@21/bin:$PATH:$HOME/.maestro/bin"
```

## Run all screenshots
```bash
cd ~/repos/add2wallet/ios
export PATH="/opt/homebrew/opt/openjdk@21/bin:$PATH:$HOME/.maestro/bin"

# Boot simulator (iPhone 16 Pro Max = 6.9")
xcrun simctl boot "iPhone 16 Pro Max" 2>/dev/null || true
open -a Simulator

# Install the debug build
xcrun simctl install booted ~/repos/add2wallet/ios/build/Debug-iphonesimulator/Add2Wallet.app

# Run each flow
maestro test maestro/screenshots/01_home.yaml
maestro test maestro/screenshots/02_processing.yaml
maestro test maestro/screenshots/03_pass_ready.yaml
maestro test maestro/screenshots/04_my_passes.yaml
```

Screenshots land in `maestro/screenshots/`.

## Flows
| # | Flow | Description |
|---|------|-------------|
| 01 | home | Empty state — hero card + "Select PDF" |
| 02 | processing | After tapping demo — processing spinner |
| 03 | pass_ready | Pass ready — "Add to Wallet" CTA visible |
| 04 | my_passes | My Passes tab with saved passes |

## Notes
- Run on iPhone 16 Pro Max (6.9") and iPhone 15 Plus (6.5") for App Store requirements
- Screenshots are taken in light mode by default; add `- setDarkMode: false` if needed
- The demo PDF is the built-in Torre Eiffel sample bundled in the app
