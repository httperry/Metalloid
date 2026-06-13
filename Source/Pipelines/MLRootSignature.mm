#include "Metalloid/Pipelines/MLRootSignature.h"
#include "Metalloid/Device/MLDevice.h"
#include <iostream>

MLRootSignature::MLRootSignature(MLDevice* device) : m_refCount(1), m_device(device), m_flags(D3D12_ROOT_SIGNATURE_FLAG_NONE) {
    if (m_device) {
        m_device->AddRef();
    }
}

MLRootSignature::~MLRootSignature() {
    if (m_device) {
        m_device->Release();
    }
}

HRESULT MLRootSignature::Initialize(const void* pBlobWithRootSignature, SIZE_T blobLengthInBytes) {
    if (!pBlobWithRootSignature || blobLengthInBytes < sizeof(uint32_t)) return E_INVALIDARG;

    const uint8_t* ptr = static_cast<const uint8_t*>(pBlobWithRootSignature);
    const uint8_t* end = ptr + blobLengthInBytes;

    uint32_t magic = *reinterpret_cast<const uint32_t*>(ptr); ptr += sizeof(uint32_t);
    if (magic != 0x4D4C5253) { // 'MLRS'
        std::cerr << "[Metalloid] Unsupported root signature format. Expected custom MLRS serialization." << std::endl;
        return E_INVALIDARG;
    }

    if (ptr + sizeof(D3D12_ROOT_SIGNATURE_FLAGS) > end) return E_INVALIDARG;
    m_flags = *reinterpret_cast<const D3D12_ROOT_SIGNATURE_FLAGS*>(ptr); ptr += sizeof(D3D12_ROOT_SIGNATURE_FLAGS);

    if (ptr + sizeof(uint32_t) > end) return E_INVALIDARG;
    uint32_t numParameters = *reinterpret_cast<const uint32_t*>(ptr); ptr += sizeof(uint32_t);

    for (uint32_t i = 0; i < numParameters; ++i) {
        if (ptr + sizeof(D3D12_ROOT_PARAMETER_TYPE) + sizeof(D3D12_SHADER_VISIBILITY) > end) return E_INVALIDARG;
        
        RootParameter param = {};
        param.Type = *reinterpret_cast<const D3D12_ROOT_PARAMETER_TYPE*>(ptr); ptr += sizeof(D3D12_ROOT_PARAMETER_TYPE);
        param.ShaderVisibility = *reinterpret_cast<const D3D12_SHADER_VISIBILITY*>(ptr); ptr += sizeof(D3D12_SHADER_VISIBILITY);

        if (param.Type == D3D12_ROOT_PARAMETER_TYPE_32BIT_CONSTANTS) {
            if (ptr + sizeof(UINT) * 3 > end) return E_INVALIDARG;
            param.ShaderRegister = *reinterpret_cast<const UINT*>(ptr); ptr += sizeof(UINT);
            param.RegisterSpace = *reinterpret_cast<const UINT*>(ptr); ptr += sizeof(UINT);
            param.Num32BitValues = *reinterpret_cast<const UINT*>(ptr); ptr += sizeof(UINT);
        } else if (param.Type == D3D12_ROOT_PARAMETER_TYPE_DESCRIPTOR_TABLE) {
            if (ptr + sizeof(uint32_t) > end) return E_INVALIDARG;
            uint32_t numRanges = *reinterpret_cast<const uint32_t*>(ptr); ptr += sizeof(uint32_t);
            for (uint32_t r = 0; r < numRanges; ++r) {
                if (ptr + sizeof(D3D12_DESCRIPTOR_RANGE) > end) return E_INVALIDARG;
                D3D12_DESCRIPTOR_RANGE range = *reinterpret_cast<const D3D12_DESCRIPTOR_RANGE*>(ptr); ptr += sizeof(D3D12_DESCRIPTOR_RANGE);
                param.DescriptorTableRanges.push_back(range);
            }
        } else {
            // CBV, SRV, UAV
            if (ptr + sizeof(UINT) * 2 > end) return E_INVALIDARG;
            param.ShaderRegister = *reinterpret_cast<const UINT*>(ptr); ptr += sizeof(UINT);
            param.RegisterSpace = *reinterpret_cast<const UINT*>(ptr); ptr += sizeof(UINT);
        }
        m_parameters.push_back(param);
    }

    if (ptr + sizeof(uint32_t) > end) return E_INVALIDARG;
    uint32_t numSamplers = *reinterpret_cast<const uint32_t*>(ptr); ptr += sizeof(uint32_t);

    for (uint32_t i = 0; i < numSamplers; ++i) {
        if (ptr + sizeof(D3D12_STATIC_SAMPLER_DESC) > end) return E_INVALIDARG;
        D3D12_STATIC_SAMPLER_DESC sampler = *reinterpret_cast<const D3D12_STATIC_SAMPLER_DESC*>(ptr); ptr += sizeof(D3D12_STATIC_SAMPLER_DESC);
        m_staticSamplers.push_back(sampler);
        
#ifdef __OBJC__
        MTLSamplerDescriptor* mtlDesc = [[MTLSamplerDescriptor alloc] init];
        
        switch (sampler.Filter) {
            case D3D12_FILTER_MIN_MAG_MIP_POINT:
                mtlDesc.minFilter = MTLSamplerMinMagFilterNearest;
                mtlDesc.magFilter = MTLSamplerMinMagFilterNearest;
                mtlDesc.mipFilter = MTLSamplerMipFilterNearest;
                break;
            case D3D12_FILTER_MIN_MAG_MIP_LINEAR:
                mtlDesc.minFilter = MTLSamplerMinMagFilterLinear;
                mtlDesc.magFilter = MTLSamplerMinMagFilterLinear;
                mtlDesc.mipFilter = MTLSamplerMipFilterLinear;
                break;
            case D3D12_FILTER_ANISOTROPIC:
                mtlDesc.minFilter = MTLSamplerMinMagFilterLinear;
                mtlDesc.magFilter = MTLSamplerMinMagFilterLinear;
                mtlDesc.mipFilter = MTLSamplerMipFilterLinear;
                mtlDesc.maxAnisotropy = std::max<UINT>(1, sampler.MaxAnisotropy);
                break;
            default:
                mtlDesc.minFilter = MTLSamplerMinMagFilterLinear;
                mtlDesc.magFilter = MTLSamplerMinMagFilterLinear;
                mtlDesc.mipFilter = MTLSamplerMipFilterLinear;
                break;
        }
        
        id<MTLDevice> nativeDevice = (id<MTLDevice>)m_device->GetMetalDevice();
        id<MTLSamplerState> samplerState = [nativeDevice newSamplerStateWithDescriptor:mtlDesc];
        m_compiledSamplers.push_back(samplerState);
#endif
    }

    return S_OK;
}

// IUnknown Methods
HRESULT STDMETHODCALLTYPE MLRootSignature::QueryInterface(REFIID riid, void** ppvObject) {
    if (!ppvObject) return E_POINTER;
    if (riid == __uuidof(IUnknown) || riid == __uuidof(ID3D12Object) || riid == __uuidof(ID3D12DeviceChild) || riid == __uuidof(ID3D12RootSignature)) {
        *ppvObject = static_cast<ID3D12RootSignature*>(this);
        AddRef();
        return S_OK;
    }
    *ppvObject = nullptr;
    return E_NOINTERFACE;
}

ULONG STDMETHODCALLTYPE MLRootSignature::AddRef() {
    return ++m_refCount;
}

ULONG STDMETHODCALLTYPE MLRootSignature::Release() {
    ULONG count = --m_refCount;
    if (count == 0) {
        delete this;
    }
    return count;
}

// ID3D12Object Methods
ML_IMPL_PRIVATE_DATA(MLRootSignature)

HRESULT STDMETHODCALLTYPE MLRootSignature::SetName(LPCWSTR Name) {
    return S_OK;
}

HRESULT STDMETHODCALLTYPE MLRootSignature::GetDevice(REFIID riid, void** ppvDevice) {
    if (!ppvDevice) return E_POINTER;
    if (m_device) return m_device->QueryInterface(riid, ppvDevice);
    return E_NOINTERFACE;
}
