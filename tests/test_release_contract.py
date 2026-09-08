#!/usr/bin/env python3
"""验证 Release workflow、资产名称和安装说明保持一致。"""

from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def require(text: str, needle: str, label: str):
    assert needle in text, f"{label} 缺少: {needle}"


def main():
    workflow = (ROOT / ".github/workflows/build.yml").read_text(encoding="utf-8")
    readme = (ROOT / "README.md").read_text(encoding="utf-8")
    openwrt_readme = (ROOT / "OpenWrt/README.md").read_text(encoding="utf-8")

    require(workflow, "tags:\n      - 'v*'", "Release tag trigger")
    require(workflow, "needs: [validate-openwrt, build-windows-qt, build-macos]", "Release dependencies")
    require(workflow, "if: startsWith(github.ref, 'refs/tags/v')", "Release guard")
    require(workflow, 'VERSION_FILE="$(cat VERSION)"', "VERSION source")
    require(workflow, 'test "$VERSION_FILE" = "$TAG_VERSION"', "tag/version equality")
    require(workflow, "sha256sum HAUTNetworkGuard-Windows.zip HAUTNetworkGuard.dmg > SHA256SUMS", "desktop checksum manifest")
    require(workflow, "find OpenWrt -type f", "OpenWrt checksum manifest")
    require(workflow, "name: Validate Release Assets", "Release asset validation step")
    require(workflow, "release-dry-run:", "PR 发布资产 dry-run job")
    require(workflow, "name: Generate And Validate Release Bundle", "发布资产 dry-run 校验步骤")
    require(workflow, "unzip -t HAUTNetworkGuard-Windows.zip", "发布资产 dry-run ZIP 校验")
    require(workflow, "sha256sum -c SHA256SUMS", "发布资产 dry-run 哈希校验")
    require(workflow, "sha256sum -c SHA256SUMS", "desktop checksum verification")
    require(workflow, 'grep -Fq "OpenWrt/$path" OpenWrt-SHA256SUMS', "OpenWrt manifest coverage")
    online_install = (ROOT / "OpenWrt/install-online.sh").read_text(encoding="utf-8")
    require(online_install, 'EXPECTED_VERSION="${REPO_REF#v}"', "OpenWrt tag/version guard")
    require(online_install, '"$VERSION" != "$EXPECTED_VERSION"', "OpenWrt tag/version equality")
    online_upgrade = (ROOT / "OpenWrt/upgrade-online.sh").read_text(encoding="utf-8")
    require(online_upgrade, 'EXPECTED_VERSION="${REPO_REF#v}"', "OpenWrt upgrade tag/version guard")
    require(online_upgrade, '"$REMOTE_VERSION" != "$EXPECTED_VERSION"', "OpenWrt upgrade tag/version equality")
    for asset in (
        "HAUTNetworkGuard-Windows.zip",
        "HAUTNetworkGuard.dmg",
        "SHA256SUMS",
        "OpenWrt-SHA256SUMS",
    ):
        require(workflow, asset, "Release asset")
    require(workflow, "HAUTNetworkGuard/${{ steps.get_version.outputs.VERSION }}/OpenWrt/install-online.sh", "Release OpenWrt URL")
    require(workflow, "sh -s -- ${{ steps.get_version.outputs.VERSION }}", "Release OpenWrt version argument")

    for asset in ("HAUTNetworkGuard-Windows.zip", "HAUTNetworkGuard.dmg", "SHA256SUMS"):
        require(readme, asset, "README")
    require(openwrt_readme, "OpenWrt-SHA256SUMS", "OpenWrt README")

    print("release contract ok")


if __name__ == "__main__":
    main()
