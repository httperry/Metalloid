#include "Metalloid/Video/MLVideoDevice.h"
#include "Metalloid/Device/MLDevice.h"
#include "Metalloid/Video/MLVideoDecoder.h"
#include <iostream>
#include <vector>

class MLVideoProcessor : public ID3D12VideoProcessor {
    ML_DECL_PRIVATE_DATA()
private:
    std::atomic<ULONG> m_refCount{1};
    UINT m_nodeMask;
    D3D12_VIDEO_PROCESS_OUTPUT_STREAM_DESC m_outputDesc;
    std::vector<D3D12_VIDEO_PROCESS_INPUT_STREAM_DESC> m_inputDescs;

public:
    MLVideoProcessor(UINT nodeMask, const D3D12_VIDEO_PROCESS_OUTPUT_STREAM_DESC* pOutputDesc, UINT NumInputStreamDescs, const D3D12_VIDEO_PROCESS_INPUT_STREAM_DESC* pInputStreamDescs) 
        : m_nodeMask(nodeMask), m_outputDesc(*pOutputDesc) 
    {
        for (UINT i = 0; i < NumInputStreamDescs; ++i) {
            m_inputDescs.push_back(pInputStreamDescs[i]);
        }
    }

    virtual ~MLVideoProcessor() {}

    // IUnknown
    virtual HRESULT STDMETHODCALLTYPE QueryInterface(REFIID riid, void** ppvObject) override {
        if (!ppvObject) return E_INVALIDARG;
        if (riid == __uuidof(ID3D12VideoProcessor) || riid == __uuidof(IUnknown) || riid == __uuidof(ID3D12Object) || riid == __uuidof(ID3D12DeviceChild) || riid == __uuidof(ID3D12Pageable)) {
            *ppvObject = static_cast<ID3D12VideoProcessor*>(this);
            AddRef();
            return S_OK;
        }
        return E_NOINTERFACE;
    }
    virtual ULONG STDMETHODCALLTYPE AddRef() override { return ++m_refCount; }
    virtual ULONG STDMETHODCALLTYPE Release() override {
        ULONG ref = --m_refCount;
        if (ref == 0) delete this;
        return ref;
    }

    // ID3D12Object
    virtual HRESULT STDMETHODCALLTYPE GetPrivateData(REFGUID guid, UINT* pDataSize, void* pData) override;
    virtual HRESULT STDMETHODCALLTYPE SetPrivateData(REFGUID guid, UINT DataSize, const void* pData) override;
    virtual HRESULT STDMETHODCALLTYPE SetPrivateDataInterface(REFGUID guid, const IUnknown* pData) override;
    virtual HRESULT STDMETHODCALLTYPE SetName(LPCWSTR Name) override { return S_OK; }

    // ID3D12DeviceChild
    virtual HRESULT STDMETHODCALLTYPE GetDevice(REFIID riid, void** ppvDevice) override { return E_FAIL; }

    // ID3D12VideoProcessor
    virtual UINT STDMETHODCALLTYPE GetNodeMask() override { return m_nodeMask; }
    virtual UINT STDMETHODCALLTYPE GetNumInputStreamDescs() override { return (UINT)m_inputDescs.size(); }
    virtual HRESULT STDMETHODCALLTYPE GetInputStreamDescs(UINT NumInputStreamDescs, D3D12_VIDEO_PROCESS_INPUT_STREAM_DESC* pInputStreamDescs) override {
        if (!pInputStreamDescs) return E_INVALIDARG;
        UINT count = std::min(NumInputStreamDescs, (UINT)m_inputDescs.size());
        for (UINT i = 0; i < count; ++i) {
            pInputStreamDescs[i] = m_inputDescs[i];
        }
        return S_OK;
    }

#if defined(_MSC_VER) || !defined(_WIN32)
    virtual D3D12_VIDEO_PROCESS_OUTPUT_STREAM_DESC STDMETHODCALLTYPE GetOutputStreamDesc() override { return m_outputDesc; }
#else
    virtual D3D12_VIDEO_PROCESS_OUTPUT_STREAM_DESC* STDMETHODCALLTYPE GetOutputStreamDesc(D3D12_VIDEO_PROCESS_OUTPUT_STREAM_DESC* RetVal) override {
        if (RetVal) *RetVal = m_outputDesc;
        return RetVal;
    }
#endif
};

ML_IMPL_PRIVATE_DATA(MLVideoProcessor)

MLVideoDevice::MLVideoDevice(MLDevice* device) : m_device(device) {
    if (m_device) {
        m_device->AddRef();
    }
}

MLVideoDevice::~MLVideoDevice() {
    if (m_device) {
        m_device->Release();
    }
}

HRESULT STDMETHODCALLTYPE MLVideoDevice::QueryInterface(REFIID riid, void** ppvObject) {
    if (!ppvObject) return E_INVALIDARG;
    if (riid == __uuidof(ID3D12VideoDevice) || riid == __uuidof(IUnknown)) {
        *ppvObject = static_cast<ID3D12VideoDevice*>(this);
        AddRef();
        return S_OK;
    }
    return E_NOINTERFACE;
}

ULONG STDMETHODCALLTYPE MLVideoDevice::AddRef() {
    return ++m_refCount;
}

ULONG STDMETHODCALLTYPE MLVideoDevice::Release() {
    ULONG ref = --m_refCount;
    if (ref == 0) {
        delete this;
    }
    return ref;
}

HRESULT STDMETHODCALLTYPE MLVideoDevice::CheckFeatureSupport(
    D3D12_FEATURE_VIDEO FeatureVideo,
    void* pFeatureSupportData,
    UINT FeatureSupportDataSize) {
    
    if (FeatureVideo == D3D12_FEATURE_VIDEO_DECODE_SUPPORT) {
        if (!pFeatureSupportData || FeatureSupportDataSize < sizeof(D3D12_FEATURE_DATA_VIDEO_DECODE_SUPPORT)) {
            return E_INVALIDARG;
        }
        
        auto* pData = static_cast<D3D12_FEATURE_DATA_VIDEO_DECODE_SUPPORT*>(pFeatureSupportData);
        const GUID& profile = pData->Configuration.DecodeProfile;
        
        bool supported = false;
        if (profile == D3D12_VIDEO_DECODE_PROFILE_H264 ||
            profile == D3D12_VIDEO_DECODE_PROFILE_H264_STEREO_PROGRESSIVE ||
            profile == D3D12_VIDEO_DECODE_PROFILE_H264_STEREO ||
            profile == D3D12_VIDEO_DECODE_PROFILE_H264_MULTIVIEW ||
            profile == D3D12_VIDEO_DECODE_PROFILE_HEVC_MAIN ||
            profile == D3D12_VIDEO_DECODE_PROFILE_HEVC_MAIN10 ||
            profile == D3D12_VIDEO_DECODE_PROFILE_HEVC_MONOCHROME ||
            profile == D3D12_VIDEO_DECODE_PROFILE_HEVC_MONOCHROME10 ||
            profile == D3D12_VIDEO_DECODE_PROFILE_HEVC_MAIN12 ||
            profile == D3D12_VIDEO_DECODE_PROFILE_HEVC_MAIN10_422 ||
            profile == D3D12_VIDEO_DECODE_PROFILE_HEVC_MAIN12_422 ||
            profile == D3D12_VIDEO_DECODE_PROFILE_HEVC_MAIN_444 ||
            profile == D3D12_VIDEO_DECODE_PROFILE_HEVC_MAIN10_EXT ||
            profile == D3D12_VIDEO_DECODE_PROFILE_HEVC_MAIN10_444 ||
            profile == D3D12_VIDEO_DECODE_PROFILE_HEVC_MAIN12_444 ||
            profile == D3D12_VIDEO_DECODE_PROFILE_HEVC_MAIN16 ||
            profile == D3D12_VIDEO_DECODE_PROFILE_VP9 ||
            profile == D3D12_VIDEO_DECODE_PROFILE_VP9_10BIT_PROFILE2) {
            supported = true;
        } else if (profile == D3D12_VIDEO_DECODE_PROFILE_AV1_PROFILE0 ||
                   profile == D3D12_VIDEO_DECODE_PROFILE_AV1_PROFILE1 ||
                   profile == D3D12_VIDEO_DECODE_PROFILE_AV1_PROFILE2 ||
                   profile == D3D12_VIDEO_DECODE_PROFILE_AV1_12BIT_PROFILE2 ||
                   profile == D3D12_VIDEO_DECODE_PROFILE_AV1_12BIT_PROFILE2_420) {
            MLAppleSiliconGen gen = MLAppleSiliconGen::Unknown;
            if (m_device) {
                gen = m_device->GetSiliconGeneration();
            }
            supported = (gen == MLAppleSiliconGen::M3 || gen == MLAppleSiliconGen::M4 || gen == MLAppleSiliconGen::M5);
        }
        
        pData->SupportFlags = supported ? D3D12_VIDEO_DECODE_SUPPORT_FLAG_SUPPORTED : D3D12_VIDEO_DECODE_SUPPORT_FLAG_NONE;
        pData->ConfigurationFlags = D3D12_VIDEO_DECODE_CONFIGURATION_FLAG_NONE;
        pData->DecodeTier = D3D12_VIDEO_DECODE_TIER_1;
        return S_OK;
    }
    
    if (FeatureVideo == D3D12_FEATURE_VIDEO_DECODE_PROFILE_COUNT) {
        if (!pFeatureSupportData || FeatureSupportDataSize < sizeof(D3D12_FEATURE_DATA_VIDEO_DECODE_PROFILE_COUNT)) {
            return E_INVALIDARG;
        }
        auto* pData = static_cast<D3D12_FEATURE_DATA_VIDEO_DECODE_PROFILE_COUNT*>(pFeatureSupportData);
        MLAppleSiliconGen gen = MLAppleSiliconGen::Unknown;
        if (m_device) {
            gen = m_device->GetSiliconGeneration();
        }
        bool av1Supported = (gen == MLAppleSiliconGen::M3 || gen == MLAppleSiliconGen::M4 || gen == MLAppleSiliconGen::M5);
        pData->ProfileCount = 18 + (av1Supported ? 5 : 0);
        return S_OK;
    }
    
    if (FeatureVideo == D3D12_FEATURE_VIDEO_DECODE_PROFILES) {
        if (!pFeatureSupportData || FeatureSupportDataSize < sizeof(D3D12_FEATURE_DATA_VIDEO_DECODE_PROFILES)) {
            return E_INVALIDARG;
        }
        auto* pData = static_cast<D3D12_FEATURE_DATA_VIDEO_DECODE_PROFILES*>(pFeatureSupportData);
        if (!pData->pProfiles) {
            return E_INVALIDARG;
        }
        
        std::vector<GUID> profiles = {
            D3D12_VIDEO_DECODE_PROFILE_H264,
            D3D12_VIDEO_DECODE_PROFILE_H264_STEREO_PROGRESSIVE,
            D3D12_VIDEO_DECODE_PROFILE_H264_STEREO,
            D3D12_VIDEO_DECODE_PROFILE_H264_MULTIVIEW,
            D3D12_VIDEO_DECODE_PROFILE_HEVC_MAIN,
            D3D12_VIDEO_DECODE_PROFILE_HEVC_MAIN10,
            D3D12_VIDEO_DECODE_PROFILE_HEVC_MONOCHROME,
            D3D12_VIDEO_DECODE_PROFILE_HEVC_MONOCHROME10,
            D3D12_VIDEO_DECODE_PROFILE_HEVC_MAIN12,
            D3D12_VIDEO_DECODE_PROFILE_HEVC_MAIN10_422,
            D3D12_VIDEO_DECODE_PROFILE_HEVC_MAIN12_422,
            D3D12_VIDEO_DECODE_PROFILE_HEVC_MAIN_444,
            D3D12_VIDEO_DECODE_PROFILE_HEVC_MAIN10_EXT,
            D3D12_VIDEO_DECODE_PROFILE_HEVC_MAIN10_444,
            D3D12_VIDEO_DECODE_PROFILE_HEVC_MAIN12_444,
            D3D12_VIDEO_DECODE_PROFILE_HEVC_MAIN16,
            D3D12_VIDEO_DECODE_PROFILE_VP9,
            D3D12_VIDEO_DECODE_PROFILE_VP9_10BIT_PROFILE2
        };
        
        MLAppleSiliconGen gen = MLAppleSiliconGen::Unknown;
        if (m_device) {
            gen = m_device->GetSiliconGeneration();
        }
        if (gen == MLAppleSiliconGen::M3 || gen == MLAppleSiliconGen::M4 || gen == MLAppleSiliconGen::M5) {
            profiles.push_back(D3D12_VIDEO_DECODE_PROFILE_AV1_PROFILE0);
            profiles.push_back(D3D12_VIDEO_DECODE_PROFILE_AV1_PROFILE1);
            profiles.push_back(D3D12_VIDEO_DECODE_PROFILE_AV1_PROFILE2);
            profiles.push_back(D3D12_VIDEO_DECODE_PROFILE_AV1_12BIT_PROFILE2);
            profiles.push_back(D3D12_VIDEO_DECODE_PROFILE_AV1_12BIT_PROFILE2_420);
        }
        
        UINT copyCount = std::min(pData->ProfileCount, (UINT)profiles.size());
        for (UINT i = 0; i < copyCount; ++i) {
            pData->pProfiles[i] = profiles[i];
        }
        return S_OK;
    }
    
    return S_OK;
}

HRESULT STDMETHODCALLTYPE MLVideoDevice::CreateVideoDecoder(
    const D3D12_VIDEO_DECODER_DESC* pDesc,
    REFIID riid,
    void** ppVideoDecoder) {
    
    if (!pDesc || !ppVideoDecoder) return E_INVALIDARG;

    // Check if configuration profile is AV1 and enforce silicon generation limits
    const GUID& profile = pDesc->Configuration.DecodeProfile;
    if (profile == D3D12_VIDEO_DECODE_PROFILE_AV1_PROFILE0 ||
        profile == D3D12_VIDEO_DECODE_PROFILE_AV1_PROFILE1 ||
        profile == D3D12_VIDEO_DECODE_PROFILE_AV1_PROFILE2 ||
        profile == D3D12_VIDEO_DECODE_PROFILE_AV1_12BIT_PROFILE2 ||
        profile == D3D12_VIDEO_DECODE_PROFILE_AV1_12BIT_PROFILE2_420) {
        
        MLAppleSiliconGen gen = MLAppleSiliconGen::Unknown;
        if (m_device) {
            gen = m_device->GetSiliconGeneration();
        }
        if (gen == MLAppleSiliconGen::M1 || gen == MLAppleSiliconGen::M2 || gen == MLAppleSiliconGen::Unknown) {
            std::cerr << "[Metalloid] Cannot create video decoder: AV1 decoding is not supported on this Apple Silicon generation." << std::endl;
            return E_INVALIDARG;
        }
    }

    MLVideoDecoder* decoder = new MLVideoDecoder();
    decoder->SetDesc(*pDesc);

    HRESULT hr = decoder->QueryInterface(riid, ppVideoDecoder);
    decoder->Release();
    return hr;
}

HRESULT STDMETHODCALLTYPE MLVideoDevice::CreateVideoDecoderHeap(
    const D3D12_VIDEO_DECODER_HEAP_DESC* pVideoDecoderHeapDesc,
    REFIID riid,
    void** ppVideoDecoderHeap) {
    if (!pVideoDecoderHeapDesc || !ppVideoDecoderHeap) return E_INVALIDARG;

    // Check if configuration profile is AV1 and enforce silicon generation limits
    const GUID& profile = pVideoDecoderHeapDesc->Configuration.DecodeProfile;
    if (profile == D3D12_VIDEO_DECODE_PROFILE_AV1_PROFILE0 ||
        profile == D3D12_VIDEO_DECODE_PROFILE_AV1_PROFILE1 ||
        profile == D3D12_VIDEO_DECODE_PROFILE_AV1_PROFILE2 ||
        profile == D3D12_VIDEO_DECODE_PROFILE_AV1_12BIT_PROFILE2 ||
        profile == D3D12_VIDEO_DECODE_PROFILE_AV1_12BIT_PROFILE2_420) {
        
        MLAppleSiliconGen gen = MLAppleSiliconGen::Unknown;
        if (m_device) {
            gen = m_device->GetSiliconGeneration();
        }
        if (gen == MLAppleSiliconGen::M1 || gen == MLAppleSiliconGen::M2 || gen == MLAppleSiliconGen::Unknown) {
            std::cerr << "[Metalloid] Cannot create video decoder heap: AV1 decoding is not supported on this Apple Silicon generation." << std::endl;
            return E_INVALIDARG;
        }
    }

    MLVideoDecoderHeap* heap = new MLVideoDecoderHeap(*pVideoDecoderHeapDesc);
    HRESULT hr = heap->QueryInterface(riid, ppVideoDecoderHeap);
    heap->Release();
    return hr;
}

HRESULT STDMETHODCALLTYPE MLVideoDevice::CreateVideoProcessor(
    UINT NodeMask,
    const D3D12_VIDEO_PROCESS_OUTPUT_STREAM_DESC* pOutputStreamDesc,
    UINT NumInputStreamDescs,
    const D3D12_VIDEO_PROCESS_INPUT_STREAM_DESC* pInputStreamDescs,
    REFIID riid,
    void** ppVideoProcessor) {
    if (!pOutputStreamDesc || !ppVideoProcessor) return E_INVALIDARG;
    
    MLVideoProcessor* processor = new MLVideoProcessor(NodeMask, pOutputStreamDesc, NumInputStreamDescs, pInputStreamDescs);
    HRESULT hr = processor->QueryInterface(riid, ppVideoProcessor);
    processor->Release();
    return hr;
}
