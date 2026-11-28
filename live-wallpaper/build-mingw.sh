#!/usr/bin/env bash
# Cross-compile LiveWallpaper.exe on Linux with MinGW-w64 (apt install mingw-w64).
# MinGW 11 lacks mfmediaengine.h, so the header is fetched from the mingw-w64 project once.
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p build/include dist
if [ ! -f build/include/mfmediaengine.h ]; then
  curl -sSfL -o build/include/mfmediaengine.h \
    https://raw.githubusercontent.com/mingw-w64/mingw-w64/master/mingw-w64-headers/include/mfmediaengine.h
fi
x86_64-w64-mingw32-windres src/app.rc -O coff -o build/app.res.o
x86_64-w64-mingw32-g++ -std=c++17 -O2 -s -static -municode -mwindows -Wall -Wno-unknown-pragmas \
  -Ibuild/include src/main.cpp build/app.res.o -o dist/LiveWallpaper.exe \
  -lmfplat -lmfuuid -lole32 -loleaut32 -lshlwapi -lwtsapi32 -ld3d11 -ldxgi -luuid \
  -lcomdlg32 -lshell32 -luser32 -ladvapi32
ls -la dist/LiveWallpaper.exe
