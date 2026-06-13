#pragma once
#include "Metalloid/Common/MLPrivateData.h"

#ifdef __OBJC__
#import <Metal/Metal.h>
typedef id<MTLSharedEvent> MetalSharedEventType;
#else
typedef void* MetalSharedEventType;
#endif

#include "d3d12_mac_common.h"
#include <atomic>
#include <mutex>
#include <condition_variable>
#include <vector>

struct MLEvent {
    std::mutex mutex;
    std::condition_variable cond;
    bool signaled = false;
};

class MLFence : public ID3D12Fence {
    ML_DECL_PRIVATE_DATA()
private:
    std::atomic<ULONG> m_refCount{1};
    ID3D12Device* m_parentDevice;
    MetalSharedEventType m_sharedEvent;
    std::atomic<UINT64> m_currentValue;
    D3D12_FENCE_FLAGS m_flags;

    struct PendingEvent {
        UINT64 value;
        HANDLE hEvent;
    };
    std::mutex m_pendingEventsMutex;
    std::vector<PendingEvent> m_pendingEvents;

public:
    MLFence(ID3D12Device* parentDevice, MetalSharedEventType sharedEvent, UINT64 initialValue, D3D12_FENCE_FLAGS flags);
    virtual ~MLFence();

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

    // ID3D12Fence
    virtual UINT64 STDMETHODCALLTYPE GetCompletedValue() override;
    virtual HRESULT STDMETHODCALLTYPE SetEventOnCompletion(UINT64 Value, HANDLE hEvent) override;
    virtual HRESULT STDMETHODCALLTYPE Signal(UINT64 Value) override;

    MetalSharedEventType GetMetalSharedEvent() const { return m_sharedEvent; }
};
