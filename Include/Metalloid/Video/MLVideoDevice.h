#pragma once

#ifdef __OBJC__
#import <VideoToolbox/VideoToolbox.h>
#import <CoreVideo/CoreVideo.h>
#endif

#include "d3d12_mac_common.h"
#include <atomic>

class MLDevice;

class MLVideoDevice : public ID3D12VideoDevice {
private:
    std::atomic<ULONG> m_refCount{1};
    MLDevice* m_device;

public:
    MLVideoDevice(MLDevice* device);
    virtual ~MLVideoDevice();

    // IUnknown
    virtual HRESULT STDMETHODCALLTYPE QueryInterface(REFIID riid, void** ppvObject) override;
    virtual ULONG STDMETHODCALLTYPE AddRef() override;
    virtual ULONG STDMETHODCALLTYPE Release() override;

    // ID3D12VideoDevice
    virtual HRESULT STDMETHODCALLTYPE CheckFeatureSupport(
        D3D12_FEATURE_VIDEO FeatureVideo,
        void* pFeatureSupportData,
        UINT FeatureSupportDataSize) override;

    virtual HRESULT STDMETHODCALLTYPE CreateVideoDecoder(
        const D3D12_VIDEO_DECODER_DESC* pDesc,
        REFIID riid,
        void** ppVideoDecoder) override;

    virtual HRESULT STDMETHODCALLTYPE CreateVideoDecoderHeap(
        const D3D12_VIDEO_DECODER_HEAP_DESC* pVideoDecoderHeapDesc,
        REFIID riid,
        void** ppVideoDecoderHeap) override;

    virtual HRESULT STDMETHODCALLTYPE CreateVideoProcessor(
        UINT NodeMask,
        const D3D12_VIDEO_PROCESS_OUTPUT_STREAM_DESC* pOutputStreamDesc,
        UINT NumInputStreamDescs,
        const D3D12_VIDEO_PROCESS_INPUT_STREAM_DESC* pInputStreamDescs,
        REFIID riid,
        void** ppVideoProcessor) override;
};
