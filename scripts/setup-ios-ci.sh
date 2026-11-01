#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."
mkdir -p artifacts
exec > >(tee artifacts/setup.log) 2>&1

fail() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
[[ "$(uname -s)" == Darwin ]] || fail 'Xcode requires macOS; run the GitHub Actions workflow.'
[[ "$(uname -m)" == x86_64 ]] || fail 'This workflow requires the macos-15-intel runner.'
[[ "${GITHUB_ACTIONS:-}" == true ]] || fail 'This installer is intended for a disposable GitHub Actions runner.'

export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode_16.2.app/Contents/Developer}"
[[ -d "$DEVELOPER_DIR" ]] || fail "Pinned Xcode is missing: $DEVELOPER_DIR. See BUILD-IOS.md."
sudo xcode-select --switch "$DEVELOPER_DIR"
xcodebuild -version
[[ "$(xcodebuild -version | head -n 1)" == 'Xcode 16.2' ]] || fail 'Xcode 16.2 is required by this configuration.'
[[ "$(xcrun --sdk iphoneos --show-sdk-version)" == 18.2 ]] || fail 'The iOS 18.2 SDK is missing.'

# actool/storyboard compilation also uses CoreSimulator, even for device builds.
xcodebuild -downloadPlatform iOS -buildVersion 18.2

download_dir="$(mktemp -d "${RUNNER_TEMP}/mageki-tools.XXXXXX")"
trap 'rm -rf "$download_dir"' EXIT
mono_pkg="$download_dir/mono.pkg"
xamarin_pkg="$download_dir/xamarin-ios.pkg"

curl --fail --location --retry 3 --connect-timeout 30 --max-time 900 \
  'https://download.mono-project.com/archive/6.12.0/macos-10-universal/MonoFramework-MDK-6.12.0.206.macos10.xamarin.universal.pkg' \
  --output "$mono_pkg"
printf '%s  %s\n' '80b0dbfa59ba9ed76dbf1393998e6a2ed2d1ccc8f5850c7a46fbe31a2aea88d8' "$mono_pkg" | shasum -a 256 --check
pkgutil --check-signature "$mono_pkg"
sudo installer -pkg "$mono_pkg" -target /

# Fixed official archive URL, listed in dotnet/macios/DOWNLOADS.md.
curl --fail --location --retry 3 --connect-timeout 30 --max-time 900 \
  'https://download.visualstudio.microsoft.com/download/pr/ceb0ea3f-4db8-46b4-8dc3-8049d27c0107/3960868aa9b1946a6c77668c3f3334ee/xamarin.ios-16.4.0.23.pkg' \
  --output "$xamarin_pkg"
pkgutil --check-signature "$xamarin_pkg"
sudo installer -pkg "$xamarin_pkg" -target /

export PATH="/Library/Frameworks/Mono.framework/Versions/Current/Commands:$PATH"
printf '%s\n' '/Library/Frameworks/Mono.framework/Versions/Current/Commands' >> "$GITHUB_PATH"
mono --version
msbuild -version
/Library/Frameworks/Xamarin.iOS.framework/Versions/Current/bin/mtouch --version
[[ "$(dotnet --version)" == 5.0.214 ]] || fail 'The .NET SDK must match global.json (5.0.214).'
[[ -f /Library/Frameworks/Mono.framework/Versions/Current/lib/mono/xbuild/Xamarin/iOS/Xamarin.iOS.CSharp.targets ]] || fail 'Xamarin.iOS MSBuild targets were not installed.'
