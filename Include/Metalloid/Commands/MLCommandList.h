#pragma once
#include <Metalloid/Common/MLPrivateData.h>

#ifdef __OBJC__
#undef interface
#import <Metal/Metal.h>
typedef id<MTLCommandBuffer> MetalCommandBufferType;
typedef id<MTLRenderCommandEncoder> MetalRenderCommandEncoderType;
typedef id<MTLComputeCommandEncoder> MetalComputeCommandEncoderType;
#else
typedef void* MetalCommandBufferType;
typedef void* MetalRenderCommandEncoderType;
typedef void* MetalComputeCommandEncoderType;
#endif

#include "d3d12_mac_common.h"
#include "Metalloid/Resources/MLResource.h"
#include <vector>

class MLDevice;

#ifndef ID3D12GraphicsCommandList14_DEFINED
#define ID3D12GraphicsCommandList14_DEFINED
typedef ID3D12GraphicsCommandList10 ID3D12GraphicsCommandList14;
#endif

class MLCommandList : public ID3D12GraphicsCommandList14 {
    ML_DECL_PRIVATE_DATA()
private:
    std::atomic<ULONG> m_refCount{1};
    MLDevice* m_device;
    D3D12_COMMAND_LIST_TYPE m_type;
    
    MetalCommandBufferType m_activeCommandBuffer;
    MetalRenderCommandEncoderType m_activeRenderEncoder;
    MetalComputeCommandEncoderType m_activeComputeEncoder;
    
    // Simple state tracking
    MLResource* m_activeRenderTargets[8];
    UINT m_numActiveRenderTargets;
    MLResource* m_activeDepthStencil;
    
    // Pipeline tracking for Milestone 2
    class MLPipelineState* m_currentPSO;
    class MLPipelineState* m_boundPSO; // Tracks what is currently set on the Metal encoder

    // Pipeline tracking for Milestone 2
    ID3D12PipelineState* m_activePipelineState;

    // Buffer tracking for Milestone 4.7
    struct VertexBufferBinding {
        MLResource* resource;
        UINT64 offset;
        UINT stride;
        UINT size;
    };
    VertexBufferBinding m_vertexBuffers[32];
    
    struct IndexBufferBinding {
        MLResource* resource;
        UINT64 offset;
        UINT size;
        DXGI_FORMAT format;
    };
    IndexBufferBinding m_indexBuffer;
    
    // Root Signature state tracking
    ID3D12RootSignature* m_graphicsRootSignature;
    ID3D12RootSignature* m_computeRootSignature;
    
    // Pending State Cache for Root Arguments
    struct RootArgument {
        enum Type { None, DescriptorTable, Constants, CBV, SRV, UAV } type = None;
        D3D12_GPU_DESCRIPTOR_HANDLE tableBase = {0};
        D3D12_GPU_VIRTUAL_ADDRESS viewLocation = 0;
        std::vector<UINT32> constants;
        UINT constantsDestOffset = 0;
    };
    RootArgument m_graphicsRootArguments[64];
    RootArgument m_computeRootArguments[64];
    
    void FlushGraphicsRootArguments();
    void FlushComputeRootArguments();
    
    // Rasterizer state tracking
    D3D12_PRIMITIVE_TOPOLOGY m_primitiveTopology;
    D3D12_VIEWPORT m_viewports[16];
    UINT m_numViewports;
    D3D12_RECT m_scissorRects[16];
    UINT m_numScissorRects;
    FLOAT m_blendFactor[4];
    UINT m_stencilRef;

    // Resource tracking for implicit decay 3
    class MLStateObject* m_currentDXRStateObject;
    // Work Graph State
    class MLStateObject* m_activeWorkGraphStateObject = nullptr;
    D3D12_GPU_VIRTUAL_ADDRESS_RANGE m_activeWorkGraphBackingMemory = {0};


    // Track accessed resources for implicit state decay
    std::vector<MLResource*> m_accessedResources;

    // Hardened Barrier Cascade Tracking
    struct PatchEntry {
        MLResource* resource;
        uint32_t subresourceIndex;
        D3D12_BARRIER_LAYOUT* oldLayoutPtr;
    };
    std::vector<PatchEntry> m_patchTable;


    std::unordered_map<MLResource*, HierarchicalResourceState> m_localStates;

public:
    MLCommandList(MLDevice* device, D3D12_COMMAND_LIST_TYPE type);
    virtual ~MLCommandList();

    const std::vector<MLResource*>& GetAccessedResources() const { return m_accessedResources; }
    void TrackResourceAccess(MLResource* resource) {
        if (resource) {
            m_accessedResources.push_back(resource);
        }
    }
    
    void MarkResourceWritten(MLResource* resource) {
        if (resource) {
            m_localStates[resource].uniform_state.ever_written = true;
        }
    }

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

    // ID3D12CommandList
    virtual D3D12_COMMAND_LIST_TYPE STDMETHODCALLTYPE GetType() override;

    // ID3D12GraphicsCommandList
    virtual HRESULT STDMETHODCALLTYPE Close() override;
    
    virtual HRESULT STDMETHODCALLTYPE Reset(
        ID3D12CommandAllocator* pAllocator,
        ID3D12PipelineState* pInitialState) override;
        
    virtual void STDMETHODCALLTYPE ClearState(
        ID3D12PipelineState* pPipelineState) override;
        
    virtual void STDMETHODCALLTYPE DrawInstanced(
        UINT VertexCountPerInstance,
        UINT InstanceCount,
        UINT StartVertexLocation,
        UINT StartInstanceLocation) override;
        
    virtual void STDMETHODCALLTYPE DrawIndexedInstanced(
        UINT IndexCountPerInstance,
        UINT InstanceCount,
        UINT StartIndexLocation,
        INT BaseVertexLocation,
        UINT StartInstanceLocation) override;
        
    virtual void STDMETHODCALLTYPE Dispatch(
        UINT ThreadGroupCountX,
        UINT ThreadGroupCountY,
        UINT ThreadGroupCountZ) override;
        
    virtual void STDMETHODCALLTYPE CopyBufferRegion(
        ID3D12Resource* pDstBuffer,
        UINT64 DstOffset,
        ID3D12Resource* pSrcBuffer,
        UINT64 SrcOffset,
        UINT64 NumBytes) override;
        
    virtual void STDMETHODCALLTYPE CopyTextureRegion(
        const D3D12_TEXTURE_COPY_LOCATION* pDst,
        UINT DstX,
        UINT DstY,
        UINT DstZ,
        const D3D12_TEXTURE_COPY_LOCATION* pSrc,
        const D3D12_BOX* pSrcBox) override;
        
    virtual void STDMETHODCALLTYPE CopyResource(
        ID3D12Resource* pDstResource,
        ID3D12Resource* pSrcResource) override;
        
    virtual void STDMETHODCALLTYPE CopyTiles(
        ID3D12Resource* pTiledResource,
        const D3D12_TILED_RESOURCE_COORDINATE* pTileRegionStartCoordinate,
        const D3D12_TILE_REGION_SIZE* pTileRegionSize,
        ID3D12Resource* pBuffer,
        UINT64 BufferOffset,
        D3D12_TILE_COPY_FLAGS Flags) override;
        
    virtual void STDMETHODCALLTYPE ResolveSubresource(
        ID3D12Resource* pDstResource,
        UINT DstSubresource,
        ID3D12Resource* pSrcResource,
        UINT SrcSubresource,
        DXGI_FORMAT Format) override;
        
    virtual void STDMETHODCALLTYPE IASetPrimitiveTopology(
        D3D12_PRIMITIVE_TOPOLOGY PrimitiveTopology) override;
        
    virtual void STDMETHODCALLTYPE RSSetViewports(
        UINT NumViewports,
        const D3D12_VIEWPORT* pViewports) override;
        
    virtual void STDMETHODCALLTYPE RSSetScissorRects(
        UINT NumRects,
        const D3D12_RECT* pRects) override;
        
    virtual void STDMETHODCALLTYPE OMSetBlendFactor(
        const FLOAT BlendFactor[4]) override;
        
    virtual void STDMETHODCALLTYPE OMSetStencilRef(
        UINT StencilRef) override;
        
    virtual void STDMETHODCALLTYPE SetPipelineState(
        ID3D12PipelineState* pPipelineState) override;
        
    virtual void STDMETHODCALLTYPE ResourceBarrier(
        UINT NumBarriers,
        const D3D12_RESOURCE_BARRIER* pBarriers) override;
        
    virtual void STDMETHODCALLTYPE ExecuteBundle(
        ID3D12GraphicsCommandList* pCommandList) override;
        
    virtual void STDMETHODCALLTYPE SetDescriptorHeaps(
        UINT NumDescriptorHeaps,
        ID3D12DescriptorHeap* const* ppDescriptorHeaps) override;
        
    virtual void STDMETHODCALLTYPE SetComputeRootSignature(
        ID3D12RootSignature* pRootSignature) override;
        
    virtual void STDMETHODCALLTYPE SetGraphicsRootSignature(
        ID3D12RootSignature* pRootSignature) override;
        
    virtual void STDMETHODCALLTYPE SetComputeRootDescriptorTable(
        UINT RootParameterIndex,
        D3D12_GPU_DESCRIPTOR_HANDLE BaseDescriptor) override;
        
    virtual void STDMETHODCALLTYPE SetGraphicsRootDescriptorTable(
        UINT RootParameterIndex,
        D3D12_GPU_DESCRIPTOR_HANDLE BaseDescriptor) override;
        
    virtual void STDMETHODCALLTYPE SetComputeRoot32BitConstant(
        UINT RootParameterIndex,
        UINT SrcData,
        UINT DestOffsetIn32BitWords) override;
        
    virtual void STDMETHODCALLTYPE SetGraphicsRoot32BitConstant(
        UINT RootParameterIndex,
        UINT SrcData,
        UINT DestOffsetIn32BitWords) override;
        
    virtual void STDMETHODCALLTYPE SetComputeRoot32BitConstants(
        UINT RootParameterIndex,
        UINT Num32BitValuesToSet,
        const void* pSrcData,
        UINT DestOffsetIn32BitWords) override;
        
    virtual void STDMETHODCALLTYPE SetGraphicsRoot32BitConstants(
        UINT RootParameterIndex,
        UINT Num32BitValuesToSet,
        const void* pSrcData,
        UINT DestOffsetIn32BitWords) override;
        
    virtual void STDMETHODCALLTYPE SetComputeRootConstantBufferView(
        UINT RootParameterIndex,
        D3D12_GPU_VIRTUAL_ADDRESS BufferLocation) override;
        
    virtual void STDMETHODCALLTYPE SetGraphicsRootConstantBufferView(
        UINT RootParameterIndex,
        D3D12_GPU_VIRTUAL_ADDRESS BufferLocation) override;
        
    virtual void STDMETHODCALLTYPE SetComputeRootShaderResourceView(
        UINT RootParameterIndex,
        D3D12_GPU_VIRTUAL_ADDRESS BufferLocation) override;
        
    virtual void STDMETHODCALLTYPE SetGraphicsRootShaderResourceView(
        UINT RootParameterIndex,
        D3D12_GPU_VIRTUAL_ADDRESS BufferLocation) override;
        
    virtual void STDMETHODCALLTYPE SetComputeRootUnorderedAccessView(
        UINT RootParameterIndex,
        D3D12_GPU_VIRTUAL_ADDRESS BufferLocation) override;
        
    virtual void STDMETHODCALLTYPE SetGraphicsRootUnorderedAccessView(
        UINT RootParameterIndex,
        D3D12_GPU_VIRTUAL_ADDRESS BufferLocation) override;
        
    virtual void STDMETHODCALLTYPE IASetIndexBuffer(
        const D3D12_INDEX_BUFFER_VIEW* pView) override;
        
    virtual void STDMETHODCALLTYPE IASetVertexBuffers(
        UINT StartSlot,
        UINT NumViews,
        const D3D12_VERTEX_BUFFER_VIEW* pViews) override;
        
    virtual void STDMETHODCALLTYPE SOSetTargets(
        UINT StartSlot,
        UINT NumViews,
        const D3D12_STREAM_OUTPUT_BUFFER_VIEW* pViews) override;
        
    virtual void STDMETHODCALLTYPE OMSetRenderTargets(
        UINT NumRenderTargetDescriptors,
        const D3D12_CPU_DESCRIPTOR_HANDLE* pRenderTargetDescriptors,
        win_BOOL RTsSingleHandleToDescriptorRange,
        const D3D12_CPU_DESCRIPTOR_HANDLE* pDepthStencilDescriptor) override;
        
    virtual void STDMETHODCALLTYPE ClearRenderTargetView(
        D3D12_CPU_DESCRIPTOR_HANDLE RenderTargetView,
        const FLOAT ColorRGBA[4],
        UINT NumRects,
        const D3D12_RECT* pRects) override;
        
    virtual void STDMETHODCALLTYPE ClearDepthStencilView(
        D3D12_CPU_DESCRIPTOR_HANDLE DepthStencilView,
        D3D12_CLEAR_FLAGS ClearFlags,
        FLOAT Depth,
        UINT8 Stencil,
        UINT NumRects,
        const D3D12_RECT* pRects) override;

    virtual void STDMETHODCALLTYPE ClearUnorderedAccessViewUint(
        D3D12_GPU_DESCRIPTOR_HANDLE ViewGPUHandleInCurrentHeap,
        D3D12_CPU_DESCRIPTOR_HANDLE ViewCPUHandle,
        ID3D12Resource* pResource,
        const UINT Values[4],
        UINT NumRects,
        const D3D12_RECT* pRects) override;

    virtual void STDMETHODCALLTYPE ClearUnorderedAccessViewFloat(
        D3D12_GPU_DESCRIPTOR_HANDLE ViewGPUHandleInCurrentHeap,
        D3D12_CPU_DESCRIPTOR_HANDLE ViewCPUHandle,
        ID3D12Resource* pResource,
        const FLOAT Values[4],
        UINT NumRects,
        const D3D12_RECT* pRects) override;
        
    virtual void STDMETHODCALLTYPE DiscardResource(
        ID3D12Resource* pResource,
        const D3D12_DISCARD_REGION* pRegion) override;
        
    virtual void STDMETHODCALLTYPE BeginQuery(
        ID3D12QueryHeap* pQueryHeap,
        D3D12_QUERY_TYPE Type,
        UINT Index) override;
        
    virtual void STDMETHODCALLTYPE EndQuery(
        ID3D12QueryHeap* pQueryHeap,
        D3D12_QUERY_TYPE Type,
        UINT Index) override;
        
    virtual void STDMETHODCALLTYPE ResolveQueryData(
        ID3D12QueryHeap* pQueryHeap,
        D3D12_QUERY_TYPE Type,
        UINT StartIndex,
        UINT NumQueries,
        ID3D12Resource* pDestinationBuffer,
        UINT64 AlignedDestinationBufferOffset) override;
        
    virtual void STDMETHODCALLTYPE SetPredication(
        ID3D12Resource* pBuffer,
        UINT64 AlignedBufferOffset,
        D3D12_PREDICATION_OP Op) override;
        
    virtual void STDMETHODCALLTYPE SetMarker(
        UINT Metadata,
        const void* pData,
        UINT Size) override;
        
    virtual void STDMETHODCALLTYPE BeginEvent(
        UINT Metadata,
        const void* pData,
        UINT Size) override;
        
    virtual void STDMETHODCALLTYPE EndEvent() override;
    
    virtual void STDMETHODCALLTYPE ExecuteIndirect(
        ID3D12CommandSignature* pCommandSignature,
        UINT MaxCommandCount,
        ID3D12Resource* pArgumentBuffer,
        UINT64 ArgumentBufferOffset,
        ID3D12Resource* pCountBuffer,
        UINT64 CountBufferOffset) override;
        
    // Helpers
    MetalCommandBufferType GetMetalCommandBuffer() const { return m_activeCommandBuffer; }
    void SetMetalCommandBuffer(MetalCommandBufferType buf) { m_activeCommandBuffer = buf; }
    std::vector<PatchEntry>& GetPatchTable() { return m_patchTable; }
    std::unordered_map<MLResource*, HierarchicalResourceState>& GetLocalStates() { return m_localStates; }

    // ID3D12GraphicsCommandList1
    virtual void STDMETHODCALLTYPE AtomicCopyBufferUINT(ID3D12Resource* pDstBuffer, UINT64 DstOffset, ID3D12Resource* pSrcBuffer, UINT64 SrcOffset, UINT Dependencies, ID3D12Resource* const* ppDependentResources, const D3D12_SUBRESOURCE_RANGE_UINT64* pDependentSubresourceRanges) override;
    virtual void STDMETHODCALLTYPE AtomicCopyBufferUINT64(ID3D12Resource* pDstBuffer, UINT64 DstOffset, ID3D12Resource* pSrcBuffer, UINT64 SrcOffset, UINT Dependencies, ID3D12Resource* const* ppDependentResources, const D3D12_SUBRESOURCE_RANGE_UINT64* pDependentSubresourceRanges) override;
    virtual void STDMETHODCALLTYPE OMSetDepthBounds(FLOAT Min, FLOAT Max) override;
    virtual void STDMETHODCALLTYPE SetSamplePositions(UINT NumSamplesPerPixel, UINT NumPixels, D3D12_SAMPLE_POSITION* pSamplePositions) override;
    virtual void STDMETHODCALLTYPE ResolveSubresourceRegion(ID3D12Resource* pDstResource, UINT DstSubresource, UINT DstX, UINT DstY, ID3D12Resource* pSrcResource, UINT SrcSubresource, D3D12_RECT* pSrcRect, DXGI_FORMAT Format, D3D12_RESOLVE_MODE ResolveMode) override;
    virtual void STDMETHODCALLTYPE SetViewInstanceMask(UINT Mask) override;

    // ID3D12GraphicsCommandList2
    virtual void STDMETHODCALLTYPE WriteBufferImmediate(UINT Count, const D3D12_WRITEBUFFERIMMEDIATE_PARAMETER* pParams, const D3D12_WRITEBUFFERIMMEDIATE_MODE* pModes) override;

    // ID3D12GraphicsCommandList3
    virtual void STDMETHODCALLTYPE SetProtectedResourceSession(ID3D12ProtectedResourceSession* pProtectedResourceSession) override;

    // ID3D12GraphicsCommandList4
    virtual void STDMETHODCALLTYPE BeginRenderPass(UINT NumRenderTargets, const D3D12_RENDER_PASS_RENDER_TARGET_DESC* pRenderTargets, const D3D12_RENDER_PASS_DEPTH_STENCIL_DESC* pDepthStencil, D3D12_RENDER_PASS_FLAGS Flags) override;
    virtual void STDMETHODCALLTYPE EndRenderPass(void) override;
    virtual void STDMETHODCALLTYPE InitializeMetaCommand(ID3D12MetaCommand* pMetaCommand, const void* pInitializationParametersData, SIZE_T InitializationParametersDataSizeInBytes) override;
    virtual void STDMETHODCALLTYPE ExecuteMetaCommand(ID3D12MetaCommand* pMetaCommand, const void* pExecutionParametersData, SIZE_T ExecutionParametersDataSizeInBytes) override;
    virtual void STDMETHODCALLTYPE BuildRaytracingAccelerationStructure(const D3D12_BUILD_RAYTRACING_ACCELERATION_STRUCTURE_DESC* pDesc, UINT NumPostbuildInfoDescs, const D3D12_RAYTRACING_ACCELERATION_STRUCTURE_POSTBUILD_INFO_DESC* pPostbuildInfoDescs) override;
    virtual void STDMETHODCALLTYPE EmitRaytracingAccelerationStructurePostbuildInfo(const D3D12_RAYTRACING_ACCELERATION_STRUCTURE_POSTBUILD_INFO_DESC* pDesc, UINT NumSourceAccelerationStructures, const D3D12_GPU_VIRTUAL_ADDRESS* pSourceAccelerationStructureData) override;
    virtual void STDMETHODCALLTYPE CopyRaytracingAccelerationStructure(D3D12_GPU_VIRTUAL_ADDRESS DestAccelerationStructureData, D3D12_GPU_VIRTUAL_ADDRESS SourceAccelerationStructureData, D3D12_RAYTRACING_ACCELERATION_STRUCTURE_COPY_MODE Mode) override;
    virtual void STDMETHODCALLTYPE SetPipelineState1(ID3D12StateObject* pStateObject) override;
    virtual void STDMETHODCALLTYPE DispatchRays(const D3D12_DISPATCH_RAYS_DESC* pDesc) override;

    // ID3D12GraphicsCommandList5
    virtual void STDMETHODCALLTYPE RSSetShadingRate(D3D12_SHADING_RATE baseShadingRate, const D3D12_SHADING_RATE_COMBINER* combiners) override;
    virtual void STDMETHODCALLTYPE RSSetShadingRateImage(ID3D12Resource* shadingRateImage) override;

    // ID3D12GraphicsCommandList6
    virtual void STDMETHODCALLTYPE DispatchMesh(UINT ThreadGroupCountX, UINT ThreadGroupCountY, UINT ThreadGroupCountZ) override;

    // ID3D12GraphicsCommandList7
    virtual void STDMETHODCALLTYPE Barrier(UINT32 NumBarrierGroups, const D3D12_BARRIER_GROUP* pBarrierGroups) override;

    // ID3D12GraphicsCommandList8 (No new methods not already covered)

    // ID3D12GraphicsCommandList9
    virtual void STDMETHODCALLTYPE OMSetFrontAndBackStencilRef(UINT FrontStencilRef, UINT BackStencilRef) override;
    virtual void STDMETHODCALLTYPE RSSetDepthBias(FLOAT DepthBias, FLOAT DepthBiasClamp, FLOAT SlopeScaledDepthBias) override;
    virtual void STDMETHODCALLTYPE IASetIndexBufferStripCutValue(D3D12_INDEX_BUFFER_STRIP_CUT_VALUE IBStripCutValue) override;

    // ID3D12GraphicsCommandList10
    virtual void STDMETHODCALLTYPE SetProgram(D3D12_SET_PROGRAM_DESC const* pDesc) override;
    virtual void STDMETHODCALLTYPE DispatchGraph(const D3D12_DISPATCH_GRAPH_DESC* pDesc) override;
};
