#pragma once
#include <Metalloid/Common/MLPrivateData.h>

#include "d3d12_mac_common.h"
#include <vector>

class MLCommandAllocator : public ID3D12CommandAllocator {
    ML_DECL_PRIVATE_DATA()
private:
    std::atomic<ULONG> m_refCount{1};
    ID3D12Device* m_parentDevice;
    D3D12_COMMAND_LIST_TYPE m_type;
    void* m_defaultQueue;
    std::vector<void*> m_commandBufferPool;

public:
    void* AllocateCommandBuffer();
    MLCommandAllocator(ID3D12Device* parentDevice, D3D12_COMMAND_LIST_TYPE type, void* defaultQueue);
    virtual ~MLCommandAllocator();

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

    // ID3D12CommandAllocator
    virtual HRESULT STDMETHODCALLTYPE Reset() override;

    D3D12_COMMAND_LIST_TYPE GetType() const { return m_type; }
    void* GetDefaultQueue() const { return m_defaultQueue; }
};
