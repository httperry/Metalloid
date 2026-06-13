#!/bin/bash
# run_game.sh - Metalloid Game Launch Wrapper

if [ -z "$1" ]; then
    echo "Usage: ./run_game.sh /path/to/game.exe [arguments]"
    exit 1
fi

GAME_EXE="$1"
shift

# 1. Path to our built d3d12.dll and dxgi.dll libraries
METALLOID_BUILD_DIR="/Users/niranjana/System/Metalloid/build"

# 2. Tell Wine to prefer local (native) DLLs over built-in ones
# 'n' means Native (our compiled ones), 'b' means Builtin (Wine's ones)
export WINEDLLOVERRIDES="d3d12=n;dxgi=n"

# 3. Add the build directory to the dynamic linker path so Wine resolves dependencies
export DYLD_LIBRARY_PATH="$METALLOID_BUILD_DIR:$DYLD_LIBRARY_PATH"

# 4. Launch the game using the Wine executable
# Adjust the path to your Wine / GPTK Wine installation as necessary
WINE_PATH="/opt/homebrew/bin/wine64" # Or Wine path from Crossover / GPTK

echo "[Metalloid] Launching: $GAME_EXE"
"$WINE_PATH" "$GAME_EXE" "$@"
