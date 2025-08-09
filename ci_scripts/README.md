# Xcode Cloud Configuration for Add2Wallet

This directory contains the build scripts necessary for Xcode Cloud to properly build the Add2Wallet Tuist-managed iOS project.

## Files Overview

- **`ci_post_clone.sh`** - Runs immediately after repository clone, verifies project structure
- **`ci_pre_xcodebuild.sh`** - Installs Tuist and generates the Xcode project before build (primary script)
- **`ci_pre_xcodebuild_mise.sh`** - Alternative script using Mise version manager (backup option)
- **`install_tuist_fallback.sh`** - Fallback installation script with multiple Tuist install methods
- **`README.md`** - This documentation file

## How It Works

1. **Post-Clone**: Xcode Cloud clones the repository and runs `ci_post_clone.sh` to verify the project structure
2. **Pre-Build**: Before attempting to build, `ci_pre_xcodebuild.sh` runs to:
   - Install Tuist using the official installer
   - Navigate to the `ios/` directory
   - Clean any existing generated files
   - Generate the Xcode project using `tuist generate`
   - Verify the generation was successful
3. **Build**: Xcode Cloud proceeds with the normal build process using the generated `.xcodeproj` and `.xcworkspace` files

## Repository Structure

```
add2wallet/
├── ci_scripts/          # ← Xcode Cloud scripts (this directory)
│   ├── ci_post_clone.sh
│   ├── ci_pre_xcodebuild.sh
│   └── ...
├── ios/                 # ← iOS project with Tuist
│   ├── Project.swift
│   ├── Add2Wallet/
│   └── ...
├── backend/             # ← Python backend
└── ...
```

## Xcode Cloud Setup Steps

1. **Enable Xcode Cloud** in your Apple Developer account
2. **Connect Repository** to your GitHub/GitLab/Bitbucket repository
3. **Configure Workflow**:
   - Set the branch you want to build (e.g., `main`)
   - Choose "Archive" or "Build" action
   - Select the scheme: `Add2Wallet`
   - Set the platform: iOS
   - **Important**: Set the "Primary Repository" path to the root (not `ios/`)
4. **Test Plan**: The project includes `ios/Add2Wallet.xctestplan` for running tests

## Troubleshooting

### If builds fail:

1. **Check Tuist Installation**: Look at the build logs to see if Tuist installed correctly
2. **Try Alternative Script**: Rename `ci_pre_xcodebuild_mise.sh` to `ci_pre_xcodebuild.sh` to use Mise instead
3. **Verify Project Structure**: Ensure `ios/Project.swift` exists and is valid
4. **Check Xcode Version**: Verify the Xcode Cloud Xcode version is compatible with your Tuist config

### Common Issues:

- **Script Not Found**: Ensure CI scripts are at the repository root, not in `ios/ci_scripts/`
- **Network Issues**: Tuist installer may fail due to network restrictions
- **Permission Issues**: Scripts need execute permissions (should be set automatically)
- **Path Issues**: Tuist may not be in PATH - scripts handle this
- **Generation Failures**: Check `ios/Project.swift` syntax and dependencies

## Manual Testing

You can test the scripts locally:

```bash
# From the repository root
./ci_scripts/ci_post_clone.sh

# Test the setup script
./ci_scripts/ci_pre_xcodebuild.sh

# Verify the generated project
cd ios
ls -la *.xcworkspace/
ls -la *.xcodeproj/
```

## Key Differences from iOS-only Projects

- **Repository Root**: Scripts are at the root level, not in `ios/ci_scripts/`
- **Directory Navigation**: Scripts navigate to `ios/` directory before running Tuist commands
- **Project Structure**: Handles monorepo structure with iOS project in subdirectory

## Environment Variables

The scripts don't require any custom environment variables, but you can set these in Xcode Cloud if needed:

- `TUIST_VERSION` - Specify a particular Tuist version
- `CI_WORKSPACE` - Xcode Cloud sets this automatically

## Support

- [Tuist Documentation](https://tuist.io)
- [Xcode Cloud Documentation](https://developer.apple.com/xcode-cloud/)
- [Tuist CI/CD Guide](https://docs.tuist.io/guides/continuous-integration)