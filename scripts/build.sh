#!/usr/bin/env bash
# Build every package in packages.txt into ./output. See README.md.
#   Usage: pixi run package [platform]   (platform defaults to linux-64)
set -euo pipefail
cd "$(dirname "$0")/.."

platform="${1:-linux-64}"

# Keep these subdirectories equal to `platforms` in pixi.toml, plus noarch.
# Every subdirectory needs an index. The committed empty index permits pixi to
# read the channel on a fresh clone. pixi reads every channel before it runs a
# task.
seed_local_channel() {
  rm -rf local-channel
  for subdir in noarch linux-64 linux-aarch64; do
    mkdir -p "local-channel/$subdir"
    printf '{"info":{"subdir":"%s"},"packages":{},"packages.conda":{}}\n' "$subdir" \
      >"local-channel/$subdir/repodata.json"
  done
}

# Empty the channel before the first build. A package from an earlier run must
# not satisfy a dependency in this one. Empty it again at the end, to leave the
# working tree clean.
seed_local_channel
mkdir -p output

while read -r package; do
  echo "::group::build $package ($platform)"
  if [ -f "$package/pixi.toml" ]; then
    # --path must name the file. The backend misreads a bare directory.
    pixi build --path "$package/pixi.toml" -o output --target-platform "$platform"
  else
    rattler-build build --recipe "$package/recipe.yaml" --output-dir output \
      --target-platform "$platform"
  fi
  # pixi writes into output/. rattler-build writes into output/<platform>/.
  find output -name '*.conda' -exec cp -n {} "local-channel/$platform/" \;
  # The next package in packages.txt builds against this index.
  python -m conda_index local-channel
  echo "::endgroup::"
done < <(grep -vE '^[[:space:]]*(#|$)' packages.txt)

seed_local_channel
