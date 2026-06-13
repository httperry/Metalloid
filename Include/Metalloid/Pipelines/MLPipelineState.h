#pragma once
#include "Metalloid/Common/MLPrivateData.h"

#ifdef __OBJC__
#import <Metal/Metal.h>
typedef id<MTLRenderPipelineState> MetalRenderPipelineType;
typedef id<MTLComputePipelineState> MetalComputePipelineType;
#else
typedef void* MetalRenderPipelineType;
typedef void* MetalComputePipelineType;
#endif

#include "d3d12_mac_common.h"
#include <atomic>

class MLPipelineState : public ID3D12PipelineState {
    ML_DECL_PRIVATE_DATA()
private:
    std::atomic<ULONG> m_refCount{1};
    ID3D12Device* m_parentDevice;
    MetalRenderPipelineType m_metalRenderPipeline{nullptr};
    MetalComputePipelineType m_metalComputePipeline{nullptr};
    bool m_isCompute{false};
    bool m_isMesh{false};
    UINT m_meshThreads[3]{1, 1, 1};
    UINT m_ampThreads[3]{1, 1, 1};
    void* m_binaryArchive{nullptr};

public:
    MLPipelineState(ID3D12Device* parentDevice, MetalRenderPipelineType renderPipeline);
    MLPipelineState(ID3D12Device* parentDevice, MetalComputePipelineType computePipeline);
    virtual ~MLPipelineState();

    MetalRenderPipelineType GetRenderPipeline() const { return m_metalRenderPipeline; }
    MetalComputePipelineType GetComputePipeline() const { return m_metalComputePipeline; }
    void SetMetalRenderPipelineState(MetalRenderPipelineType pipelineState) { m_metalRenderPipeline = pipelineState; }
    void SetMetalComputePipelineState(MetalComputePipelineType pipelineState) { m_metalComputePipeline = pipelineState; }
    bool IsCompute() const { return m_isCompute; }
    bool IsMesh() const { return m_isMesh; }
    void GetMeshThreads(UINT& x, UINT& y, UINT& z) const { x = m_meshThreads[0]; y = m_meshThreads[1]; z = m_meshThreads[2]; }
    void GetAmpThreads(UINT& x, UINT& y, UINT& z) const { x = m_ampThreads[0]; y = m_ampThreads[1]; z = m_ampThreads[2]; }
    void SetMeshThreads(UINT x, UINT y, UINT z) { m_isMesh = true; m_meshThreads[0] = x; m_meshThreads[1] = y; m_meshThreads[2] = z; }
    void SetAmpThreads(UINT x, UINT y, UINT z) { m_ampThreads[0] = x; m_ampThreads[1] = y; m_ampThreads[2] = z; }
    void SetBinaryArchive(void* archive) { m_binaryArchive = archive; }

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

    // ID3D12Pageable
    // (We stub these for now, not strictly needed for basic rendering)

    // ID3D12PipelineState
    virtual HRESULT STDMETHODCALLTYPE GetCachedBlob(ID3DBlob** ppBlob) override;
};
