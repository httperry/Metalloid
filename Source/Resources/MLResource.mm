#include "Metalloid/Resources/MLResource.h"
#include <iostream>

MLResource::MLResource(ID3D12Device* parentDevice, std::function<void(UINT64)> unregisterCallback, MetalResourceType metalResource, const D3D12_RESOURCE_DESC& desc, const D3D12_HEAP_PROPERTIES* pHeapProps)
    : m_refCount(1), m_parentDevice(parentDevice), m_metalResource(metalResource), m_desc(desc), m_unregisterCallback(unregisterCallback), m_state(D3D12_RESOURCE_STATE_COMMON) {
    m_shadowState.granularity = HierarchicalResourceState::TRACK_WHOLE_RESOURCE;
    m_shadowState.uniform_state.layout = D3D12_BARRIER_LAYOUT_UNDEFINED;
    m_shadowState.uniform_state.memory_generation = 0;
    m_shadowState.uniform_state.ever_written = false;
    m_shadowState.mip_levels = std::max(1u, (UINT)m_desc.MipLevels);
    m_shadowState.array_layers = (m_desc.Dimension == D3D12_RESOURCE_DIMENSION_TEXTURE3D) ? 1 : m_desc.DepthOrArraySize;

    if (pHeapProps) {
        m_heapProperties = *pHeapProps;
    } else {
        memset(&m_heapProperties, 0, sizeof(m_heapProperties));
    }
    std::cout << "[Metalloid] ID3D12Resource created. Dimension: " << desc.Dimension << std::endl;
}

MLResource::~MLResource() {
    if (m_unregisterCallback && m_desc.Dimension == D3D12_RESOURCE_DIMENSION_BUFFER) {
        UINT64 gpuva = GetGPUVirtualAddress();
        m_unregisterCallback(gpuva);
    }
    for (auto& pair : m_mappedSubresources) {
        free(pair.second);
    }
    m_mappedSubresources.clear();
    std::cout << "[Metalloid] ID3D12Resource destroyed." << std::endl;
}

void MLResource::SetAccelerationStructure(UINT64 offset, void* mtlAccelerationStructure) {
#ifdef __OBJC__
    m_accelerationStructures[offset] = (__bridge id<MTLAccelerationStructure>)mtlAccelerationStructure;
#endif
}

void* MLResource::GetAccelerationStructure(UINT64 offset) {
#ifdef __OBJC__
    auto it = m_accelerationStructures.find(offset);
    if (it != m_accelerationStructures.end()) {
        return (__bridge void*)it->second;
    }
#endif
    return nullptr;
}

void MLResource::ApplyImplicitDecay() {
    // D3D12 Spec: Buffers and SIMULTANEOUS_ACCESS textures decay to COMMON after ExecuteCommandLists
    if (m_desc.Dimension == D3D12_RESOURCE_DIMENSION_BUFFER || (m_desc.Flags & D3D12_RESOURCE_FLAG_ALLOW_SIMULTANEOUS_ACCESS)) {
        m_state = D3D12_RESOURCE_STATE_COMMON;
    }
}

HRESULT STDMETHODCALLTYPE MLResource::QueryInterface(REFIID riid, void** ppvObject) {
    if (!ppvObject) return E_POINTER;

    if (riid == __uuidof(IUnknown) ||
        riid == __uuidof(ID3D12Object) ||
        riid == __uuidof(ID3D12DeviceChild) ||
        riid == __uuidof(ID3D12Pageable) ||
        riid == __uuidof(ID3D12Resource)) {
        *ppvObject = static_cast<ID3D12Resource*>(this);
        AddRef();
        return S_OK;
    }

    *ppvObject = nullptr;
    return E_NOINTERFACE;
}

ULONG STDMETHODCALLTYPE MLResource::AddRef() {
    return ++m_refCount;
}

ULONG STDMETHODCALLTYPE MLResource::Release() {
    ULONG count = --m_refCount;
    if (count == 0) {
        delete this;
    }
    return count;
}

ML_IMPL_PRIVATE_DATA(MLResource)

HRESULT STDMETHODCALLTYPE MLResource::SetName(LPCWSTR Name) {
#ifdef __OBJC__
    if (m_metalResource && Name) {
        NSString* nameStr = [[NSString alloc] initWithBytes:Name length:wcslen(Name)*sizeof(wchar_t) encoding:(sizeof(wchar_t) == 4 ? NSUTF32LittleEndianStringEncoding : NSUTF16LittleEndianStringEncoding)];
        m_metalResource.label = nameStr;
    }
#endif
    return S_OK;
}

HRESULT STDMETHODCALLTYPE MLResource::GetDevice(REFIID riid, void** ppvDevice) {
    if (!ppvDevice) return E_POINTER;
    if (m_parentDevice) {
        return m_parentDevice->QueryInterface(riid, ppvDevice);
    }
    return E_NOINTERFACE;
}

HRESULT STDMETHODCALLTYPE MLResource::Map(
    UINT Subresource,
    const D3D12_RANGE* pReadRange,
    void** ppData) {
    if (!ppData) return E_INVALIDARG;

#ifdef __OBJC__
    if (m_desc.Dimension == D3D12_RESOURCE_DIMENSION_BUFFER) {
        id<MTLBuffer> buffer = (id<MTLBuffer>)m_metalResource;
        void* ptr = [buffer contents];
        if (!ptr) {
            *ppData = nullptr;
            return E_FAIL;
        }
        *ppData = ptr;
        MarkSubresourceWritten(Subresource);
        return S_OK;
    } else {
        UINT width, height, depth, rowPitch, depthPitch, size;
        GetFootprint(Subresource, width, height, depth, rowPitch, depthPitch, size);
        
        void* ptr = m_mappedSubresources[Subresource];
        if (!ptr) {
            ptr = malloc(size);
            if (!ptr) return E_OUTOFMEMORY;
            m_mappedSubresources[Subresource] = ptr;
        }
        
        bool shouldRead = true;
        if (pReadRange && pReadRange->End <= pReadRange->Begin) {
            shouldRead = false;
        }
        
        if (shouldRead) {
            id<MTLTexture> texture = (id<MTLTexture>)m_metalResource;
            UINT mipLevels = std::max(1u, (UINT)m_desc.MipLevels);
            UINT arraySize = (m_desc.Dimension == D3D12_RESOURCE_DIMENSION_TEXTURE3D) ? 1 : m_desc.DepthOrArraySize;
            UINT mipLevel = Subresource % mipLevels;
            UINT arraySlice = (Subresource / mipLevels) % arraySize;
            UINT planeSlice = Subresource / (mipLevels * arraySize);
            UINT slice = arraySlice + planeSlice * arraySize;
            MTLRegion region = MTLRegionMake3D(0, 0, 0, width, height, depth);
            [texture getBytes:ptr bytesPerRow:rowPitch bytesPerImage:depthPitch fromRegion:region mipmapLevel:mipLevel slice:slice];
        }
        
        *ppData = ptr;
        MarkSubresourceWritten(Subresource);
        return S_OK;
    }
#endif

    return E_FAIL;
}

void STDMETHODCALLTYPE MLResource::Unmap(
    UINT Subresource,
    const D3D12_RANGE* pWrittenRange) {
#ifdef __OBJC__
    if (m_desc.Dimension == D3D12_RESOURCE_DIMENSION_BUFFER) {
        id<MTLBuffer> buffer = (id<MTLBuffer>)m_metalResource;
        if (buffer.storageMode == MTLStorageModeManaged) {
            NSRange range = NSMakeRange(0, buffer.length);
            if (pWrittenRange) {
                if (pWrittenRange->End <= pWrittenRange->Begin) return;
                NSUInteger begin = pWrittenRange->Begin;
                NSUInteger length = pWrittenRange->End - pWrittenRange->Begin;
                if (begin >= buffer.length) return;
                if (begin + length > buffer.length) length = buffer.length - begin;
                range = NSMakeRange(begin, length);
            }
            if (range.length > 0) {
                [buffer didModifyRange:range];
            }
        }
        MarkSubresourceWritten(Subresource);
    } else {
        auto it = m_mappedSubresources.find(Subresource);
        if (it != m_mappedSubresources.end()) {
            void* ptr = it->second;
            bool shouldWrite = true;
            if (pWrittenRange && pWrittenRange->End <= pWrittenRange->Begin) {
                shouldWrite = false;
            }
            if (shouldWrite) {
                id<MTLTexture> texture = (id<MTLTexture>)m_metalResource;
                UINT width, height, depth, rowPitch, depthPitch, size;
                GetFootprint(Subresource, width, height, depth, rowPitch, depthPitch, size);
                UINT mipLevels = std::max(1u, (UINT)m_desc.MipLevels);
                UINT arraySize = (m_desc.Dimension == D3D12_RESOURCE_DIMENSION_TEXTURE3D) ? 1 : m_desc.DepthOrArraySize;
                UINT mipLevel = Subresource % mipLevels;
                UINT arraySlice = (Subresource / mipLevels) % arraySize;
                UINT planeSlice = Subresource / (mipLevels * arraySize);
                UINT slice = arraySlice + planeSlice * arraySize;
                
                MTLRegion region = MTLRegionMake3D(0, 0, 0, width, height, depth);
                uint8_t* writePtr = (uint8_t*)ptr;

                NSRange modRange = NSMakeRange(0, size);
                if (pWrittenRange && pWrittenRange->End > pWrittenRange->Begin) {
                    UINT writtenBegin = pWrittenRange->Begin;
                    UINT writtenSize = pWrittenRange->End - writtenBegin;
                    if (writtenBegin < size) {
                        if (writtenBegin + writtenSize > size) writtenSize = size - writtenBegin;
                        modRange = NSMakeRange(writtenBegin, writtenSize);
                        
                        UINT startZ = writtenBegin / depthPitch;
                        UINT endZ = std::min((UINT)depth - 1, (writtenBegin + writtenSize - 1) / depthPitch);
                        UINT startY = (writtenBegin % depthPitch) / rowPitch;
                        UINT endY = std::min((UINT)height - 1, ((writtenBegin + writtenSize - 1) % depthPitch) / rowPitch);
                        
                        if (startZ != endZ) {
                            startY = 0;
                            endY = height - 1;
                        }
                        
                        region = MTLRegionMake3D(0, startY, startZ, width, endY - startY + 1, endZ - startZ + 1);
                        writePtr += (startZ * depthPitch) + (startY * rowPitch);
                    }
                }

                [texture replaceRegion:region mipmapLevel:mipLevel slice:slice withBytes:writePtr bytesPerRow:rowPitch bytesPerImage:depthPitch];

                if (texture.storageMode == MTLStorageModeManaged) {
                    if ([texture respondsToSelector:@selector(didModifyRange:)]) {
                        [(id)texture didModifyRange:modRange];
                    } else if ([texture buffer]) {
                        [[texture buffer] didModifyRange:NSMakeRange([texture bufferOffset] + modRange.location, modRange.length)];
                    }
                }
            }
            free(ptr);
            m_mappedSubresources.erase(it);
            if (shouldWrite) MarkSubresourceWritten(Subresource);
        }
    }
#endif
}

D3D12_RESOURCE_DESC STDMETHODCALLTYPE MLResource::GetDesc() {
    return m_desc;
}

D3D12_GPU_VIRTUAL_ADDRESS STDMETHODCALLTYPE MLResource::GetGPUVirtualAddress() {
#ifdef __OBJC__
    if (m_desc.Dimension == D3D12_RESOURCE_DIMENSION_BUFFER) {
        id<MTLBuffer> buffer = (id<MTLBuffer>)m_metalResource;
        if (@available(macOS 13.0, iOS 16.0, *)) {
            return (D3D12_GPU_VIRTUAL_ADDRESS)[buffer gpuAddress];
        }
    }
#endif
    return 0;
}

HRESULT STDMETHODCALLTYPE MLResource::WriteToSubresource(
    UINT DstSubresource,
    const D3D12_BOX* pDstBox,
    const void* pSrcData,
    UINT SrcRowPitch,
    UINT SrcDepthPitch) {
    if (!pSrcData) return E_INVALIDARG;

#ifdef __OBJC__
    if (m_desc.Dimension == D3D12_RESOURCE_DIMENSION_BUFFER) {
        id<MTLBuffer> buffer = (id<MTLBuffer>)m_metalResource;
        void* dst = [buffer contents];
        if (!dst) return E_FAIL;
        UINT offset = pDstBox ? pDstBox->left : 0;
        UINT size = pDstBox ? (pDstBox->right - pDstBox->left) : buffer.length;
        memcpy((uint8_t*)dst + offset, pSrcData, size);
        if (buffer.storageMode == MTLStorageModeManaged) {
            [buffer didModifyRange:NSMakeRange(offset, size)];
        }
        MarkSubresourceWritten(DstSubresource);
        return S_OK;
    } else {
        id<MTLTexture> texture = (id<MTLTexture>)m_metalResource;
        UINT mipLevels = std::max(1u, (UINT)m_desc.MipLevels);
        UINT arraySize = (m_desc.Dimension == D3D12_RESOURCE_DIMENSION_TEXTURE3D) ? 1 : m_desc.DepthOrArraySize;
        UINT mipLevel = DstSubresource % mipLevels;
        UINT arraySlice = (DstSubresource / mipLevels) % arraySize;
        UINT planeSlice = DstSubresource / (mipLevels * arraySize);
        UINT slice = arraySlice + planeSlice * arraySize;
        
        MTLRegion region;
        if (pDstBox) {
            region = MTLRegionMake3D(pDstBox->left, pDstBox->top, pDstBox->front,
                                     pDstBox->right - pDstBox->left,
                                     pDstBox->bottom - pDstBox->top,
                                     pDstBox->back - pDstBox->front);
        } else {
            region = MTLRegionMake3D(0, 0, 0, std::max<NSUInteger>(1, texture.width >> mipLevel), std::max<NSUInteger>(1, texture.height >> mipLevel), std::max<NSUInteger>(1, texture.depth >> mipLevel));
        }
        
        [texture replaceRegion:region
                   mipmapLevel:mipLevel
                         slice:slice
                     withBytes:pSrcData
                   bytesPerRow:SrcRowPitch
                 bytesPerImage:SrcDepthPitch];
        MarkSubresourceWritten(DstSubresource);
        return S_OK;
    }
#endif

    return E_FAIL;
}

HRESULT STDMETHODCALLTYPE MLResource::ReadFromSubresource(
    void* pDstData,
    UINT DstRowPitch,
    UINT DstDepthPitch,
    UINT SrcSubresource,
    const D3D12_BOX* pSrcBox) {
    if (!pDstData) return E_INVALIDARG;

#ifdef __OBJC__
    if (m_desc.Dimension == D3D12_RESOURCE_DIMENSION_BUFFER) {
        id<MTLBuffer> buffer = (id<MTLBuffer>)m_metalResource;
        void* src = [buffer contents];
        if (!src) return E_FAIL;
        UINT offset = pSrcBox ? pSrcBox->left : 0;
        UINT size = pSrcBox ? (pSrcBox->right - pSrcBox->left) : buffer.length;
        memcpy(pDstData, (uint8_t*)src + offset, size);
        return S_OK;
    } else {
        id<MTLTexture> texture = (id<MTLTexture>)m_metalResource;
        UINT mipLevels = std::max(1u, (UINT)m_desc.MipLevels);
        UINT arraySize = (m_desc.Dimension == D3D12_RESOURCE_DIMENSION_TEXTURE3D) ? 1 : m_desc.DepthOrArraySize;
        UINT mipLevel = SrcSubresource % mipLevels;
        UINT arraySlice = (SrcSubresource / mipLevels) % arraySize;
        UINT planeSlice = SrcSubresource / (mipLevels * arraySize);
        UINT slice = arraySlice + planeSlice * arraySize;
        
        MTLRegion region;
        if (pSrcBox) {
            region = MTLRegionMake3D(pSrcBox->left, pSrcBox->top, pSrcBox->front,
                                     pSrcBox->right - pSrcBox->left,
                                     pSrcBox->bottom - pSrcBox->top,
                                     pSrcBox->back - pSrcBox->front);
        } else {
            region = MTLRegionMake3D(0, 0, 0, std::max<NSUInteger>(1, texture.width >> mipLevel), std::max<NSUInteger>(1, texture.height >> mipLevel), std::max<NSUInteger>(1, texture.depth >> mipLevel));
        }
        
        [texture getBytes:pDstData
              bytesPerRow:DstRowPitch
            bytesPerImage:DstDepthPitch
               fromRegion:region
              mipmapLevel:mipLevel
                    slice:slice];
        return S_OK;
    }
#endif

    return E_FAIL;
}

HRESULT STDMETHODCALLTYPE MLResource::GetHeapProperties(
    D3D12_HEAP_PROPERTIES* pHeapProperties,
    D3D12_HEAP_FLAGS* pHeapFlags) {
    if (pHeapProperties) {
        *pHeapProperties = m_heapProperties;
    }
    if (pHeapFlags) {
        *pHeapFlags = D3D12_HEAP_FLAG_NONE;
    }
    return S_OK;
}

void MLResource::AllocateICB(UINT maxCommandCount, bool isCompute) {
#ifdef __OBJC__
    if (!m_parentDevice) return;
    
    id<MTLDevice> device = nil;
    if (m_metalResource) {
        device = m_metalResource.device;
    }
    if (!device) return;

    MTLIndirectCommandBufferDescriptor* icbDesc = [[MTLIndirectCommandBufferDescriptor alloc] init];
    icbDesc.commandTypes = isCompute ? MTLIndirectCommandTypeConcurrentDispatch : MTLIndirectCommandTypeDrawIndexed | MTLIndirectCommandTypeDraw;
    icbDesc.inheritPipelineState = YES;
    icbDesc.inheritBuffers = NO;
    icbDesc.maxVertexBufferBindCount = isCompute ? 0 : 31;
    icbDesc.maxFragmentBufferBindCount = isCompute ? 0 : 31;
    icbDesc.maxKernelBufferBindCount = isCompute ? 31 : 0;
    
    // For Work Graphs, max command count needs to handle variable dispatch grid sizes
    m_icb = [device newIndirectCommandBufferWithDescriptor:icbDesc maxCommandCount:maxCommandCount options:MTLResourceStorageModePrivate];
    
    // Allocate atomic counter buffer for dispatch tracking
    m_icbCounter = [device newBufferWithLength:sizeof(uint32_t) options:MTLResourceStorageModeShared];
    if (m_icbCounter && m_icbCounter.contents) {
        memset(m_icbCounter.contents, 0, sizeof(uint32_t));
    }
#endif
}

void MLResource::PromoteToPerSubresource() {
    if (m_shadowState.granularity == HierarchicalResourceState::TRACK_PER_SUBRESOURCE) return;
    
    uint32_t totalSubresources = m_shadowState.mip_levels * m_shadowState.array_layers;
    m_shadowState.per_sub_states.resize(totalSubresources, m_shadowState.uniform_state);
    m_shadowState.granularity = HierarchicalResourceState::TRACK_PER_SUBRESOURCE;
}

void MLResource::DemoteToWholeResource(D3D12_BARRIER_LAYOUT unifiedLayout) {
    if (m_shadowState.granularity == HierarchicalResourceState::TRACK_WHOLE_RESOURCE) {
        m_shadowState.uniform_state.layout = unifiedLayout;
        return;
    }
    
    m_shadowState.granularity = HierarchicalResourceState::TRACK_WHOLE_RESOURCE;
    bool any_written = false;
    uint64_t max_gen = 0;
    for (const auto& state : m_shadowState.per_sub_states) {
        if (state.ever_written) any_written = true;
        if (state.memory_generation > max_gen) max_gen = state.memory_generation;
    }
    m_shadowState.uniform_state.layout = unifiedLayout;
    m_shadowState.uniform_state.ever_written = any_written;
    m_shadowState.uniform_state.memory_generation = max_gen;
    m_shadowState.per_sub_states.clear();
}

void MLResource::MarkSubresourceWritten(UINT subresource) {
    if (m_shadowState.granularity == HierarchicalResourceState::TRACK_WHOLE_RESOURCE) {
        m_shadowState.uniform_state.ever_written = true;
    } else if (subresource < m_shadowState.per_sub_states.size()) {
        m_shadowState.per_sub_states[subresource].ever_written = true;
    }
}

void MLResource::GetFootprint(UINT subresource, UINT& width, UINT& height, UINT& depth, UINT& rowPitch, UINT& depthPitch, UINT& size) {
    UINT mipLevel = subresource % std::max(1u, (UINT)m_desc.MipLevels);
    width = std::max(1u, (UINT)(m_desc.Width >> mipLevel));
    height = std::max(1u, m_desc.Height >> mipLevel);
    depth = std::max(1u, (UINT)(m_desc.DepthOrArraySize >> mipLevel));
    bool isBC = false;
    UINT blockSize = 0;
    UINT bytesPerPixel = 4;
    switch (m_desc.Format) {
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
        case DXGI_FORMAT_B8G8R8A8_UNORM:
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

    if (isBC) {
        UINT numBlocksWide = std::max(1u, (width + 3) / 4);
        UINT numBlocksHigh = std::max(1u, (height + 3) / 4);
        rowPitch = numBlocksWide * blockSize;
        rowPitch = (rowPitch + 255) & ~255;
        depthPitch = rowPitch * numBlocksHigh;
        size = depthPitch * depth;
    } else {
        rowPitch = width * bytesPerPixel;
        rowPitch = (rowPitch + 255) & ~255;
        depthPitch = rowPitch * height;
        size = depthPitch * depth;
    }
}
