#!/bin/zsh
# Builds the share sheet's native code (native/share/share.mm) into
# native/share/bin/libshare.ios.dylib, which the iOS export packs into the
# app, and libshare.macos.dylib, which does nothing (the Mac's tools load
# it instead of printing an error). Re-run it only after changing
# share.mm (the two .dylib files are committed).
#
# Needs godot-cpp (the C++ kit for GDExtensions) OUTSIDE the project, next
# to it, with its own scons: the first run fetches both (~3 min a platform).
set -e
cd "$(dirname "$0")/.."
GODOT_CPP="${GODOT_CPP:-$(cd .. && pwd)/godot-cpp}"
TAG=godot-4.5-stable    # the newest godot-cpp; a 4.5 extension runs on Godot 4.7

if [ ! -d "$GODOT_CPP" ]; then
	git clone --depth 1 --branch "$TAG" https://github.com/godotengine/godot-cpp.git "$GODOT_CPP"
fi
if [ ! -x "$GODOT_CPP/.venv/bin/scons" ]; then
	python3 -m venv "$GODOT_CPP/.venv"
	"$GODOT_CPP/.venv/bin/pip" install -q scons
fi

cd native/share
# iOS 15: the oldest iOS Godot 4.7's apps run on (the export's own minimum).
GODOT_CPP="$GODOT_CPP" "$GODOT_CPP/.venv/bin/scons" platform=ios ios_min_version=15.0 arch=arm64 target=template_release -j8
rm -f share.os    # the object file: only the .dylib is kept
GODOT_CPP="$GODOT_CPP" "$GODOT_CPP/.venv/bin/scons" platform=macos arch=arm64 target=template_release -j8
rm -f share.os
ls -la bin/
