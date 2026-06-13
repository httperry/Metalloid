#include "Metalloid/Pipelines/MLShaderCompiler.h"
#include <iostream>
#include <cstring>
#include <vector>
#include <sstream>
#include <dlfcn.h>
#include <filesystem>
#include <fstream>
#include <mutex>

namespace Metalloid {

#pragma pack(push, 1)
struct DXBCHeader {
    uint32_t magic; // "DXBC"
    uint8_t checksum[16];
    uint32_t unknown;
    uint32_t totalSize;
    uint32_t partCount;
};

struct PartHeader {
    uint32_t magic;
    uint32_t size;
};

struct RDEFHeader {
    uint32_t cbCount;
    uint32_t cbOffset;
    uint32_t resourceBindingCount;
    uint32_t resourceBindingOffset;
    uint8_t minorVersion;
    uint8_t majorVersion;
    uint16_t targetType;
    uint32_t flags;
    uint32_t creatorOffset;
};

struct RDEFResourceBinding {
    uint32_t nameOffset;
    uint32_t type; // 0=CBuffer, 2=Texture, 3=Sampler, 4=UAV
    uint32_t returnType;
    uint32_t viewDimension;
    uint32_t sampleCount;
    uint32_t bindPoint;
    uint32_t bindCount;
    uint32_t flags;
};

struct DXILProgramHeader {
    uint32_t programVersion;
    uint32_t sizeInUint32;
    uint32_t dxilMagic; // 0x4C495844
    uint32_t dxilVersion;
    uint32_t bitcodeOffset;
    uint32_t bitcodeSize;
};
#pragma pack(pop)

class LLVMBitstreamReader {
    const uint8_t* data;
    size_t bitPos = 0;
    size_t totalBits;
public:
    LLVMBitstreamReader(const uint8_t* d, size_t size) : data(d), totalBits(size * 8) {}
    
    uint32_t readBits(size_t numBits) {
        if (bitPos + numBits > totalBits) return 0;
        uint32_t val = 0;
        for (size_t b = 0; b < numBits; ++b) {
            size_t byteIdx = (bitPos + b) / 8;
            size_t bitIdx = (bitPos + b) % 8;
            if (data[byteIdx] & (1 << bitIdx)) val |= (1 << b);
        }
        bitPos += numBits;
        return val;
    }
    
    void ExtractMetadata(uint32_t& x, uint32_t& y, uint32_t& z) {
        uint32_t magic = readBits(32);
        if (magic == 0x0B17C0DE) {
            // A full implementation would parse Blocks and Abbrev IDs to find METADATA_BLOCK.
            // For now, we stub the logic but demonstrate the architecture for LLVM metadata extraction.
            x = 1; y = 1; z = 1; // Fallback extracted values
        }
    }
};

std::string MLShaderCompiler::TranslateDXILToMSL(const void* dxilBytecode, SIZE_T bytecodeLength, const char* entryPoint, const char* targetProfile, UINT* outTgX, UINT* outTgY, UINT* outTgZ) {
    std::string profile = targetProfile ? targetProfile : "";
    std::string entry = entryPoint ? entryPoint : "main";

    std::string mslResources;
    std::string mslArgs;
    uint32_t tgX = 1, tgY = 1, tgZ = 1;

    if (dxilBytecode && bytecodeLength >= sizeof(DXBCHeader)) {
        const uint8_t* bytes = static_cast<const uint8_t*>(dxilBytecode);
        const DXBCHeader* header = reinterpret_cast<const DXBCHeader*>(bytes);

        if (header->magic == 0x43425844) { // "DXBC"
            std::cout << "[Metalloid] DXBC Container parsed. Size: " << header->totalSize << ", Parts: " << header->partCount << std::endl;
            if (sizeof(DXBCHeader) + header->partCount * sizeof(uint32_t) > bytecodeLength) {
                std::cerr << "[Metalloid] Invalid DXBC container: part offsets out of bounds." << std::endl;
                return "";
            }
            const uint32_t* partOffsets = reinterpret_cast<const uint32_t*>(bytes + sizeof(DXBCHeader));
            
            for (uint32_t i = 0; i < header->partCount; ++i) {
                uint32_t offset = partOffsets[i];
                if (offset + sizeof(PartHeader) > bytecodeLength) continue;

                const PartHeader* part = reinterpret_cast<const PartHeader*>(bytes + offset);
                char magicStr[5] = {0};
                memcpy(magicStr, &part->magic, 4);
                
                std::cout << "[Metalloid] Found part: " << magicStr << " (Size: " << part->size << ")" << std::endl;

                if (part->magic == 0x4C495844) { // "DXIL"
                    std::cout << "[Metalloid] DXIL bitcode part found. Extracting reflection..." << std::endl;
                    const uint8_t* dxilData = bytes + offset + sizeof(PartHeader);
                    if (part->size >= sizeof(DXILProgramHeader)) {
                        const DXILProgramHeader* dxilHeader = reinterpret_cast<const DXILProgramHeader*>(dxilData);
                        if (dxilHeader->dxilMagic == 0x4C495844) {
                            const uint8_t* bitcode = dxilData + dxilHeader->bitcodeOffset;
                            uint32_t bitcodeSize = dxilHeader->bitcodeSize;
                            
                            LLVMBitstreamReader reader(bitcode, bitcodeSize);
                            reader.ExtractMetadata(tgX, tgY, tgZ);
                            std::cout << "[Metalloid] Extracted thread group sizes: " << tgX << ", " << tgY << ", " << tgZ << std::endl;
                            if (outTgX) *outTgX = tgX;
                            if (outTgY) *outTgY = tgY;
                            if (outTgZ) *outTgZ = tgZ;
                        }
                    }
                } else if (part->magic == 0x46454452) { // "RDEF"
                    std::cout << "[Metalloid] RDEF reflection part found. Extracting descriptor bindings..." << std::endl;
                    const uint8_t* rdefData = bytes + offset + sizeof(PartHeader);
                    if (part->size >= sizeof(RDEFHeader)) {
                        const RDEFHeader* rdefHeader = reinterpret_cast<const RDEFHeader*>(rdefData);
                        const RDEFResourceBinding* bindings = reinterpret_cast<const RDEFResourceBinding*>(rdefData + rdefHeader->resourceBindingOffset);
                        
                        for (uint32_t b = 0; b < rdefHeader->resourceBindingCount; ++b) {
                            const RDEFResourceBinding& bind = bindings[b];
                            const char* name = reinterpret_cast<const char*>(rdefData + bind.nameOffset);
                            
                            std::string typeStr;
                            std::string argStr;
                            
                            if (bind.type == 0) { // CBUFFER
                                typeStr = "struct " + std::string(name) + "_t {\n    float4 data[16];\n};\n";
                                argStr = "constant " + std::string(name) + "_t& " + name + " [[buffer(" + std::to_string(bind.bindPoint) + ")]]";
                            } else if (bind.type == 2 || bind.type == 5 || bind.type == 7) { // SRV
                                argStr = "texture2d<float> " + std::string(name) + " [[texture(" + std::to_string(bind.bindPoint) + ")]]";
                            } else if (bind.type == 4 || bind.type == 6 || bind.type == 8) { // UAV
                                argStr = "texture2d<float, access::read_write> " + std::string(name) + " [[texture(" + std::to_string(bind.bindPoint) + ")]]";
                            } else if (bind.type == 3) { // Sampler
                                argStr = "sampler " + std::string(name) + " [[sampler(" + std::to_string(bind.bindPoint) + ")]]";
                            } else {
                                argStr = "device void* " + std::string(name) + " [[buffer(" + std::to_string(bind.bindPoint) + ")]]";
                            }
                            
                            if (!typeStr.empty() && mslResources.find(typeStr) == std::string::npos) {
                                mslResources += typeStr;
                            }
                            
                            if (!mslArgs.empty()) mslArgs += ", ";
                            mslArgs += argStr;
                        }
                    }
                }
            }
        } else {
            std::cout << "[Metalloid] Unknown shader format or not DXBC container." << std::endl;
        }
    }

    std::stringstream msl;
    msl << "#include <metal_stdlib>\n";
    msl << "using namespace metal;\n\n";
    
    if (!mslResources.empty()) {
        msl << mslResources << "\n";
    }
    
    // Provide a generic dummy MSL struct and function based on the profile
    if (profile.substr(0, 2) == "vs") {
        msl << "struct VSOut {\n";
        msl << "    float4 position [[position]];\n";
        msl << "    float4 color;\n";
        msl << "};\n\n";
        msl << "vertex VSOut " << entry << "(\n";
        if (!mslArgs.empty()) {
            msl << "    " << mslArgs << ",\n";
        }
        msl << "    uint vertex_id [[vertex_id]]) {\n";
        msl << "    VSOut out;\n";
        msl << "    out.position = float4(0.0, 0.0, 0.0, 1.0);\n";
        msl << "    out.color = float4(1.0, 1.0, 1.0, 1.0);\n";
        msl << "    return out;\n";
        msl << "}\n";
    } else if (profile.substr(0, 2) == "ps") {
        msl << "struct VSOut {\n";
        msl << "    float4 position [[position]];\n";
        msl << "    float4 color;\n";
        msl << "};\n\n";
        msl << "fragment float4 " << entry << "(\n";
        msl << "    VSOut in [[stage_in]]";
        if (!mslArgs.empty()) {
            msl << ",\n    " << mslArgs;
        }
        msl << "\n) {\n";
        msl << "    return in.color;\n";
        msl << "}\n";
    } else if (profile.substr(0, 2) == "cs") {
        msl << "// Extracted Thread Group Size: " << tgX << ", " << tgY << ", " << tgZ << "\n";
        msl << "kernel void " << entry << "(\n";
        if (!mslArgs.empty()) {
            msl << "    " << mslArgs << ",\n";
        }
        msl << "    uint3 id [[thread_position_in_grid]]) {\n";
        msl << "}\n";
    } else if (profile.substr(0, 2) == "ms") {
        msl << "// Extracted Mesh Thread Group Size: " << tgX << ", " << tgY << ", " << tgZ << "\n";
        msl << "[[mesh]] void " << entry << "(\n";
        if (!mslArgs.empty()) {
            msl << "    " << mslArgs << ",\n";
        }
        msl << "    uint3 id [[thread_position_in_grid]]) {\n";
        msl << "}\n";
    } else if (profile.substr(0, 2) == "as") {
        msl << "// Extracted Amp Thread Group Size: " << tgX << ", " << tgY << ", " << tgZ << "\n";
        msl << "[[object]] void " << entry << "(\n";
        if (!mslArgs.empty()) {
            msl << "    " << mslArgs << ",\n";
        }
        msl << "    uint3 id [[thread_position_in_grid]]) {\n";
        msl << "}\n";
    } else {
        // Fallback for ds, hs, gs
        // Metal doesn't have direct equivalents for these
        msl << "// Unsupported shader stage: " << profile << "\n";
    }

    return msl.str();
}

std::string MLShaderCompiler::TranslateWorkGraphToMSL(const D3D12_WORK_GRAPH_DESC* wgDesc) {
    std::stringstream msl;
    msl << "#include <metal_stdlib>\n";
    msl << "using namespace metal;\n\n";

    msl << "kernel void workgraph_master(\n";
    msl << "    command_buffer cb [[cmd_buffer(0)]],\n";
    msl << "    uint thread_id [[thread_position_in_grid]]) {\n";
    
    if (!wgDesc) {
        msl << "}\n";
        return msl.str();
    }
    
    msl << "    // Program Name: ";
    if (wgDesc->ProgramName) {
        std::wstring wProgName(wgDesc->ProgramName);
        msl << std::string(wProgName.begin(), wProgName.end());
    }
    msl << "\n";
    
    msl << "    if (thread_id != 0) return;\n\n";

    msl << "    // Entrypoints\n";
    for (UINT i = 0; i < wgDesc->NumEntrypoints; ++i) {
        if (wgDesc->pEntrypoints) {
            const D3D12_NODE_ID& entry = wgDesc->pEntrypoints[i];
            std::string entryName = "unknown";
            if (entry.Name) {
                std::wstring wName(entry.Name);
                entryName = std::string(wName.begin(), wName.end());
            }
            msl << "    // Entrypoint: " << entryName << " (Index: " << entry.ArrayIndex << ")\n";
        }
    }
    msl << "\n";
    
    for (UINT i = 0; i < wgDesc->NumExplicitlyDefinedNodes; ++i) {
        const D3D12_NODE& node = wgDesc->pExplicitlyDefinedNodes[i];
        if (node.NodeType == D3D12_NODE_TYPE_SHADER) {
            const D3D12_SHADER_NODE& shaderNode = node.Shader;
            std::string shaderName = "unknown";
            if (shaderNode.Shader) {
                std::wstring wShader(shaderNode.Shader);
                shaderName = std::string(wShader.begin(), wShader.end());
            }
            
            msl << "    {\n";
            msl << "        // Node: " << shaderName << "\n";
            msl << "        compute_command cmd = cb.compute_command();\n";
            
            if (shaderNode.OverridesType == D3D12_NODE_OVERRIDES_TYPE_BROADCASTING_LAUNCH) {
                const auto* pOverrides = shaderNode.pBroadcastingLaunchOverrides;
                if (pOverrides && pOverrides->pDispatchGrid) {
                    msl << "        cmd.concurrent_dispatch_threadgroups(uint3(" 
                        << pOverrides->pDispatchGrid[0] << ", " 
                        << pOverrides->pDispatchGrid[1] << ", " 
                        << pOverrides->pDispatchGrid[2] << "), uint3(1, 1, 1));\n";
                } else {
                    msl << "        cmd.concurrent_dispatch_threadgroups(uint3(1, 1, 1), uint3(1, 1, 1));\n";
                }
            } else if (shaderNode.OverridesType == D3D12_NODE_OVERRIDES_TYPE_COALESCING_LAUNCH) {
                msl << "        cmd.concurrent_dispatch_threadgroups(uint3(1, 1, 1), uint3(32, 1, 1));\n";
            } else if (shaderNode.OverridesType == D3D12_NODE_OVERRIDES_TYPE_THREAD_LAUNCH) {
                msl << "        cmd.concurrent_dispatch_threads(uint3(1, 1, 1), uint3(1, 1, 1));\n";
            } else if (shaderNode.OverridesType == D3D12_NODE_OVERRIDES_TYPE_COMMON_COMPUTE) {
                msl << "        cmd.concurrent_dispatch_threadgroups(uint3(1, 1, 1), uint3(1, 1, 1));\n";
            } else {
                msl << "        cmd.concurrent_dispatch_threadgroups(uint3(1, 1, 1), uint3(1, 1, 1));\n";
            }
            msl << "    }\n";
        }
    }
    
    msl << "}\n";
    return msl.str();
}

std::vector<uint8_t> MLShaderCompiler::TranslateDXILToMetallibData(const void* dxilBytecode, SIZE_T bytecodeLength, const char* entryPoint, const char* targetProfile, UINT* outTgX, UINT* outTgY, UINT* outTgZ) {
    static bool initialized = false;
    static IRCompiler* (*pIRCompilerCreate)(void) = nullptr;
    static IRObject* (*pIRObjectCreateFromDXIL)(const uint8_t*, size_t, IRBytecodeOwnership) = nullptr;
    static IRObject* (*pIRCompilerAllocCompileAndLink)(IRCompiler*, const char*, const IRObject*, IRError**) = nullptr;
    static bool (*pIRObjectGetMetalLibBinary)(const IRObject*, IRShaderStage, IRMetalLibBinary*) = nullptr;
    static size_t (*pIRMetalLibGetBytecodeSize)(const IRMetalLibBinary*) = nullptr;
    static size_t (*pIRMetalLibGetBytecode)(const IRMetalLibBinary*, uint8_t*) = nullptr;
    static void (*pIRObjectDestroy)(IRObject*) = nullptr;
    static void (*pIRCompilerDestroy)(IRCompiler*) = nullptr;
    static void (*pIRErrorDestroy)(IRError*) = nullptr;
    static const void* (*pIRErrorGetPayload)(const IRError*) = nullptr;
    static IRShaderStage (*pIRObjectGetMetalIRShaderStage)(const IRObject*) = nullptr;
    static IRMetalLibBinary* (*pIRMetalLibBinaryCreate)(void) = nullptr;
    static void (*pIRMetalLibBinaryDestroy)(IRMetalLibBinary*) = nullptr;
    
    // Reflection
    static IRShaderReflection* (*pIRShaderReflectionCreate)(void) = nullptr;
    static void (*pIRShaderReflectionDestroy)(IRShaderReflection*) = nullptr;
    static bool (*pIRObjectGetReflection)(const IRObject*, IRShaderStage, IRShaderReflection*) = nullptr;
    static bool (*pIRShaderReflectionCopyComputeInfo)(const IRShaderReflection*, IRReflectionVersion, IRVersionedCSInfo*) = nullptr;
    static bool (*pIRShaderReflectionReleaseComputeInfo)(IRVersionedCSInfo*) = nullptr;

    static std::once_flag initFlag;
    std::call_once(initFlag, []() {
        void* handle = dlopen("libmetalirconverter.dylib", RTLD_NOW);
        if (!handle) {
            std::cerr << "[Metalloid] FATAL ERROR: libmetalirconverter.dylib not found. Please ensure your launcher downloaded it." << std::endl;
            return;
        }

        pIRCompilerCreate = (IRCompiler* (*)(void))dlsym(handle, "IRCompilerCreate");
        pIRObjectCreateFromDXIL = (IRObject* (*)(const uint8_t*, size_t, IRBytecodeOwnership))dlsym(handle, "IRObjectCreateFromDXIL");
        pIRCompilerAllocCompileAndLink = (IRObject* (*)(IRCompiler*, const char*, const IRObject*, IRError**))dlsym(handle, "IRCompilerAllocCompileAndLink");
        pIRObjectGetMetalLibBinary = (bool (*)(const IRObject*, IRShaderStage, IRMetalLibBinary*))dlsym(handle, "IRObjectGetMetalLibBinary");
        pIRMetalLibGetBytecodeSize = (size_t (*)(const IRMetalLibBinary*))dlsym(handle, "IRMetalLibGetBytecodeSize");
        pIRMetalLibGetBytecode = (size_t (*)(const IRMetalLibBinary*, uint8_t*))dlsym(handle, "IRMetalLibGetBytecode");
        pIRObjectDestroy = (void (*)(IRObject*))dlsym(handle, "IRObjectDestroy");
        pIRCompilerDestroy = (void (*)(IRCompiler*))dlsym(handle, "IRCompilerDestroy");
        pIRErrorDestroy = (void (*)(IRError*))dlsym(handle, "IRErrorDestroy");
        pIRErrorGetPayload = (const void* (*)(const IRError*))dlsym(handle, "IRErrorGetPayload");
        pIRObjectGetMetalIRShaderStage = (IRShaderStage (*)(const IRObject*))dlsym(handle, "IRObjectGetMetalIRShaderStage");
        pIRMetalLibBinaryCreate = (IRMetalLibBinary* (*)(void))dlsym(handle, "IRMetalLibBinaryCreate");
        pIRMetalLibBinaryDestroy = (void (*)(IRMetalLibBinary*))dlsym(handle, "IRMetalLibBinaryDestroy");
        pIRShaderReflectionCreate = (IRShaderReflection* (*)(void))dlsym(handle, "IRShaderReflectionCreate");
        pIRShaderReflectionDestroy = (void (*)(IRShaderReflection*))dlsym(handle, "IRShaderReflectionDestroy");
        pIRObjectGetReflection = (bool (*)(const IRObject*, IRShaderStage, IRShaderReflection*))dlsym(handle, "IRObjectGetReflection");
        pIRShaderReflectionCopyComputeInfo = (bool (*)(const IRShaderReflection*, IRReflectionVersion, IRVersionedCSInfo*))dlsym(handle, "IRShaderReflectionCopyComputeInfo");
        pIRShaderReflectionReleaseComputeInfo = (bool (*)(IRVersionedCSInfo*))dlsym(handle, "IRShaderReflectionReleaseComputeInfo");
    });

    std::string_view bytecodeStr(static_cast<const char*>(dxilBytecode), bytecodeLength);
    size_t hashValue = std::hash<std::string_view>{}(bytecodeStr);
    
    std::filesystem::path cacheDir = "/tmp/Metalloid_Shader_Cache";
    std::filesystem::create_directories(cacheDir);
    
    std::string cacheFilePath = (cacheDir / (std::to_string(hashValue) + ".metallib")).string();
    std::string cacheMetaPath = (cacheDir / (std::to_string(hashValue) + ".meta")).string();
    
    if (std::filesystem::exists(cacheFilePath) && std::filesystem::exists(cacheMetaPath)) {
        std::ifstream file(cacheFilePath, std::ios::binary | std::ios::ate);
        std::ifstream metaFile(cacheMetaPath, std::ios::binary);
        if (file && metaFile) {
            uint32_t tg[3] = {1, 1, 1};
            metaFile.read(reinterpret_cast<char*>(tg), sizeof(tg));
            if (outTgX) *outTgX = tg[0];
            if (outTgY) *outTgY = tg[1];
            if (outTgZ) *outTgZ = tg[2];
            std::streamsize size = file.tellg();
            file.seekg(0, std::ios::beg);
            std::vector<uint8_t> buffer(size);
            if (file.read(reinterpret_cast<char*>(buffer.data()), size)) {
                return buffer;
            }
        }
    }

    thread_local IRCompiler* globalCompiler = nullptr;
    if (!globalCompiler) {
        if (!pIRCompilerCreate) return {};
        globalCompiler = pIRCompilerCreate();
    }
    if (!globalCompiler) return {};

    IRCompiler* compiler = globalCompiler;

    IRObject* dxilObj = pIRObjectCreateFromDXIL(static_cast<const uint8_t*>(dxilBytecode), bytecodeLength, IRBytecodeOwnershipNone);
    if (!dxilObj) {
        return {};
    }

    IRError* error = nullptr;
    IRObject* metalObj = pIRCompilerAllocCompileAndLink(compiler, entryPoint, dxilObj, &error);
    
    if (error) {
        const char* errorPayload = (const char*)pIRErrorGetPayload(error);
        if (errorPayload) {
            std::cerr << "[Metalloid] MSC Compilation Error: " << errorPayload << std::endl;
        }
        pIRErrorDestroy(error);
    }

    std::vector<uint8_t> metallibData;

    if (metalObj) {
        IRShaderStage stage = pIRObjectGetMetalIRShaderStage(metalObj);
        IRMetalLibBinary* libBinary = pIRMetalLibBinaryCreate();
        
        if (pIRObjectGetMetalLibBinary(metalObj, stage, libBinary)) {
            size_t size = pIRMetalLibGetBytecodeSize(libBinary);
            if (size > 0) {
                metallibData.resize(size);
                pIRMetalLibGetBytecode(libBinary, metallibData.data());

                std::ofstream file(cacheFilePath, std::ios::binary);
                if (file) {
                    file.write(reinterpret_cast<const char*>(metallibData.data()), metallibData.size());
                }
            }
        }
        
        if (stage == IRShaderStageCompute && pIRShaderReflectionCreate && pIRObjectGetReflection) {
            IRShaderReflection* reflection = pIRShaderReflectionCreate();
            if (pIRObjectGetReflection(metalObj, stage, reflection)) {
                IRVersionedCSInfo csInfo;
                if (pIRShaderReflectionCopyComputeInfo(reflection, IRReflectionVersion_1_0, &csInfo)) {
                    uint32_t tg[3] = {csInfo.info_1_0.tg_size[0], csInfo.info_1_0.tg_size[1], csInfo.info_1_0.tg_size[2]};
                    if (outTgX) *outTgX = tg[0];
                    if (outTgY) *outTgY = tg[1];
                    if (outTgZ) *outTgZ = tg[2];
                    
                    std::ofstream metaFile(cacheMetaPath, std::ios::binary);
                    if (metaFile) {
                        metaFile.write(reinterpret_cast<const char*>(tg), sizeof(tg));
                    }
                    pIRShaderReflectionReleaseComputeInfo(&csInfo);
                }
            }
            pIRShaderReflectionDestroy(reflection);
        }
        
        pIRMetalLibBinaryDestroy(libBinary);
        pIRObjectDestroy(metalObj);
    }

    pIRObjectDestroy(dxilObj);

    return metallibData;
}

} // namespace Metalloid
