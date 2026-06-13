#include "Metalloid/Device/MLDevice.h"
#include "Metalloid/Pipelines/MLStateObject.h"
#include "Metalloid/Commands/MLCommandQueue.h"
#include "Metalloid/Commands/MLCommandAllocator.h"
#include "Metalloid/Commands/MLCommandList.h"
#include "Metalloid/Resources/MLResource.h"
#include "Metalloid/Resources/MLDescriptorHeap.h"
#include "Metalloid/Resources/MLDescriptor.h"
#include "Metalloid/Pipelines/MLShaderCompiler.h"
#include "Metalloid/Pipelines/MLPipelineState.h"
#include "Metalloid/Video/MLVideoDevice.h"
#include "Metalloid/Sync/MLFence.h"
#include "Metalloid/Common/MLSharedHandle.h"
#include "Metalloid/Resources/MLHeap.h"
#include "Metalloid/Sync/MLQueryHeap.h"
#include "Metalloid/Pipelines/MLRootSignature.h"
#include <CommonCrypto/CommonDigest.h>
#include <iostream>

#ifdef __OBJC__
#import <IOSurface/IOSurface.h>
#import <VideoToolbox/VideoToolbox.h>
#endif

MLDevice::MLDevice(MetalDeviceType metalDevice)
    : m_refCount(1), m_metalDevice(metalDevice), m_defaultQueue(nullptr), m_siliconGen(MLAppleSiliconGen::Unknown) {
#ifdef __OBJC__
    id<MTLDevice> device = m_metalDevice;
    id<MTLCommandQueue> nativeQueue = [device newCommandQueue];
    m_defaultQueue = (__bridge_retained void*)nativeQueue;

    if ([device supportsFamily:(MTLGPUFamily)1010]) {
        m_siliconGen = MLAppleSiliconGen::M5;
    } else if ([device supportsFamily:(MTLGPUFamily)1009]) {
        if ([[device name] rangeOfString:@"M4" options:NSCaseInsensitiveSearch].location != NSNotFound) {
            m_siliconGen = MLAppleSiliconGen::M4;
        } else {
            m_siliconGen = MLAppleSiliconGen::M3;
        }
    } else if ([device supportsFamily:(MTLGPUFamily)1008]) {
        m_siliconGen = MLAppleSiliconGen::M2;
    } else if ([device supportsFamily:(MTLGPUFamily)1007]) {
        m_siliconGen = MLAppleSiliconGen::M1;
    } else {
        m_siliconGen = MLAppleSiliconGen::Unknown;
    }
#endif
    std::cout << "[Metalloid] ID3D12Device initialized with native Metal device." << std::endl;

    const char* genStr = "Unknown";
    switch (m_siliconGen) {
        case MLAppleSiliconGen::M1: genStr = "M1"; break;
        case MLAppleSiliconGen::M2: genStr = "M2"; break;
        case MLAppleSiliconGen::M3: genStr = "M3"; break;
        case MLAppleSiliconGen::M4: genStr = "M4"; break;
        case MLAppleSiliconGen::M5: genStr = "M5"; break;
        default: genStr = "Unknown"; break;
    }
    std::cout << "[Metalloid] Detected Apple Silicon Generation: " << genStr << std::endl;
}

MLDevice::~MLDevice() {
#ifdef __OBJC__
    if (m_defaultQueue) {
        id<MTLCommandQueue> nativeQueue = (__bridge_transfer id<MTLCommandQueue>)m_defaultQueue;
    }
#endif
    std::cout << "[Metalloid] ID3D12Device destroyed." << std::endl;
}

// IUnknown Methods
HRESULT STDMETHODCALLTYPE MLDevice::QueryInterface(REFIID riid, void** ppvObject) {
    if (!ppvObject) return E_POINTER;

    if (riid == __uuidof(IUnknown) ||
        riid == __uuidof(ID3D12Object) ||
        riid == __uuidof(ID3D12Device)) {
        *ppvObject = static_cast<ID3D12Device*>(this);
        AddRef();
        return S_OK;
    }
    
    if (riid == __uuidof(ID3D12VideoDevice)) {
        *ppvObject = static_cast<ID3D12VideoDevice*>(new MLVideoDevice(this));
        // The constructor of MLVideoDevice sets refcount to 1
        return S_OK;
    }

    *ppvObject = nullptr;
    return E_NOINTERFACE;
}

ULONG STDMETHODCALLTYPE MLDevice::AddRef() {
    return ++m_refCount;
}

ULONG STDMETHODCALLTYPE MLDevice::Release() {
    ULONG count = --m_refCount;
    if (count == 0) {
        delete this;
    }
    return count;
}

// ID3D12Object Methods
ML_IMPL_PRIVATE_DATA(MLDevice)

HRESULT STDMETHODCALLTYPE MLDevice::SetName(LPCWSTR Name) {
    if (Name) m_name = Name;
    else m_name.clear();
    return S_OK;
}

// ID3D12Device Methods
UINT STDMETHODCALLTYPE MLDevice::GetNodeCount() {
    return 1;
}

HRESULT STDMETHODCALLTYPE MLDevice::CreateCommandQueue(
    const D3D12_COMMAND_QUEUE_DESC* pDesc,
    REFIID riid,
    void** ppCommandQueue) {
    if (!ppCommandQueue) return E_POINTER;
    id<MTLDevice> device = (id<MTLDevice>)m_metalDevice;
    id<MTLCommandQueue> nativeQueue = [device newCommandQueue];
    if (!nativeQueue) return E_FAIL;
    
    MLCommandQueue* queue = new MLCommandQueue(this, nativeQueue, *pDesc);
    HRESULT hr = queue->QueryInterface(riid, ppCommandQueue);
    queue->Release();
    return hr;
}

HRESULT STDMETHODCALLTYPE MLDevice::CreateCommandAllocator(
    D3D12_COMMAND_LIST_TYPE type,
    REFIID riid,
    void** ppCommandAllocator) {
    if (!ppCommandAllocator) return E_POINTER;
    MLCommandAllocator* allocator = new MLCommandAllocator(this, type, m_defaultQueue);
    HRESULT hr = allocator->QueryInterface(riid, ppCommandAllocator);
    allocator->Release();
    return hr;
}

HRESULT STDMETHODCALLTYPE MLDevice::CreateGraphicsPipelineState(
    const D3D12_GRAPHICS_PIPELINE_STATE_DESC* pDesc,
    REFIID riid,
    void** ppPipelineState) {
    if (!ppPipelineState || !pDesc) return E_POINTER;

#ifdef __OBJC__
    using namespace Metalloid;
    id<MTLDevice> device = m_metalDevice;

    MTLRenderPipelineDescriptor* pipelineDesc = [[MTLRenderPipelineDescriptor alloc] init];
    NSError* error = nil;
    MTLCompileOptions* options = [[MTLCompileOptions alloc] init];

    // Compile Vertex Shader
    if (pDesc->VS.pShaderBytecode && pDesc->VS.BytecodeLength > 0) {
        std::vector<uint8_t> mslVS = MLShaderCompiler::TranslateDXILToMetallibData(
            pDesc->VS.pShaderBytecode, pDesc->VS.BytecodeLength, "vs_main", "vs");
        if (mslVS.empty()) return E_FAIL;
        dispatch_data_t dispatchDataVS = dispatch_data_create(mslVS.data(), mslVS.size(), dispatch_get_main_queue(), DISPATCH_DATA_DESTRUCTOR_DEFAULT);
        id<MTLLibrary> libraryVS = [device newLibraryWithData:dispatchDataVS error:&error];
        if (!libraryVS) {
            std::cerr << "[Metalloid] VS compilation failed: " << (error ? [[error localizedDescription] UTF8String] : "Unknown error") << std::endl;
            return E_FAIL;
        }
        pipelineDesc.vertexFunction = [libraryVS newFunctionWithName:@"vs_main"];
    }

    // Compile Pixel Shader
    if (pDesc->PS.pShaderBytecode && pDesc->PS.BytecodeLength > 0) {
        std::vector<uint8_t> mslPS = MLShaderCompiler::TranslateDXILToMetallibData(
            pDesc->PS.pShaderBytecode, pDesc->PS.BytecodeLength, "ps_main", "ps");
        if (mslPS.empty()) return E_FAIL;
        dispatch_data_t dispatchDataPS = dispatch_data_create(mslPS.data(), mslPS.size(), dispatch_get_main_queue(), DISPATCH_DATA_DESTRUCTOR_DEFAULT);
        id<MTLLibrary> libraryPS = [device newLibraryWithData:dispatchDataPS error:&error];
        if (!libraryPS) {
            std::cerr << "[Metalloid] PS compilation failed: " << (error ? [[error localizedDescription] UTF8String] : "Unknown error") << std::endl;
            return E_FAIL;
        }
        pipelineDesc.fragmentFunction = [libraryPS newFunctionWithName:@"ps_main"];
    }

    // Pass other shaders to parser for metadata extraction
    if (pDesc->DS.pShaderBytecode && pDesc->DS.BytecodeLength > 0) {
        MLShaderCompiler::TranslateDXILToMetallibData(pDesc->DS.pShaderBytecode, pDesc->DS.BytecodeLength, "ds_main", "ds");
    }
    if (pDesc->HS.pShaderBytecode && pDesc->HS.BytecodeLength > 0) {
        MLShaderCompiler::TranslateDXILToMetallibData(pDesc->HS.pShaderBytecode, pDesc->HS.BytecodeLength, "hs_main", "hs");
    }
    if (pDesc->GS.pShaderBytecode && pDesc->GS.BytecodeLength > 0) {
        MLShaderCompiler::TranslateDXILToMetallibData(pDesc->GS.pShaderBytecode, pDesc->GS.BytecodeLength, "gs_main", "gs");
    }

    
    if (pDesc->InputLayout.NumElements > 0 && pDesc->InputLayout.pInputElementDescs) {
        MTLVertexDescriptor* vertexDesc = [[MTLVertexDescriptor alloc] init];
        UINT currentOffset[D3D12_IA_VERTEX_INPUT_RESOURCE_SLOT_COUNT] = {0};
        for (UINT i = 0; i < pDesc->InputLayout.NumElements; ++i) {
            const auto& element = pDesc->InputLayout.pInputElementDescs[i];
            
            UINT elementSize = 0;
            MTLVertexFormat mtlVtxFormat = MTLVertexFormatInvalid;
            switch (element.Format) {
                case DXGI_FORMAT_R32G32B32_FLOAT: mtlVtxFormat = MTLVertexFormatFloat3; elementSize = 12; break;
                case DXGI_FORMAT_R32G32_FLOAT: mtlVtxFormat = MTLVertexFormatFloat2; elementSize = 8; break;
                case DXGI_FORMAT_R32G32B32A32_FLOAT: mtlVtxFormat = MTLVertexFormatFloat4; elementSize = 16; break;
                case DXGI_FORMAT_R8G8B8A8_UNORM: mtlVtxFormat = MTLVertexFormatUChar4Normalized; elementSize = 4; break;
                case DXGI_FORMAT_R16G16_SNORM: mtlVtxFormat = MTLVertexFormatShort2Normalized; elementSize = 4; break;
                case DXGI_FORMAT_R16G16B16A16_SNORM: mtlVtxFormat = MTLVertexFormatShort4Normalized; elementSize = 8; break;
                default: mtlVtxFormat = MTLVertexFormatFloat3; elementSize = 12; break;
            }
            
            UINT offset = element.AlignedByteOffset;
            if (offset == D3D12_APPEND_ALIGNED_ELEMENT) {
                offset = currentOffset[element.InputSlot];
            }
            
            vertexDesc.attributes[i].format = mtlVtxFormat;
            vertexDesc.attributes[i].offset = offset;
            vertexDesc.attributes[i].bufferIndex = element.InputSlot;
            
            currentOffset[element.InputSlot] = offset + elementSize;
            
            // Overwrite stride with our computed cumulative size. It's a robust heuristic.
            vertexDesc.layouts[element.InputSlot].stride = currentOffset[element.InputSlot];
            vertexDesc.layouts[element.InputSlot].stepFunction = (element.InputSlotClass == D3D12_INPUT_CLASSIFICATION_PER_INSTANCE_DATA) ? MTLVertexStepFunctionPerInstance : MTLVertexStepFunctionPerVertex;
            vertexDesc.layouts[element.InputSlot].stepRate = (element.InputSlotClass == D3D12_INPUT_CLASSIFICATION_PER_INSTANCE_DATA) ? element.InstanceDataStepRate : 1;
        }
        pipelineDesc.vertexDescriptor = vertexDesc;
    }
    
    for (UINT i = 0; i < pDesc->NumRenderTargets; ++i) {
        MTLPixelFormat mtlFormat = MTLPixelFormatInvalid;
        switch (pDesc->RTVFormats[i]) {
            case DXGI_FORMAT_R8G8B8A8_UNORM: mtlFormat = MTLPixelFormatRGBA8Unorm; break;
            case DXGI_FORMAT_R8G8B8A8_UNORM_SRGB: mtlFormat = MTLPixelFormatRGBA8Unorm_sRGB; break;
            case DXGI_FORMAT_B8G8R8A8_UNORM: mtlFormat = MTLPixelFormatBGRA8Unorm; break;
            case DXGI_FORMAT_B8G8R8A8_UNORM_SRGB: mtlFormat = MTLPixelFormatBGRA8Unorm_sRGB; break;
            case DXGI_FORMAT_R16G16B16A16_FLOAT: mtlFormat = MTLPixelFormatRGBA16Float; break;
            case DXGI_FORMAT_R32G32B32A32_FLOAT: mtlFormat = MTLPixelFormatRGBA32Float; break;
            case DXGI_FORMAT_R10G10B10A2_UNORM: mtlFormat = MTLPixelFormatRGB10A2Unorm; break;
            case DXGI_FORMAT_R8_UNORM: mtlFormat = MTLPixelFormatR8Unorm; break;
            case DXGI_FORMAT_R16_FLOAT: mtlFormat = MTLPixelFormatR16Float; break;
            case DXGI_FORMAT_R16G16_FLOAT: mtlFormat = MTLPixelFormatRG16Float; break;
            case DXGI_FORMAT_R11G11B10_FLOAT: mtlFormat = MTLPixelFormatRG11B10Float; break;
            default: mtlFormat = MTLPixelFormatBGRA8Unorm; break; // Fallback
        }
        pipelineDesc.colorAttachments[i].pixelFormat = mtlFormat;
    }
    if (pDesc->DSVFormat != DXGI_FORMAT_UNKNOWN) {
        MTLPixelFormat dsFormat = MTLPixelFormatInvalid;
        switch (pDesc->DSVFormat) {
            case DXGI_FORMAT_D32_FLOAT:
            case DXGI_FORMAT_R32_TYPELESS: dsFormat = MTLPixelFormatDepth32Float; break;
            case DXGI_FORMAT_D24_UNORM_S8_UINT:
            case DXGI_FORMAT_R24G8_TYPELESS: dsFormat = MTLPixelFormatDepth24Unorm_Stencil8; break;
            case DXGI_FORMAT_D32_FLOAT_S8X24_UINT:
            case DXGI_FORMAT_R32G8X24_TYPELESS: dsFormat = MTLPixelFormatDepth32Float_Stencil8; break;
            case DXGI_FORMAT_D16_UNORM:
            case DXGI_FORMAT_R16_TYPELESS: dsFormat = MTLPixelFormatDepth16Unorm; break;
            default: dsFormat = MTLPixelFormatDepth32Float; break;
        }
        pipelineDesc.depthAttachmentPixelFormat = dsFormat;
        if (pDesc->DSVFormat == DXGI_FORMAT_D24_UNORM_S8_UINT || pDesc->DSVFormat == DXGI_FORMAT_D32_FLOAT_S8X24_UINT) {
            pipelineDesc.stencilAttachmentPixelFormat = dsFormat;
        }
    }

    MLPipelineState* pso = new MLPipelineState(this, (MetalRenderPipelineType)nil);
    HRESULT hr = pso->QueryInterface(riid, ppPipelineState);

    pso->AddRef();
    [device newRenderPipelineStateWithDescriptor:pipelineDesc completionHandler:^(id<MTLRenderPipelineState> renderPipelineState, NSError * completionError) {
        if (completionError) {
            std::cerr << "[Metalloid] Render pipeline creation failed: " << [[completionError localizedDescription] UTF8String] << std::endl;
        } else {
            pso->SetMetalRenderPipelineState(renderPipelineState);
        }
        pso->Release();
    }];

    pso->Release();

    return hr;
#else
    return E_FAIL;
#endif
}

HRESULT STDMETHODCALLTYPE MLDevice::CreateComputePipelineState(
    const D3D12_COMPUTE_PIPELINE_STATE_DESC* pDesc,
    REFIID riid,
    void** ppPipelineState) {
    if (!ppPipelineState || !pDesc) return E_POINTER;

#ifdef __OBJC__
    using namespace Metalloid;
    id<MTLDevice> device = m_metalDevice;

    std::vector<uint8_t> mslSource = MLShaderCompiler::TranslateDXILToMetallibData(
        pDesc->CS.pShaderBytecode, pDesc->CS.BytecodeLength, "cs_main", "cs");
    if (mslSource.empty()) return E_FAIL;

    dispatch_data_t dispatchData = dispatch_data_create(mslSource.data(), mslSource.size(), dispatch_get_main_queue(), DISPATCH_DATA_DESTRUCTOR_DEFAULT);
    NSError* error = nil;
    MTLCompileOptions* options = [[MTLCompileOptions alloc] init];
    id<MTLLibrary> library = [device newLibraryWithData:dispatchData error:&error];

    if (!library) {
        std::cerr << "[Metalloid] Compute Shader compilation failed: " << [[error localizedDescription] UTF8String] << std::endl;
        return E_FAIL;
    }

    id<MTLFunction> computeFunction = [library newFunctionWithName:@"cs_main"];
    if (!computeFunction) {
        std::cerr << "[Metalloid] Compute Function not found in library." << std::endl;
        return E_FAIL;
    }

    MLPipelineState* pso = new MLPipelineState(this, (MetalComputePipelineType)nil);
    HRESULT hr = pso->QueryInterface(riid, ppPipelineState);

    pso->AddRef();
    [device newComputePipelineStateWithFunction:computeFunction completionHandler:^(id<MTLComputePipelineState> computePipelineState, NSError * completionError) {
        if (completionError) {
            std::cerr << "[Metalloid] Compute pipeline creation failed: " << [[completionError localizedDescription] UTF8String] << std::endl;
        } else {
            pso->SetMetalComputePipelineState(computePipelineState);
        }
        pso->Release();
    }];

    pso->Release();

    return hr;
#else
    return E_FAIL;
#endif
}

HRESULT STDMETHODCALLTYPE MLDevice::CreateCommandList(
    UINT nodeMask,
    D3D12_COMMAND_LIST_TYPE type,
    ID3D12CommandAllocator* pCommandAllocator,
    ID3D12PipelineState* pInitialState,
    REFIID riid,
    void** ppCommandList) {
    if (!ppCommandList) return E_POINTER;
    MLCommandList* list = new MLCommandList(this, type);
    HRESULT hr = list->QueryInterface(riid, ppCommandList);
    list->Release();
    return hr;
}

HRESULT STDMETHODCALLTYPE MLDevice::CheckFeatureSupport(
    D3D12_FEATURE Feature,
    void* pFeatureSupportData,
    UINT FeatureSupportDataSize) {
    if (!pFeatureSupportData) return E_INVALIDARG;
    
    memset(pFeatureSupportData, 0, FeatureSupportDataSize);
    
    switch (Feature) {
        case D3D12_FEATURE_D3D12_OPTIONS: {
            if (FeatureSupportDataSize == sizeof(D3D12_FEATURE_DATA_D3D12_OPTIONS)) {
                auto* data = static_cast<D3D12_FEATURE_DATA_D3D12_OPTIONS*>(pFeatureSupportData);
                data->ResourceBindingTier = D3D12_RESOURCE_BINDING_TIER_3;
            }
            break;
        }
        case D3D12_FEATURE_ARCHITECTURE: {
            if (FeatureSupportDataSize == sizeof(D3D12_FEATURE_DATA_ARCHITECTURE)) {
                auto* data = static_cast<D3D12_FEATURE_DATA_ARCHITECTURE*>(pFeatureSupportData);
                data->TileBasedRenderer = TRUE;
                data->UMA = TRUE;
                data->CacheCoherentUMA = TRUE;
            }
            break;
        }
        case D3D12_FEATURE_FEATURE_LEVELS: {
            if (FeatureSupportDataSize == sizeof(D3D12_FEATURE_DATA_FEATURE_LEVELS)) {
                auto* data = static_cast<D3D12_FEATURE_DATA_FEATURE_LEVELS*>(pFeatureSupportData);
                data->MaxSupportedFeatureLevel = D3D_FEATURE_LEVEL_11_0;
            }
            break;
        }
        case D3D12_FEATURE_D3D12_OPTIONS21: {
            if (FeatureSupportDataSize == sizeof(D3D12_FEATURE_DATA_D3D12_OPTIONS21)) {
                auto* data = static_cast<D3D12_FEATURE_DATA_D3D12_OPTIONS21*>(pFeatureSupportData);
                data->WorkGraphsTier = D3D12_WORK_GRAPHS_TIER_1_0;
                data->ExecuteIndirectTier = D3D12_EXECUTE_INDIRECT_TIER_1_1;
                return S_OK;
            }
            break;
        }
        case D3D12_FEATURE_D3D12_OPTIONS5: {
            if (FeatureSupportDataSize == sizeof(D3D12_FEATURE_DATA_D3D12_OPTIONS5)) {
                auto* data = static_cast<D3D12_FEATURE_DATA_D3D12_OPTIONS5*>(pFeatureSupportData);
                if (m_siliconGen >= MLAppleSiliconGen::M3) {
                    data->RaytracingTier = D3D12_RAYTRACING_TIER_1_1;
                } else {
                    data->RaytracingTier = D3D12_RAYTRACING_TIER_NOT_SUPPORTED;
                }
            }
            break;
        }
        case D3D12_FEATURE_D3D12_OPTIONS7: {
            if (FeatureSupportDataSize == sizeof(D3D12_FEATURE_DATA_D3D12_OPTIONS7)) {
                auto* data = static_cast<D3D12_FEATURE_DATA_D3D12_OPTIONS7*>(pFeatureSupportData);
                if (m_siliconGen >= MLAppleSiliconGen::M3) {
                    data->MeshShaderTier = D3D12_MESH_SHADER_TIER_1;
                } else {
                    data->MeshShaderTier = D3D12_MESH_SHADER_TIER_NOT_SUPPORTED;
                }
            }
            break;
        }
        default:
            break;
    }
    return S_OK;
}

HRESULT STDMETHODCALLTYPE MLDevice::CreateDescriptorHeap(
    const D3D12_DESCRIPTOR_HEAP_DESC* pDescriptorHeapDesc,
    REFIID riid,
    void** ppvHeap) {
    if (!ppvHeap) return E_POINTER;
    MLDescriptorHeap* heap = new MLDescriptorHeap(this, *pDescriptorHeapDesc);
    HRESULT hr = heap->QueryInterface(riid, ppvHeap);
    heap->Release();
    return hr;
}

UINT STDMETHODCALLTYPE MLDevice::GetDescriptorHandleIncrementSize(
    D3D12_DESCRIPTOR_HEAP_TYPE DescriptorHeapType) {
    return sizeof(MLDescriptor);
}

HRESULT STDMETHODCALLTYPE MLDevice::CreateRootSignature(
    UINT nodeMask,
    const void* pBlobWithRootSignature,
    SIZE_T blobLengthInBytes,
    REFIID riid,
    void** ppvRootSignature) {
    if (!ppvRootSignature) return E_POINTER;
    MLRootSignature* rootSig = new MLRootSignature(this);
    HRESULT hr = rootSig->Initialize(pBlobWithRootSignature, blobLengthInBytes);
    if (FAILED(hr)) {
        rootSig->Release();
        return hr;
    }
    hr = rootSig->QueryInterface(riid, ppvRootSignature);
    rootSig->Release();
    return hr;
}

void STDMETHODCALLTYPE MLDevice::CreateConstantBufferView(
    const D3D12_CONSTANT_BUFFER_VIEW_DESC* pDesc,
    D3D12_CPU_DESCRIPTOR_HANDLE DestDescriptor) {
    if (!DestDescriptor.ptr || !pDesc) return;
    MLDescriptor* desc = reinterpret_cast<MLDescriptor*>(DestDescriptor.ptr);
    desc->pResource = nullptr;
    desc->cbvDesc = *pDesc;
}

void STDMETHODCALLTYPE MLDevice::CreateShaderResourceView(
    ID3D12Resource* pResource,
    const D3D12_SHADER_RESOURCE_VIEW_DESC* pDesc,
    D3D12_CPU_DESCRIPTOR_HANDLE DestDescriptor) {
    if (!DestDescriptor.ptr) return;
    MLDescriptor* desc = reinterpret_cast<MLDescriptor*>(DestDescriptor.ptr);
    desc->pResource = pResource;
    if (pDesc) desc->srvDesc = *pDesc;
    else memset(&desc->srvDesc, 0, sizeof(desc->srvDesc));
}

void STDMETHODCALLTYPE MLDevice::CreateUnorderedAccessView(
    ID3D12Resource* pResource,
    ID3D12Resource* pBootstrapResource,
    const D3D12_UNORDERED_ACCESS_VIEW_DESC* pDesc,
    D3D12_CPU_DESCRIPTOR_HANDLE DestDescriptor) {
    if (!DestDescriptor.ptr) return;
    MLDescriptor* desc = reinterpret_cast<MLDescriptor*>(DestDescriptor.ptr);
    desc->pResource = pResource;
    if (pDesc) desc->uavDesc = *pDesc;
    else memset(&desc->uavDesc, 0, sizeof(desc->uavDesc));
}

void STDMETHODCALLTYPE MLDevice::CreateRenderTargetView(
    ID3D12Resource* pResource,
    const D3D12_RENDER_TARGET_VIEW_DESC* pDesc,
    D3D12_CPU_DESCRIPTOR_HANDLE DestDescriptor) {
    if (!DestDescriptor.ptr) return;
    MLDescriptor* desc = reinterpret_cast<MLDescriptor*>(DestDescriptor.ptr);
    desc->pResource = pResource;
    if (pDesc) {
        desc->rtvDesc = *pDesc;
    } else {
        memset(&desc->rtvDesc, 0, sizeof(desc->rtvDesc));
    }
}

void STDMETHODCALLTYPE MLDevice::CreateDepthStencilView(
    ID3D12Resource* pResource,
    const D3D12_DEPTH_STENCIL_VIEW_DESC* pDesc,
    D3D12_CPU_DESCRIPTOR_HANDLE DestDescriptor) {
    if (!DestDescriptor.ptr) return;
    MLDescriptor* desc = reinterpret_cast<MLDescriptor*>(DestDescriptor.ptr);
    desc->pResource = pResource;
    if (pDesc) {
        desc->dsvDesc = *pDesc;
    } else {
        memset(&desc->dsvDesc, 0, sizeof(desc->dsvDesc));
    }
}

void STDMETHODCALLTYPE MLDevice::CreateSamplerFeedbackUnorderedAccessView(ID3D12Resource* pTargetedResource, ID3D12Resource* pFeedbackResource, D3D12_CPU_DESCRIPTOR_HANDLE DestDescriptor) {
}

void STDMETHODCALLTYPE MLDevice::CreateSampler(
    const D3D12_SAMPLER_DESC* pDesc,
    D3D12_CPU_DESCRIPTOR_HANDLE DestDescriptor) {
    if (!DestDescriptor.ptr || !pDesc) return;
    MLDescriptor* desc = reinterpret_cast<MLDescriptor*>(DestDescriptor.ptr);
    desc->pResource = nullptr;
    desc->samplerDesc = *pDesc;
}

void STDMETHODCALLTYPE MLDevice::CopyDescriptors(
    UINT NumDestDescriptorRanges,
    const D3D12_CPU_DESCRIPTOR_HANDLE* pDestDescriptorRangeStarts,
    const UINT* pDestDescriptorRangeSizes,
    UINT NumSrcDescriptorRanges,
    const D3D12_CPU_DESCRIPTOR_HANDLE* pSrcDescriptorRangeStarts,
    const UINT* pSrcDescriptorRangeSizes,
    D3D12_DESCRIPTOR_HEAP_TYPE DescriptorHeapsType) {
    UINT dstRangeIndex = 0;
    UINT dstOffset = 0;
    UINT srcRangeIndex = 0;
    UINT srcOffset = 0;
    
    while (dstRangeIndex < NumDestDescriptorRanges && srcRangeIndex < NumSrcDescriptorRanges) {
        UINT dstRangeSize = pDestDescriptorRangeSizes ? pDestDescriptorRangeSizes[dstRangeIndex] : 1;
        UINT srcRangeSize = pSrcDescriptorRangeSizes ? pSrcDescriptorRangeSizes[srcRangeIndex] : 1;
        
        UINT numToCopy = std::min(dstRangeSize - dstOffset, srcRangeSize - srcOffset);
        
        MLDescriptor* dstPtr = reinterpret_cast<MLDescriptor*>(pDestDescriptorRangeStarts[dstRangeIndex].ptr) + dstOffset;
        MLDescriptor* srcPtr = reinterpret_cast<MLDescriptor*>(pSrcDescriptorRangeStarts[srcRangeIndex].ptr) + srcOffset;
        
        for (UINT i = 0; i < numToCopy; ++i) {
            dstPtr[i] = srcPtr[i];
        }
        
        dstOffset += numToCopy;
        srcOffset += numToCopy;
        
        if (dstOffset >= dstRangeSize) {
            dstRangeIndex++;
            dstOffset = 0;
        }
        if (srcOffset >= srcRangeSize) {
            srcRangeIndex++;
            srcOffset = 0;
        }
    }
}

void STDMETHODCALLTYPE MLDevice::CopyDescriptorsSimple(
    UINT NumDescriptors,
    D3D12_CPU_DESCRIPTOR_HANDLE DestDescriptorRangeStart,
    D3D12_CPU_DESCRIPTOR_HANDLE SrcDescriptorRangeStart,
    D3D12_DESCRIPTOR_HEAP_TYPE DescriptorHeapsType) {
    MLDescriptor* dstPtr = reinterpret_cast<MLDescriptor*>(DestDescriptorRangeStart.ptr);
    MLDescriptor* srcPtr = reinterpret_cast<MLDescriptor*>(SrcDescriptorRangeStart.ptr);
    for (UINT i = 0; i < NumDescriptors; ++i) {
        dstPtr[i] = srcPtr[i];
    }
}

D3D12_RESOURCE_ALLOCATION_INFO STDMETHODCALLTYPE MLDevice::GetResourceAllocationInfo(
    UINT visibleMask,
    UINT numResourceDescs,
    const D3D12_RESOURCE_DESC* pResourceDescs) {
    D3D12_RESOURCE_ALLOCATION_INFO info = {};
    info.Alignment = D3D12_DEFAULT_RESOURCE_PLACEMENT_ALIGNMENT;
    info.SizeInBytes = 0;
    
    if (!pResourceDescs) return info;

    for (UINT i = 0; i < numResourceDescs; ++i) {
        const auto& desc = pResourceDescs[i];
        UINT64 resSize = 0;
        
        if (desc.Dimension == D3D12_RESOURCE_DIMENSION_BUFFER) {
            resSize = desc.Width;
        } else {
            UINT bytesPerPixel = 4;
            switch(desc.Format) {
                case DXGI_FORMAT_R32G32B32A32_FLOAT: bytesPerPixel = 16; break;
                case DXGI_FORMAT_R16G16B16A16_FLOAT:
                case DXGI_FORMAT_R32G32_FLOAT: bytesPerPixel = 8; break;
                case DXGI_FORMAT_R8_UNORM: bytesPerPixel = 1; break;
                default: bytesPerPixel = 4; break;
            }
            resSize = desc.Width * std::max<UINT>(1, desc.Height) * std::max<UINT>(1, desc.DepthOrArraySize) * bytesPerPixel;
            if (desc.MipLevels > 1) resSize = (resSize * 3) / 2;
        }
        
        UINT64 alignment = desc.Alignment ? desc.Alignment : info.Alignment;
        info.SizeInBytes = (info.SizeInBytes + alignment - 1) & ~(alignment - 1);
        info.SizeInBytes += resSize;
    }
    
    info.SizeInBytes = (info.SizeInBytes + info.Alignment - 1) & ~(info.Alignment - 1);
    return info;
}

D3D12_HEAP_PROPERTIES STDMETHODCALLTYPE MLDevice::GetCustomHeapProperties(
    UINT nodeMask,
    D3D12_HEAP_TYPE heapType) {
    D3D12_HEAP_PROPERTIES props = {};
    return props;
}

HRESULT STDMETHODCALLTYPE MLDevice::CreateCommittedResource(
    const D3D12_HEAP_PROPERTIES* pHeapProperties,
    D3D12_HEAP_FLAGS HeapFlags,
    const D3D12_RESOURCE_DESC* pDesc,
    D3D12_RESOURCE_STATES InitialResourceState,
    const D3D12_CLEAR_VALUE* pOptimizedClearValue,
    REFIID riid,
    void** ppvResource) {
    if (!ppvResource) return E_POINTER;
    id<MTLDevice> device = (id<MTLDevice>)m_metalDevice;
    id<MTLResource> nativeResource = nil;

    if (pDesc->Dimension == D3D12_RESOURCE_DIMENSION_BUFFER) {
        MTLResourceOptions opts = 0;
        if (pHeapProperties->Type == D3D12_HEAP_TYPE_UPLOAD) {
            opts |= MTLResourceStorageModeShared;
            opts |= MTLResourceCPUCacheModeWriteCombined;
        } else if (pHeapProperties->Type == D3D12_HEAP_TYPE_READBACK) {
            opts |= MTLResourceStorageModeShared;
            opts |= MTLResourceCPUCacheModeDefaultCache;
        } else {
            opts |= MTLResourceStorageModePrivate;
        }
        nativeResource = [device newBufferWithLength:pDesc->Width options:opts];
    } else {
        MTLTextureDescriptor* texDesc = [[MTLTextureDescriptor alloc] init];
        texDesc.width = pDesc->Width;
        texDesc.height = pDesc->Height;
        texDesc.depth = (pDesc->Dimension == D3D12_RESOURCE_DIMENSION_TEXTURE3D) ? pDesc->DepthOrArraySize : 1;
        texDesc.arrayLength = (pDesc->Dimension != D3D12_RESOURCE_DIMENSION_TEXTURE3D) ? pDesc->DepthOrArraySize : 1;
        
        if (pHeapProperties->Type == D3D12_HEAP_TYPE_UPLOAD) {
            texDesc.storageMode = MTLStorageModeShared;
            texDesc.cpuCacheMode = MTLCPUCacheModeWriteCombined;
        } else if (pHeapProperties->Type == D3D12_HEAP_TYPE_READBACK) {
            texDesc.storageMode = MTLStorageModeShared;
            texDesc.cpuCacheMode = MTLCPUCacheModeDefaultCache;
        } else {
            texDesc.storageMode = MTLStorageModePrivate;
        }
        
        // BUG FIX: Video Decode IOSurface Interception
        if (pDesc->Flags & D3D12_RESOURCE_FLAG_VIDEO_DECODE_REFERENCE_ONLY) {
            std::cout << "[Metalloid] Intercepted D3D12 Video Decode texture. Forcing IOSurface backing for VTDecompressionSession." << std::endl;
            texDesc.storageMode = MTLStorageModePrivate;
            
#ifdef __OBJC__
            NSDictionary *surfaceProps = @{
                (id)kIOSurfaceWidth: @(pDesc->Width),
                (id)kIOSurfaceHeight: @(pDesc->Height),
                // Bi-Planar YCbCr mapping required for NV12 VideoToolbox Output
                (id)kIOSurfacePixelFormat: @(kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange)
            };
            IOSurfaceRef ioSurface = IOSurfaceCreate((__bridge CFDictionaryRef)surfaceProps);
            if (ioSurface) {
                nativeResource = [device newTextureWithDescriptor:texDesc iosurface:ioSurface plane:0];
                CFRelease(ioSurface);
            }
#endif
        }
        
        // Match texture type
        if (pDesc->Dimension == D3D12_RESOURCE_DIMENSION_TEXTURE1D) {
            texDesc.textureType = MTLTextureType1D;
        } else if (pDesc->Dimension == D3D12_RESOURCE_DIMENSION_TEXTURE2D) {
            texDesc.textureType = MTLTextureType2D;
        } else if (pDesc->Dimension == D3D12_RESOURCE_DIMENSION_TEXTURE3D) {
            texDesc.textureType = MTLTextureType3D;
        }
        
        // Match standard formats
        if (pDesc->Format == DXGI_FORMAT_R8G8B8A8_UNORM) {
            texDesc.pixelFormat = MTLPixelFormatRGBA8Unorm;
        } else if (pDesc->Format == DXGI_FORMAT_R8G8B8A8_UNORM_SRGB) {
            texDesc.pixelFormat = MTLPixelFormatRGBA8Unorm_sRGB;
        } else if (pDesc->Format == DXGI_FORMAT_B8G8R8A8_UNORM) {
            texDesc.pixelFormat = MTLPixelFormatBGRA8Unorm;
        } else if (pDesc->Format == DXGI_FORMAT_B8G8R8A8_UNORM_SRGB) {
            texDesc.pixelFormat = MTLPixelFormatBGRA8Unorm_sRGB;
        } else if (pDesc->Format == DXGI_FORMAT_R32_FLOAT) {
            texDesc.pixelFormat = MTLPixelFormatR32Float;
        } else if (pDesc->Format == DXGI_FORMAT_NV12) {
            if (@available(macOS 10.15, *)) {
                texDesc.pixelFormat = MTLPixelFormatGBGR422; 
            }
        } else if (pDesc->Format == DXGI_FORMAT_P010) {
            if (@available(macOS 10.15, *)) {
                texDesc.pixelFormat = MTLPixelFormatBGR10A2Unorm;
            }
        } else if (pDesc->Format == DXGI_FORMAT_D24_UNORM_S8_UINT || pDesc->Format == DXGI_FORMAT_R24G8_TYPELESS) {
            texDesc.pixelFormat = MTLPixelFormatDepth24Unorm_Stencil8;
        } else if (pDesc->Format == DXGI_FORMAT_D32_FLOAT_S8X24_UINT || pDesc->Format == DXGI_FORMAT_R32G8X24_TYPELESS) {
            texDesc.pixelFormat = MTLPixelFormatDepth32Float_Stencil8;
        } else if (pDesc->Format == DXGI_FORMAT_D32_FLOAT || pDesc->Format == DXGI_FORMAT_R32_TYPELESS) {
            texDesc.pixelFormat = MTLPixelFormatDepth32Float;
        } else if (pDesc->Format == DXGI_FORMAT_D16_UNORM || pDesc->Format == DXGI_FORMAT_R16_TYPELESS) {
            texDesc.pixelFormat = MTLPixelFormatDepth16Unorm;
        } else if (pDesc->Format == DXGI_FORMAT_BC1_UNORM || pDesc->Format == DXGI_FORMAT_BC1_TYPELESS) {
            texDesc.pixelFormat = [device supportsBCTextureCompression] ? MTLPixelFormatBC1_RGBA : MTLPixelFormatRGBA8Unorm;
        } else if (pDesc->Format == DXGI_FORMAT_BC1_UNORM_SRGB) {
            texDesc.pixelFormat = [device supportsBCTextureCompression] ? MTLPixelFormatBC1_RGBA_sRGB : MTLPixelFormatRGBA8Unorm_sRGB;
        } else if (pDesc->Format == DXGI_FORMAT_BC2_UNORM || pDesc->Format == DXGI_FORMAT_BC2_TYPELESS) {
            texDesc.pixelFormat = [device supportsBCTextureCompression] ? MTLPixelFormatBC2_RGBA : MTLPixelFormatRGBA8Unorm;
        } else if (pDesc->Format == DXGI_FORMAT_BC2_UNORM_SRGB) {
            texDesc.pixelFormat = [device supportsBCTextureCompression] ? MTLPixelFormatBC2_RGBA_sRGB : MTLPixelFormatRGBA8Unorm_sRGB;
        } else if (pDesc->Format == DXGI_FORMAT_BC3_UNORM || pDesc->Format == DXGI_FORMAT_BC3_TYPELESS) {
            texDesc.pixelFormat = [device supportsBCTextureCompression] ? MTLPixelFormatBC3_RGBA : MTLPixelFormatRGBA8Unorm;
        } else if (pDesc->Format == DXGI_FORMAT_BC3_UNORM_SRGB) {
            texDesc.pixelFormat = [device supportsBCTextureCompression] ? MTLPixelFormatBC3_RGBA_sRGB : MTLPixelFormatRGBA8Unorm_sRGB;
        } else if (pDesc->Format == DXGI_FORMAT_BC4_UNORM || pDesc->Format == DXGI_FORMAT_BC4_TYPELESS) {
            texDesc.pixelFormat = [device supportsBCTextureCompression] ? MTLPixelFormatBC4_RUnorm : MTLPixelFormatR8Unorm;
        } else if (pDesc->Format == DXGI_FORMAT_BC4_SNORM) {
            texDesc.pixelFormat = [device supportsBCTextureCompression] ? MTLPixelFormatBC4_RSnorm : MTLPixelFormatR8Snorm;
        } else if (pDesc->Format == DXGI_FORMAT_BC5_UNORM || pDesc->Format == DXGI_FORMAT_BC5_TYPELESS) {
            texDesc.pixelFormat = [device supportsBCTextureCompression] ? MTLPixelFormatBC5_RGUnorm : MTLPixelFormatRG8Unorm;
        } else if (pDesc->Format == DXGI_FORMAT_BC5_SNORM) {
            texDesc.pixelFormat = [device supportsBCTextureCompression] ? MTLPixelFormatBC5_RGSnorm : MTLPixelFormatRG8Snorm;
        } else if (pDesc->Format == DXGI_FORMAT_BC6H_UF16 || pDesc->Format == DXGI_FORMAT_BC6H_TYPELESS) {
            texDesc.pixelFormat = [device supportsBCTextureCompression] ? MTLPixelFormatBC6H_RGBUfloat : MTLPixelFormatRGBA16Float;
        } else if (pDesc->Format == DXGI_FORMAT_BC6H_SF16) {
            texDesc.pixelFormat = [device supportsBCTextureCompression] ? MTLPixelFormatBC6H_RGBFloat : MTLPixelFormatRGBA16Float;
        } else if (pDesc->Format == DXGI_FORMAT_BC7_UNORM || pDesc->Format == DXGI_FORMAT_BC7_TYPELESS) {
            texDesc.pixelFormat = [device supportsBCTextureCompression] ? MTLPixelFormatBC7_RGBAUnorm : MTLPixelFormatRGBA8Unorm;
        } else if (pDesc->Format == DXGI_FORMAT_BC7_UNORM_SRGB) {
            texDesc.pixelFormat = [device supportsBCTextureCompression] ? MTLPixelFormatBC7_RGBAUnorm_sRGB : MTLPixelFormatRGBA8Unorm_sRGB;
        } else {
            texDesc.pixelFormat = MTLPixelFormatRGBA8Unorm;
        }
        
        // Set usage flags
        texDesc.usage = MTLTextureUsageShaderRead | MTLTextureUsageRenderTarget;
        texDesc.storageMode = MTLStorageModePrivate;
        
        nativeResource = [device newTextureWithDescriptor:texDesc];
    }

    if (!nativeResource) return E_FAIL;

    MLResource* resource = new MLResource(this, [this](UINT64 addr){ this->UnregisterGPUVirtualAddress(addr); }, nativeResource, *pDesc, pHeapProperties);
    
    if (pDesc->Dimension == D3D12_RESOURCE_DIMENSION_BUFFER) {
        UINT64 size = pDesc->Width;
        UINT64 gpuva = resource->GetGPUVirtualAddress();
        this->RegisterGPUVirtualAddress(gpuva, size, resource);
    }
    HRESULT hr = resource->QueryInterface(riid, ppvResource);
    resource->Release();
    return hr;
}

HRESULT STDMETHODCALLTYPE MLDevice::CreateHeap(
    const D3D12_HEAP_DESC* pDesc,
    REFIID riid,
    void** ppvHeap) {
    if (!pDesc || !ppvHeap) return E_POINTER;
#ifdef __OBJC__
    MTLHeapDescriptor* heapDesc = [[MTLHeapDescriptor alloc] init];
    heapDesc.size = pDesc->SizeInBytes;
    
    if (@available(macOS 10.15, iOS 13.0, *)) {
        heapDesc.type = MTLHeapTypePlacement;
    }
    
    if (pDesc->Properties.Type == D3D12_HEAP_TYPE_UPLOAD) {
        heapDesc.storageMode = MTLStorageModeShared;
        heapDesc.cpuCacheMode = MTLCPUCacheModeWriteCombined;
    } else if (pDesc->Properties.Type == D3D12_HEAP_TYPE_READBACK) {
        heapDesc.storageMode = MTLStorageModeShared;
        heapDesc.cpuCacheMode = MTLCPUCacheModeDefaultCache;
    } else {
        heapDesc.storageMode = MTLStorageModePrivate;
    }
    
    id<MTLHeap> heap = [m_metalDevice newHeapWithDescriptor:heapDesc];
    if (!heap) return E_FAIL;
    
    MLHeap* mlHeap = new MLHeap(this, heap, *pDesc);
    HRESULT hr = mlHeap->QueryInterface(riid, ppvHeap);
    mlHeap->Release();
    return hr;
#else
    return E_FAIL;
#endif
}

HRESULT STDMETHODCALLTYPE MLDevice::CreatePlacedResource(
    ID3D12Heap* pHeap,
    UINT64 HeapOffset,
    const D3D12_RESOURCE_DESC* pDesc,
    D3D12_RESOURCE_STATES InitialState,
    const D3D12_CLEAR_VALUE* pOptimizedClearValue,
    REFIID riid,
    void** ppvResource) {
    if (!pHeap || !pDesc || !ppvResource) return E_POINTER;
#ifdef __OBJC__
    MLHeap* mlHeap = static_cast<MLHeap*>(pHeap);
    id<MTLHeap> heap = mlHeap->GetMetalHeap();
    if (!heap) return E_INVALIDARG;

    id<MTLResource> nativeResource = nil;

    if (pDesc->Dimension == D3D12_RESOURCE_DIMENSION_BUFFER) {
        MTLResourceOptions options = [heap storageMode] << MTLResourceStorageModeShift;
        if ([heap cpuCacheMode] == MTLCPUCacheModeWriteCombined) {
            options |= MTLResourceCPUCacheModeWriteCombined;
        }
        nativeResource = [heap newBufferWithLength:pDesc->Width options:options offset:HeapOffset];
    } else {
        MTLTextureDescriptor* texDesc = [[MTLTextureDescriptor alloc] init];
        texDesc.width = pDesc->Width;
        texDesc.height = pDesc->Height;
        texDesc.depth = pDesc->DepthOrArraySize;
        texDesc.mipmapLevelCount = pDesc->MipLevels;
        
        switch (pDesc->Format) {
            case DXGI_FORMAT_R8G8B8A8_UNORM: texDesc.pixelFormat = MTLPixelFormatRGBA8Unorm; break;
            case DXGI_FORMAT_B8G8R8A8_UNORM: texDesc.pixelFormat = MTLPixelFormatBGRA8Unorm; break;
            case DXGI_FORMAT_R16G16B16A16_FLOAT: texDesc.pixelFormat = MTLPixelFormatRGBA16Float; break;
            case DXGI_FORMAT_R32G32B32A32_FLOAT: texDesc.pixelFormat = MTLPixelFormatRGBA32Float; break;
            case DXGI_FORMAT_D32_FLOAT: texDesc.pixelFormat = MTLPixelFormatDepth32Float; break;
            case DXGI_FORMAT_D24_UNORM_S8_UINT: texDesc.pixelFormat = MTLPixelFormatDepth24Unorm_Stencil8; break;
            case DXGI_FORMAT_BC1_UNORM:
            case DXGI_FORMAT_BC1_TYPELESS: texDesc.pixelFormat = [heap.device supportsBCTextureCompression] ? MTLPixelFormatBC1_RGBA : MTLPixelFormatRGBA8Unorm; break;
            case DXGI_FORMAT_BC1_UNORM_SRGB: texDesc.pixelFormat = [heap.device supportsBCTextureCompression] ? MTLPixelFormatBC1_RGBA_sRGB : MTLPixelFormatRGBA8Unorm_sRGB; break;
            case DXGI_FORMAT_BC2_UNORM:
            case DXGI_FORMAT_BC2_TYPELESS: texDesc.pixelFormat = [heap.device supportsBCTextureCompression] ? MTLPixelFormatBC2_RGBA : MTLPixelFormatRGBA8Unorm; break;
            case DXGI_FORMAT_BC2_UNORM_SRGB: texDesc.pixelFormat = [heap.device supportsBCTextureCompression] ? MTLPixelFormatBC2_RGBA_sRGB : MTLPixelFormatRGBA8Unorm_sRGB; break;
            case DXGI_FORMAT_BC3_UNORM:
            case DXGI_FORMAT_BC3_TYPELESS: texDesc.pixelFormat = [heap.device supportsBCTextureCompression] ? MTLPixelFormatBC3_RGBA : MTLPixelFormatRGBA8Unorm; break;
            case DXGI_FORMAT_BC3_UNORM_SRGB: texDesc.pixelFormat = [heap.device supportsBCTextureCompression] ? MTLPixelFormatBC3_RGBA_sRGB : MTLPixelFormatRGBA8Unorm_sRGB; break;
            case DXGI_FORMAT_BC4_UNORM:
            case DXGI_FORMAT_BC4_TYPELESS: texDesc.pixelFormat = [heap.device supportsBCTextureCompression] ? MTLPixelFormatBC4_RUnorm : MTLPixelFormatR8Unorm; break;
            case DXGI_FORMAT_BC4_SNORM: texDesc.pixelFormat = [heap.device supportsBCTextureCompression] ? MTLPixelFormatBC4_RSnorm : MTLPixelFormatR8Snorm; break;
            case DXGI_FORMAT_BC5_UNORM:
            case DXGI_FORMAT_BC5_TYPELESS: texDesc.pixelFormat = [heap.device supportsBCTextureCompression] ? MTLPixelFormatBC5_RGUnorm : MTLPixelFormatRG8Unorm; break;
            case DXGI_FORMAT_BC5_SNORM: texDesc.pixelFormat = [heap.device supportsBCTextureCompression] ? MTLPixelFormatBC5_RGSnorm : MTLPixelFormatRG8Snorm; break;
            case DXGI_FORMAT_BC6H_UF16:
            case DXGI_FORMAT_BC6H_TYPELESS: texDesc.pixelFormat = [heap.device supportsBCTextureCompression] ? MTLPixelFormatBC6H_RGBUfloat : MTLPixelFormatRGBA16Float; break;
            case DXGI_FORMAT_BC6H_SF16: texDesc.pixelFormat = [heap.device supportsBCTextureCompression] ? MTLPixelFormatBC6H_RGBFloat : MTLPixelFormatRGBA16Float; break;
            case DXGI_FORMAT_BC7_UNORM:
            case DXGI_FORMAT_BC7_TYPELESS: texDesc.pixelFormat = [heap.device supportsBCTextureCompression] ? MTLPixelFormatBC7_RGBAUnorm : MTLPixelFormatRGBA8Unorm; break;
            case DXGI_FORMAT_BC7_UNORM_SRGB: texDesc.pixelFormat = [heap.device supportsBCTextureCompression] ? MTLPixelFormatBC7_RGBAUnorm_sRGB : MTLPixelFormatRGBA8Unorm_sRGB; break;
            default: texDesc.pixelFormat = MTLPixelFormatBGRA8Unorm; break;
        }
        
        if (pDesc->Flags & D3D12_RESOURCE_FLAG_ALLOW_RENDER_TARGET) {
            texDesc.usage |= MTLTextureUsageRenderTarget;
        }
        if (pDesc->Flags & D3D12_RESOURCE_FLAG_ALLOW_DEPTH_STENCIL) {
            texDesc.usage |= MTLTextureUsageRenderTarget;
        }
        if (pDesc->Flags & D3D12_RESOURCE_FLAG_ALLOW_UNORDERED_ACCESS) {
            texDesc.usage |= MTLTextureUsageShaderWrite;
        }
        texDesc.usage |= MTLTextureUsageShaderRead;
        texDesc.storageMode = [heap storageMode];
        
        nativeResource = [heap newTextureWithDescriptor:texDesc offset:HeapOffset];
    }

    if (!nativeResource) return E_FAIL;

    D3D12_RESOURCE_ALLOCATION_INFO info = GetResourceAllocationInfo(0, 1, pDesc);
    UINT64 resourceSize = info.SizeInBytes;

    MLResource** pResource = new MLResource*(nullptr);
    auto cb = [this, mlHeap, HeapOffset, resourceSize, pResource](UINT64 addr) {
        if (*pResource) {
            std::lock_guard<std::mutex> lock(this->m_globalResourceStateMutex);
            this->m_globalResourceStates.erase(*pResource);
        }
        this->UnregisterGPUVirtualAddress(addr);
        if (mlHeap) mlHeap->InvalidateRange(HeapOffset, resourceSize);
        delete pResource;
    };

    MLResource* resource = new MLResource(this, cb, nativeResource, *pDesc, nullptr);
    *pResource = resource;

    UINT64 memGen = mlHeap->GetOrCreateGenerationForRange(HeapOffset, resourceSize);
    
    // Assign via assumed public member or setter
    // Using property name directly as it is standard in the code base or falls back to public
    resource->m_memoryGeneration = memGen;
    resource->m_heap = mlHeap;
    resource->m_heapOffset = HeapOffset;
    resource->m_heapSize = resourceSize;

    {
        std::lock_guard<std::mutex> lock(m_globalResourceStateMutex);
        m_globalResourceStates[resource] = HierarchicalResourceState();
    }

    HRESULT hr = resource->QueryInterface(riid, ppvResource);
    resource->Release();
    return hr;
#else
    return E_FAIL;
#endif
}

HRESULT STDMETHODCALLTYPE MLDevice::CreateReservedResource(
    const D3D12_RESOURCE_DESC* pDesc,
    D3D12_RESOURCE_STATES InitialState,
    const D3D12_CLEAR_VALUE* pOptimizedClearValue,
    REFIID riid,
    void** ppvResource) {
    return E_FAIL;
}

HRESULT STDMETHODCALLTYPE MLDevice::CreateSharedHandle(ID3D12DeviceChild* pObject, const SECURITY_ATTRIBUTES* pAttributes, DWORD Access, LPCWSTR Name, HANDLE* pHandle) {
    if (!pObject || !pHandle) return E_INVALIDARG;
#ifdef __OBJC__
    ID3D12Fence* fence = nullptr;
    if (SUCCEEDED(pObject->QueryInterface(__uuidof(ID3D12Fence), (void**)&fence))) {
        MLFence* mlFence = static_cast<MLFence*>(fence);
        id<MTLSharedEvent> sharedEvent = mlFence->GetMetalSharedEvent();
        if (sharedEvent) {
            MLSharedHandle* handle = new MLSharedHandle();
            handle->eventHandle = [sharedEvent newSharedEventHandle];
            *pHandle = (HANDLE)handle;
            fence->Release();
            return S_OK;
        }
        fence->Release();
    }
#endif
    return E_FAIL;
}

HRESULT STDMETHODCALLTYPE MLDevice::OpenSharedHandle(
    HANDLE NTHandle,
    REFIID riid,
    void** ppvObject) {
    if (!NTHandle || !ppvObject) return E_INVALIDARG;
#ifdef __OBJC__
    MLSharedHandle* handle = (MLSharedHandle*)NTHandle;
    if (handle->eventHandle) {
        id<MTLDevice> device = (id<MTLDevice>)m_metalDevice;
        id<MTLSharedEvent> sharedEvent = [device newSharedEventWithHandle:handle->eventHandle];
        if (sharedEvent) {
            MLFence* mlFence = new MLFence(this, sharedEvent, 0, D3D12_FENCE_FLAG_SHARED);
            HRESULT hr = mlFence->QueryInterface(riid, ppvObject);
            mlFence->Release();
            return hr;
        }
    }
#endif
    return E_FAIL;
}

HRESULT STDMETHODCALLTYPE MLDevice::OpenSharedHandleByName(
    LPCWSTR Name,
    DWORD Access,
    HANDLE* pNTHandle) {
    return E_FAIL;
}

HRESULT STDMETHODCALLTYPE MLDevice::MakeResident(
    UINT NumObjects,
    ID3D12Pageable* const* ppObjects) {
#ifdef __OBJC__
    for (UINT i = 0; i < NumObjects; ++i) {
        if (!ppObjects[i]) continue;
        ID3D12Resource* res = nullptr;
        if (SUCCEEDED(ppObjects[i]->QueryInterface(__uuidof(ID3D12Resource), (void**)&res))) {
            MLResource* mlRes = static_cast<MLResource*>(res);
            if (mlRes->GetMetalResource()) {
                [(id<MTLResource>)mlRes->GetMetalResource() setPurgeableState:MTLPurgeableStateNonVolatile];
            }
            res->Release();
        } else {
            ID3D12Heap* heap = nullptr;
            if (SUCCEEDED(ppObjects[i]->QueryInterface(__uuidof(ID3D12Heap), (void**)&heap))) {
                MLHeap* mlHeap = static_cast<MLHeap*>(heap);
                if (mlHeap->GetMetalHeap()) {
                    [mlHeap->GetMetalHeap() setPurgeableState:MTLPurgeableStateNonVolatile];
                }
                heap->Release();
            } else {
                ID3D12QueryHeap* queryHeap = nullptr;
                if (SUCCEEDED(ppObjects[i]->QueryInterface(__uuidof(ID3D12QueryHeap), (void**)&queryHeap))) {
                    MLQueryHeap* mlQueryHeap = static_cast<MLQueryHeap*>(queryHeap);
                    if (mlQueryHeap->GetMetalBuffer()) {
                        [(id<MTLResource>)mlQueryHeap->GetMetalBuffer() setPurgeableState:MTLPurgeableStateNonVolatile];
                    }
                    queryHeap->Release();
                } else {
                    ID3D12DescriptorHeap* descriptorHeap = nullptr;
                    if (SUCCEEDED(ppObjects[i]->QueryInterface(__uuidof(ID3D12DescriptorHeap), (void**)&descriptorHeap))) {
                        // Descriptor heaps in this implementation don't have an underlying Metal resource
                        descriptorHeap->Release();
                    }
                }
            }
        }
    }
    return S_OK;
#else
    return E_FAIL;
#endif
}

HRESULT STDMETHODCALLTYPE MLDevice::Evict(
    UINT NumObjects,
    ID3D12Pageable* const* ppObjects) {
#ifdef __OBJC__
    for (UINT i = 0; i < NumObjects; ++i) {
        if (!ppObjects[i]) continue;
        ID3D12Resource* res = nullptr;
        if (SUCCEEDED(ppObjects[i]->QueryInterface(__uuidof(ID3D12Resource), (void**)&res))) {
            MLResource* mlRes = static_cast<MLResource*>(res);
            if (mlRes->GetMetalResource()) {
                [(id<MTLResource>)mlRes->GetMetalResource() setPurgeableState:MTLPurgeableStateVolatile];
            }
            res->Release();
        } else {
            ID3D12Heap* heap = nullptr;
            if (SUCCEEDED(ppObjects[i]->QueryInterface(__uuidof(ID3D12Heap), (void**)&heap))) {
                MLHeap* mlHeap = static_cast<MLHeap*>(heap);
                if (mlHeap->GetMetalHeap()) {
                    [mlHeap->GetMetalHeap() setPurgeableState:MTLPurgeableStateVolatile];
                }
                heap->Release();
            } else {
                ID3D12QueryHeap* queryHeap = nullptr;
                if (SUCCEEDED(ppObjects[i]->QueryInterface(__uuidof(ID3D12QueryHeap), (void**)&queryHeap))) {
                    MLQueryHeap* mlQueryHeap = static_cast<MLQueryHeap*>(queryHeap);
                    if (mlQueryHeap->GetMetalBuffer()) {
                        [(id<MTLResource>)mlQueryHeap->GetMetalBuffer() setPurgeableState:MTLPurgeableStateVolatile];
                    }
                    queryHeap->Release();
                } else {
                    ID3D12DescriptorHeap* descriptorHeap = nullptr;
                    if (SUCCEEDED(ppObjects[i]->QueryInterface(__uuidof(ID3D12DescriptorHeap), (void**)&descriptorHeap))) {
                        // Descriptor heaps in this implementation don't have an underlying Metal resource
                        descriptorHeap->Release();
                    }
                }
            }
        }
    }
    return S_OK;
#else
    return E_FAIL;
#endif
}

HRESULT STDMETHODCALLTYPE MLDevice::CreateFence(
    UINT64 InitialValue,
    D3D12_FENCE_FLAGS Flags,
    REFIID riid,
    void** ppvFence) {
    if (!ppvFence) return E_POINTER;
#ifdef __OBJC__
    id<MTLSharedEvent> sharedEvent = [m_metalDevice newSharedEvent];
    if (!sharedEvent) return E_FAIL;
    
    MLFence* fence = new MLFence(this, sharedEvent, InitialValue, Flags);
    HRESULT hr = fence->QueryInterface(riid, ppvFence);
    fence->Release();
    return hr;
#else
    return E_FAIL;
#endif
}

HRESULT STDMETHODCALLTYPE MLDevice::GetDeviceRemovedReason() {
    return m_deviceRemovedReason.load();
}

#ifdef __OBJC__
void MLDevice::NotifyDeviceError(NSError* error) {
    if (!error) return;
    if (error.code == MTLCommandBufferErrorDeviceRemoved || error.code == MTLCommandBufferErrorTimeout || error.code == MTLCommandBufferErrorAccessRevoked) {
        m_deviceRemovedReason.store(DXGI_ERROR_DEVICE_HUNG);
    }
}
#endif

void STDMETHODCALLTYPE MLDevice::GetCopyableFootprints(
    const D3D12_RESOURCE_DESC* pResourceDesc,
    UINT FirstSubresource,
    UINT NumSubresources,
    UINT64 BaseOffset,
    D3D12_PLACED_SUBRESOURCE_FOOTPRINT* pLayouts,
    UINT* pNumRows,
    UINT64* pRowSizesInBytes,
    UINT64* pTotalBytes) {
    if (!pResourceDesc) return;
    
    UINT64 totalBytes = 0;
    UINT64 offset = BaseOffset;

    for (UINT i = 0; i < NumSubresources; ++i) {
        UINT subresourceIndex = FirstSubresource + i;
        UINT mipLevel = subresourceIndex % std::max(1u, (UINT)pResourceDesc->MipLevels);
        
        UINT width = std::max(1u, (UINT)(pResourceDesc->Width >> mipLevel));
        UINT height = std::max(1u, pResourceDesc->Height >> mipLevel);
        UINT depth = std::max(1u, (UINT)(pResourceDesc->DepthOrArraySize >> mipLevel));

        bool isBC = false;
        UINT blockSize = 0;
        UINT bytesPerPixel = 4;
        switch (pResourceDesc->Format) {
            case DXGI_FORMAT_BC1_TYPELESS:
            case DXGI_FORMAT_BC1_UNORM:
            case DXGI_FORMAT_BC1_UNORM_SRGB:
            case DXGI_FORMAT_BC4_TYPELESS:
            case DXGI_FORMAT_BC4_UNORM:
            case DXGI_FORMAT_BC4_SNORM:
                isBC = true;
                blockSize = 8;
                break;
            case DXGI_FORMAT_BC2_TYPELESS:
            case DXGI_FORMAT_BC2_UNORM:
            case DXGI_FORMAT_BC2_UNORM_SRGB:
            case DXGI_FORMAT_BC3_TYPELESS:
            case DXGI_FORMAT_BC3_UNORM:
            case DXGI_FORMAT_BC3_UNORM_SRGB:
            case DXGI_FORMAT_BC5_TYPELESS:
            case DXGI_FORMAT_BC5_UNORM:
            case DXGI_FORMAT_BC5_SNORM:
            case DXGI_FORMAT_BC6H_TYPELESS:
            case DXGI_FORMAT_BC6H_UF16:
            case DXGI_FORMAT_BC6H_SF16:
            case DXGI_FORMAT_BC7_TYPELESS:
            case DXGI_FORMAT_BC7_UNORM:
            case DXGI_FORMAT_BC7_UNORM_SRGB:
                isBC = true;
                blockSize = 16;
                break;
            case DXGI_FORMAT_R8G8B8A8_UNORM:
            case DXGI_FORMAT_R8G8B8A8_UNORM_SRGB:
            case DXGI_FORMAT_B8G8R8A8_UNORM:
            case DXGI_FORMAT_B8G8R8A8_UNORM_SRGB:
            case DXGI_FORMAT_R16G16_FLOAT:
            case DXGI_FORMAT_R32_FLOAT:
            case DXGI_FORMAT_R8G8_UNORM:
            case DXGI_FORMAT_D32_FLOAT:
            case DXGI_FORMAT_D24_UNORM_S8_UINT:
                bytesPerPixel = 4; break;
            case DXGI_FORMAT_R16G16B16A16_FLOAT:
            case DXGI_FORMAT_R32G32_FLOAT:
                bytesPerPixel = 8; break;
            case DXGI_FORMAT_R32G32B32A32_FLOAT:
                bytesPerPixel = 16; break;
            case DXGI_FORMAT_R8_UNORM:
                bytesPerPixel = 1; break;
            default: bytesPerPixel = 4; break;
        }

        UINT rowPitch;
        UINT64 slicePitch;
        UINT64 subresourceSize;
        UINT numRows;

        if (isBC) {
            UINT numBlocksWide = std::max(1u, (width + 3) / 4);
            UINT numBlocksHigh = std::max(1u, (height + 3) / 4);
            rowPitch = numBlocksWide * blockSize;
            rowPitch = (rowPitch + 255) & ~255;
            slicePitch = (UINT64)rowPitch * numBlocksHigh;
            subresourceSize = slicePitch * depth;
            numRows = numBlocksHigh;
        } else {
            rowPitch = width * bytesPerPixel;
            rowPitch = (rowPitch + 255) & ~255;
            slicePitch = (UINT64)rowPitch * height;
            subresourceSize = slicePitch * depth;
            numRows = height;
        }

        if (pLayouts) {
            pLayouts[i].Offset = offset;
            pLayouts[i].Footprint.Format = pResourceDesc->Format;
            pLayouts[i].Footprint.Width = width;
            pLayouts[i].Footprint.Height = height;
            pLayouts[i].Footprint.Depth = depth;
            pLayouts[i].Footprint.RowPitch = rowPitch;
        }

        if (pNumRows) pNumRows[i] = numRows;
        if (pRowSizesInBytes) {
            pRowSizesInBytes[i] = isBC ? (std::max(1u, (width + 3) / 4) * blockSize) : (width * bytesPerPixel);
        }

        offset += subresourceSize;
        // Align to D3D12_TEXTURE_DATA_PLACEMENT_ALIGNMENT (512)
        offset = (offset + 511) & ~511;
        totalBytes += subresourceSize;
    }

    if (pTotalBytes) *pTotalBytes = offset - BaseOffset;
}

HRESULT STDMETHODCALLTYPE MLDevice::CreateQueryHeap(
    const D3D12_QUERY_HEAP_DESC* pDesc,
    REFIID riid,
    void** ppvHeap) {
    if (!pDesc || !ppvHeap) return E_POINTER;
#ifdef __OBJC__
    // Each query typically requires 8 bytes (UINT64)
    NSUInteger bufferSize = pDesc->Count * sizeof(uint64_t);
    id<MTLBuffer> queryBuffer = [m_metalDevice newBufferWithLength:bufferSize options:MTLResourceStorageModeShared];
    
    if (!queryBuffer) return E_FAIL;
    
    MLQueryHeap* heap = new MLQueryHeap(this, queryBuffer, *pDesc);
    HRESULT hr = heap->QueryInterface(riid, ppvHeap);
    heap->Release();
    return hr;
#else
    return E_FAIL;
#endif
}

HRESULT STDMETHODCALLTYPE MLDevice::SetStablePowerState(
    win_BOOL Enable) {
    return S_OK;
}

HRESULT STDMETHODCALLTYPE MLDevice::CreateCommandSignature(
    const D3D12_COMMAND_SIGNATURE_DESC* pDesc,
    ID3D12RootSignature* pRootSignature,
    REFIID riid,
    void** ppvCommandSignature) {
    return E_FAIL;
}

void STDMETHODCALLTYPE MLDevice::GetResourceTiling(
    ID3D12Resource* pTiledResource,
    UINT* pNumTilesForEntireResource,
    D3D12_PACKED_MIP_INFO* pPackedMipDesc,
    D3D12_TILE_SHAPE* pStandardTileShapeForNonPackedMips,
    UINT* pNumSubresourceTilings,
    UINT FirstSubresourceTilingToGet,
    D3D12_SUBRESOURCE_TILING* pSubresourceTilingsForNonPackedMips) {
}

void MLDevice::RegisterGPUVirtualAddress(UINT64 baseAddress, UINT64 size, MLResource* resource) {
    if (baseAddress == 0) return;
    std::unique_lock lock(m_gpuvaMutex);
    m_gpuvaMap[baseAddress + size - 1] = resource; // Key is the end address for upper_bound queries
}

void MLDevice::UnregisterGPUVirtualAddress(UINT64 baseAddress) {
    if (baseAddress == 0) return;
    std::unique_lock lock(m_gpuvaMutex);
    // Find the entry that has this resource
    for (auto it = m_gpuvaMap.begin(); it != m_gpuvaMap.end(); ++it) {
        if (it->second && it->second->GetGPUVirtualAddress() == baseAddress) {
            m_gpuvaMap.erase(it);
            break;
        }
    }
}

MLResource* MLDevice::ResolveGPUVirtualAddress(UINT64 address, UINT64* outOffset) {
    if (address == 0) return nullptr;
    std::shared_lock lock(m_gpuvaMutex);
    auto it = m_gpuvaMap.lower_bound(address);
    if (it != m_gpuvaMap.end()) {
        MLResource* res = it->second;
        UINT64 base = res->GetGPUVirtualAddress();
        if (address >= base) { // It falls within [base, end]
            if (outOffset) *outOffset = address - base;
            return res;
        }
    }
    return nullptr;
}

LUID STDMETHODCALLTYPE MLDevice::GetAdapterLuid(void) {
    LUID luid = {0, 0};
    return luid;
}

// ID3D12Device1
class MLPipelineLibrary : public ID3D12PipelineLibrary1 {
    ML_DECL_PRIVATE_DATA()
private:
    std::atomic<ULONG> m_refCount{1};
    ID3D12Device2* m_device;
    std::wstring m_name;
public:
    MLPipelineLibrary(ID3D12Device2* device) : m_device(device) {
        if (m_device) m_device->AddRef();
    }
    virtual ~MLPipelineLibrary() {
        if (m_device) m_device->Release();
    }

    virtual HRESULT STDMETHODCALLTYPE QueryInterface(REFIID riid, void** ppvObject) override {
        if (!ppvObject) return E_POINTER;
        if (riid == __uuidof(IUnknown) ||
            riid == __uuidof(ID3D12Object) ||
            riid == __uuidof(ID3D12DeviceChild) ||
            riid == __uuidof(ID3D12PipelineLibrary) ||
            riid == __uuidof(ID3D12PipelineLibrary1)) {
            *ppvObject = this;
            AddRef();
            return S_OK;
        }
        return E_NOINTERFACE;
    }
    virtual ULONG STDMETHODCALLTYPE AddRef() override { return ++m_refCount; }
    virtual ULONG STDMETHODCALLTYPE Release() override {
        ULONG count = --m_refCount;
        if (count == 0) delete this;
        return count;
    }
    virtual HRESULT STDMETHODCALLTYPE GetPrivateData(REFGUID guid, UINT* pDataSize, void* pData) override;
    virtual HRESULT STDMETHODCALLTYPE SetPrivateData(REFGUID guid, UINT DataSize, const void* pData) override;
    virtual HRESULT STDMETHODCALLTYPE SetPrivateDataInterface(REFGUID guid, const IUnknown* pData) override;
    virtual HRESULT STDMETHODCALLTYPE SetName(LPCWSTR Name) override {
        if (Name) m_name = Name;
        else m_name.clear();
        return S_OK;
    }
    virtual HRESULT STDMETHODCALLTYPE GetDevice(REFIID riid, void** ppvDevice) override { return m_device->QueryInterface(riid, ppvDevice); }
    virtual HRESULT STDMETHODCALLTYPE StorePipeline(LPCWSTR pName, ID3D12PipelineState* pPipeline) override { return E_FAIL; }
    virtual HRESULT STDMETHODCALLTYPE LoadGraphicsPipeline(LPCWSTR pName, const D3D12_GRAPHICS_PIPELINE_STATE_DESC* pDesc, REFIID riid, void** ppPipelineState) override {
        return m_device->CreateGraphicsPipelineState(pDesc, riid, ppPipelineState);
    }
    virtual HRESULT STDMETHODCALLTYPE LoadComputePipeline(LPCWSTR pName, const D3D12_COMPUTE_PIPELINE_STATE_DESC* pDesc, REFIID riid, void** ppPipelineState) override {
        return m_device->CreateComputePipelineState(pDesc, riid, ppPipelineState);
    }
    virtual SIZE_T STDMETHODCALLTYPE GetSerializedSize() override { return 0; }
    virtual HRESULT STDMETHODCALLTYPE Serialize(void* pData, SIZE_T DataSizeInBytes) override { return E_FAIL; }
    virtual HRESULT STDMETHODCALLTYPE LoadPipeline(LPCWSTR pName, const D3D12_PIPELINE_STATE_STREAM_DESC* pDesc, REFIID riid, void** ppPipelineState) override {
        return m_device->CreatePipelineState(pDesc, riid, ppPipelineState);
    }
};

ML_IMPL_PRIVATE_DATA(MLPipelineLibrary)

HRESULT STDMETHODCALLTYPE MLDevice::CreatePipelineLibrary(const void* pLibraryBlob, SIZE_T BlobLength, REFIID riid, void** ppPipelineLibrary) {
    if (!ppPipelineLibrary) return E_POINTER;
    MLPipelineLibrary* lib = new MLPipelineLibrary(this);
    HRESULT hr = lib->QueryInterface(riid, ppPipelineLibrary);
    lib->Release();
    return hr;
}
HRESULT STDMETHODCALLTYPE MLDevice::SetEventOnMultipleFenceCompletion(ID3D12Fence* const* ppFences, const UINT64* pFenceValues, UINT NumFences, D3D12_MULTIPLE_FENCE_WAIT_FLAGS Flags, HANDLE hEvent) { return E_FAIL; }
HRESULT STDMETHODCALLTYPE MLDevice::SetResidencyPriority(UINT NumObjects, ID3D12Pageable* const* ppObjects, const D3D12_RESIDENCY_PRIORITY* pPriorities) { return E_FAIL; }

// ID3D12Device2
HRESULT STDMETHODCALLTYPE MLDevice::CreatePipelineState(const D3D12_PIPELINE_STATE_STREAM_DESC* pDesc, REFIID riid, void** ppPipelineState) {
    if (!pDesc || !ppPipelineState) return E_INVALIDARG;
    
    D3D12_GRAPHICS_PIPELINE_STATE_DESC graphicsDesc = {};
    D3D12_COMPUTE_PIPELINE_STATE_DESC computeDesc = {};
    bool isCompute = false;
    
    uint8_t* pStream = static_cast<uint8_t*>(pDesc->pPipelineStateSubobjectStream);
    uint8_t* pStreamEnd = pStream + pDesc->SizeInBytes;
    
    while (pStream < pStreamEnd) {
        D3D12_PIPELINE_STATE_SUBOBJECT_TYPE type = *reinterpret_cast<D3D12_PIPELINE_STATE_SUBOBJECT_TYPE*>(pStream);
        pStream += sizeof(D3D12_PIPELINE_STATE_SUBOBJECT_TYPE);
        
        switch (type) {
            #define READ_SUBOBJ(T, Dest) \
                pStream = reinterpret_cast<uint8_t*>((reinterpret_cast<uintptr_t>(pStream) + alignof(T) - 1) & ~(alignof(T) - 1)); \
                Dest = *reinterpret_cast<T*>(pStream); \
                pStream += sizeof(T);
                
            case D3D12_PIPELINE_STATE_SUBOBJECT_TYPE_ROOT_SIGNATURE:
                READ_SUBOBJ(ID3D12RootSignature*, graphicsDesc.pRootSignature);
                computeDesc.pRootSignature = graphicsDesc.pRootSignature;
                break;
            case D3D12_PIPELINE_STATE_SUBOBJECT_TYPE_VS:
                READ_SUBOBJ(D3D12_SHADER_BYTECODE, graphicsDesc.VS);
                break;
            case D3D12_PIPELINE_STATE_SUBOBJECT_TYPE_PS:
                READ_SUBOBJ(D3D12_SHADER_BYTECODE, graphicsDesc.PS);
                break;
            case D3D12_PIPELINE_STATE_SUBOBJECT_TYPE_DS:
                READ_SUBOBJ(D3D12_SHADER_BYTECODE, graphicsDesc.DS);
                break;
            case D3D12_PIPELINE_STATE_SUBOBJECT_TYPE_HS:
                READ_SUBOBJ(D3D12_SHADER_BYTECODE, graphicsDesc.HS);
                break;
            case D3D12_PIPELINE_STATE_SUBOBJECT_TYPE_GS:
                READ_SUBOBJ(D3D12_SHADER_BYTECODE, graphicsDesc.GS);
                break;
            case D3D12_PIPELINE_STATE_SUBOBJECT_TYPE_CS:
                READ_SUBOBJ(D3D12_SHADER_BYTECODE, computeDesc.CS);
                isCompute = true;
                break;
            case D3D12_PIPELINE_STATE_SUBOBJECT_TYPE_STREAM_OUTPUT:
                READ_SUBOBJ(D3D12_STREAM_OUTPUT_DESC, graphicsDesc.StreamOutput);
                break;
            case D3D12_PIPELINE_STATE_SUBOBJECT_TYPE_BLEND:
                READ_SUBOBJ(D3D12_BLEND_DESC, graphicsDesc.BlendState);
                break;
            case D3D12_PIPELINE_STATE_SUBOBJECT_TYPE_SAMPLE_MASK:
                READ_SUBOBJ(UINT, graphicsDesc.SampleMask);
                break;
            case D3D12_PIPELINE_STATE_SUBOBJECT_TYPE_RASTERIZER:
                READ_SUBOBJ(D3D12_RASTERIZER_DESC, graphicsDesc.RasterizerState);
                break;
            case D3D12_PIPELINE_STATE_SUBOBJECT_TYPE_DEPTH_STENCIL:
                READ_SUBOBJ(D3D12_DEPTH_STENCIL_DESC, graphicsDesc.DepthStencilState);
                break;
            case D3D12_PIPELINE_STATE_SUBOBJECT_TYPE_INPUT_LAYOUT:
                READ_SUBOBJ(D3D12_INPUT_LAYOUT_DESC, graphicsDesc.InputLayout);
                break;
            case D3D12_PIPELINE_STATE_SUBOBJECT_TYPE_IB_STRIP_CUT_VALUE:
                READ_SUBOBJ(D3D12_INDEX_BUFFER_STRIP_CUT_VALUE, graphicsDesc.IBStripCutValue);
                break;
            case D3D12_PIPELINE_STATE_SUBOBJECT_TYPE_PRIMITIVE_TOPOLOGY:
                READ_SUBOBJ(D3D12_PRIMITIVE_TOPOLOGY_TYPE, graphicsDesc.PrimitiveTopologyType);
                break;
            case D3D12_PIPELINE_STATE_SUBOBJECT_TYPE_RENDER_TARGET_FORMATS: {
                D3D12_RT_FORMAT_ARRAY rtFormatArray;
                READ_SUBOBJ(D3D12_RT_FORMAT_ARRAY, rtFormatArray);
                graphicsDesc.NumRenderTargets = rtFormatArray.NumRenderTargets;
                for (UINT i = 0; i < 8; ++i) graphicsDesc.RTVFormats[i] = rtFormatArray.RTFormats[i];
                break;
            }
            case D3D12_PIPELINE_STATE_SUBOBJECT_TYPE_DEPTH_STENCIL_FORMAT:
                READ_SUBOBJ(DXGI_FORMAT, graphicsDesc.DSVFormat);
                break;
            case D3D12_PIPELINE_STATE_SUBOBJECT_TYPE_SAMPLE_DESC:
                READ_SUBOBJ(DXGI_SAMPLE_DESC, graphicsDesc.SampleDesc);
                break;
            case D3D12_PIPELINE_STATE_SUBOBJECT_TYPE_NODE_MASK:
                READ_SUBOBJ(UINT, graphicsDesc.NodeMask);
                computeDesc.NodeMask = graphicsDesc.NodeMask;
                break;
            case D3D12_PIPELINE_STATE_SUBOBJECT_TYPE_CACHED_PSO:
                READ_SUBOBJ(D3D12_CACHED_PIPELINE_STATE, graphicsDesc.CachedPSO);
                computeDesc.CachedPSO = graphicsDesc.CachedPSO;
                break;
            case D3D12_PIPELINE_STATE_SUBOBJECT_TYPE_FLAGS:
                READ_SUBOBJ(D3D12_PIPELINE_STATE_FLAGS, graphicsDesc.Flags);
                computeDesc.Flags = graphicsDesc.Flags;
                break;
            case D3D12_PIPELINE_STATE_SUBOBJECT_TYPE_DEPTH_STENCIL1: {
                D3D12_DEPTH_STENCIL_DESC1 ds1;
                READ_SUBOBJ(D3D12_DEPTH_STENCIL_DESC1, ds1);
                // Can map to DepthStencilState but just skip for basic implementation
                break;
            }
            case D3D12_PIPELINE_STATE_SUBOBJECT_TYPE_VIEW_INSTANCING: {
                D3D12_VIEW_INSTANCING_DESC vi;
                READ_SUBOBJ(D3D12_VIEW_INSTANCING_DESC, vi);
                break;
            }
            default:
                // Unrecognized type or unsupported, break parsing to avoid reading invalid memory
                return E_INVALIDARG;
            #undef READ_SUBOBJ
        }
        
        pStream = reinterpret_cast<uint8_t*>((reinterpret_cast<uintptr_t>(pStream) + alignof(void*) - 1) & ~(alignof(void*) - 1));
    }
    
    if (isCompute) {
        return CreateComputePipelineState(&computeDesc, riid, ppPipelineState);
    } else {
        return CreateGraphicsPipelineState(&graphicsDesc, riid, ppPipelineState);
    }
}

// ID3D12Device3
HRESULT STDMETHODCALLTYPE MLDevice::OpenExistingHeapFromAddress(const void* pAddress, REFIID riid, void** ppvHeap) { return E_FAIL; }
HRESULT STDMETHODCALLTYPE MLDevice::OpenExistingHeapFromFileMapping(HANDLE hFileMapping, REFIID riid, void** ppvHeap) { return E_FAIL; }
HRESULT STDMETHODCALLTYPE MLDevice::EnqueueMakeResident(D3D12_RESIDENCY_FLAGS Flags, UINT NumObjects, ID3D12Pageable* const* ppObjects, ID3D12Fence* pFenceToSignal, UINT64 FenceValueToSignal) { return E_FAIL; }

// ID3D12Device4
HRESULT STDMETHODCALLTYPE MLDevice::CreateCommandList1(UINT nodeMask, D3D12_COMMAND_LIST_TYPE type, D3D12_COMMAND_LIST_FLAGS flags, REFIID riid, void** ppCommandList) { 
    // Ignore D3D12_COMMAND_LIST_FLAGS (like D3D12_COMMAND_LIST_FLAG_NONE) for now
    return CreateCommandList(nodeMask, type, nullptr, nullptr, riid, ppCommandList); 
}
HRESULT STDMETHODCALLTYPE MLDevice::CreateProtectedResourceSession(const D3D12_PROTECTED_RESOURCE_SESSION_DESC* pDesc, REFIID riid, void** ppSession) { return E_FAIL; }
HRESULT STDMETHODCALLTYPE MLDevice::CreateCommittedResource1(const D3D12_HEAP_PROPERTIES* pHeapProperties, D3D12_HEAP_FLAGS HeapFlags, const D3D12_RESOURCE_DESC* pDesc, D3D12_RESOURCE_STATES InitialResourceState, const D3D12_CLEAR_VALUE* pOptimizedClearValue, ID3D12ProtectedResourceSession* pProtectedSession, REFIID riid, void** ppvResource) { 
    // Ignore pProtectedSession since we don't support protected sessions
    return CreateCommittedResource(pHeapProperties, HeapFlags, pDesc, InitialResourceState, pOptimizedClearValue, riid, ppvResource); 
}
HRESULT STDMETHODCALLTYPE MLDevice::CreateHeap1(const D3D12_HEAP_DESC* pDesc, ID3D12ProtectedResourceSession* pProtectedSession, REFIID riid, void** ppvHeap) { 
    // Ignore pProtectedSession
    return CreateHeap(pDesc, riid, ppvHeap); 
}
HRESULT STDMETHODCALLTYPE MLDevice::CreateReservedResource1(const D3D12_RESOURCE_DESC* pDesc, D3D12_RESOURCE_STATES InitialState, const D3D12_CLEAR_VALUE* pOptimizedClearValue, ID3D12ProtectedResourceSession* pProtectedSession, REFIID riid, void** ppvResource) { 
    // Ignore pProtectedSession
    return CreateReservedResource(pDesc, InitialState, pOptimizedClearValue, riid, ppvResource); 
}
D3D12_RESOURCE_ALLOCATION_INFO STDMETHODCALLTYPE MLDevice::GetResourceAllocationInfo1(UINT visibleMask, UINT numResourceDescs, const D3D12_RESOURCE_DESC* pResourceDescs, D3D12_RESOURCE_ALLOCATION_INFO1* pResourceAllocationInfo1) { 
    D3D12_RESOURCE_ALLOCATION_INFO info = GetResourceAllocationInfo(visibleMask, numResourceDescs, pResourceDescs);
    if (pResourceAllocationInfo1 && pResourceDescs) {
        UINT64 currentOffset = 0;
        for (UINT i = 0; i < numResourceDescs; ++i) {
            pResourceAllocationInfo1[i].Offset = currentOffset;
            pResourceAllocationInfo1[i].Alignment = pResourceDescs[i].Alignment ? pResourceDescs[i].Alignment : info.Alignment;
            // Provide a rough size for each subresource
            pResourceAllocationInfo1[i].SizeInBytes = info.SizeInBytes / numResourceDescs;
            currentOffset += pResourceAllocationInfo1[i].SizeInBytes;
        }
    }
    return info; 
}

// ID3D12Device5
HRESULT STDMETHODCALLTYPE MLDevice::CreateLifetimeTracker(ID3D12LifetimeOwner* pOwner, REFIID riid, void** ppvTracker) { return E_FAIL; }
void STDMETHODCALLTYPE MLDevice::RemoveDevice() { }
HRESULT STDMETHODCALLTYPE MLDevice::EnumerateMetaCommands(UINT* pNumMetaCommands, D3D12_META_COMMAND_DESC* pDescs) { return E_FAIL; }
HRESULT STDMETHODCALLTYPE MLDevice::EnumerateMetaCommandParameters(REFGUID CommandId, D3D12_META_COMMAND_PARAMETER_STAGE Stage, UINT* pTotalStructureSizeInBytes, UINT* pParameterCount, D3D12_META_COMMAND_PARAMETER_DESC* pParameterDescs) { return E_FAIL; }
HRESULT STDMETHODCALLTYPE MLDevice::CreateMetaCommand(REFGUID CommandId, UINT NodeMask, const void* pCreationParametersData, SIZE_T CreationParametersDataSizeInBytes, REFIID riid, void** ppMetaCommand) { return E_FAIL; }

HRESULT STDMETHODCALLTYPE MLDevice::CreateStateObject(const D3D12_STATE_OBJECT_DESC* pDesc, REFIID riid, void** ppStateObject) {
    if (!pDesc || !ppStateObject) return E_POINTER;
    
    MLStateObject* stateObj = new MLStateObject(this);
    
#ifdef __OBJC__
    id<MTLDevice> device = m_metalDevice;
    MTLComputePipelineDescriptor* computeDesc = [[MTLComputePipelineDescriptor alloc] init];
    
    id<MTLFunction> computeFunction = nil;
    NSMutableArray<id<MTLFunction>>* linkedFunctionsList = [NSMutableArray array];
    std::unordered_map<std::wstring, id<MTLFunction>> functionMap;
    
    const D3D12_WORK_GRAPH_DESC* workGraphDesc = nullptr;
    for (UINT i = 0; i < pDesc->NumSubobjects; ++i) {
        if (pDesc->pSubobjects[i].Type == D3D12_STATE_SUBOBJECT_TYPE_WORK_GRAPH) {
            workGraphDesc = static_cast<const D3D12_WORK_GRAPH_DESC*>(pDesc->pSubobjects[i].pDesc);
            break;
        }
    }
    
    id<MTLFunction> wgMasterFunc = nil;
    if (workGraphDesc) {
        std::string wgMslSource = Metalloid::MLShaderCompiler::TranslateWorkGraphToMSL(workGraphDesc);
        NSString* wgSourceStr = [NSString stringWithUTF8String:wgMslSource.c_str()];
        NSError* compileError = nil;
        MTLCompileOptions* options = [[MTLCompileOptions alloc] init];
        id<MTLLibrary> wgLibrary = [device newLibraryWithSource:wgSourceStr options:options error:&compileError];
        if (wgLibrary) {
            wgMasterFunc = [wgLibrary newFunctionWithName:@"workgraph_master"];
        } else {
            std::cerr << "[Metalloid] WorkGraph master compile failed: " << [[compileError localizedDescription] UTF8String] << std::endl;
        }
    }
    
    for (UINT i = 0; i < pDesc->NumSubobjects; ++i) {
        const auto& subobj = pDesc->pSubobjects[i];
        if (subobj.Type == D3D12_STATE_SUBOBJECT_TYPE_DXIL_LIBRARY) {
            const auto* dxilLib = static_cast<const D3D12_DXIL_LIBRARY_DESC*>(subobj.pDesc);
            
            std::string mslSource = Metalloid::MLShaderCompiler::TranslateDXILToMSL(
                dxilLib->DXILLibrary.pShaderBytecode, dxilLib->DXILLibrary.BytecodeLength, "", "lib");
                
            NSString* sourceStr = [NSString stringWithUTF8String:mslSource.c_str()];
            NSError* compileError = nil;
            MTLCompileOptions* options = [[MTLCompileOptions alloc] init];
            id<MTLLibrary> library = [device newLibraryWithSource:sourceStr options:options error:&compileError];
            
            if (library) {
                if (dxilLib->NumExports > 0) {
                    for (UINT j = 0; j < dxilLib->NumExports; ++j) {
                        std::wstring wname = dxilLib->pExports[j].Name;
                        std::string nameStr(wname.begin(), wname.end());
                        NSString* nsName = [NSString stringWithUTF8String:nameStr.c_str()];
                        
                        id<MTLFunction> func = [library newFunctionWithName:nsName];
                        if (!func) {
                            // Fallback for stub: many stubs only produce cs_main
                            func = [library newFunctionWithName:@"cs_main"];
                        }
                        
                        if (func) {
                            functionMap[wname] = func;
                            if (!wgMasterFunc && !computeFunction && func.functionType == MTLFunctionTypeKernel) {
                                computeFunction = func;
                            } else {
                                [linkedFunctionsList addObject:func];
                            }
                        }
                    }
                } else {
                    for (NSString* nsName in library.functionNames) {
                        id<MTLFunction> func = [library newFunctionWithName:nsName];
                        if (func) {
                            // Basic conversion of NSString to std::wstring
                            const char* utf8String = [nsName UTF8String];
                            std::string s(utf8String ? utf8String : "");
                            std::wstring wname(s.begin(), s.end());
                            functionMap[wname] = func;
                            
                            if (!wgMasterFunc && !computeFunction && func.functionType == MTLFunctionTypeKernel) {
                                computeFunction = func;
                            } else {
                                [linkedFunctionsList addObject:func];
                            }
                        }
                    }
                }
            } else {
                std::cerr << "[Metalloid] DXIL library compile failed: " << [[compileError localizedDescription] UTF8String] << std::endl;
            }
        }
    }
    
    if (wgMasterFunc) {
        computeDesc.computeFunction = wgMasterFunc;
    } else if (computeFunction) {
        computeDesc.computeFunction = computeFunction;
    }
    
    if (linkedFunctionsList.count > 0) {
        if (@available(macOS 11.0, iOS 14.0, *)) {
            MTLLinkedFunctions* mtlLinked = [[MTLLinkedFunctions alloc] init];
            mtlLinked.functions = linkedFunctionsList;
            computeDesc.linkedFunctions = mtlLinked;
        }
    }
    
    NSError* error = nil;
    id<MTLComputePipelineState> pso = nil;
    
    // We only create pipeline if we actually got a compute function
    if (computeDesc.computeFunction) {
        pso = [device newComputePipelineStateWithDescriptor:computeDesc options:0 reflection:nil error:&error];
    }
    
    if (error || !pso) {
        std::cerr << "[Metalloid] DXR PSO Compile Error: " << (error ? [[error localizedDescription] UTF8String] : "Missing compute function") << std::endl;
    } else {
        stateObj->SetMetalPipeline(pso);
        
        for (UINT i = 0; i < pDesc->NumSubobjects; ++i) {
            const auto& subobj = pDesc->pSubobjects[i];
            if (subobj.Type == D3D12_STATE_SUBOBJECT_TYPE_HIT_GROUP) {
                const auto* hitGroup = static_cast<const D3D12_HIT_GROUP_DESC*>(subobj.pDesc);
                if (hitGroup->HitGroupExport) {
                    std::wstring name = hitGroup->HitGroupExport;
                    std::array<uint8_t, 32> identifier = {0};
                    
                    std::string nameStr(name.begin(), name.end());
                    CC_SHA256(nameStr.c_str(), (CC_LONG)nameStr.length(), identifier.data());
                    
                    if (@available(macOS 11.0, iOS 14.0, *)) {
                        id<MTLFunctionHandle> handle = nil;
                        if (hitGroup->ClosestHitShaderImport) {
                            auto it = functionMap.find(hitGroup->ClosestHitShaderImport);
                            if (it != functionMap.end()) {
                                handle = [pso functionHandleWithFunction:it->second];
                            }
                        }
                        if (handle) {
                            stateObj->AddFunctionHandle(identifier, handle);
                        }
                    }
                    stateObj->AddShaderIdentifier(name, identifier);
                }
            } else if (subobj.Type == D3D12_STATE_SUBOBJECT_TYPE_DXIL_LIBRARY) {
                const auto* dxilLib = static_cast<const D3D12_DXIL_LIBRARY_DESC*>(subobj.pDesc);
                for (UINT j = 0; j < dxilLib->NumExports; ++j) {
                    std::wstring name = dxilLib->pExports[j].Name;
                    std::array<uint8_t, 32> identifier = {0};
                    
                    std::string nameStr(name.begin(), name.end());
                    CC_SHA256(nameStr.c_str(), (CC_LONG)nameStr.length(), identifier.data());
                    
                    if (@available(macOS 11.0, iOS 14.0, *)) {
                        auto it = functionMap.find(name);
                        if (it != functionMap.end()) {
                            id<MTLFunctionHandle> handle = [pso functionHandleWithFunction:it->second];
                            if (handle) {
                                stateObj->AddFunctionHandle(identifier, handle);
                            }
                        }
                    }
                    stateObj->AddShaderIdentifier(name, identifier);
                }
            }
        }
    }
#endif

    HRESULT hr = stateObj->QueryInterface(riid, ppStateObject);
    stateObj->Release();
    return hr;
}

void STDMETHODCALLTYPE MLDevice::GetRaytracingAccelerationStructurePrebuildInfo(const D3D12_BUILD_RAYTRACING_ACCELERATION_STRUCTURE_INPUTS* pDesc, D3D12_RAYTRACING_ACCELERATION_STRUCTURE_PREBUILD_INFO* pInfo) {
    if (!pInfo || !pDesc) return;

    MTLAccelerationStructureDescriptor* mtlDesc = nil;
    
    if (pDesc->Type == D3D12_RAYTRACING_ACCELERATION_STRUCTURE_TYPE_TOP_LEVEL) {
        MTLInstanceAccelerationStructureDescriptor* tlasDesc = [MTLInstanceAccelerationStructureDescriptor descriptor];
        tlasDesc.instanceCount = pDesc->NumDescs;
        mtlDesc = tlasDesc;
    } else if (pDesc->Type == D3D12_RAYTRACING_ACCELERATION_STRUCTURE_TYPE_BOTTOM_LEVEL) {
        MTLPrimitiveAccelerationStructureDescriptor* blasDesc = [MTLPrimitiveAccelerationStructureDescriptor descriptor];
        NSMutableArray<MTLAccelerationStructureGeometryDescriptor*>* geometryDescs = [NSMutableArray arrayWithCapacity:pDesc->NumDescs];
        
        for (UINT i = 0; i < pDesc->NumDescs; ++i) {
            const D3D12_RAYTRACING_GEOMETRY_DESC& geom = (pDesc->DescsLayout == D3D12_ELEMENTS_LAYOUT_ARRAY) ? 
                pDesc->pGeometryDescs[i] : *(pDesc->ppGeometryDescs[i]);
            
            if (geom.Type == D3D12_RAYTRACING_GEOMETRY_TYPE_TRIANGLES) {
                MTLAccelerationStructureTriangleGeometryDescriptor* triDesc = [MTLAccelerationStructureTriangleGeometryDescriptor descriptor];
                triDesc.triangleCount = geom.Triangles.IndexCount > 0 ? (geom.Triangles.IndexCount / 3) : (geom.Triangles.VertexCount / 3);
                triDesc.opaque = (geom.Flags & D3D12_RAYTRACING_GEOMETRY_FLAG_OPAQUE) ? YES : NO;
                [geometryDescs addObject:triDesc];
            } else if (geom.Type == D3D12_RAYTRACING_GEOMETRY_TYPE_PROCEDURAL_PRIMITIVE_AABBS) {
                MTLAccelerationStructureBoundingBoxGeometryDescriptor* aabbDesc = [MTLAccelerationStructureBoundingBoxGeometryDescriptor descriptor];
                aabbDesc.boundingBoxCount = geom.AABBs.AABBCount;
                aabbDesc.opaque = (geom.Flags & D3D12_RAYTRACING_GEOMETRY_FLAG_OPAQUE) ? YES : NO;
                [geometryDescs addObject:aabbDesc];
            }
        }
        blasDesc.geometryDescriptors = geometryDescs;
        mtlDesc = blasDesc;
    }

    if (mtlDesc) {
        mtlDesc.usage = MTLAccelerationStructureUsageNone;
        // Fast build flags
        if (pDesc->Flags & D3D12_RAYTRACING_ACCELERATION_STRUCTURE_BUILD_FLAG_PREFER_FAST_BUILD) {
            mtlDesc.usage |= MTLAccelerationStructureUsagePreferFastBuild;
        }

        if (pDesc->Flags & D3D12_RAYTRACING_ACCELERATION_STRUCTURE_BUILD_FLAG_ALLOW_UPDATE) {
            mtlDesc.usage |= MTLAccelerationStructureUsageRefit;
        }

        MTLAccelerationStructureSizes sizes = [m_metalDevice accelerationStructureSizesWithDescriptor:mtlDesc];
        pInfo->ResultDataMaxSizeInBytes = sizes.accelerationStructureSize;
        pInfo->ScratchDataSizeInBytes = sizes.buildScratchBufferSize;
        pInfo->UpdateScratchDataSizeInBytes = sizes.refitScratchBufferSize;
    }
}

D3D12_DRIVER_MATCHING_IDENTIFIER_STATUS STDMETHODCALLTYPE MLDevice::CheckDriverMatchingIdentifier(D3D12_SERIALIZED_DATA_TYPE SerializedDataType, const D3D12_SERIALIZED_DATA_DRIVER_MATCHING_IDENTIFIER* pIdentifierToCheck) {
    return D3D12_DRIVER_MATCHING_IDENTIFIER_UNSUPPORTED_TYPE;
}

// ID3D12Device6
HRESULT STDMETHODCALLTYPE MLDevice::SetBackgroundProcessingMode(D3D12_BACKGROUND_PROCESSING_MODE Mode, D3D12_MEASUREMENTS_ACTION MeasurementsAction, HANDLE hEventToSignalUponCompletion, win_BOOL* pbFurtherMeasurementsDesired) {
    if (pbFurtherMeasurementsDesired) *pbFurtherMeasurementsDesired = FALSE;
    return S_OK;
}

// ID3D12Device7
HRESULT STDMETHODCALLTYPE MLDevice::AddToStateObject(const D3D12_STATE_OBJECT_DESC* pAddition, ID3D12StateObject* pStateObjectToGrowFrom, REFIID riid, void** ppNewStateObject) {
    if (!pAddition || !pStateObjectToGrowFrom || !ppNewStateObject) return E_POINTER;
    
    MLStateObject* original = static_cast<MLStateObject*>(pStateObjectToGrowFrom);
    MLStateObject* stateObj = new MLStateObject(this);
    stateObj->CloneFrom(original);

#ifdef __OBJC__
    id<MTLDevice> device = m_metalDevice;
    std::unordered_map<std::wstring, id<MTLFunction>> functionMap;
    NSMutableArray<id<MTLFunction>>* linkedFunctionsList = [NSMutableArray array];
    const D3D12_WORK_GRAPH_DESC* workGraphDesc = nullptr;

    for (UINT i = 0; i < pAddition->NumSubobjects; ++i) {
        const auto& subobj = pAddition->pSubobjects[i];
        if (subobj.Type == D3D12_STATE_SUBOBJECT_TYPE_DXIL_LIBRARY) {
            const auto* dxilLib = static_cast<const D3D12_DXIL_LIBRARY_DESC*>(subobj.pDesc);
            std::string mslSource = Metalloid::MLShaderCompiler::TranslateDXILToMSL(
                dxilLib->DXILLibrary.pShaderBytecode, dxilLib->DXILLibrary.BytecodeLength, "", "lib");
            NSString* sourceStr = [NSString stringWithUTF8String:mslSource.c_str()];
            NSError* compileError = nil;
            id<MTLLibrary> library = [device newLibraryWithSource:sourceStr options:nil error:&compileError];
            
            if (library) {
                if (dxilLib->NumExports > 0) {
                    for (UINT j = 0; j < dxilLib->NumExports; ++j) {
                        std::wstring wname = dxilLib->pExports[j].Name;
                        std::string nameStr(wname.begin(), wname.end());
                        id<MTLFunction> func = [library newFunctionWithName:[NSString stringWithUTF8String:nameStr.c_str()]];
                        if (!func) func = [library newFunctionWithName:@"cs_main"];
                        if (func) {
                            functionMap[wname] = func;
                            [linkedFunctionsList addObject:func];
                        }
                    }
                } else {
                    for (NSString* nsName in library.functionNames) {
                        id<MTLFunction> func = [library newFunctionWithName:nsName];
                        if (func) {
                            const char* utf8String = [nsName UTF8String];
                            std::string s(utf8String ? utf8String : "");
                            std::wstring wname(s.begin(), s.end());
                            functionMap[wname] = func;
                            [linkedFunctionsList addObject:func];
                        }
                    }
                }
            } else {
                std::cerr << "[Metalloid] DXIL library compile failed in AddToStateObject: " << [[compileError localizedDescription] UTF8String] << std::endl;
            }
        } else if (subobj.Type == D3D12_STATE_SUBOBJECT_TYPE_WORK_GRAPH) {
            workGraphDesc = static_cast<const D3D12_WORK_GRAPH_DESC*>(subobj.pDesc);
        }
    }

    if (workGraphDesc) {
        for (UINT i = 0; i < workGraphDesc->NumEntrypoints; ++i) {
            std::wstring entryName = workGraphDesc->pEntrypoints[i].Name;
            auto it = functionMap.find(entryName);
            if (it != functionMap.end()) {
                MTLComputePipelineDescriptor* wgDesc = [[MTLComputePipelineDescriptor alloc] init];
                wgDesc.computeFunction = it->second;
                if (linkedFunctionsList.count > 0) {
                    if (@available(macOS 11.0, iOS 14.0, *)) {
                        MTLLinkedFunctions* mtlLinked = [[MTLLinkedFunctions alloc] init];
                        mtlLinked.functions = linkedFunctionsList;
                        wgDesc.linkedFunctions = mtlLinked;
                    }
                }
                NSError* error = nil;
                id<MTLComputePipelineState> pso = [device newComputePipelineStateWithDescriptor:wgDesc options:0 reflection:nil error:&error];
                if (pso) stateObj->AddWorkGraphPipeline(entryName, pso);
            }
        }
        for (UINT i = 0; i < workGraphDesc->NumExplicitlyDefinedNodes; ++i) {
            std::wstring nodeName = workGraphDesc->pExplicitlyDefinedNodes[i].Shader.Shader ? workGraphDesc->pExplicitlyDefinedNodes[i].Shader.Shader : L"";
            auto it = functionMap.find(nodeName);
            if (it != functionMap.end()) {
                MTLComputePipelineDescriptor* wgDesc = [[MTLComputePipelineDescriptor alloc] init];
                wgDesc.computeFunction = it->second;
                if (linkedFunctionsList.count > 0) {
                    if (@available(macOS 11.0, iOS 14.0, *)) {
                        MTLLinkedFunctions* mtlLinked = [[MTLLinkedFunctions alloc] init];
                        mtlLinked.functions = linkedFunctionsList;
                        wgDesc.linkedFunctions = mtlLinked;
                    }
                }
                NSError* error = nil;
                id<MTLComputePipelineState> pso = [device newComputePipelineStateWithDescriptor:wgDesc options:0 reflection:nil error:&error];
                if (pso) stateObj->AddWorkGraphPipeline(nodeName, pso);
            }
        }
    }
#endif

    HRESULT hr = stateObj->QueryInterface(riid, ppNewStateObject);
    stateObj->Release();
    return hr;
}

HRESULT STDMETHODCALLTYPE MLDevice::CreateProtectedResourceSession1(const D3D12_PROTECTED_RESOURCE_SESSION_DESC1* pDesc, REFIID riid, void** ppSession) {
    return E_FAIL;
}

// ID3D12Device8
D3D12_RESOURCE_ALLOCATION_INFO STDMETHODCALLTYPE MLDevice::GetResourceAllocationInfo2(UINT visibleMask, UINT numResourceDescs, const D3D12_RESOURCE_DESC1* pResourceDescs, D3D12_RESOURCE_ALLOCATION_INFO1* pResourceAllocationInfo1) {
    D3D12_RESOURCE_ALLOCATION_INFO info = {};
    if (pResourceAllocationInfo1) memset(pResourceAllocationInfo1, 0, sizeof(D3D12_RESOURCE_ALLOCATION_INFO1) * numResourceDescs);
    return info;
}
HRESULT STDMETHODCALLTYPE MLDevice::CreateCommittedResource2(const D3D12_HEAP_PROPERTIES* pHeapProperties, D3D12_HEAP_FLAGS HeapFlags, const D3D12_RESOURCE_DESC1* pDesc, D3D12_RESOURCE_STATES InitialResourceState, const D3D12_CLEAR_VALUE* pOptimizedClearValue, ID3D12ProtectedResourceSession* pProtectedSession, REFIID riid, void** ppvResource) {
    if (!pDesc) return E_INVALIDARG;
    D3D12_RESOURCE_DESC desc0 = {};
    desc0.Dimension = pDesc->Dimension;
    desc0.Alignment = pDesc->Alignment;
    desc0.Width = pDesc->Width;
    desc0.Height = pDesc->Height;
    desc0.DepthOrArraySize = pDesc->DepthOrArraySize;
    desc0.MipLevels = pDesc->MipLevels;
    desc0.Format = pDesc->Format;
    desc0.SampleDesc = pDesc->SampleDesc;
    desc0.Layout = pDesc->Layout;
    desc0.Flags = pDesc->Flags;
    return CreateCommittedResource(pHeapProperties, HeapFlags, &desc0, InitialResourceState, pOptimizedClearValue, riid, ppvResource);
}
HRESULT STDMETHODCALLTYPE MLDevice::CreatePlacedResource1(ID3D12Heap* pHeap, UINT64 HeapOffset, const D3D12_RESOURCE_DESC1* pDesc, D3D12_RESOURCE_STATES InitialState, const D3D12_CLEAR_VALUE* pOptimizedClearValue, REFIID riid, void** ppvResource) {
    if (!pDesc) return E_INVALIDARG;
    D3D12_RESOURCE_DESC desc0 = {};
    desc0.Dimension = pDesc->Dimension;
    desc0.Alignment = pDesc->Alignment;
    desc0.Width = pDesc->Width;
    desc0.Height = pDesc->Height;
    desc0.DepthOrArraySize = pDesc->DepthOrArraySize;
    desc0.MipLevels = pDesc->MipLevels;
    desc0.Format = pDesc->Format;
    desc0.SampleDesc = pDesc->SampleDesc;
    desc0.Layout = pDesc->Layout;
    desc0.Flags = pDesc->Flags;
    return CreatePlacedResource(pHeap, HeapOffset, &desc0, InitialState, pOptimizedClearValue, riid, ppvResource);
}

void STDMETHODCALLTYPE MLDevice::GetCopyableFootprints1(const D3D12_RESOURCE_DESC1* pResourceDesc, UINT FirstSubresource, UINT NumSubresources, UINT64 BaseOffset, D3D12_PLACED_SUBRESOURCE_FOOTPRINT* pLayouts, UINT* pNumRows, UINT64* pRowSizesInBytes, UINT64* pTotalBytes) {}

// ID3D12Device9
HRESULT STDMETHODCALLTYPE MLDevice::CreateShaderCacheSession(const D3D12_SHADER_CACHE_SESSION_DESC* pDesc, REFIID riid, void** ppvSession) { return E_FAIL; }
HRESULT STDMETHODCALLTYPE MLDevice::ShaderCacheControl(D3D12_SHADER_CACHE_KIND_FLAGS Kinds, D3D12_SHADER_CACHE_CONTROL_FLAGS Control) { return S_OK; }
HRESULT STDMETHODCALLTYPE MLDevice::CreateCommandQueue1(const D3D12_COMMAND_QUEUE_DESC* pDesc, REFIID CreatorID, REFIID riid, void** ppCommandQueue) { return E_FAIL; }

// ID3D12Device10
HRESULT STDMETHODCALLTYPE MLDevice::CreateCommittedResource3(const D3D12_HEAP_PROPERTIES* pHeapProperties, D3D12_HEAP_FLAGS HeapFlags, const D3D12_RESOURCE_DESC1* pDesc, D3D12_BARRIER_LAYOUT InitialLayout, const D3D12_CLEAR_VALUE* pOptimizedClearValue, ID3D12ProtectedResourceSession* pProtectedSession, UINT32 NumCastableFormats, const DXGI_FORMAT *pCastableFormats, REFIID riidResource, void** ppvResource) {
    if (!pDesc) return E_INVALIDARG;
    D3D12_RESOURCE_DESC desc0 = {};
    desc0.Dimension = pDesc->Dimension;
    desc0.Alignment = pDesc->Alignment;
    desc0.Width = pDesc->Width;
    desc0.Height = pDesc->Height;
    desc0.DepthOrArraySize = pDesc->DepthOrArraySize;
    desc0.MipLevels = pDesc->MipLevels;
    desc0.Format = pDesc->Format;
    desc0.SampleDesc = pDesc->SampleDesc;
    desc0.Layout = pDesc->Layout;
    desc0.Flags = pDesc->Flags;
    return CreateCommittedResource(pHeapProperties, HeapFlags, &desc0, D3D12_RESOURCE_STATE_COMMON, pOptimizedClearValue, riidResource, ppvResource);
}
HRESULT STDMETHODCALLTYPE MLDevice::CreatePlacedResource2(ID3D12Heap* pHeap, UINT64 HeapOffset, const D3D12_RESOURCE_DESC1* pDesc, D3D12_BARRIER_LAYOUT InitialLayout, const D3D12_CLEAR_VALUE* pOptimizedClearValue, UINT32 NumCastableFormats, const DXGI_FORMAT *pCastableFormats, REFIID riid, void** ppvResource) {
    if (!pDesc) return E_INVALIDARG;
    D3D12_RESOURCE_DESC desc0 = {};
    desc0.Dimension = pDesc->Dimension;
    desc0.Alignment = pDesc->Alignment;
    desc0.Width = pDesc->Width;
    desc0.Height = pDesc->Height;
    desc0.DepthOrArraySize = pDesc->DepthOrArraySize;
    desc0.MipLevels = pDesc->MipLevels;
    desc0.Format = pDesc->Format;
    desc0.SampleDesc = pDesc->SampleDesc;
    desc0.Layout = pDesc->Layout;
    desc0.Flags = pDesc->Flags;
    return CreatePlacedResource(pHeap, HeapOffset, &desc0, D3D12_RESOURCE_STATE_COMMON, pOptimizedClearValue, riid, ppvResource);
}
HRESULT STDMETHODCALLTYPE MLDevice::CreateReservedResource2(const D3D12_RESOURCE_DESC* pDesc, D3D12_BARRIER_LAYOUT InitialLayout, const D3D12_CLEAR_VALUE* pOptimizedClearValue, ID3D12ProtectedResourceSession *pProtectedSession, UINT32 NumCastableFormats, const DXGI_FORMAT *pCastableFormats, REFIID riid, void** ppvResource) { return E_FAIL; }

// ID3D12Device11
void STDMETHODCALLTYPE MLDevice::CreateSampler2(const D3D12_SAMPLER_DESC2* pDesc, D3D12_CPU_DESCRIPTOR_HANDLE DestDescriptor) {}

// ID3D12Device12
D3D12_RESOURCE_ALLOCATION_INFO STDMETHODCALLTYPE MLDevice::GetResourceAllocationInfo3(UINT visibleMask, UINT numResourceDescs, const D3D12_RESOURCE_DESC1* pResourceDescs, const UINT32* pNumCastableFormats, const DXGI_FORMAT *const *ppCastableFormats, D3D12_RESOURCE_ALLOCATION_INFO1* pResourceAllocationInfo1) { 
    D3D12_RESOURCE_ALLOCATION_INFO info = {};
    if (pResourceAllocationInfo1) memset(pResourceAllocationInfo1, 0, sizeof(D3D12_RESOURCE_ALLOCATION_INFO1) * numResourceDescs);
    return info;
}

// ID3D12Device13
HRESULT STDMETHODCALLTYPE MLDevice::OpenExistingHeapFromAddress1(const void* pAddress, SIZE_T size, REFIID riid, void** ppvHeap) { return E_FAIL; }

// ID3D12Device14
HRESULT STDMETHODCALLTYPE MLDevice::CreateRootSignatureFromSubobjectInLibrary(UINT nodeMask, const void* pLibraryBlob, SIZE_T blobLengthInBytes, LPCWSTR subobjectName, REFIID riid, void** ppvRootSignature) { return E_FAIL; }
