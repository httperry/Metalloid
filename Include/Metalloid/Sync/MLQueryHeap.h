#pragma once
#include "Metalloid/Common/MLPrivateData.h"

#ifdef __OBJC__
#import <Metal/Metal.h>
typedef id<MTLBuffer> MetalBufferType;
#else
typedef void* MetalBufferType;
#endif

#include "d3d12_mac_common.h"

class MLQueryHeap : public ID3D12QueryHeap {
    ML_DECL_PRIVATE_DATA()
private:
    std::atomic<ULONG> m_refCount{1};
#ifdef __OBJC__
    id<MTLCounterSampleBuffer> m_counterSampleBuffer;
#else
    void* m_counterSampleBuffer;
#endif

    ID3D12Device* m_parentDevice;
    MetalBufferType m_queryBuffer;
    D3D12_QUERY_HEAP_DESC m_desc;

public:
    MLQueryHeap(ID3D12Device* parentDevice, MetalBufferType queryBuffer, const D3D12_QUERY_HEAP_DESC& desc);
    virtual ~MLQueryHeap();

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

    MetalBufferType GetMetalBuffer() const { return m_queryBuffer; }
    D3D12_QUERY_HEAP_TYPE GetType() const { return m_desc.Type; }
    UINT GetCount() const { return m_desc.Count; }

#ifdef __OBJC__
    id<MTLCounterSampleBuffer> GetCounterSampleBuffer() const { return m_counterSampleBuffer; }
    void SetCounterSampleBuffer(id<MTLCounterSampleBuffer> buf) { m_counterSampleBuffer = buf; }
#else
    void* GetCounterSampleBuffer() const { return m_counterSampleBuffer; }
    void SetCounterSampleBuffer(void* buf) { m_counterSampleBuffer = buf; }
#endif
};
