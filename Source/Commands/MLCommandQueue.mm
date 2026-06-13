#include "Metalloid/Commands/MLCommandQueue.h"
#include "Metalloid/Commands/MLCommandList.h"
#include "Metalloid/Device/MLDevice.h"
#include "Metalloid/Resources/MLResource.h"
#include "Metalloid/Sync/MLFence.h"
#include <iostream>

MLCommandQueue::MLCommandQueue(ID3D12Device* parentDevice, MetalCommandQueueType metalQueue, const D3D12_COMMAND_QUEUE_DESC& desc)
    : m_refCount(1), m_parentDevice(parentDevice), m_metalCommandQueue(metalQueue), m_desc(desc) {
    std::cout << "[Metalloid] ID3D12CommandQueue created." << std::endl;
#ifdef __OBJC__
    if (m_metalCommandQueue) {
        m_metalCommandQueue.label = @"Metalloid Default Queue";
    }
#endif
}

MLCommandQueue::~MLCommandQueue() {
    std::cout << "[Metalloid] ID3D12CommandQueue destroyed." << std::endl;
}

HRESULT STDMETHODCALLTYPE MLCommandQueue::QueryInterface(REFIID riid, void** ppvObject) {
    if (!ppvObject) return E_POINTER;

    if (riid == __uuidof(IUnknown) ||
        riid == __uuidof(ID3D12Object) ||
        riid == __uuidof(ID3D12DeviceChild) ||
        riid == __uuidof(ID3D12CommandQueue)) {
        *ppvObject = static_cast<ID3D12CommandQueue*>(this);
        AddRef();
        return S_OK;
    }

    *ppvObject = nullptr;
    return E_NOINTERFACE;
}

ULONG STDMETHODCALLTYPE MLCommandQueue::AddRef() {
    return ++m_refCount;
}

ULONG STDMETHODCALLTYPE MLCommandQueue::Release() {
    ULONG count = --m_refCount;
    if (count == 0) {
        delete this;
    }
    return count;
}

ML_IMPL_PRIVATE_DATA(MLCommandQueue)

HRESULT STDMETHODCALLTYPE MLCommandQueue::SetName(LPCWSTR Name) {
#ifdef __OBJC__
    if (m_metalCommandQueue && Name) {
        UINT size = (UINT)(wcslen(Name) * sizeof(wchar_t));
        NSString* nameStr = [[NSString alloc] initWithBytes:Name length:size encoding:NSUTF32LittleEndianStringEncoding];
        m_metalCommandQueue.label = nameStr;
    }
#endif
    return S_OK;
}

HRESULT STDMETHODCALLTYPE MLCommandQueue::GetDevice(REFIID riid, void** ppvDevice) {
    if (!ppvDevice) return E_POINTER;
    if (m_parentDevice) {
        return m_parentDevice->QueryInterface(riid, ppvDevice);
    }
    return E_NOINTERFACE;
}

void STDMETHODCALLTYPE MLCommandQueue::UpdateTileMappings(
    ID3D12Resource* pResource,
    UINT NumResourceRegions,
    const D3D12_TILED_RESOURCE_COORDINATE* pResourceRegionStartCoordinates,
    const D3D12_TILE_REGION_SIZE* pResourceRegionSizes,
    ID3D12Heap* pHeap,
    UINT NumRanges,
    const D3D12_TILE_RANGE_FLAGS* pRangeFlags,
    const UINT* pHeapRangeStartOffsets,
    const UINT* pRangeTileCounts,
    D3D12_TILE_MAPPING_FLAGS Flags) {
}

void STDMETHODCALLTYPE MLCommandQueue::CopyTileMappings(
    ID3D12Resource* pDstResource,
    const D3D12_TILED_RESOURCE_COORDINATE* pDstRegionStartCoordinate,
    ID3D12Resource* pSrcResource,
    const D3D12_TILED_RESOURCE_COORDINATE* pSrcRegionStartCoordinate,
    const D3D12_TILE_REGION_SIZE* pRegionSize,
    D3D12_TILE_MAPPING_FLAGS Flags) {
}

void STDMETHODCALLTYPE MLCommandQueue::ExecuteCommandLists(
    UINT NumCommandLists,
    ID3D12CommandList* const* ppCommandLists) {
    std::cout << "[Metalloid] ID3D12CommandQueue::ExecuteCommandLists called with " << NumCommandLists << " lists." << std::endl;
#ifdef __OBJC__
    for (UINT i = 0; i < NumCommandLists; ++i) {
        if (ppCommandLists[i]) {
            MLCommandList* mlList = static_cast<MLCommandList*>(ppCommandLists[i]);
            id<MTLCommandBuffer> cmdBuf = mlList->GetMetalCommandBuffer();
            if (cmdBuf) {
                cmdBuf.label = @"Metalloid Command Buffer";
                
                // Timeline Drift Fix 2: Resolve patch tables
                MLDevice* mlDevice = static_cast<MLDevice*>(m_parentDevice);
                if (mlDevice) {
                    mlDevice->m_globalResourceStateMutex.lock();
                    for (auto& patch : mlList->GetPatchTable()) {
                        auto it = mlDevice->m_globalResourceStates.find(patch.resource);
                        if (it != mlDevice->m_globalResourceStates.end()) {
                            *patch.oldLayoutPtr = it->second.uniform_state.layout;
                        }
                    }
                    for (auto& pair : mlList->GetLocalStates()) {
                        mlDevice->m_globalResourceStates[pair.first] = pair.second;
                    }
                    mlDevice->m_globalResourceStateMutex.unlock();
                }

                // BUG FIX: Implicit Resource State Decay
                // We must copy the vector so the block captures it
                std::vector<MLResource*> accessedResources = mlList->GetAccessedResources();
                [cmdBuf addCompletedHandler:^(id<MTLCommandBuffer> buffer) {
                    if (buffer.status == MTLCommandBufferStatusError) {
                        mlDevice->NotifyDeviceError(buffer.error);
                    }
                    for (MLResource* res : accessedResources) {
                        if (res) {
                            res->ApplyImplicitDecay();
                        }
                    }
                }];
                [cmdBuf commit];
                mlList->SetMetalCommandBuffer(nil);
            }
        }
    }
#endif
}

void STDMETHODCALLTYPE MLCommandQueue::SetMarker(UINT Metadata, const void* pData, UINT Size) {
#ifdef __OBJC__
    if (m_metalCommandQueue && pData && Size > 0) {
        NSString* marker = [[NSString alloc] initWithBytes:pData length:Size encoding:NSUTF8StringEncoding];
        if (marker) {
            // MTLCommandQueue doesn't have an exact insertDebugSignpost equivalent to CommandBuffer, 
            // but we can log or just ignore it safely.
            // Some drivers map this to os_signpost. Safe stub.
        }
    }
#endif
}
void STDMETHODCALLTYPE MLCommandQueue::BeginEvent(UINT Metadata, const void* pData, UINT Size) {
#ifdef __OBJC__
    if (m_metalCommandQueue && pData && Size > 0) {
        NSString* marker = [[NSString alloc] initWithBytes:pData length:Size encoding:NSUTF8StringEncoding];
        if (marker) {
            id<MTLCommandBuffer> cmdBuf = [m_metalCommandQueue commandBuffer];
            [cmdBuf pushDebugGroup:marker];
            [cmdBuf commit];
        }
    }
#endif
}
void STDMETHODCALLTYPE MLCommandQueue::EndEvent() {
#ifdef __OBJC__
    if (m_metalCommandQueue) {
        id<MTLCommandBuffer> cmdBuf = [m_metalCommandQueue commandBuffer];
        [cmdBuf popDebugGroup];
        [cmdBuf commit];
    }
#endif
}

HRESULT STDMETHODCALLTYPE MLCommandQueue::Signal(ID3D12Fence* pFence, UINT64 Value) {
#ifdef __OBJC__
    if (!pFence) return E_INVALIDARG;
    MLFence* mlFence = static_cast<MLFence*>(pFence);
    id<MTLSharedEvent> sharedEvent = mlFence->GetMetalSharedEvent();
    id<MTLCommandQueue> mtlQueue = m_metalCommandQueue;
    
    if (mtlQueue && sharedEvent) {
        id<MTLCommandBuffer> cmdBuf = [mtlQueue commandBuffer];
        [cmdBuf encodeSignalEvent:sharedEvent value:Value];
        [cmdBuf commit];
    }
#endif
    return S_OK;
}

HRESULT STDMETHODCALLTYPE MLCommandQueue::Wait(ID3D12Fence* pFence, UINT64 Value) {
#ifdef __OBJC__
    if (!pFence) return E_INVALIDARG;
    MLFence* mlFence = static_cast<MLFence*>(pFence);
    id<MTLSharedEvent> sharedEvent = mlFence->GetMetalSharedEvent();
    id<MTLCommandQueue> mtlQueue = m_metalCommandQueue;
    
    if (mtlQueue && sharedEvent) {
        id<MTLCommandBuffer> cmdBuf = [mtlQueue commandBuffer];
        [cmdBuf encodeWaitForEvent:sharedEvent value:Value];
        [cmdBuf commit];
    }
#endif
    return S_OK;
}

HRESULT STDMETHODCALLTYPE MLCommandQueue::GetTimestampFrequency(UINT64* pFrequency) {
    if (pFrequency) {
        *pFrequency = 1000000000ULL; // 1 GHz
    }
    return S_OK;
}

HRESULT STDMETHODCALLTYPE MLCommandQueue::GetClockCalibration(UINT64* pGpuTimestamp, UINT64* pCpuTimestamp) {
    if (pGpuTimestamp) *pGpuTimestamp = 0;
    if (pCpuTimestamp) *pCpuTimestamp = 0;
    return S_OK;
}

D3D12_COMMAND_QUEUE_DESC STDMETHODCALLTYPE MLCommandQueue::GetDesc() {
    return m_desc;
}
