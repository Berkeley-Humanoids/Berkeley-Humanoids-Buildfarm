#!/usr/bin/env bash
# Upload ./output/*.conda to the prefix.dev channel. See README.md.
#   Usage: pixi run publish
#   CHANNEL defaults to berkeley-humanoids. Without PREFIX_API_KEY, the upload
#   uses OIDC trusted publishing instead.
#
# --skip-existing never replaces a package that the channel already holds. A
# rebuild at an unchanged version therefore publishes nothing, and still reports
# success.
set -euo pipefail
cd "$(dirname "$0")/.."

channel="${CHANNEL:-berkeley-humanoids}"

# pixi writes into output/. rattler-build writes into output/<platform>/.
mapfile -t packages < <(find output -name '*.conda' 2>/dev/null | sort)
if [ ${#packages[@]} -eq 0 ]; then
  echo "::error::no .conda files in output/ — run 'pixi run package' first" >&2
  exit 1
fi

api_key=()
if [ -n "${PREFIX_API_KEY:-}" ]; then
  api_key=(--api-key "$PREFIX_API_KEY")
fi

echo "uploading ${#packages[@]} package(s) to prefix.dev/$channel"
rattler-build upload prefix --skip-existing -c "$channel" "${api_key[@]}" "${packages[@]}"
