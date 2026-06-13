#pragma once
#include <Metalloid/Common/MLPrivateData.h>

#ifdef __OBJC__
#import <Metal/Metal.h>
typedef id<MTLResource> MetalResourceType;
typedef id<MTLBuffer> MetalBufferType;
typedef id<MTLTexture> MetalTextureType;
#else
typedef void* MetalResourceType;
typedef void* MetalBufferType;
typedef void* MetalTextureType;
#endif

#include "d3d12_mac_common.h"

#include <atomic>
#include <unordered_map>
#include <functional>
#include <vector>

class MLHeap;

struct SubresourceStateV2 {
    D3D12_BARRIER_LAYOUT layout = D3D12_BARRIER_LAYOUT_UNDEFINED;
    uint64_t memory_generation = 0;
    bool ever_written = false;
};

struct HierarchicalResourceState {
    enum Granularity {
        TRACK_WHOLE_RESOURCE,
        TRACK_PER_SUBRESOURCE
    } granularity = TRACK_WHOLE_RESOURCE;

    SubresourceStateV2 uniform_state;
    std::vector<SubresourceStateV2> per_sub_states;
    uint32_t mip_levels = 1;
    uint32_t array_layers = 1;
};

class MLResource : public ID3D12Resource {
    ML_DECL_PRIVATE_DATA()
private:
    std::atomic<ULONG> m_refCount{1};
    ID3D12Device* m_parentDevice;
    MetalResourceType m_metalResource;
    D3D12_RESOURCE_DESC m_desc;
    D3D12_HEAP_PROPERTIES m_heapProperties;
    D3D12_RESOURCE_STATES m_state;
    std::function<void(UINT64)> m_unregisterCallback;

public:
    MLHeap* m_heap = nullptr;
    UINT64 m_heapOffset = 0;
    UINT64 m_heapSize = 0;
    UINT64 m_memoryGeneration = 0;
    uint32_t m_undiscardedUndefinedCount = 0;
    bool m_pinnedToGeneral = false;
    HierarchicalResourceState m_shadowState;

private:

#ifdef __OBJC__
    std::unordered_map<UINT64, id<MTLAccelerationStructure>> m_accelerationStructures;
#else
    std::unordered_map<UINT64, void*> m_accelerationStructures;
#endif

    std::unordered_map<UINT, void*> m_mappedSubresources;

#ifdef __OBJC__
    id<MTLIndirectCommandBuffer> m_icb;
    id<MTLBuffer> m_icbCounter;
#else
    void* m_icb;
    void* m_icbCounter;
#endif


public:
    MLResource(ID3D12Device* parentDevice, std::function<void(UINT64)> unregisterCallback, MetalResourceType metalResource, const D3D12_RESOURCE_DESC& desc, const D3D12_HEAP_PROPERTIES* pHeapProps = nullptr);
    virtual ~MLResource();

    void SetAccelerationStructure(UINT64 offset, void* mtlAccelerationStructure);
    void* GetAccelerationStructure(UINT64 offset);

    void SetState(D3D12_RESOURCE_STATES state) { m_state = state; }
    D3D12_RESOURCE_STATES GetState() const { return m_state; }
    void ApplyImplicitDecay();

    // Heap placement tracking getters/setters
    void SetHeapPlacement(MLHeap* heap, UINT64 offset, UINT64 size) {
        m_heap = heap;
        m_heapOffset = offset;
        m_heapSize = size;
    }
    MLHeap* GetHeap() const { return m_heap; }
    UINT64 GetHeapOffset() const { return m_heapOffset; }
    UINT64 GetHeapSize() const { return m_heapSize; }

    void SetMemoryGeneration(UINT64 gen) { m_memoryGeneration = gen; }
    UINT64 GetMemoryGeneration() const { return m_memoryGeneration; }

    void SetPinnedToGeneral(bool pinned) { m_pinnedToGeneral = pinned; }
    bool IsPinnedToGeneral() const { return m_pinnedToGeneral; }

    void IncrementUndiscardedUndefinedCount() { m_undiscardedUndefinedCount++; }
    uint32_t GetUndiscardedUndefinedCount() const { return m_undiscardedUndefinedCount; }

    // Layout states getters/setters and helpers
    HierarchicalResourceState& GetShadowState() { return m_shadowState; }
    const HierarchicalResourceState& GetShadowState() const { return m_shadowState; }
    void PromoteToPerSubresource();
    void DemoteToWholeResource(D3D12_BARRIER_LAYOUT unifiedLayout);
    void MarkSubresourceWritten(UINT subresource);

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

    // ID3D12Resource
    virtual HRESULT STDMETHODCALLTYPE Map(
        UINT Subresource,
        const D3D12_RANGE* pReadRange,
        void** ppData) override;

    virtual void STDMETHODCALLTYPE Unmap(
        UINT Subresource,
        const D3D12_RANGE* pWrittenRange) override;

    virtual D3D12_RESOURCE_DESC STDMETHODCALLTYPE GetDesc() override;

    virtual D3D12_GPU_VIRTUAL_ADDRESS STDMETHODCALLTYPE GetGPUVirtualAddress() override;

    virtual HRESULT STDMETHODCALLTYPE WriteToSubresource(
        UINT DstSubresource,
        const D3D12_BOX* pDstBox,
        const void* pSrcData,
        UINT SrcRowPitch,
        UINT SrcDepthPitch) override;

    virtual HRESULT STDMETHODCALLTYPE ReadFromSubresource(
        void* pDstData,
        UINT DstRowPitch,
        UINT DstDepthPitch,
        UINT SrcSubresource,
        const D3D12_BOX* pSrcBox) override;

    virtual HRESULT STDMETHODCALLTYPE GetHeapProperties(
        D3D12_HEAP_PROPERTIES* pHeapProperties,
        D3D12_HEAP_FLAGS* pHeapFlags) override;

    // Helper utilities
    MetalResourceType GetMetalResource() const { return m_metalResource; }
    MetalTextureType GetMetalTexture() const { return (MetalTextureType)m_metalResource; }
    MetalBufferType GetMetalBuffer() const { return (MetalBufferType)m_metalResource; }

    // ICB Management for Work Graphs / GPU-Driven rendering
    void AllocateICB(UINT maxCommandCount, bool isCompute);
    void* GetICB() const { return (__bridge void*)m_icb; }
    void* GetICBCounter() const { return (__bridge void*)m_icbCounter; }

private:
    void GetFootprint(UINT subresource, UINT& width, UINT& height, UINT& depth, UINT& rowPitch, UINT& depthPitch, UINT& size);
};
