#include "Metalloid/Device/MLDevice.h"
#import <Metal/Metal.h>
#include <iostream>
#include <vector>
#include <cstring>

class MLBlob : public ID3DBlob {
private:
    ULONG m_refCount;
    std::vector<uint8_t> m_data;
public:
    MLBlob(size_t size) : m_refCount(1) {
        m_data.resize(size);
    }
    virtual ~MLBlob() {}

    HRESULT STDMETHODCALLTYPE QueryInterface(REFIID riid, void** ppvObject) override {
        if (!ppvObject) return E_POINTER;
        const GUID IID_ID3D10Blob_Local = { 0x8ba5fb08, 0x5195, 0x40e2, { 0xac, 0x58, 0x0d, 0x98, 0x9c, 0x3a, 0x01, 0x02 } };
        const GUID IID_IUnknown_Local = { 0x00000000, 0x0000, 0x0000, { 0xC0, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x46 } };
        if (memcmp(&riid, &IID_IUnknown_Local, sizeof(GUID)) == 0 || memcmp(&riid, &IID_ID3D10Blob_Local, sizeof(GUID)) == 0) {
            *ppvObject = this;
            AddRef();
            return S_OK;
        }
        *ppvObject = nullptr;
        return E_NOINTERFACE;
    }

    ULONG STDMETHODCALLTYPE AddRef() override {
        return ++m_refCount;
    }

    ULONG STDMETHODCALLTYPE Release() override {
        ULONG count = --m_refCount;
        if (count == 0) delete this;
        return count;
    }

    LPVOID STDMETHODCALLTYPE GetBufferPointer() override {
        return m_data.data();
    }

    SIZE_T STDMETHODCALLTYPE GetBufferSize() override {
        return m_data.size();
    }
};

extern "C" ML_EXPORT HRESULT WINAPI D3D12CreateDevice(
    IUnknown* pAdapter,
    D3D_FEATURE_LEVEL MinimumFeatureLevel,
    REFIID riid,
    void** ppDevice
) {
    if (!ppDevice) return E_INVALIDARG;

    // Get the default Metal device on macOS
    id<MTLDevice> metalDevice = MTLCreateSystemDefaultDevice();
    if (!metalDevice) {
        std::cerr << "[Metalloid] Failed to create system default Metal device." << std::endl;
        return E_FAIL;
    }

    // Allocate MLDevice wrapping the Metal device
    MLDevice* device = new MLDevice(metalDevice);
    if (!device) {
        return E_OUTOFMEMORY;
    }

    HRESULT hr = device->QueryInterface(riid, ppDevice);
    device->Release(); // QueryInterface added a ref count, release local pointer
    return hr;
}

extern "C" ML_EXPORT HRESULT WINAPI D3D12GetDebugInterface(
    REFIID riid,
    void** ppvDebug
) {
    if (ppvDebug) {
        *ppvDebug = nullptr;
    }
    return E_NOINTERFACE;
}

static HRESULT SerializeRootSignatureImpl(const D3D12_ROOT_SIGNATURE_DESC* pDesc, ID3DBlob** ppBlob) {
    if (!pDesc || !ppBlob) return E_INVALIDARG;

    // Calculate required size
    size_t size = sizeof(uint32_t); // magic
    size += sizeof(D3D12_ROOT_SIGNATURE_FLAGS);
    size += sizeof(uint32_t); // num parameters

    for (UINT i = 0; i < pDesc->NumParameters; ++i) {
        const auto& param = pDesc->pParameters[i];
        size += sizeof(D3D12_ROOT_PARAMETER_TYPE) + sizeof(D3D12_SHADER_VISIBILITY);
        if (param.ParameterType == D3D12_ROOT_PARAMETER_TYPE_32BIT_CONSTANTS) {
            size += sizeof(UINT) * 3;
        } else if (param.ParameterType == D3D12_ROOT_PARAMETER_TYPE_DESCRIPTOR_TABLE) {
            size += sizeof(uint32_t); // num ranges
            size += param.DescriptorTable.NumDescriptorRanges * sizeof(D3D12_DESCRIPTOR_RANGE);
        } else {
            size += sizeof(UINT) * 2;
        }
    }

    size += sizeof(uint32_t); // num samplers
    size += pDesc->NumStaticSamplers * sizeof(D3D12_STATIC_SAMPLER_DESC);

    MLBlob* blob = new MLBlob(size);
    uint8_t* ptr = static_cast<uint8_t*>(blob->GetBufferPointer());

    uint32_t magic = 0x4D4C5253; // 'MLRS'
    memcpy(ptr, &magic, sizeof(magic)); ptr += sizeof(magic);

    memcpy(ptr, &pDesc->Flags, sizeof(pDesc->Flags)); ptr += sizeof(pDesc->Flags);

    uint32_t numParams = pDesc->NumParameters;
    memcpy(ptr, &numParams, sizeof(numParams)); ptr += sizeof(numParams);

    for (UINT i = 0; i < pDesc->NumParameters; ++i) {
        const auto& param = pDesc->pParameters[i];
        memcpy(ptr, &param.ParameterType, sizeof(param.ParameterType)); ptr += sizeof(param.ParameterType);
        memcpy(ptr, &param.ShaderVisibility, sizeof(param.ShaderVisibility)); ptr += sizeof(param.ShaderVisibility);

        if (param.ParameterType == D3D12_ROOT_PARAMETER_TYPE_32BIT_CONSTANTS) {
            memcpy(ptr, &param.Constants.ShaderRegister, sizeof(UINT)); ptr += sizeof(UINT);
            memcpy(ptr, &param.Constants.RegisterSpace, sizeof(UINT)); ptr += sizeof(UINT);
            memcpy(ptr, &param.Constants.Num32BitValues, sizeof(UINT)); ptr += sizeof(UINT);
        } else if (param.ParameterType == D3D12_ROOT_PARAMETER_TYPE_DESCRIPTOR_TABLE) {
            uint32_t numRanges = param.DescriptorTable.NumDescriptorRanges;
            memcpy(ptr, &numRanges, sizeof(numRanges)); ptr += sizeof(numRanges);
            size_t rangesSize = numRanges * sizeof(D3D12_DESCRIPTOR_RANGE);
            memcpy(ptr, param.DescriptorTable.pDescriptorRanges, rangesSize); ptr += rangesSize;
        } else {
            memcpy(ptr, &param.Descriptor.ShaderRegister, sizeof(UINT)); ptr += sizeof(UINT);
            memcpy(ptr, &param.Descriptor.RegisterSpace, sizeof(UINT)); ptr += sizeof(UINT);
        }
    }

    uint32_t numSamplers = pDesc->NumStaticSamplers;
    memcpy(ptr, &numSamplers, sizeof(numSamplers)); ptr += sizeof(numSamplers);
    
    size_t samplersSize = numSamplers * sizeof(D3D12_STATIC_SAMPLER_DESC);
    memcpy(ptr, pDesc->pStaticSamplers, samplersSize); ptr += samplersSize;

    *ppBlob = blob;
    return S_OK;
}

extern "C" int MLDevice_CreateDevice(void* pAdapter, int featureLevel, const void* riid, void** ppDevice)
{
    return D3D12CreateDevice(
        (IUnknown*)pAdapter,
        (D3D_FEATURE_LEVEL)featureLevel,
        *(const IID*)riid,
        ppDevice
    );
}

extern "C" ML_EXPORT HRESULT WINAPI D3D12SerializeRootSignature(
    const D3D12_ROOT_SIGNATURE_DESC* pRootSignature,
    D3D_ROOT_SIGNATURE_VERSION Version,
    ID3DBlob** ppBlob,
    ID3DBlob** ppErrorBlob
) {
    if (ppErrorBlob) *ppErrorBlob = nullptr;
    if (Version != D3D_ROOT_SIGNATURE_VERSION_1) {
        return E_INVALIDARG;
    }
    return SerializeRootSignatureImpl(pRootSignature, ppBlob);
}

extern "C" ML_EXPORT HRESULT WINAPI D3D12SerializeVersionedRootSignature(
    const D3D12_VERSIONED_ROOT_SIGNATURE_DESC* pRootSignature,
    ID3DBlob** ppBlob,
    ID3DBlob** ppErrorBlob
) {
    if (ppErrorBlob) *ppErrorBlob = nullptr;
    if (!pRootSignature) return E_INVALIDARG;

    if (pRootSignature->Version == D3D_ROOT_SIGNATURE_VERSION_1_0) {
        return SerializeRootSignatureImpl(&pRootSignature->Desc_1_0, ppBlob);
    }
    
    // We only support Version 1.0 for now, but 1.1 could be mapped if needed
    std::cerr << "[Metalloid] D3D12SerializeVersionedRootSignature: Unsupported version " << pRootSignature->Version << std::endl;
    return E_INVALIDARG;
}
