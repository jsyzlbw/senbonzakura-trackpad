#!/bin/bash
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
movie="$root/Assets/Senbonzakura.mp4"
score=
case ${1:-} in
    "") ;;
    --midi)
        [[ $# == 2 && -f "$2" ]] || { echo 'Usage: scripts/build.sh [--midi path/to/score.mid]' >&2; exit 2; }
        score=$2 ;;
    *) echo 'Usage: scripts/build.sh [--midi path/to/score.mid]' >&2; exit 2 ;;
esac

if [[ ! -s "$movie" ]]; then
    echo 'Missing Assets/Senbonzakura.mp4. Generate the MV as described in the README before building.' >&2
    exit 1
fi

name='千本樱·声画合演.app'
output="$root/build"
mkdir -p "$output"
staging=$(mktemp -d "${TMPDIR:-/tmp}/senbon-build.XXXXXX")
publish=$(mktemp -d "$output/.install.XXXXXX")
trap 'rm -rf -- "$staging" "$publish"' EXIT
app="$staging/$name"
contents="$app/Contents"
mkdir -p "$contents"/{MacOS,Helpers,Resources}

# Native builds need only the installed Command Line Tools. ARCHS="arm64 x86_64" creates a universal bundle.
read -ra architectures <<< "${ARCHS:-$(uname -m)}"
compile() {
    local src=$1 executable=$2 architecture
    local binaries=()
    for architecture in "${architectures[@]}"; do
        case "$architecture" in arm64|x86_64) ;; *) echo "Unsupported architecture: $architecture" >&2; return 1 ;; esac
        local binary="$staging/$(basename "$executable")-$architecture"
        xcrun swiftc -O -target "$architecture-apple-macos14.0" "$src" -o "$binary"
        binaries+=("$binary")
    done
    if [[ ${#binaries[@]} == 1 ]]; then
        cp "${binaries[0]}" "$executable"
    else
        xcrun lipo -create "${binaries[@]}" -output "$executable"
    fi
}

compile "$root/Sources/Show.swift" "$contents/MacOS/Show"
compile "$root/Sources/Haptic.swift" "$contents/Helpers/Haptic"
compile "$root/Sources/PrepareScore.swift" "$contents/Helpers/PrepareScore"
cp "$root/Resources/Info.plist" "$contents/Info.plist"
cp -X "$movie" "$contents/Resources/Senbonzakura.mp4"
cp "$root/LICENSES/nospeaker.txt" "$contents/Resources/NOSPEAKER-LICENSE"
if [[ -n "$score" ]]; then
    "$contents/Helpers/PrepareScore" "$score" "$contents/Resources/Performance.mid"
fi

for tool in Haptic PrepareScore; do
    codesign --force --sign - "$contents/Helpers/$tool"
done
codesign --force --sign - "$app"
codesign --verify --deep --strict "$app"
ditto --norsrc --noextattr "$app" "$publish/$name"
codesign --verify --deep "$publish/$name"

# Move the entire bundle so that a clean build can never retain a previously embedded MIDI.
if [[ -e "$output/$name" ]]; then
    mv "$output/$name" "$publish/previous.app"
fi
if ! mv "$publish/$name" "$output/$name"; then
    if [[ -d "$publish/previous.app" ]]; then mv "$publish/previous.app" "$output/$name"; fi
    exit 1
fi
echo "$output/$name"
