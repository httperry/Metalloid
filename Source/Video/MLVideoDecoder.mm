#include "Metalloid/Video/MLVideoDecoder.h"
#include <iostream>

MLVideoDecoder::MLVideoDecoder() {}

MLVideoDecoder::~MLVideoDecoder() {
#ifdef __OBJC__
    if (m_vtSession) {
        VTDecompressionSessionInvalidate(m_vtSession);
        CFRelease(m_vtSession);
        m_vtSession = nullptr;
    }
    if (m_formatDesc) {
        CFRelease(m_formatDesc);
        m_formatDesc = nullptr;
    }
#endif
}

HRESULT STDMETHODCALLTYPE MLVideoDecoder::QueryInterface(REFIID riid, void** ppvObject) {
    if (!ppvObject) return E_INVALIDARG;
    if (riid == __uuidof(ID3D12VideoDecoder) || riid == __uuidof(IUnknown) || riid == __uuidof(ID3D12Object) || riid == __uuidof(ID3D12DeviceChild)) {
        *ppvObject = static_cast<ID3D12VideoDecoder*>(this);
        AddRef();
        return S_OK;
    }
    return E_NOINTERFACE;
}

ULONG STDMETHODCALLTYPE MLVideoDecoder::AddRef() {
    return ++m_refCount;
}

ULONG STDMETHODCALLTYPE MLVideoDecoder::Release() {
    ULONG ref = --m_refCount;
    if (ref == 0) {
        delete this;
    }
    return ref;
}

ML_IMPL_PRIVATE_DATA(MLVideoDecoder)
HRESULT STDMETHODCALLTYPE MLVideoDecoder::SetName(LPCWSTR Name) { return S_OK; }
HRESULT STDMETHODCALLTYPE MLVideoDecoder::GetDevice(REFIID riid, void** ppvDevice) { return E_FAIL; }
#if defined(_MSC_VER) || !defined(_WIN32)
D3D12_VIDEO_DECODER_DESC STDMETHODCALLTYPE MLVideoDecoder::GetDesc() { return m_desc; }
#else
D3D12_VIDEO_DECODER_DESC* STDMETHODCALLTYPE MLVideoDecoder::GetDesc(D3D12_VIDEO_DECODER_DESC* RetVal) {
    if (RetVal) {
        *RetVal = m_desc;
    }
    return RetVal;
}
#endif

MLVideoDecoderHeap::MLVideoDecoderHeap(const D3D12_VIDEO_DECODER_HEAP_DESC& desc) : m_desc(desc) {
#ifdef __OBJC__
    // Create CVPixelBufferPool based on heap description
    CFMutableDictionaryRef poolAttributes = CFDictionaryCreateMutable(kCFAllocatorDefault, 1, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
    
    CFMutableDictionaryRef pixelBufferAttributes = CFDictionaryCreateMutable(kCFAllocatorDefault, 4, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
    
    SInt32 pixelFormat = kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange; // NV12
    CFNumberRef pixelFormatNumber = CFNumberCreate(kCFAllocatorDefault, kCFNumberSInt32Type, &pixelFormat);
    CFDictionarySetValue(pixelBufferAttributes, kCVPixelBufferPixelFormatTypeKey, pixelFormatNumber);
    CFRelease(pixelFormatNumber);

    SInt32 width = desc.DecodeWidth;
    CFNumberRef widthNumber = CFNumberCreate(kCFAllocatorDefault, kCFNumberSInt32Type, &width);
    CFDictionarySetValue(pixelBufferAttributes, kCVPixelBufferWidthKey, widthNumber);
    CFRelease(widthNumber);

    SInt32 height = desc.DecodeHeight;
    CFNumberRef heightNumber = CFNumberCreate(kCFAllocatorDefault, kCFNumberSInt32Type, &height);
    CFDictionarySetValue(pixelBufferAttributes, kCVPixelBufferHeightKey, heightNumber);
    CFRelease(heightNumber);

    CFDictionaryRef ioSurfaceProps = CFDictionaryCreate(kCFAllocatorDefault, nullptr, nullptr, 0, nullptr, nullptr);
    CFDictionarySetValue(pixelBufferAttributes, kCVPixelBufferIOSurfacePropertiesKey, ioSurfaceProps);
    CFRelease(ioSurfaceProps);

    CVReturn status = CVPixelBufferPoolCreate(kCFAllocatorDefault, poolAttributes, pixelBufferAttributes, &m_pixelBufferPool);
    if (status != kCVReturnSuccess) {
        std::cerr << "[Metalloid] CVPixelBufferPoolCreate failed: " << status << std::endl;
    }

    CFRelease(poolAttributes);
    CFRelease(pixelBufferAttributes);
#endif
}

MLVideoDecoderHeap::~MLVideoDecoderHeap() {
#ifdef __OBJC__
    if (m_pixelBufferPool) {
        CVPixelBufferPoolRelease(m_pixelBufferPool);
        m_pixelBufferPool = nullptr;
    }
#endif
}

HRESULT STDMETHODCALLTYPE MLVideoDecoderHeap::QueryInterface(REFIID riid, void** ppvObject) {
    if (!ppvObject) return E_INVALIDARG;
    if (riid == __uuidof(ID3D12VideoDecoderHeap) || riid == __uuidof(IUnknown) || riid == __uuidof(ID3D12Object) || riid == __uuidof(ID3D12DeviceChild)) {
        *ppvObject = static_cast<ID3D12VideoDecoderHeap*>(this);
        AddRef();
        return S_OK;
    }
    return E_NOINTERFACE;
}

ULONG STDMETHODCALLTYPE MLVideoDecoderHeap::AddRef() {
    return ++m_refCount;
}

ULONG STDMETHODCALLTYPE MLVideoDecoderHeap::Release() {
    ULONG ref = --m_refCount;
    if (ref == 0) {
        delete this;
    }
    return ref;
}

ML_IMPL_PRIVATE_DATA(MLVideoDecoderHeap)
HRESULT STDMETHODCALLTYPE MLVideoDecoderHeap::SetName(LPCWSTR Name) { return S_OK; }
HRESULT STDMETHODCALLTYPE MLVideoDecoderHeap::GetDevice(REFIID riid, void** ppvDevice) { return E_FAIL; }
#if defined(_MSC_VER) || !defined(_WIN32)
D3D12_VIDEO_DECODER_HEAP_DESC STDMETHODCALLTYPE MLVideoDecoderHeap::GetDesc() { return m_desc; }
#else
D3D12_VIDEO_DECODER_HEAP_DESC* STDMETHODCALLTYPE MLVideoDecoderHeap::GetDesc(D3D12_VIDEO_DECODER_HEAP_DESC* RetVal) {
    if (RetVal) {
        *RetVal = m_desc;
    }
    return RetVal;
}
#endif
