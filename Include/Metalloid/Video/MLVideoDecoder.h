#pragma once
#include "Metalloid/Common/MLPrivateData.h"

#ifdef __OBJC__
#import <VideoToolbox/VideoToolbox.h>
#import <CoreVideo/CoreVideo.h>
#endif

#include "d3d12_mac_common.h"
#include <atomic>

class MLVideoDecoder : public ID3D12VideoDecoder {
    ML_DECL_PRIVATE_DATA()
private:
    std::atomic<ULONG> m_refCount{1};
    
#ifdef __OBJC__
    VTDecompressionSessionRef m_vtSession = nullptr;
    CMVideoFormatDescriptionRef m_formatDesc = nullptr;
#else
    void* m_vtSession = nullptr;
    void* m_formatDesc = nullptr;
#endif

    D3D12_VIDEO_DECODER_DESC m_desc{};

public:
    MLVideoDecoder();
    virtual ~MLVideoDecoder();

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
    // ID3D12VideoDecoder
#if defined(_MSC_VER) || !defined(_WIN32)
    virtual D3D12_VIDEO_DECODER_DESC STDMETHODCALLTYPE GetDesc() override;
#else
    virtual D3D12_VIDEO_DECODER_DESC* STDMETHODCALLTYPE GetDesc(D3D12_VIDEO_DECODER_DESC* RetVal) override;
#endif

    // Metalloid Internal
#ifdef __OBJC__
    void SetVTSession(VTDecompressionSessionRef session, CMVideoFormatDescriptionRef formatDesc) {
        m_vtSession = session;
        m_formatDesc = formatDesc;
    }
    VTDecompressionSessionRef GetVTSession() const { return m_vtSession; }
    CMVideoFormatDescriptionRef GetFormatDesc() const { return m_formatDesc; }
#endif
    void SetDesc(const D3D12_VIDEO_DECODER_DESC& desc) { m_desc = desc; }
};

class MLVideoDecoderHeap : public ID3D12VideoDecoderHeap {
    ML_DECL_PRIVATE_DATA()
private:
    std::atomic<ULONG> m_refCount{1};
    D3D12_VIDEO_DECODER_HEAP_DESC m_desc{};
#ifdef __OBJC__
    CVPixelBufferPoolRef m_pixelBufferPool = nullptr;
#endif

public:
    MLVideoDecoderHeap(const D3D12_VIDEO_DECODER_HEAP_DESC& desc);
    virtual ~MLVideoDecoderHeap();

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

    // ID3D12VideoDecoderHeap
#if defined(_MSC_VER) || !defined(_WIN32)
    virtual D3D12_VIDEO_DECODER_HEAP_DESC STDMETHODCALLTYPE GetDesc() override;
#else
    virtual D3D12_VIDEO_DECODER_HEAP_DESC* STDMETHODCALLTYPE GetDesc(D3D12_VIDEO_DECODER_HEAP_DESC* RetVal) override;
#endif

#ifdef __OBJC__
    CVPixelBufferPoolRef GetPixelBufferPool() const { return m_pixelBufferPool; }
#endif
};
