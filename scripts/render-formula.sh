#!/usr/bin/env bash
# Prints the Homebrew formula for a released version.
# Usage: scripts/render-formula.sh <version> <sha256 of Pismo-<version>.zip>
set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "Usage: $0 <version> <sha256>" >&2
  exit 1
fi

VERSION="$1"
SHA256="$2"
REPOSITORY="aleksandargosevski/pismo"

if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "Error: version must look like 1.2.3, got \"$VERSION\"" >&2
  exit 1
fi
if [[ ! "$SHA256" =~ ^[0-9a-f]{64}$ ]]; then
  echo "Error: sha256 must be 64 lowercase hex characters" >&2
  exit 1
fi

cat <<EOF
class Pismo < Formula
  desc "Switches the keyboard layout per app and per text field"
  homepage "https://github.com/${REPOSITORY}"
  url "https://github.com/${REPOSITORY}/releases/download/v${VERSION}/Pismo-${VERSION}.zip"
  sha256 "${SHA256}"

  depends_on arch: :arm64
  depends_on macos: :sonoma

  def install
    # Homebrew enters an archive's single top-level directory, which here is Pismo.app itself.
    source = File.directory?("Contents") ? "." : "Pismo.app"
    (prefix/"Pismo.app").install Dir["#{source}/*"]
  end

  service do
    run [opt_prefix/"Pismo.app/Contents/MacOS/Pismo"]
    keep_alive crashed: true
    process_type :interactive
  end

  def caveats
    <<~EOS
      Start Pismo now and at every login:
        brew services start pismo

      Then allow Pismo in System Settings → Privacy & Security → Accessibility.
      Rules live in ~/.config/pismo/rules.json.
    EOS
  end

  test do
    assert_path_exists prefix/"Pismo.app/Contents/MacOS/Pismo"
  end
end
EOF
