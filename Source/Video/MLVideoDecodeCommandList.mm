#include "Metalloid/Video/MLVideoDecodeCommandList.h"
#include "Metalloid/Device/MLDevice.h"
#include "Metalloid/Video/MLVideoDecoder.h"
#include "Metalloid/Resources/MLResource.h"
#include <iostream>

#ifdef __OBJC__
@interface MLResourceWrapper : NSObject
@property (nonatomic, assign) ID3D12Resource* resource;
@property (nonatomic, assign) bool isMapped;
@end

@implementation MLResourceWrapper
- (instancetype)initWithResource:(ID3D12Resource*)res {
    self = [super init];
    if (self) {
        _resource = res;
        if (_resource) _resource->AddRef();
        _isMapped = false;
    }
    return self;
}
- (void)dealloc {
    if (_resource) {
        if (_isMapped) {
            _resource->Unmap(0, nullptr);
        }
        _resource->Release();
    }
}
@end

@interface MLDecoderWrapper : NSObject
@property (nonatomic, assign) MLVideoDecoder* decoder;
@end

@implementation MLDecoderWrapper
- (instancetype)initWithDecoder:(MLVideoDecoder*)dec {
    self = [super init];
    if (self) {
        _decoder = dec;
        if (_decoder) _decoder->AddRef();
    }
    return self;
}
- (void)dealloc {
    if (_decoder) {
        _decoder->Release();
    }
}
@end
#endif


MLVideoDecodeCommandList::MLVideoDecodeCommandList(MLDevice* device) : m_device(device), m_type(D3D12_COMMAND_LIST_TYPE_VIDEO_DECODE) {
    if (m_device) m_device->AddRef();
#ifdef __OBJC__
    id<MTLCommandQueue> queue = (__bridge id<MTLCommandQueue>)m_device->GetDefaultQueue();
    m_activeCommandBuffer = [queue commandBuffer];
#endif
}

MLVideoDecodeCommandList::~MLVideoDecodeCommandList() {
    if (m_device) m_device->Release();
}

HRESULT STDMETHODCALLTYPE MLVideoDecodeCommandList::QueryInterface(REFIID riid, void** ppvObject) {
    if (!ppvObject) return E_INVALIDARG;
    if (riid == __uuidof(ID3D12VideoDecodeCommandList3) ||
        riid == __uuidof(ID3D12VideoDecodeCommandList2) ||
        riid == __uuidof(ID3D12VideoDecodeCommandList1) ||
        riid == __uuidof(ID3D12VideoDecodeCommandList) || 
        riid == __uuidof(ID3D12CommandList) || 
        riid == __uuidof(ID3D12DeviceChild) || 
        riid == __uuidof(ID3D12Object) || 
        riid == __uuidof(IUnknown)) {
        *ppvObject = static_cast<ID3D12VideoDecodeCommandList3*>(this);
        AddRef();
        return S_OK;
    }
    return E_NOINTERFACE;
}

ULONG STDMETHODCALLTYPE MLVideoDecodeCommandList::AddRef() { return ++m_refCount; }
ULONG STDMETHODCALLTYPE MLVideoDecodeCommandList::Release() {
    ULONG ref = --m_refCount;
    if (ref == 0) delete this;
    return ref;
}

ML_IMPL_PRIVATE_DATA(MLVideoDecodeCommandList)
HRESULT STDMETHODCALLTYPE MLVideoDecodeCommandList::SetName(LPCWSTR Name) { return S_OK; }
HRESULT STDMETHODCALLTYPE MLVideoDecodeCommandList::GetDevice(REFIID riid, void** ppvDevice) { return E_FAIL; }
D3D12_COMMAND_LIST_TYPE STDMETHODCALLTYPE MLVideoDecodeCommandList::GetType() { return D3D12_COMMAND_LIST_TYPE_VIDEO_DECODE; }

HRESULT STDMETHODCALLTYPE MLVideoDecodeCommandList::Close() { return S_OK; }
HRESULT STDMETHODCALLTYPE MLVideoDecodeCommandList::Reset(ID3D12CommandAllocator* pAllocator) {
#ifdef __OBJC__
    id<MTLCommandQueue> queue = (__bridge id<MTLCommandQueue>)m_device->GetDefaultQueue();
    m_activeCommandBuffer = [queue commandBuffer];
#endif
    return S_OK;
}
void STDMETHODCALLTYPE MLVideoDecodeCommandList::ClearState() {}
void STDMETHODCALLTYPE MLVideoDecodeCommandList::ResourceBarrier(UINT NumBarriers, const D3D12_RESOURCE_BARRIER* pBarriers) {
    if (!pBarriers) return;
    for (UINT i = 0; i < NumBarriers; ++i) {
        if (pBarriers[i].Type == D3D12_RESOURCE_BARRIER_TYPE_TRANSITION) {
            MLResource* pResource = static_cast<MLResource*>(pBarriers[i].Transition.pResource);
            if (pResource) {
                pResource->SetState(pBarriers[i].Transition.StateAfter);
            }
        }
    }
}

void STDMETHODCALLTYPE MLVideoDecodeCommandList::DiscardResource(ID3D12Resource* pResource, const D3D12_DISCARD_REGION* pRegion) {}
void STDMETHODCALLTYPE MLVideoDecodeCommandList::BeginQuery(ID3D12QueryHeap* pQueryHeap, D3D12_QUERY_TYPE Type, UINT Index) {}
void STDMETHODCALLTYPE MLVideoDecodeCommandList::EndQuery(ID3D12QueryHeap* pQueryHeap, D3D12_QUERY_TYPE Type, UINT Index) {}
void STDMETHODCALLTYPE MLVideoDecodeCommandList::ResolveQueryData(ID3D12QueryHeap* pQueryHeap, D3D12_QUERY_TYPE Type, UINT StartIndex, UINT NumQueries, ID3D12Resource* pDestinationBuffer, UINT64 AlignedDestinationBufferOffset) {}
void STDMETHODCALLTYPE MLVideoDecodeCommandList::SetPredication(ID3D12Resource* pBuffer, UINT64 AlignedBufferOffset, D3D12_PREDICATION_OP Operation) {}
void STDMETHODCALLTYPE MLVideoDecodeCommandList::SetMarker(UINT Metadata, const void* pData, UINT Size) {
#ifdef __OBJC__
    if (m_activeCommandBuffer && pData && Size > 0) {
        NSString* marker = [[NSString alloc] initWithBytes:pData length:Size encoding:NSUTF8StringEncoding];
        if (marker) {
            [(id<MTLCommandBuffer>)m_activeCommandBuffer pushDebugGroup:marker];
            [(id<MTLCommandBuffer>)m_activeCommandBuffer popDebugGroup];
        }
    }
#endif
}
void STDMETHODCALLTYPE MLVideoDecodeCommandList::BeginEvent(UINT Metadata, const void* pData, UINT Size) {
#ifdef __OBJC__
    if (m_activeCommandBuffer && pData && Size > 0) {
        NSString* marker = [[NSString alloc] initWithBytes:pData length:Size encoding:NSUTF8StringEncoding];
        if (marker) {
            [(id<MTLCommandBuffer>)m_activeCommandBuffer pushDebugGroup:marker];
        }
    }
#endif
}
void STDMETHODCALLTYPE MLVideoDecodeCommandList::EndEvent() {
#ifdef __OBJC__
    if (m_activeCommandBuffer) {
        [(id<MTLCommandBuffer>)m_activeCommandBuffer popDebugGroup];
    }
#endif
}

void STDMETHODCALLTYPE MLVideoDecodeCommandList::DecodeFrame(
    ID3D12VideoDecoder* pDecoder,
    const D3D12_VIDEO_DECODE_OUTPUT_STREAM_ARGUMENTS* pOutputArguments,
    const D3D12_VIDEO_DECODE_INPUT_STREAM_ARGUMENTS* pInputArguments) {
    
    if (!pDecoder || !pInputArguments || !pOutputArguments) return;
    if (!pOutputArguments->pOutputTexture2D || !pInputArguments->CompressedBitstream.pBuffer) return;
    
    MLVideoDecoder* decoder = static_cast<MLVideoDecoder*>(pDecoder);

#ifdef __OBJC__
    VTDecompressionSessionRef session = decoder->GetVTSession();
    
    if (!session) {
        CMVideoCodecType codecType = kCMVideoCodecType_H264; 
        const GUID& decodeProfile = decoder->GetDesc().Configuration.DecodeProfile;
        
        if (decodeProfile == D3D12_VIDEO_DECODE_PROFILE_HEVC_MAIN ||
            decodeProfile == D3D12_VIDEO_DECODE_PROFILE_HEVC_MAIN10 ||
            decodeProfile == D3D12_VIDEO_DECODE_PROFILE_HEVC_MONOCHROME ||
            decodeProfile == D3D12_VIDEO_DECODE_PROFILE_HEVC_MONOCHROME10 ||
            decodeProfile == D3D12_VIDEO_DECODE_PROFILE_HEVC_MAIN12 ||
            decodeProfile == D3D12_VIDEO_DECODE_PROFILE_HEVC_MAIN10_422 ||
            decodeProfile == D3D12_VIDEO_DECODE_PROFILE_HEVC_MAIN12_422 ||
            decodeProfile == D3D12_VIDEO_DECODE_PROFILE_HEVC_MAIN_444 ||
            decodeProfile == D3D12_VIDEO_DECODE_PROFILE_HEVC_MAIN10_EXT ||
            decodeProfile == D3D12_VIDEO_DECODE_PROFILE_HEVC_MAIN10_444 ||
            decodeProfile == D3D12_VIDEO_DECODE_PROFILE_HEVC_MAIN12_444 ||
            decodeProfile == D3D12_VIDEO_DECODE_PROFILE_HEVC_MAIN16) {
            codecType = kCMVideoCodecType_HEVC;
        } else if (decodeProfile == D3D12_VIDEO_DECODE_PROFILE_AV1_PROFILE0 ||
                   decodeProfile == D3D12_VIDEO_DECODE_PROFILE_AV1_PROFILE1 ||
                   decodeProfile == D3D12_VIDEO_DECODE_PROFILE_AV1_PROFILE2 ||
                   decodeProfile == D3D12_VIDEO_DECODE_PROFILE_AV1_12BIT_PROFILE2 ||
                   decodeProfile == D3D12_VIDEO_DECODE_PROFILE_AV1_12BIT_PROFILE2_420) {
            #ifndef kCMVideoCodecType_AV1
            #define kCMVideoCodecType_AV1 'av01'
            #endif
            codecType = (CMVideoCodecType)kCMVideoCodecType_AV1;
        }

        ID3D12Resource* pOutTex = pOutputArguments->pOutputTexture2D;
        D3D12_RESOURCE_DESC outDesc = pOutTex->GetDesc();

        CMVideoFormatDescriptionRef formatDesc = nullptr;
        OSStatus status = CMVideoFormatDescriptionCreate(
            kCFAllocatorDefault,
            codecType,
            outDesc.Width,
            outDesc.Height,
            nullptr,
            &formatDesc);
        if (status != noErr || !formatDesc) {
            std::cerr << "[Metalloid] CMVideoFormatDescriptionCreate failed: " << status << std::endl;
            return;
        }
            
        CFMutableDictionaryRef destinationImageBufferAttributes = CFDictionaryCreateMutable(kCFAllocatorDefault, 1, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
        SInt32 pixelFormat = kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange; // NV12
        CFNumberRef pixelFormatNumber = CFNumberCreate(kCFAllocatorDefault, kCFNumberSInt32Type, &pixelFormat);
        CFDictionarySetValue(destinationImageBufferAttributes, kCVPixelBufferPixelFormatTypeKey, pixelFormatNumber);
        CFRelease(pixelFormatNumber);

        status = VTDecompressionSessionCreate(
            kCFAllocatorDefault,
            formatDesc,
            nullptr,
            destinationImageBufferAttributes,
            nullptr,
            &session);
        
        CFRelease(destinationImageBufferAttributes);
        
        if (status != noErr || !session) {
            std::cerr << "[Metalloid] VTDecompressionSessionCreate failed: " << status << std::endl;
            CFRelease(formatDesc);
            return;
        }
        
        decoder->SetVTSession(session, formatDesc);
    }
    
    if (!session || !m_activeCommandBuffer) return;

    ID3D12Resource* bitstreamResourceRaw = pInputArguments->CompressedBitstream.pBuffer;
    UINT64 offset = pInputArguments->CompressedBitstream.Offset;
    UINT64 size = pInputArguments->CompressedBitstream.Size;
    
    MLResourceWrapper* bitstreamWrapper = [[MLResourceWrapper alloc] initWithResource:bitstreamResourceRaw];
    MLDecoderWrapper* decoderWrapper = [[MLDecoderWrapper alloc] initWithDecoder:decoder];
    
    id<MTLDevice> metalDevice = m_device->GetMetalDevice();
    id<MTLCommandQueue> metalCommandQueue = (__bridge id<MTLCommandQueue>)m_device->GetDefaultQueue();
    id<MTLTexture> dstTexture = static_cast<MLResource*>(pOutputArguments->pOutputTexture2D)->GetMetalTexture();
    
    id<MTLSharedEvent> syncEvent = [metalDevice newSharedEvent];
    [(id<MTLCommandBuffer>)m_activeCommandBuffer encodeWaitForEvent:syncEvent value:1];

    [(id<MTLCommandBuffer>)m_activeCommandBuffer addScheduledHandler:^(id<MTLCommandBuffer> cb) {
        if (!decoderWrapper.decoder || !decoderWrapper.decoder->GetVTSession()) {
            id<MTLCommandBuffer> failCmdBuf = [metalCommandQueue commandBuffer];
            [failCmdBuf encodeSignalEvent:syncEvent value:1];
            [failCmdBuf commit];
            return;
        }
        
        void* bitstreamData = nullptr;
        bitstreamWrapper.resource->Map(0, nullptr, &bitstreamData);
        if (!bitstreamData) {
            id<MTLCommandBuffer> failCmdBuf = [metalCommandQueue commandBuffer];
            [failCmdBuf encodeSignalEvent:syncEvent value:1];
            [failCmdBuf commit];
            return;
        }
        bitstreamWrapper.isMapped = true;

        CMBlockBufferRef blockBuffer = nullptr;
        CMBlockBufferCreateWithMemoryBlock(
            kCFAllocatorDefault, 
            (uint8_t*)bitstreamData + offset, 
            size, 
            kCFAllocatorNull, nullptr, 0, size, 
            0, &blockBuffer);
        
        CMSampleBufferRef sampleBuffer = nullptr;
        size_t sampleSize = size;
        CMSampleBufferCreateReady(kCFAllocatorDefault, blockBuffer, decoderWrapper.decoder->GetFormatDesc(), 1, 0, nullptr, 1, &sampleSize, &sampleBuffer);
        
        VTDecodeInfoFlags flags = 0;
        OSStatus vtStatus = VTDecompressionSessionDecodeFrameWithOutputHandler(decoderWrapper.decoder->GetVTSession(), sampleBuffer, flags, nullptr, 
            ^(OSStatus status, VTDecodeInfoFlags infoFlags, CVImageBufferRef imageBuffer, CMTime presentationTimeStamp, CMTime presentationDuration) {
                id<MTLCommandBuffer> blitCmdBuf = [metalCommandQueue commandBuffer];
                
                if (status == noErr && imageBuffer) {
                    CVMetalTextureCacheRef textureCache = NULL;
                    CVMetalTextureCacheCreate(kCFAllocatorDefault, NULL, metalDevice, NULL, &textureCache);
                    if (textureCache) {
                        CVMetalTextureRef metalTextureY = NULL;
                        CVMetalTextureRef metalTextureUV = NULL;
                        
                        CVMetalTextureCacheCreateTextureFromImage(kCFAllocatorDefault, textureCache, imageBuffer, NULL, MTLPixelFormatR8Unorm, CVPixelBufferGetWidthOfPlane(imageBuffer, 0), CVPixelBufferGetHeightOfPlane(imageBuffer, 0), 0, &metalTextureY);
                        CVMetalTextureCacheCreateTextureFromImage(kCFAllocatorDefault, textureCache, imageBuffer, NULL, MTLPixelFormatRG8Unorm, CVPixelBufferGetWidthOfPlane(imageBuffer, 1), CVPixelBufferGetHeightOfPlane(imageBuffer, 1), 1, &metalTextureUV);
                        
                        if (metalTextureY && metalTextureUV) {
                            id<MTLTexture> srcTextureY = CVMetalTextureGetTexture(metalTextureY);
                            id<MTLTexture> srcTextureUV = CVMetalTextureGetTexture(metalTextureUV);
                            
                            if (srcTextureY && srcTextureUV && dstTexture) {
                                id<MTLBlitCommandEncoder> blitEncoder = [blitCmdBuf blitCommandEncoder];
                                
                                [blitEncoder copyFromTexture:srcTextureY sourceSlice:0 sourceLevel:0 sourceOrigin:MTLOriginMake(0,0,0) sourceSize:MTLSizeMake(srcTextureY.width, srcTextureY.height, 1) toTexture:dstTexture destinationSlice:0 destinationLevel:0 destinationOrigin:MTLOriginMake(0,0,0)];
                                [blitEncoder copyFromTexture:srcTextureUV sourceSlice:0 sourceLevel:0 sourceOrigin:MTLOriginMake(0,0,0) sourceSize:MTLSizeMake(srcTextureUV.width, srcTextureUV.height, 1) toTexture:dstTexture destinationSlice:1 destinationLevel:0 destinationOrigin:MTLOriginMake(0,0,0)];
                                
                                [blitEncoder endEncoding];
                            }
                        }
                        if (metalTextureY) CFRelease(metalTextureY);
                        if (metalTextureUV) CFRelease(metalTextureUV);
                        CFRelease(textureCache);
                    }
                }
                
                [blitCmdBuf encodeSignalEvent:syncEvent value:1];
                [blitCmdBuf commit];
                
                // Keep wrapper alive until here; it will unmap and release when deallocated.
                (void)bitstreamWrapper;
                (void)decoderWrapper;
            });
            
        if (vtStatus != noErr) {
            id<MTLCommandBuffer> failCmdBuf = [metalCommandQueue commandBuffer];
            [failCmdBuf encodeSignalEvent:syncEvent value:1];
            [failCmdBuf commit];
        }
            
        CFRelease(sampleBuffer);
        CFRelease(blockBuffer);
    }];
#endif
}

void STDMETHODCALLTYPE MLVideoDecodeCommandList::WriteBufferImmediate(UINT Count, const D3D12_WRITEBUFFERIMMEDIATE_PARAMETER* pParams, const D3D12_WRITEBUFFERIMMEDIATE_MODE* pModes) {}

void STDMETHODCALLTYPE MLVideoDecodeCommandList::DecodeFrame1(
    ID3D12VideoDecoder* pDecoder,
    const D3D12_VIDEO_DECODE_OUTPUT_STREAM_ARGUMENTS1* pOutputArguments,
    const D3D12_VIDEO_DECODE_INPUT_STREAM_ARGUMENTS* pInputArguments) {
    // DecodeFrame1 extends DecodeFrame with protected session support
    if (!pDecoder || !pInputArguments || !pOutputArguments) return;
    
    // We can just forward to DecodeFrame
    D3D12_VIDEO_DECODE_OUTPUT_STREAM_ARGUMENTS args = {};
    args.pOutputTexture2D = pOutputArguments->pOutputTexture2D;
    args.OutputSubresource = pOutputArguments->OutputSubresource;
    args.ConversionArguments.Enable = pOutputArguments->ConversionArguments.Enable;
    args.ConversionArguments.pReferenceTexture2D = pOutputArguments->ConversionArguments.pReferenceTexture2D;
    args.ConversionArguments.ReferenceSubresource = pOutputArguments->ConversionArguments.ReferenceSubresource;
    args.ConversionArguments.OutputColorSpace = pOutputArguments->ConversionArguments.OutputColorSpace;
    args.ConversionArguments.DecodeColorSpace = pOutputArguments->ConversionArguments.DecodeColorSpace;
    DecodeFrame(pDecoder, &args, pInputArguments);
}

void STDMETHODCALLTYPE MLVideoDecodeCommandList::SetProtectedResourceSession(ID3D12ProtectedResourceSession* pProtectedResourceSession) {}
void STDMETHODCALLTYPE MLVideoDecodeCommandList::InitializeExtensionCommand(ID3D12VideoExtensionCommand* pExtensionCommand, const void* pInitializationParameters, SIZE_T InitializationParametersSizeInBytes) {}
void STDMETHODCALLTYPE MLVideoDecodeCommandList::ExecuteExtensionCommand(ID3D12VideoExtensionCommand* pExtensionCommand, const void* pExecutionParameters, SIZE_T ExecutionParametersSizeInBytes) {}

void STDMETHODCALLTYPE MLVideoDecodeCommandList::Barrier(UINT32 NumBarrierGroups, const D3D12_BARRIER_GROUP* pBarrierGroups) {
    if (!pBarrierGroups) return;
    for (UINT32 i = 0; i < NumBarrierGroups; ++i) {
        const D3D12_BARRIER_GROUP& group = pBarrierGroups[i];
        if (group.Type == D3D12_BARRIER_TYPE_TEXTURE) {
            for (UINT32 j = 0; j < group.NumBarriers; ++j) {
                const D3D12_TEXTURE_BARRIER& texBarrier = group.pTextureBarriers[j];
                MLResource* pResource = static_cast<MLResource*>(texBarrier.pResource);
                if (pResource) {
                    D3D12_RESOURCE_STATES stateAfter = D3D12_RESOURCE_STATE_COMMON;
                    if (texBarrier.AccessAfter & D3D12_BARRIER_ACCESS_VIDEO_DECODE_WRITE) {
                        stateAfter = D3D12_RESOURCE_STATE_VIDEO_DECODE_WRITE;
                    } else if (texBarrier.AccessAfter & D3D12_BARRIER_ACCESS_VIDEO_DECODE_READ) {
                        stateAfter = D3D12_RESOURCE_STATE_VIDEO_DECODE_READ;
                    } else if (texBarrier.AccessAfter & D3D12_BARRIER_ACCESS_COMMON) {
                        stateAfter = D3D12_RESOURCE_STATE_COMMON;
                    } else {
                        // Just a generic catch-all mapping to keep state updated
                        stateAfter = D3D12_RESOURCE_STATE_COMMON; 
                    }
                    if (stateAfter != D3D12_RESOURCE_STATE_COMMON) {
                        pResource->SetState(stateAfter);
                    }
                }
            }
        } else if (group.Type == D3D12_BARRIER_TYPE_BUFFER) {
            for (UINT32 j = 0; j < group.NumBarriers; ++j) {
                const D3D12_BUFFER_BARRIER& bufBarrier = group.pBufferBarriers[j];
                MLResource* pResource = static_cast<MLResource*>(bufBarrier.pResource);
                if (pResource) {
                    D3D12_RESOURCE_STATES stateAfter = D3D12_RESOURCE_STATE_COMMON;
                    if (bufBarrier.AccessAfter & D3D12_BARRIER_ACCESS_VIDEO_DECODE_WRITE) {
                        stateAfter = D3D12_RESOURCE_STATE_VIDEO_DECODE_WRITE;
                    } else if (bufBarrier.AccessAfter & D3D12_BARRIER_ACCESS_VIDEO_DECODE_READ) {
                        stateAfter = D3D12_RESOURCE_STATE_VIDEO_DECODE_READ;
                    }
                    if (stateAfter != D3D12_RESOURCE_STATE_COMMON) {
                        pResource->SetState(stateAfter);
                    }
                }
            }
        }
    }
}
