#pragma once
#include "Metalloid/Common/MLPrivateData.h"

#ifdef __OBJC__
#import <Metal/Metal.h>
typedef id<MTLHeap> MetalHeapType;
#else
typedef void* MetalHeapType;
#endif

#include "d3d12_mac_common.h"
#include <vector>
#include <mutex>

struct PhysicalMemoryRange {
    UINT64 offset;
    UINT64 size;
    UINT64 generationId;
};

class MLHeap : public ID3D12Heap {
    ML_DECL_PRIVATE_DATA()
private:
    std::atomic<ULONG> m_refCount{1};
    ID3D12Device* m_parentDevice;
    MetalHeapType m_metalHeap;
    D3D12_HEAP_DESC m_desc;
    
    std::vector<PhysicalMemoryRange> m_memoryRanges;
    std::mutex m_heapMutex;
    UINT64 m_globalHeapGen = 1;

public:
    MLHeap(ID3D12Device* parentDevice, MetalHeapType metalHeap, const D3D12_HEAP_DESC& desc);
    virtual ~MLHeap();

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

    // ID3D12Heap
    virtual D3D12_HEAP_DESC STDMETHODCALLTYPE GetDesc() override;

    MetalHeapType GetMetalHeap() const { return m_metalHeap; }

    UINT64 GetOrCreateGenerationForRange(UINT64 offset, UINT64 size);
    void InvalidateRange(UINT64 offset, UINT64 size);
};
