#pragma once
#include "Metalloid/Common/MLPrivateData.h"

#ifdef __OBJC__
@protocol MTLSamplerState;
#endif

#include "d3d12_mac_common.h"
#include <vector>

class MLDevice;

class MLRootSignature : public ID3D12RootSignature {
    ML_DECL_PRIVATE_DATA()
private:
    ULONG m_refCount;
    MLDevice* m_device;

public:
    struct RootParameter {
        D3D12_ROOT_PARAMETER_TYPE Type;
        D3D12_SHADER_VISIBILITY ShaderVisibility;
        UINT ShaderRegister;
        UINT RegisterSpace;
        UINT Num32BitValues;
        std::vector<D3D12_DESCRIPTOR_RANGE> DescriptorTableRanges;
    };

    std::vector<RootParameter> m_parameters;
    std::vector<D3D12_STATIC_SAMPLER_DESC> m_staticSamplers;
#ifdef __OBJC__
    std::vector<id<MTLSamplerState>> m_compiledSamplers;
#else
    std::vector<void*> m_compiledSamplers;
#endif
    D3D12_ROOT_SIGNATURE_FLAGS m_flags;

    MLRootSignature(MLDevice* device);
    virtual ~MLRootSignature();

    HRESULT Initialize(const void* pBlobWithRootSignature, SIZE_T blobLengthInBytes);

    // IUnknown Methods
    virtual HRESULT STDMETHODCALLTYPE QueryInterface(REFIID riid, void** ppvObject) override;
    virtual ULONG STDMETHODCALLTYPE AddRef() override;
    virtual ULONG STDMETHODCALLTYPE Release() override;

    // ID3D12Object Methods
    virtual HRESULT STDMETHODCALLTYPE GetPrivateData(REFGUID guid, UINT* pDataSize, void* pData) override;
    virtual HRESULT STDMETHODCALLTYPE SetPrivateData(REFGUID guid, UINT DataSize, const void* pData) override;
    virtual HRESULT STDMETHODCALLTYPE SetPrivateDataInterface(REFGUID guid, const IUnknown* pData) override;
    virtual HRESULT STDMETHODCALLTYPE SetName(LPCWSTR Name) override;

    // ID3D12DeviceChild
    virtual HRESULT STDMETHODCALLTYPE GetDevice(REFIID riid, void** ppvDevice) override;
};
