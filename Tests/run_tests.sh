#!/bin/bash
# run_tests.sh - Metalloid Automated Test Suite Runner

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}===================================================${NC}"
echo -e "${BLUE}        Metalloid Automated Test Suite             ${NC}"
echo -e "${BLUE}===================================================${NC}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="$SCRIPT_DIR/../build"

# 1. Compile the latest codebase
echo -e "\n${YELLOW}[1/3] Building the latest test binaries...${NC}"
mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR" || exit 1

cmake .. > /dev/null
make -j8 > /dev/null
if [ $? -ne 0 ]; then
    echo -e "${RED}ERROR: Compilation failed!${NC}"
    exit 1
fi
echo -e "${GREEN}Build successful!${NC}"

# Initialize Statuses
DETECTED_CPU="Unknown"
RASTER_STATUS="FAIL"
SHADER_STATUS="FAIL"
DECODER_STATUS="FAIL"

# 2. Run test_triangle
echo -e "\n${YELLOW}[2/3] Running Triangle Rasterization Test...${NC}"
RASTER_OUT=$(./test_triangle 2>&1)
if [ $? -eq 0 ]; then
    RASTER_STATUS="PASS"
fi

# Extract detected CPU from output
DETECTED_CPU=$(echo "$RASTER_OUT" | grep "Detected Apple Silicon Generation" | cut -d':' -f2 | xargs)
if [ -z "$DETECTED_CPU" ]; then
    DETECTED_CPU="Unknown / Intel"
fi

# 3. Run test_triangle_shader
echo -e "${YELLOW}[3/3] Running Shader Pipeline compilation Test...${NC}"
SHADER_OUT=$(./test_triangle_shader 2>&1)
if [ $? -eq 0 ]; then
    SHADER_STATUS="PASS"
fi

# 4. Run test_decoder
DECODER_OUT=$(./test_decoder 2>&1)
if [ $? -eq 0 ]; then
    DECODER_STATUS="PASS"
fi

# 5. Print Summary Table
echo -e "\n${BLUE}===================================================${NC}"
echo -e "${BLUE}                TEST SUITE SUMMARY                 ${NC}"
echo -e "${BLUE}===================================================${NC}"
echo -e "Detected Hardware Family : ${GREEN}$DETECTED_CPU${NC}"
echo -e "---------------------------------------------------"

# Format Row Helper
print_row() {
    local name="$1"
    local status="$2"
    local desc="$3"
    if [ "$status" == "PASS" ]; then
        printf "%-32s | [ ${GREEN}PASS${NC} ] | %s\n" "$name" "$desc"
    else
        printf "%-32s | [ ${RED}FAIL${NC} ] | %s\n" "$name" "$desc"
    fi
}

print_row "Triangle Rasterization" "$RASTER_STATUS" "5 frames presented cleanly to swapchain"
print_row "Shader Pipeline Compilation" "$SHADER_STATUS" "Dynamic MSL compilation & draw call dispatch"
print_row "Video Decoder Limits (AV1)" "$DECODER_STATUS" "AV1 decoder blocked/allowed based on gen"

echo -e "${BLUE}===================================================${NC}"

if [ "$RASTER_STATUS" == "PASS" ] && [ "$SHADER_STATUS" == "PASS" ] && [ "$DECODER_STATUS" == "PASS" ]; then
    echo -e "${GREEN}ALL TESTS PASSED SUCCESSFULLY!${NC}"
    exit 0
else
    echo -e "${RED}SOME TESTS FAILED! Check build log.${NC}"
    exit 1
fi
