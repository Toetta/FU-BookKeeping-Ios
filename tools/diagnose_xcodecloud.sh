#!/bin/bash
set -euo pipefail

# Local diagnostics to quickly probe common Xcode Cloud issues
# Run from repo root: bash tools/diagnose_xcodecloud.sh

say() { echo "[diagnose] $*"; }

say "Repo root: $(pwd)"

say "Git remotes:"; git remote -v || true
say "Current branch:"; git rev-parse --abbrev-ref HEAD || true

say "Looking for Xcode project/workspace..."
XCODEPROJ=$(find . -name "*.xcodeproj" | head -n 1 || true)
XCWSPC=$(find . -name "*.xcworkspace" | head -n 1 || true)
say "Project: ${XCODEPROJ:-none}"
say "Workspace: ${XCWSPC:-none}"

if [ -n "${XCODEPROJ:-}" ]; then
  say "Listing schemes via xcodebuild -list"
  xcodebuild -list -project "$XCODEPROJ" || true
  say "Shared schemes:"
  ls -la "$XCODEPROJ/xcshareddata/xcschemes" || true
fi

say "Checking CI scripts..."
ls -la ci_scripts || true

say "Node/npm versions (if installed):"
command -v node >/dev/null 2>&1 && node -v || say "node not found"
command -v npm  >/dev/null 2>&1 && npm -v  || say "npm not found"

say "Capacitor config present?"
ls -la capacitor.config.* || true

say "Bundle identifiers from Info.plist (if present):"
/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' $(find . -name Info.plist | tr '\n' ' ') 2>/dev/null || true

say "Done. Review output above for missing shared schemes, scripts, or misconfig."
