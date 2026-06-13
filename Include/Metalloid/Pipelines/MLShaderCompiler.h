#pragma once

#include "d3d12_mac_common.h"
#include <string>
#include <vector>
#include <metal_irconverter/metal_irconverter.h>

namespace Metalloid {

class MLShaderCompiler {
public:
    static std::string TranslateDXILToMSL(const void* dxilBytecode, SIZE_T bytecodeLength, const char* entryPoint, const char* targetProfile, UINT* outTgX = nullptr, UINT* outTgY = nullptr, UINT* outTgZ = nullptr);
    static std::string TranslateWorkGraphToMSL(const D3D12_WORK_GRAPH_DESC* wgDesc);
    static std::vector<uint8_t> TranslateDXILToMetallibData(const void* dxilBytecode, SIZE_T bytecodeLength, const char* entryPoint, const char* targetProfile);
};

} // namespace Metalloid
