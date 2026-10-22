"""Choose native iOS 27 integrations or a compatible iOS 26 build spec.

Keep project.yml authoritative. The generated spec lives beside it so XcodeGen
resolves source paths the same way. No third-party Python packages are required.
"""
from pathlib import Path
import argparse


def prepare_spec(source: str, sdk_major: int) -> str:
    if sdk_major < 26:
        raise ValueError("Ledger requires Xcode 26+ to build (deployment target remains iOS 17).")
    if sdk_major >= 27:
        marker = "    SWIFT_VERSION: '5.0'"
        assert source.count(marker) == 1, "Swift language setting changed; update prepare_build.py"
        return source.replace(marker, marker + '\n    SWIFT_ACTIVE_COMPILATION_CONDITIONS: "$(inherited) LEDGER_SIRI_AI"')
    icon_marker = "        ASSETCATALOG_COMPILER_APPICON_NAME: Ledger"
    source_marker = "        excludes: [Info.plist]"
    assert source.count(icon_marker) == 1 and source.count(source_marker) == 1, "Project source structure changed"
    return source.replace(icon_marker, icon_marker + "Fallback").replace(
        source_marker,
        "        excludes: [Info.plist, Ledger.icon]\n      - path: Resources/LegacyIcon.xcassets",
    )


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--sdk-version", required=True)
    parser.add_argument("--output", default="project-ci.yml")
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    sdk_major = int(args.sdk_version.split(".")[0])
    spec = prepare_spec((root / "project.yml").read_text(encoding="utf-8"), sdk_major)
    output = root / args.output
    if output.resolve() != root / "project-ci.yml":
        raise ValueError("The generated spec must be project-ci.yml in the repository root.")
    output.write_text(spec, encoding="utf-8")
    mode = "native Icon Composer + Siri AI search" if sdk_major >= 27 else "exported icon + App Shortcuts (SDK 26 compatibility)"
    print(f"Ledger: {mode}")


if __name__ == "__main__":
    main()
