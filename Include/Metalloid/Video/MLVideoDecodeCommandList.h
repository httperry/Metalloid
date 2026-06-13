#pragma once
#include "Metalloid/Common/MLPrivateData.h"

#ifdef __OBJC__
#import <Metal/Metal.h>
#import <VideoToolbox/VideoToolbox.h>
#import <CoreVideo/CoreVideo.h>
#endif

#include "d3d12_mac_common.h"
#include <atomic>

class MLDevice;

class MLVideoDecodeCommandList : public ID3D12VideoDecodeCommandList3 {
    ML_DECL_PRIVATE_DATA()
private:
    std::atomic<ULONG> m_refCount{1};
    MLDevice* m_device;
    D3D12_COMMAND_LIST_TYPE m_type;
    
#ifdef __OBJC__
    id<MTLCommandBuffer> m_activeCommandBuffer;
#else
    void* m_activeCommandBuffer;
#endif

public:
    MLVideoDecodeCommandList(MLDevice* device);
    virtual ~MLVideoDecodeCommandList();

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

    // ID3D12VideoDecodeCommandList
    virtual HRESULT STDMETHODCALLTYPE Close() override;
    virtual HRESULT STDMETHODCALLTYPE Reset(ID3D12CommandAllocator* pAllocator) override;
    virtual void STDMETHODCALLTYPE ClearState() override;
    virtual void STDMETHODCALLTYPE ResourceBarrier(
        UINT NumBarriers,
        const D3D12_RESOURCE_BARRIER* pBarriers) override;

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
        D3D12_PREDICATION_OP Operation) override;

    virtual void STDMETHODCALLTYPE SetMarker(
        UINT Metadata,
        const void* pData,
        UINT Size) override;

    virtual void STDMETHODCALLTYPE BeginEvent(
        UINT Metadata,
        const void* pData,
        UINT Size) override;

    virtual void STDMETHODCALLTYPE EndEvent() override;

    virtual void STDMETHODCALLTYPE DecodeFrame(
        ID3D12VideoDecoder* pDecoder,
        const D3D12_VIDEO_DECODE_OUTPUT_STREAM_ARGUMENTS* pOutputArguments,
        const D3D12_VIDEO_DECODE_INPUT_STREAM_ARGUMENTS* pInputArguments) override;

    virtual void STDMETHODCALLTYPE WriteBufferImmediate(
        UINT Count,
        const D3D12_WRITEBUFFERIMMEDIATE_PARAMETER* pParams,
        const D3D12_WRITEBUFFERIMMEDIATE_MODE* pModes) override;

    // ID3D12VideoDecodeCommandList1
    virtual void STDMETHODCALLTYPE DecodeFrame1( 
        ID3D12VideoDecoder *pDecoder,
        const D3D12_VIDEO_DECODE_OUTPUT_STREAM_ARGUMENTS1 *pOutputArguments,
        const D3D12_VIDEO_DECODE_INPUT_STREAM_ARGUMENTS *pInputArguments) override;

    // ID3D12VideoDecodeCommandList2
    virtual void STDMETHODCALLTYPE SetProtectedResourceSession( 
        ID3D12ProtectedResourceSession *pProtectedResourceSession) override;
    virtual void STDMETHODCALLTYPE InitializeExtensionCommand( 
        ID3D12VideoExtensionCommand *pExtensionCommand,
        const void *pInitializationParameters,
        SIZE_T InitializationParametersSizeInBytes) override;
    virtual void STDMETHODCALLTYPE ExecuteExtensionCommand( 
        ID3D12VideoExtensionCommand *pExtensionCommand,
        const void *pExecutionParameters,
        SIZE_T ExecutionParametersSizeInBytes) override;

    // ID3D12VideoDecodeCommandList3
    virtual void STDMETHODCALLTYPE Barrier( 
        UINT32 NumBarrierGroups,
        const D3D12_BARRIER_GROUP *pBarrierGroups) override;
};
