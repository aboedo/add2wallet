# Xcode Cloud Troubleshooting Guide

## Issues Identified and Fixed

### ✅ **Fixed Issues:**

1. **Incorrect Tuist Version Command**
   - **Problem**: Scripts used `tuist --version` (invalid command)
   - **Fix**: Changed to `tuist version` in all CI scripts
   - **Files Fixed**: `ci_pre_xcodebuild.sh`, `ci_pre_xcodebuild_mise.sh`, `install_tuist_fallback.sh`

2. **Redundant Tuist Installation**
   - **Problem**: Scripts always tried to install Tuist, even when already present
   - **Fix**: Added installation check before attempting download
   - **Benefit**: Faster CI builds, fewer network calls

3. **PATH Issues**
   - **Problem**: Tuist might not be found in PATH on Xcode Cloud
   - **Fix**: Added common installation paths: `$HOME/.tuist/bin:/opt/homebrew/bin:/usr/local/bin`

## Current Configuration Status

### ✅ **Correctly Configured:**

- **CI Scripts Location**: `ci_scripts/` at repository root ✅
- **File Permissions**: All scripts are executable (`chmod +x`) ✅  
- **Project Structure**: iOS project in `ios/` subdirectory ✅
- **Tuist Project**: `ios/Project.swift` exists and valid ✅
- **Schemes**: Shared schemes available for Xcode Cloud ✅
- **Test Plan**: `ios/Add2Wallet.xctestplan` exists ✅

## Xcode Cloud Setup Checklist

### 1. Repository Configuration
- [ ] Ensure this repository is connected to Xcode Cloud
- [ ] Set "Primary Repository" to the root (not `ios/` subdirectory)
- [ ] Verify branch permissions and webhook setup

### 2. Workflow Configuration  
- [ ] Create workflow in Xcode Cloud dashboard
- [ ] Set source branch (e.g., `main`)
- [ ] Choose scheme: **Add2Wallet** (not Add2Wallet-Workspace)
- [ ] Set platform: **iOS**
- [ ] Choose action: **Build** or **Archive**

### 3. Environment Variables (Optional)
You can set these in Xcode Cloud if needed:
- `TUIST_VERSION`: Pin to specific version (e.g., "4.58.1")
- `CI_WORKSPACE`: Set automatically by Xcode Cloud

### 4. Build Settings
- **Xcode Version**: Ensure compatible with Tuist version
- **iOS SDK**: Use latest stable
- **Scheme**: Use `Add2Wallet` (not workspace scheme)

## Testing Locally

Test the CI scripts locally to verify they work:

```bash
# Test post-clone script
./ci_scripts/ci_post_clone.sh

# Test pre-build script  
./ci_scripts/ci_pre_xcodebuild.sh

# Verify generated files
ls -la ios/*.xcworkspace/
ls -la ios/*.xcodeproj/

# Test build
cd ios
xcodebuild -workspace Add2Wallet.xcworkspace -scheme Add2Wallet -destination 'platform=iOS Simulator,name=iPhone 15,OS=latest' build
```

## Common Xcode Cloud Errors & Solutions

### "No such file or directory: ci_scripts"
- **Cause**: Scripts not at repository root
- **Solution**: Ensure `ci_scripts/` is at the root of your primary repository

### "Command not found: tuist"
- **Cause**: Tuist installation failed or PATH issue
- **Solution**: Check build logs for installation errors, try fallback script

### "Unknown option '--version'"
- **Cause**: Using wrong Tuist command syntax
- **Solution**: ✅ **FIXED** - Now using `tuist version`

### "Permission denied"
- **Cause**: CI scripts not executable
- **Solution**: `chmod +x ci_scripts/*.sh` (should be automatic)

### "Project generation failed"
- **Cause**: Invalid `Project.swift` or missing dependencies  
- **Solution**: Test `tuist generate` locally, check syntax

### "Scheme not found"
- **Cause**: Scheme not shared or wrong name
- **Solution**: Use scheme name exactly as shown in Xcode

## Build Optimization Tips

1. **Cache Tuist**: Installation check speeds up builds
2. **Use Fallback**: Multiple installation methods improve reliability
3. **Minimal Logging**: Reduce CI log noise while keeping essential info
4. **Test Locally**: Always test scripts locally before pushing

## Next Steps

1. **Push Changes**: Commit the fixed CI scripts
2. **Trigger Build**: Create a new Xcode Cloud build
3. **Check Logs**: Monitor build logs for any remaining issues
4. **Iterate**: Make adjustments based on build results

## Updated Files

The following files have been updated:
- `ci_scripts/ci_pre_xcodebuild.sh` - Main build script
- `ci_scripts/ci_pre_xcodebuild_mise.sh` - Alternative with Mise
- `ci_scripts/install_tuist_fallback.sh` - Fallback installer

## Support Resources

- [Tuist Documentation](https://tuist.io)
- [Xcode Cloud Documentation](https://developer.apple.com/xcode-cloud/)
- [Tuist CI/CD Guide](https://docs.tuist.io/guides/continuous-integration)