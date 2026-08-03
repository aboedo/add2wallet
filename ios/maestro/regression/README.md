# Regression flows

Flows that pin down bugs we've already fixed. Unlike `maestro/screenshots/`,
these assert behaviour rather than producing App Store assets.

## Requirements
- Maestro 2.6+, Java 21+
- A booted simulator with the Debug build installed
- Onboarding already completed (`maestro/screenshots/00_setup.yaml`)

A fresh install also raises a StoreKit "Sign in to Apple Account" system alert
that Maestro can't see in the view hierarchy, so these flows deliberately use
`clearState: false`. If the alert is on screen, dismiss it once by hand (or with
`tapOn: point: "31%,44%"`) before running them.

## portrait_image_preview.yaml

A tall phone screenshot (1320x2868) imported through the Photos picker used to
blow out the whole screen when "View original file" was expanded:
`ImageFilePreviewView` wrapped a bare `UIImageView`, whose intrinsic content size
is the image's pixel size, so it demanded 1320pt of width from SwiftUI. The
collapsed thumbnail was fine only because it pins both width and height.

```bash
cd ios
export PATH="/opt/homebrew/opt/openjdk@21/bin:$PATH:$HOME/.maestro/bin"

# One-off: build the fixture and put it in the simulator's photo library
python3 maestro/regression/make_fixture.py
xcrun simctl addmedia booted maestro/regression/output/portrait_ticket.png

maestro test maestro/regression/portrait_image_preview.yaml
```

Screenshots land in `maestro/regression/output/` (gitignored — imported tickets
are personal data and must not end up in this repo).
