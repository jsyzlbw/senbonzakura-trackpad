#!/bin/bash
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
mkdir -p "$root/Assets" "$root/build"
scratch=$(mktemp -d "$root/build/render.XXXXXX")
trap 'rm -rf "$scratch"' EXIT
xcrun swiftc -O "$root/Art/Encode.swift" "$root/Art/SenbonArt.swift" -o "$scratch/Encode"
"$scratch/Encode" "$scratch/Senbonzakura.mp4" 0 7521
mv -f "$scratch/Senbonzakura.mp4" "$root/Assets/Senbonzakura.mp4"
