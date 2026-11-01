#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."
project_root="$PWD"
mkdir -p artifacts
exec > >(tee artifacts/build.log) 2>&1
fail() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
[[ "$(uname -s)" == Darwin ]] || fail 'This build requires macOS and Xcode. Use GitHub Actions from Windows.'

export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode_16.2.app/Contents/Developer}"
export PATH="/Library/Frameworks/Mono.framework/Versions/Current/Commands:$PATH"
command -v msbuild >/dev/null || fail 'Mono MSBuild is missing.'
[[ "$(xcodebuild -version | head -n 1)" == 'Xcode 16.2' ]] || fail 'Use the pinned Xcode 16.2 toolchain.'
[[ "$(dotnet --version)" == 5.0.214 ]] || fail 'Install the SDK specified in global.json.'

# Keep the source manifest unchanged. Xcode 16.2 no longer targets iOS 8.
manifest="$project_root/artifacts/Unsigned-Info.plist"
cp Mageki/Mageki.iOS/Info.plist "$manifest"
/usr/libexec/PlistBuddy -c 'Set :MinimumOSVersion 12.0' "$manifest"
ipa="$project_root/artifacts/Mageki-unsigned.ipa"
# Never accidentally upload a stale package after a failed build.
rm -f "$ipa" "$ipa.sha256"

msbuild Mageki/Mageki.iOS/Mageki.iOS.csproj \
  -restore -t:Rebuild -verbosity:minimal -nologo \
  -p:Configuration=Release -p:Platform=iPhone \
  -p:MagekiUnsignedIpa=true \
  "-p:AppManifest=$manifest" \
  "-p:IpaPackageDir=$project_root/artifacts/" \
  -p:IpaPackageName=Mageki-unsigned.ipa \
  "-bl:$project_root/artifacts/build.binlog"

[[ -s "$ipa" ]] || fail 'MSBuild returned without producing an IPA.'
python3 scripts/verify-ipa.py "$ipa"
(
  cd artifacts
  shasum -a 256 Mageki-unsigned.ipa > Mageki-unsigned.ipa.sha256
)
cp Mageki/Mageki.iOS/Entitlements.plist artifacts/Entitlements.plist
cat > artifacts/INSTALL.txt <<'EOF'
This is an UNSIGNED iPhone/iPad ARM64 application, targeting iOS 12 or later.
Sign it with your own certificate and provisioning profile before installing.
The original bundle ID is icu.sanhei.mageki; the signing service may replace it.
Entitlements.plist is provided separately for re-signing, not embedded as a signature.
NFC reading requires an eligible profile with the NFC Tag Reading capability.
An account/profile without that capability may install an app without working NFC,
or may reject signing if unsupported NFC entitlements are retained.
This package is not an App Store or TestFlight submission.
EOF
printf 'Verified unsigned IPA: %s\n' "$ipa"
