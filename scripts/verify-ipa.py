"""Check that the artifact is an unsigned, ARM64 iPhone device application."""
import argparse
import plistlib
import struct
import zipfile
from pathlib import Path


def verify(path):
    with zipfile.ZipFile(path) as archive:
        bad = archive.testzip()
        if bad:
            raise ValueError(f"Corrupt ZIP member: {bad}")
        names = archive.namelist()
        manifests = [n for n in names if n.startswith("Payload/")
                     and n.endswith(".app/Info.plist") and n.count("/") == 2]
        if len(manifests) != 1:
            raise ValueError("Expected exactly one Payload/*.app/Info.plist")
        manifest = manifests[0]
        app = manifest.rsplit("/", 1)[0]
        info = plistlib.loads(archive.read(manifest))
        if info.get("CFBundleSupportedPlatforms") != ["iPhoneOS"]:
            raise ValueError("Expected an iPhoneOS device build, not a simulator")
        executable = info.get("CFBundleExecutable", "")
        if not executable or "/" in executable or "\\" in executable:
            raise ValueError("Invalid CFBundleExecutable")
        entry = archive.getinfo(f"{app}/{executable}")
        if not (entry.external_attr >> 16) & 0o111:
            raise ValueError("The app executable has no executable permission in the ZIP")
        data = archive.read(entry)
        # This configuration produces a thin, little-endian ARM64 Mach-O executable.
        if len(data) < 32:
            raise ValueError("Truncated executable")
        magic, cpu, _, filetype, ncmds, sizeofcmds, _, _ = struct.unpack_from("<8I", data)
        if (magic, cpu, filetype) != (0xFEEDFACF, 0x0100000C, 2):
            raise ValueError("Expected a thin ARM64 Mach-O executable")
        end = 32 + sizeofcmds
        if end > len(data):
            raise ValueError("Truncated Mach-O load commands")
        offset = 32
        for _ in range(ncmds):
            if offset + 8 > end:
                raise ValueError("Truncated Mach-O command header")
            command, size = struct.unpack_from("<2I", data, offset)
            if size < 8 or offset + size > end:
                raise ValueError("Invalid Mach-O load command size")
            if command == 0x1D:  # LC_CODE_SIGNATURE
                raise ValueError("Executable already has a code signature")
            offset += size
        if offset != end:
            raise ValueError("Inconsistent Mach-O command table")
        if any(n.startswith(f"{app}/_CodeSignature/")
               or n == f"{app}/embedded.mobileprovision" for n in names):
            raise ValueError("Unexpected signature or provisioning profile")
        print(f"Verified: {path.name}; ARM64 iPhoneOS; unsigned; "
              f"bundle={info.get('CFBundleIdentifier')}; "
              f"version={info.get('CFBundleShortVersionString')}; "
              f"minimum iOS={info.get('MinimumOSVersion')}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("ipa", type=Path)
    args = parser.parse_args()
    try:
        verify(args.ipa)
    except (OSError, ValueError, KeyError, zipfile.BadZipFile) as error:
        parser.exit(1, f"IPA validation failed: {error}\n")
