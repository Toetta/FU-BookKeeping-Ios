#!/bin/bash
set -euo pipefail

echo "[Xcode Cloud] ci_post_clone.sh starting"

cd "${CI_PRIMARY_REPOSITORY_PATH:-$(pwd)}"

echo "[Xcode Cloud] Repository: $(pwd)"
echo "[Xcode Cloud] Node: $(node --version)"
echo "[Xcode Cloud] npm: $(npm --version)"

npm ci
npm run build:verify
npx cap sync ios

echo "[Xcode Cloud] ci_post_clone.sh finished"
