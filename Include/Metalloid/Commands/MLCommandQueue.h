#pragma once
#include <Metalloid/Common/MLPrivateData.h>

#ifdef __OBJC__
#import <Metal/Metal.h>
typedef id<MTLCommandQueue> MetalCommandQueueType;
#else
typedef void* MetalCommandQueueType;
#endif

#include "d3d12_mac_common.h"

class MLCommandQueue : public ID3D12CommandQueue {
    ML_DECL_PRIVATE_DATA()
private:
    std::atomic<ULONG> m_refCount{1};
    ID3D12Device* m_parentDevice;
    MetalCommandQueueType m_metalCommandQueue;
    D3D12_COMMAND_QUEUE_DESC m_desc;

public:
    MLCommandQueue(ID3D12Device* parentDevice, MetalCommandQueueType metalQueue, const D3D12_COMMAND_QUEUE_DESC& desc);
    virtual ~MLCommandQueue();

    // IUnknown
    virtual HRESULT STDMETHODCALLTYPE QueryInterface(REFIID riid, void** ppvObject) override;
    virtual ULONG STDMETHODCALLTYPE AddRef() override;
    virtual ULONG STDMETHODCALLTYPE Release() override;

    // ID3D12Object
    virtual HRESULT STDMETHODCALLTYPE GetPrivateData(REFGUID guid, UINT* pDataSize, void* pData) override;
    virtual HRESULT STDMETHODCALLTYPE SetPrivateData(REFGUID guid, UINT DataSize, const void* pData) override;
    virtual HRESULT STDMETHODCALLTYPE SetPrivateDataInterface(REFGUID guid, const IUnknown* pData) override;
    virtual HRESULT STDMETHODCALLTYPE SetName(LPCWSTR Name) override;

    // ID3D12DeviceChild
    virtual HRESULT STDMETHODCALLTYPE GetDevice(REFIID riid, void** ppvDevice) override;

    // ID3D12CommandQueue
    virtual void STDMETHODCALLTYPE UpdateTileMappings(
        ID3D12Resource* pResource,
        UINT NumResourceRegions,
        const D3D12_TILED_RESOURCE_COORDINATE* pResourceRegionStartCoordinates,
        const D3D12_TILE_REGION_SIZE* pResourceRegionSizes,
        ID3D12Heap* pHeap,
        UINT NumRanges,
        const D3D12_TILE_RANGE_FLAGS* pRangeFlags,
        const UINT* pHeapRangeStartOffsets,
        const UINT* pRangeTileCounts,
        D3D12_TILE_MAPPING_FLAGS Flags) override;

    virtual void STDMETHODCALLTYPE CopyTileMappings(
        ID3D12Resource* pDstResource,
        const D3D12_TILED_RESOURCE_COORDINATE* pDstRegionStartCoordinate,
        ID3D12Resource* pSrcResource,
        const D3D12_TILED_RESOURCE_COORDINATE* pSrcRegionStartCoordinate,
        const D3D12_TILE_REGION_SIZE* pRegionSize,
        D3D12_TILE_MAPPING_FLAGS Flags) override;

    virtual void STDMETHODCALLTYPE ExecuteCommandLists(
        UINT NumCommandLists,
        ID3D12CommandList* const* ppCommandLists) override;

    virtual void STDMETHODCALLTYPE SetMarker(
        UINT Metadata,
        const void* pData,
        UINT Size) override;

    virtual void STDMETHODCALLTYPE BeginEvent(
        UINT Metadata,
        const void* pData,
        UINT Size) override;

    virtual void STDMETHODCALLTYPE EndEvent() override;

    virtual HRESULT STDMETHODCALLTYPE Signal(
        ID3D12Fence* pFence,
        UINT64 Value) override;

    virtual HRESULT STDMETHODCALLTYPE Wait(
        ID3D12Fence* pFence,
        UINT64 Value) override;

    virtual HRESULT STDMETHODCALLTYPE GetTimestampFrequency(
        UINT64* pFrequency) override;

    virtual HRESULT STDMETHODCALLTYPE GetClockCalibration(
        UINT64* pGpuTimestamp,
        UINT64* pCpuTimestamp) override;

    virtual D3D12_COMMAND_QUEUE_DESC STDMETHODCALLTYPE GetDesc() override;

    MetalCommandQueueType GetMetalQueue() const { return m_metalCommandQueue; }
};
