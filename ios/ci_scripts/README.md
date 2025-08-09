# Xcode Cloud Configuration for Tuist Projects

This directory contains the build scripts necessary for Xcode Cloud to properly build a Tuist-managed project.

## Files Overview

- **`ci_post_clone.sh`** - Runs immediately after repository clone, verifies project structure
- **`ci_pre_xcodebuild.sh`** - Installs Tuist and generates the Xcode project before build (primary script)
- **`ci_pre_xcodebuild_mise.sh`** - Alternative script using Mise version manager (backup option)
- **`README.md`** - This documentation file

## How It Works

1. **Post-Clone**: Xcode Cloud clones the repository and runs `ci_post_clone.sh` to verify the project structure
2. **Pre-Build**: Before attempting to build, `ci_pre_xcodebuild.sh` runs to:
   - Install Tuist using the official installer
   - Navigate to the `ios` directory
   - Clean any existing generated files
   - Generate the Xcode project using `tuist generate`
   - Verify the generation was successful
3. **Build**: Xcode Cloud proceeds with the normal build process using the generated `.xcodeproj` and `.xcworkspace` files

## Xcode Cloud Setup Steps

1. **Enable Xcode Cloud** in your Apple Developer account
2. **Connect Repository** to your GitHub/GitLab/Bitbucket repository
3. **Configure Workflow**:
   - Set the branch you want to build (e.g., `main`)
   - Choose "Archive" or "Build" action
   - Select the scheme: `Add2Wallet`
   - Set the platform: iOS
4. **Test Plan**: The project includes `Add2Wallet.xctestplan` for running tests

## Troubleshooting

### If builds fail:

1. **Check Tuist Installation**: Look at the build logs to see if Tuist installed correctly
2. **Try Alternative Script**: Rename `ci_pre_xcodebuild_mise.sh` to `ci_pre_xcodebuild.sh` to use Mise instead
3. **Verify Project Structure**: Ensure `ios/Project.swift` exists and is valid
4. **Check Xcode Version**: Verify the Xcode Cloud Xcode version is compatible with your Tuist config

### Common Issues:

- **Network Issues**: Tuist installer may fail due to network restrictions
- **Permission Issues**: Scripts need execute permissions (already set)
- **Path Issues**: Tuist may not be in PATH - scripts handle this
- **Generation Failures**: Check `Project.swift` syntax and dependencies

## Manual Testing

You can test the scripts locally:

```bash
cd ios
# Test the setup script
./ci_scripts/ci_pre_xcodebuild.sh

# Verify the generated project
ls -la *.xcworkspace/
ls -la *.xcodeproj/
```

## Environment Variables

The scripts don't require any custom environment variables, but you can set these in Xcode Cloud if needed:

- `TUIST_VERSION` - Specify a particular Tuist version
- `CI_WORKSPACE` - Xcode Cloud sets this automatically

## Support

- [Tuist Documentation](https://tuist.io)
- [Xcode Cloud Documentation](https://developer.apple.com/xcode-cloud/)
- [Tuist CI/CD Guide](https://docs.tuist.io/guides/continuous-integration)