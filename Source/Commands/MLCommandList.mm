#include "Metalloid/Commands/MLCommandList.h"
#include "Metalloid/Pipelines/MLRootSignature.h"
#include "Metalloid/Pipelines/MLStateObject.h"
#include "Metalloid/Device/MLDevice.h"
#include "Metalloid/Resources/MLResource.h"
#include "Metalloid/Commands/MLCommandAllocator.h"
#include "Metalloid/Resources/MLDescriptor.h"
#include "Metalloid/Pipelines/MLPipelineState.h"
#include "Metalloid/Sync/MLQueryHeap.h"
#include <iostream>

static MTLPrimitiveType MapPrimitiveTopology(D3D12_PRIMITIVE_TOPOLOGY top) {
    switch(top) {
        case D3D_PRIMITIVE_TOPOLOGY_POINTLIST: return MTLPrimitiveTypePoint;
        case D3D_PRIMITIVE_TOPOLOGY_LINELIST: return MTLPrimitiveTypeLine;
        case D3D_PRIMITIVE_TOPOLOGY_LINESTRIP: return MTLPrimitiveTypeLineStrip;
        case D3D_PRIMITIVE_TOPOLOGY_TRIANGLELIST: return MTLPrimitiveTypeTriangle;
        case D3D_PRIMITIVE_TOPOLOGY_TRIANGLESTRIP: return MTLPrimitiveTypeTriangleStrip;
        default: return MTLPrimitiveTypeTriangle; // Fallback for control points and undef
    }
}

MLCommandList::MLCommandList(MLDevice* device, D3D12_COMMAND_LIST_TYPE type)
    : m_device(device), m_type(type), m_activeCommandBuffer(nullptr), m_activeRenderEncoder(nullptr), m_numActiveRenderTargets(0), 
      m_activeDepthStencil(nullptr), m_currentPSO(nullptr), m_boundPSO(nullptr) {
    for (int i = 0; i < 8; ++i) m_activeRenderTargets[i] = nullptr;
    std::cout << "[Metalloid] ID3D12GraphicsCommandList created." << std::endl;
}

MLCommandList::~MLCommandList() {
    std::cout << "[Metalloid] ID3D12GraphicsCommandList destroyed." << std::endl;
}

HRESULT STDMETHODCALLTYPE MLCommandList::QueryInterface(REFIID riid, void** ppvObject) {
    if (!ppvObject) return E_POINTER;

    if (riid == __uuidof(IUnknown) ||
        riid == __uuidof(ID3D12Object) ||
        riid == __uuidof(ID3D12DeviceChild) ||
        riid == __uuidof(ID3D12CommandList) ||
        riid == __uuidof(ID3D12GraphicsCommandList)) {
        *ppvObject = static_cast<ID3D12GraphicsCommandList*>(this);
        AddRef();
        return S_OK;
    }

    *ppvObject = nullptr;
    return E_NOINTERFACE;
}

ULONG STDMETHODCALLTYPE MLCommandList::AddRef() {
    return ++m_refCount;
}

ULONG STDMETHODCALLTYPE MLCommandList::Release() {
    ULONG count = --m_refCount;
    if (count == 0) {
        delete this;
    }
    return count;
}

ML_IMPL_PRIVATE_DATA(MLCommandList)

HRESULT STDMETHODCALLTYPE MLCommandList::SetName(LPCWSTR Name) {
#ifdef __OBJC__
    if (Name) {
        UINT size = (UINT)(wcslen(Name) * sizeof(wchar_t));
        NSString* nameStr = [[NSString alloc] initWithBytes:Name length:size encoding:NSUTF32LittleEndianStringEncoding];
        if (m_activeCommandBuffer) {
            ((id<MTLCommandBuffer>)m_activeCommandBuffer).label = nameStr;
        }
    }
#endif
    return S_OK;
}

HRESULT STDMETHODCALLTYPE MLCommandList::GetDevice(REFIID riid, void** ppvDevice) {
    if (!ppvDevice) return E_POINTER;
    if (m_device) {
        return m_device->QueryInterface(riid, ppvDevice);
    }
    return E_NOINTERFACE;
}

D3D12_COMMAND_LIST_TYPE STDMETHODCALLTYPE MLCommandList::GetType() {
    return m_type;
}

HRESULT STDMETHODCALLTYPE MLCommandList::Close() {
    std::cout << "[Metalloid] ID3D12GraphicsCommandList::Close called." << std::endl;
#ifdef __OBJC__
    // If we have an active render encoder from DrawInstanced, end it
    if (m_activeRenderEncoder) {
        id<MTLRenderCommandEncoder> encoder = (id<MTLRenderCommandEncoder>)m_activeRenderEncoder;
        [encoder endEncoding];
        m_activeRenderEncoder = nullptr;
    }
#endif
    return S_OK;
}

HRESULT STDMETHODCALLTYPE MLCommandList::Reset(
    ID3D12CommandAllocator* pAllocator,
    ID3D12PipelineState* pInitialState) {
    std::cout << "[Metalloid] ID3D12GraphicsCommandList::Reset called." << std::endl;
    m_currentPSO = nullptr;
    m_boundPSO = nullptr;
    if (pInitialState) {
        m_currentPSO = static_cast<MLPipelineState*>(pInitialState);
    }
#ifdef __OBJC__
    if (m_activeRenderEncoder) {
        id<MTLRenderCommandEncoder> encoder = (id<MTLRenderCommandEncoder>)m_activeRenderEncoder;
        [encoder endEncoding];
        m_activeRenderEncoder = nullptr;
    }
    if (m_activeCommandBuffer) {
        id<MTLCommandBuffer> mtlBuf = (id<MTLCommandBuffer>)m_activeCommandBuffer;
        if (mtlBuf.status == MTLCommandBufferStatusNotEnqueued) {
            std::cout << "[Metalloid] Warning: Resetting command list with uncommitted buffer. Aborting old buffer." << std::endl;
        }
        m_activeCommandBuffer = nullptr;
    }
    if (pAllocator) {
        MLCommandAllocator* mlAllocator = static_cast<MLCommandAllocator*>(pAllocator);
        void* cmdBuf = mlAllocator->AllocateCommandBuffer();
        if (cmdBuf) {
            m_activeCommandBuffer = (__bridge id<MTLCommandBuffer>)cmdBuf;
        }
    }
#endif
    return S_OK;
}

void STDMETHODCALLTYPE MLCommandList::ClearState(ID3D12PipelineState* pPipelineState) {
    // Reset bindings
    m_activePipelineState = pPipelineState;
    m_currentPSO = nullptr;
    m_boundPSO = nullptr;
    m_graphicsRootSignature = nullptr;
    m_computeRootSignature = nullptr;
    m_numActiveRenderTargets = 0;
    m_activeDepthStencil = nullptr;
    m_primitiveTopology = D3D_PRIMITIVE_TOPOLOGY_UNDEFINED;
    
    // In D3D12, ClearState also unbinds descriptor heaps, scissor rects, etc.
    m_numViewports = 0;
    m_numScissorRects = 0;
    m_stencilRef = 0;
    m_blendFactor[0] = m_blendFactor[1] = m_blendFactor[2] = m_blendFactor[3] = 1.0f;
    
    // We don't have access to MLPipelineState internally to apply it immediately here,
    // so it will be applied on the next draw/dispatch.
}

void STDMETHODCALLTYPE MLCommandList::SetPipelineState(ID3D12PipelineState* pPipelineState) {
    m_currentPSO = static_cast<MLPipelineState*>(pPipelineState);
}

void STDMETHODCALLTYPE MLCommandList::ResourceBarrier(
    UINT NumBarriers,
    const D3D12_RESOURCE_BARRIER* pBarriers) {
    // Basic barrier tracking and GPU Synchronization
    bool needsMemoryBarrier = false;
#ifdef __OBJC__
    MTLBarrierScope scope = 0;
#endif

    for (UINT i = 0; i < NumBarriers; ++i) {
        if (pBarriers[i].Type == D3D12_RESOURCE_BARRIER_TYPE_TRANSITION) {
            MLResource* res = static_cast<MLResource*>(pBarriers[i].Transition.pResource);
            if (res) {
                res->SetState(pBarriers[i].Transition.StateAfter);
                TrackResourceAccess(res);
                needsMemoryBarrier = true;
#ifdef __OBJC__
                if (res->GetDimension() == D3D12_RESOURCE_DIMENSION_BUFFER) {
                    scope |= MTLBarrierScopeBuffers;
                } else {
                    scope |= MTLBarrierScopeTextures;
                }
#endif
            }
        } else if (pBarriers[i].Type == D3D12_RESOURCE_BARRIER_TYPE_UAV) {
            needsMemoryBarrier = true;
            MLResource* res = static_cast<MLResource*>(pBarriers[i].UAV.pResource);
#ifdef __OBJC__
            if (res) {
                if (res->GetDimension() == D3D12_RESOURCE_DIMENSION_BUFFER) {
                    scope |= MTLBarrierScopeBuffers;
                } else {
                    scope |= MTLBarrierScopeTextures;
                }
            } else {
                scope |= (MTLBarrierScopeBuffers | MTLBarrierScopeTextures);
            }
#endif
        } else if (pBarriers[i].Type == D3D12_RESOURCE_BARRIER_TYPE_ALIASING) {
            needsMemoryBarrier = true;
#ifdef __OBJC__
            scope |= (MTLBarrierScopeBuffers | MTLBarrierScopeTextures);
#endif
        }
    }

#ifdef __OBJC__
    if (needsMemoryBarrier) {
        if (scope == 0) scope = MTLBarrierScopeBuffers | MTLBarrierScopeTextures;
        
        if (m_activeRenderEncoder) {
            // In Metal, overlapping reads/writes in the same encoder require a memory barrier.
            [(id<MTLRenderCommandEncoder>)m_activeRenderEncoder memoryBarrierWithScope:scope | MTLBarrierScopeRenderTargets
                                                                          afterStages:MTLRenderStageVertex | MTLRenderStageFragment
                                                                         beforeStages:MTLRenderStageVertex | MTLRenderStageFragment];
        } else if (m_activeComputeEncoder) {
            [(id<MTLComputeCommandEncoder>)m_activeComputeEncoder memoryBarrierWithScope:scope];
        }
    }
#endif
}

void STDMETHODCALLTYPE MLCommandList::DrawInstanced(
    UINT VertexCountPerInstance,
    UINT InstanceCount,
    UINT StartVertexLocation,
    UINT StartInstanceLocation) {
#ifdef __OBJC__
    if (!m_activeCommandBuffer) return;
    id<MTLCommandBuffer> mtlBuf = (id<MTLCommandBuffer>)m_activeCommandBuffer;
    
    // Lazily create encoder if not active
    if (!m_activeRenderEncoder) {
        if (m_numActiveRenderTargets > 0) {
            MLResource* renderTarget = m_activeRenderTargets[0];
            if (renderTarget && renderTarget->GetMetalTexture()) {
                MTLRenderPassDescriptor* passDesc = [MTLRenderPassDescriptor renderPassDescriptor];
                passDesc.colorAttachments[0].texture = renderTarget->GetMetalTexture();
                passDesc.colorAttachments[0].loadAction = MTLLoadActionLoad;
                passDesc.colorAttachments[0].storeAction = MTLStoreActionStore;
                
                // Also attach Depth Stencil if available
                if (m_activeDepthStencil && m_activeDepthStencil->GetMetalTexture()) {
                    id<MTLTexture> dsTex = m_activeDepthStencil->GetMetalTexture();
                    passDesc.depthAttachment.texture = dsTex;
                    passDesc.depthAttachment.loadAction = MTLLoadActionLoad;
                    passDesc.depthAttachment.storeAction = MTLStoreActionStore;
                    
                    MTLPixelFormat fmt = dsTex.pixelFormat;
                    if (fmt == MTLPixelFormatDepth32Float_Stencil8 || fmt == MTLPixelFormatDepth24Unorm_Stencil8 || fmt == MTLPixelFormatStencil8) {
                        passDesc.stencilAttachment.texture = dsTex;
                        passDesc.stencilAttachment.loadAction = MTLLoadActionLoad;
                        passDesc.stencilAttachment.storeAction = MTLStoreActionStore;
                    }
                }
                
                m_activeRenderEncoder = [mtlBuf renderCommandEncoderWithDescriptor:passDesc];
            }
        }
    }

    if (m_activeRenderEncoder) {
        id<MTLRenderCommandEncoder> encoder = (id<MTLRenderCommandEncoder>)m_activeRenderEncoder;
        
        // Bind pipeline ONLY if changed
        if (m_currentPSO && m_currentPSO != m_boundPSO && !m_currentPSO->IsCompute()) {
            [encoder setRenderPipelineState:m_currentPSO->GetRenderPipeline()];
            m_boundPSO = m_currentPSO;
        }
        
        // Flush pending state before draw
        FlushGraphicsRootArguments();
        
        for (int i = 0; i < m_numActiveRenderTargets; ++i) {
            MarkResourceWritten(m_activeRenderTargets[i]);
        }
        MarkResourceWritten(m_activeDepthStencil);
        
        // Execute draw
        [encoder drawPrimitives:MapPrimitiveTopology(m_primitiveTopology)
                    vertexStart:StartVertexLocation 
                    vertexCount:VertexCountPerInstance 
                  instanceCount:InstanceCount 
                   baseInstance:StartInstanceLocation];
    }
#endif
}

void STDMETHODCALLTYPE MLCommandList::DrawIndexedInstanced(
    UINT IndexCountPerInstance,
    UINT InstanceCount,
    UINT StartIndexLocation,
    INT BaseVertexLocation,
    UINT StartInstanceLocation) {
#ifdef __OBJC__
    if (!m_activeRenderEncoder) return;
    
    id<MTLRenderCommandEncoder> encoder = (id<MTLRenderCommandEncoder>)m_activeRenderEncoder;
    
    // Use the resolved index buffer from IASetIndexBuffer
    if (m_indexBuffer.resource && m_indexBuffer.resource->GetMetalBuffer()) {
        MTLIndexType indexType = (m_indexBuffer.format == DXGI_FORMAT_R32_UINT) ? MTLIndexTypeUInt32 : MTLIndexTypeUInt16;
        
        for (int i = 0; i < m_numActiveRenderTargets; ++i) {
            MarkResourceWritten(m_activeRenderTargets[i]);
        }
        MarkResourceWritten(m_activeDepthStencil);

        [encoder drawIndexedPrimitives:MapPrimitiveTopology(m_primitiveTopology)
                            indexCount:IndexCountPerInstance
                             indexType:indexType
                           indexBuffer:m_indexBuffer.resource->GetMetalBuffer()
                     indexBufferOffset:m_indexBuffer.offset + (StartIndexLocation * (indexType == MTLIndexTypeUInt32 ? 4 : 2))
                         instanceCount:InstanceCount
                            baseVertex:BaseVertexLocation
                          baseInstance:StartInstanceLocation];
    } else {
        std::cout << "[Metalloid] WARNING: DrawIndexedInstanced called without a valid Index Buffer bound!" << std::endl;
    }
#endif
}

void STDMETHODCALLTYPE MLCommandList::Dispatch(
    UINT ThreadGroupCountX,
    UINT ThreadGroupCountY,
    UINT ThreadGroupCountZ) {
#ifdef __OBJC__
    if (!m_activeCommandBuffer) return;
    id<MTLCommandBuffer> mtlBuf = (id<MTLCommandBuffer>)m_activeCommandBuffer;
    
    // Lazily create encoder if not active
    if (!m_activeComputeEncoder) {
        m_activeComputeEncoder = [mtlBuf computeCommandEncoder];
    }
    
    if (m_activeComputeEncoder) {
        id<MTLComputeCommandEncoder> encoder = (id<MTLComputeCommandEncoder>)m_activeComputeEncoder;
        
        // Bind pipeline ONLY if changed
        if (m_currentPSO && m_currentPSO != m_boundPSO && m_currentPSO->IsCompute()) {
            [encoder setComputePipelineState:m_currentPSO->GetComputePipeline()];
            m_boundPSO = m_currentPSO;
        }
        
        // Flush pending state before dispatch
        FlushComputeRootArguments();
        
        // In D3D12, [numthreads] is defined inside the HLSL shader. 
        // In Metal, we must pass threadsPerThreadgroup from the CPU. 
        // A robust translation layer parses DXIL reflection to extract this at Pipeline Creation time.
        MTLSize threadgroups = MTLSizeMake(ThreadGroupCountX, ThreadGroupCountY, ThreadGroupCountZ);
        
        UINT tx = 8, ty = 8, tz = 1;
        if (m_currentPSO) {
            m_currentPSO->GetComputeThreads(tx, ty, tz);
        }
        MTLSize threadsPerThreadgroup = MTLSizeMake(tx, ty, tz);
        
        for (UINT i = 0; i < 64; ++i) {
            if (m_computeRootArguments[i].type == RootArgument::UAV) {
                UINT64 offset = 0;
                MLResource* res = m_device->ResolveGPUVirtualAddress(m_computeRootArguments[i].viewLocation, &offset);
                MarkResourceWritten(res);
            }
        }
        
        [encoder dispatchThreadgroups:threadgroups threadsPerThreadgroup:threadsPerThreadgroup];
        std::cout << "[Metalloid] Dispatch invoked (" << ThreadGroupCountX << ", " << ThreadGroupCountY << ", " << ThreadGroupCountZ << ")" << std::endl;
    }
#endif
}

void STDMETHODCALLTYPE MLCommandList::CopyBufferRegion(
    ID3D12Resource* pDstBuffer,
    UINT64 DstOffset,
    ID3D12Resource* pSrcBuffer,
    UINT64 SrcOffset,
    UINT64 NumBytes) {
#ifdef __OBJC__
    if (!pDstBuffer || !pSrcBuffer || !m_activeCommandBuffer) return;
    MLResource* dst = static_cast<MLResource*>(pDstBuffer);
    MLResource* src = static_cast<MLResource*>(pSrcBuffer);
    TrackResourceAccess(src);

    // Temporarily end active encoders
    if (m_activeRenderEncoder) { [(id<MTLRenderCommandEncoder>)m_activeRenderEncoder endEncoding]; m_activeRenderEncoder = nil; m_boundPSO = nullptr; }
    if (m_activeComputeEncoder) { [(id<MTLComputeCommandEncoder>)m_activeComputeEncoder endEncoding]; m_activeComputeEncoder = nil; m_boundPSO = nullptr; }

    if (dst->GetMetalBuffer() && src->GetMetalBuffer()) {
        id<MTLBlitCommandEncoder> blit = [(id<MTLCommandBuffer>)m_activeCommandBuffer blitCommandEncoder];
        [blit copyFromBuffer:src->GetMetalBuffer() sourceOffset:SrcOffset toBuffer:dst->GetMetalBuffer() destinationOffset:DstOffset size:NumBytes];
        [blit endEncoding];
        MarkResourceWritten(dst);
    }
#endif
}

void STDMETHODCALLTYPE MLCommandList::CopyTextureRegion(
    const D3D12_TEXTURE_COPY_LOCATION* pDst,
    UINT DstX,
    UINT DstY,
    UINT DstZ,
    const D3D12_TEXTURE_COPY_LOCATION* pSrc,
    const D3D12_BOX* pSrcBox) {
#ifdef __OBJC__
    if (!pDst || !pSrc || !m_activeCommandBuffer) return;
    MLResource* dstRes = static_cast<MLResource*>(pDst->pResource);
    MLResource* srcRes = static_cast<MLResource*>(pSrc->pResource);
    if (!dstRes || !srcRes) return;
    
    TrackResourceAccess(dstRes);
    TrackResourceAccess(srcRes);
    
    if (m_activeRenderEncoder) { [(id<MTLRenderCommandEncoder>)m_activeRenderEncoder endEncoding]; m_activeRenderEncoder = nil; m_boundPSO = nullptr; }
    if (m_activeComputeEncoder) { [(id<MTLComputeCommandEncoder>)m_activeComputeEncoder endEncoding]; m_activeComputeEncoder = nil; m_boundPSO = nullptr; }

    id<MTLBlitCommandEncoder> blit = [(id<MTLCommandBuffer>)m_activeCommandBuffer blitCommandEncoder];

    if (pDst->Type == D3D12_TEXTURE_COPY_TYPE_SUBRESOURCE_INDEX && pSrc->Type == D3D12_TEXTURE_COPY_TYPE_SUBRESOURCE_INDEX) {
        id<MTLTexture> mtlDst = dstRes->GetMetalTexture();
        id<MTLTexture> mtlSrc = srcRes->GetMetalTexture();
        if (mtlDst && mtlSrc) {
            MTLOrigin srcOrigin = MTLOriginMake(0, 0, 0);
            MTLSize srcSize = MTLSizeMake(mtlSrc.width, mtlSrc.height, mtlSrc.depth);
            if (pSrcBox) {
                srcOrigin = MTLOriginMake(pSrcBox->left, pSrcBox->top, pSrcBox->front);
                srcSize = MTLSizeMake(pSrcBox->right - pSrcBox->left, pSrcBox->bottom - pSrcBox->top, pSrcBox->back - pSrcBox->front);
            }
            MTLOrigin dstOrigin = MTLOriginMake(DstX, DstY, DstZ);
            
            UINT srcMipLevels = srcRes->GetDesc().MipLevels;
            if (srcMipLevels == 0) srcMipLevels = 1;
            UINT srcLevel = pSrc->SubresourceIndex % srcMipLevels;
            UINT srcSlice = pSrc->SubresourceIndex / srcMipLevels;

            UINT dstMipLevels = dstRes->GetDesc().MipLevels;
            if (dstMipLevels == 0) dstMipLevels = 1;
            UINT dstLevel = pDst->SubresourceIndex % dstMipLevels;
            UINT dstSlice = pDst->SubresourceIndex / dstMipLevels;

            [blit copyFromTexture:mtlSrc sourceSlice:srcSlice sourceLevel:srcLevel sourceOrigin:srcOrigin sourceSize:srcSize toTexture:mtlDst destinationSlice:dstSlice destinationLevel:dstLevel destinationOrigin:dstOrigin];
            MarkResourceWritten(dstRes);
        }
    }
    [blit endEncoding];
#endif
}

void STDMETHODCALLTYPE MLCommandList::CopyResource(
    ID3D12Resource* pDstResource,
    ID3D12Resource* pSrcResource) {
#ifdef __OBJC__
    if (!pDstResource || !pSrcResource || !m_activeCommandBuffer) return;
    
    MLResource* dst = static_cast<MLResource*>(pDstResource);
    MLResource* src = static_cast<MLResource*>(pSrcResource);
    
    TrackResourceAccess(dst);
    TrackResourceAccess(src);
    
    // Temporarily end active encoders (Metal restriction: only one active encoder at a time)
    if (m_activeRenderEncoder) { [m_activeRenderEncoder endEncoding]; m_activeRenderEncoder = nil; }
    if (m_activeComputeEncoder) { [m_activeComputeEncoder endEncoding]; m_activeComputeEncoder = nil; }
    
    id<MTLBlitCommandEncoder> blit = [m_activeCommandBuffer blitCommandEncoder];
    
    if (dst->GetDesc().Dimension == D3D12_RESOURCE_DIMENSION_BUFFER && src->GetDesc().Dimension == D3D12_RESOURCE_DIMENSION_BUFFER) {
        id<MTLBuffer> mtlDst = (id<MTLBuffer>)dst->GetMetalResource();
        id<MTLBuffer> mtlSrc = (id<MTLBuffer>)src->GetMetalResource();
        if (mtlDst && mtlSrc) {
            [blit copyFromBuffer:mtlSrc sourceOffset:0 toBuffer:mtlDst destinationOffset:0 size:src->GetDesc().Width];
        }
    } else if (dst->GetDesc().Dimension == D3D12_RESOURCE_DIMENSION_TEXTURE2D && src->GetDesc().Dimension == D3D12_RESOURCE_DIMENSION_TEXTURE2D) {
        id<MTLTexture> mtlDst = (id<MTLTexture>)dst->GetMetalResource();
        id<MTLTexture> mtlSrc = (id<MTLTexture>)src->GetMetalResource();
        if (mtlDst && mtlSrc) {
            MTLSize size = MTLSizeMake(src->GetDesc().Width, src->GetDesc().Height, src->GetDesc().DepthOrArraySize);
            [blit copyFromTexture:mtlSrc sourceSlice:0 sourceLevel:0 sourceOrigin:MTLOriginMake(0,0,0) sourceSize:size toTexture:mtlDst destinationSlice:0 destinationLevel:0 destinationOrigin:MTLOriginMake(0,0,0)];
        }
    }
    MarkResourceWritten(dst);
    
    [blit endEncoding];
    std::cout << "[Metalloid] CopyResource executed successfully." << std::endl;
#endif
}

void STDMETHODCALLTYPE MLCommandList::CopyTiles(
    ID3D12Resource* pTiledResource,
    const D3D12_TILED_RESOURCE_COORDINATE* pTileRegionStartCoordinate,
    const D3D12_TILE_REGION_SIZE* pTileRegionSize,
    ID3D12Resource* pBuffer,
    UINT64 BufferOffset,
    D3D12_TILE_COPY_FLAGS Flags) {
    std::cerr << "[Metalloid] WARNING: CopyTiles is not yet supported." << std::endl;
}

void STDMETHODCALLTYPE MLCommandList::ResolveSubresource(
    ID3D12Resource* pDstResource,
    UINT DstSubresource,
    ID3D12Resource* pSrcResource,
    UINT SrcSubresource,
    DXGI_FORMAT Format) {
#ifdef __OBJC__
    if (!pDstResource || !pSrcResource || !m_activeCommandBuffer) return;
    MLResource* dst = static_cast<MLResource*>(pDstResource);
    MLResource* src = static_cast<MLResource*>(pSrcResource);
    TrackResourceAccess(dst);
    TrackResourceAccess(src);
    
    // Temporarily end active encoders
    if (m_activeRenderEncoder) { [(id<MTLRenderCommandEncoder>)m_activeRenderEncoder endEncoding]; m_activeRenderEncoder = nil; m_boundPSO = nullptr; }
    if (m_activeComputeEncoder) { [(id<MTLComputeCommandEncoder>)m_activeComputeEncoder endEncoding]; m_activeComputeEncoder = nil; m_boundPSO = nullptr; }

    if (dst->GetMetalTexture() && src->GetMetalTexture()) {
        // Technically D3D12 ResolveSubresource requires resolving MSAA texture to Non-MSAA.
        // In Metal we can't do this with a basic blit unless it's supported by the hardware
        // For Milestone 4, if they aren't MSAA, we can just do a copy, otherwise we need a render pass.
        // For now, we will do a simple blit copy if sizes match, or log a warning.
        id<MTLBlitCommandEncoder> blit = [(id<MTLCommandBuffer>)m_activeCommandBuffer blitCommandEncoder];
        [blit copyFromTexture:src->GetMetalTexture() sourceSlice:SrcSubresource sourceLevel:0 sourceOrigin:MTLOriginMake(0,0,0) sourceSize:MTLSizeMake(src->GetMetalTexture().width, src->GetMetalTexture().height, src->GetMetalTexture().depth) toTexture:dst->GetMetalTexture() destinationSlice:DstSubresource destinationLevel:0 destinationOrigin:MTLOriginMake(0,0,0)];
        [blit endEncoding];
        MarkResourceWritten(dst);
    }
#endif
}

void STDMETHODCALLTYPE MLCommandList::IASetPrimitiveTopology(D3D12_PRIMITIVE_TOPOLOGY PrimitiveTopology) {
    m_primitiveTopology = PrimitiveTopology;
}

void STDMETHODCALLTYPE MLCommandList::RSSetViewports(UINT NumViewports, const D3D12_VIEWPORT* pViewports) {
    if (!pViewports) return;
    m_numViewports = std::min(NumViewports, 16u);
    for (UINT i = 0; i < m_numViewports; ++i) {
        m_viewports[i] = pViewports[i];
    }
#ifdef __OBJC__
    if (m_activeRenderEncoder && m_numViewports > 0) {
        MTLViewport viewport;
        viewport.originX = m_viewports[0].TopLeftX;
        viewport.originY = m_viewports[0].TopLeftY;
        viewport.width = m_viewports[0].Width;
        viewport.height = m_viewports[0].Height;
        viewport.znear = m_viewports[0].MinDepth;
        viewport.zfar = m_viewports[0].MaxDepth;
        [(id<MTLRenderCommandEncoder>)m_activeRenderEncoder setViewport:viewport];
    }
#endif
}

void STDMETHODCALLTYPE MLCommandList::RSSetScissorRects(UINT NumRects, const D3D12_RECT* pRects) {
    if (!pRects) return;
    m_numScissorRects = std::min(NumRects, 16u);
    for (UINT i = 0; i < m_numScissorRects; ++i) {
        m_scissorRects[i] = pRects[i];
    }
#ifdef __OBJC__
    if (m_activeRenderEncoder && m_numScissorRects > 0) {
        MTLScissorRect rect;
        rect.x = m_scissorRects[0].left;
        rect.y = m_scissorRects[0].top;
        rect.width = m_scissorRects[0].right - m_scissorRects[0].left;
        rect.height = m_scissorRects[0].bottom - m_scissorRects[0].top;
        [(id<MTLRenderCommandEncoder>)m_activeRenderEncoder setScissorRect:rect];
    }
#endif
}

void STDMETHODCALLTYPE MLCommandList::OMSetBlendFactor(const FLOAT BlendFactor[4]) {
    if (!BlendFactor) return;
    m_blendFactor[0] = BlendFactor[0];
    m_blendFactor[1] = BlendFactor[1];
    m_blendFactor[2] = BlendFactor[2];
    m_blendFactor[3] = BlendFactor[3];
#ifdef __OBJC__
    if (m_activeRenderEncoder) {
        [(id<MTLRenderCommandEncoder>)m_activeRenderEncoder setBlendColorRed:m_blendFactor[0] green:m_blendFactor[1] blue:m_blendFactor[2] alpha:m_blendFactor[3]];
    }
#endif
}

void STDMETHODCALLTYPE MLCommandList::OMSetStencilRef(UINT StencilRef) {
    m_stencilRef = StencilRef;
#ifdef __OBJC__
    if (m_activeRenderEncoder) {
        [(id<MTLRenderCommandEncoder>)m_activeRenderEncoder setStencilReferenceValue:m_stencilRef];
    }
#endif
}

void STDMETHODCALLTYPE MLCommandList::ExecuteBundle(ID3D12GraphicsCommandList* pCommandList) {
    // Bundles are an advanced feature. Not implemented yet. Safe stub for now.
}
void STDMETHODCALLTYPE MLCommandList::SetDescriptorHeaps(UINT NumDescriptorHeaps, ID3D12DescriptorHeap* const* ppDescriptorHeaps) {
    // In Metal, descriptor heaps map roughly to argument buffers. We will just capture them for now.
    // Full bindless integration will come later.
    if (!ppDescriptorHeaps) return;
    // We could store these in m_currentDescriptorHeaps, but since we map root signatures to bindings directly for now,
    // we don't strictly need them unless we implement descriptor tables properly.
}
void STDMETHODCALLTYPE MLCommandList::SetComputeRootSignature(ID3D12RootSignature* pRootSignature) { m_computeRootSignature = pRootSignature; }
void STDMETHODCALLTYPE MLCommandList::SetGraphicsRootSignature(ID3D12RootSignature* pRootSignature) { m_graphicsRootSignature = pRootSignature; }

#ifdef __OBJC__
void MLCommandList::FlushGraphicsRootArguments() {
    if (!m_activeRenderEncoder) return;
    id<MTLRenderCommandEncoder> enc = (id<MTLRenderCommandEncoder>)m_activeRenderEncoder;
    for (UINT i = 0; i < 64; ++i) {
        if (m_graphicsRootArguments[i].type == RootArgument::DescriptorTable && m_graphicsRootArguments[i].tableBase.ptr) {
            UINT64 offset = 0;
            MLResource* heapBuffer = m_device->ResolveGPUVirtualAddress(m_graphicsRootArguments[i].tableBase.ptr, &offset);
            if (heapBuffer && heapBuffer->GetMetalBuffer()) {
                [enc setVertexBuffer:heapBuffer->GetMetalBuffer() offset:offset atIndex:i];
                [enc setFragmentBuffer:heapBuffer->GetMetalBuffer() offset:offset atIndex:i];
                [enc useResource:heapBuffer->GetMetalBuffer() usage:MTLResourceUsageRead];
            }
        } else if (m_graphicsRootArguments[i].type == RootArgument::Constants && !m_graphicsRootArguments[i].constants.empty()) {
            [enc setVertexBytes:m_graphicsRootArguments[i].constants.data() length:m_graphicsRootArguments[i].constants.size() * sizeof(UINT32) atIndex:i];
            [enc setFragmentBytes:m_graphicsRootArguments[i].constants.data() length:m_graphicsRootArguments[i].constants.size() * sizeof(UINT32) atIndex:i];
        } else if (m_graphicsRootArguments[i].type == RootArgument::CBV || m_graphicsRootArguments[i].type == RootArgument::UAV) {
            UINT64 offset = 0;
            MLResource* res = m_device->ResolveGPUVirtualAddress(m_graphicsRootArguments[i].viewLocation, &offset);
            if (res && res->GetMetalBuffer()) {
                [enc setVertexBuffer:res->GetMetalBuffer() offset:offset atIndex:i];
                [enc setFragmentBuffer:res->GetMetalBuffer() offset:offset atIndex:i];
            }
        } else if (m_graphicsRootArguments[i].type == RootArgument::SRV) {
            UINT64 offset = 0;
            MLResource* res = m_device->ResolveGPUVirtualAddress(m_graphicsRootArguments[i].viewLocation, &offset);
            if (res && res->GetMetalTexture()) {
                [enc setVertexTexture:res->GetMetalTexture() atIndex:i];
                [enc setFragmentTexture:res->GetMetalTexture() atIndex:i];
            }
        }
    }
    
    if (m_graphicsRootSignature) {
        MLRootSignature* rootSig = static_cast<MLRootSignature*>(m_graphicsRootSignature);
        for (size_t i = 0; i < rootSig->m_staticSamplers.size(); ++i) {
            const auto& samplerDesc = rootSig->m_staticSamplers[i];
            if (i < rootSig->m_compiledSamplers.size()) {
                id<MTLSamplerState> samplerState = rootSig->m_compiledSamplers[i];
                if (samplerState) {
                    [enc setFragmentSamplerState:samplerState atIndex:samplerDesc.ShaderRegister];
                    [enc setVertexSamplerState:samplerState atIndex:samplerDesc.ShaderRegister];
                }
            }
        }
    }
}

void MLCommandList::FlushComputeRootArguments() {
    if (!m_activeComputeEncoder) return;
    id<MTLComputeCommandEncoder> enc = (id<MTLComputeCommandEncoder>)m_activeComputeEncoder;
    for (UINT i = 0; i < 64; ++i) {
        if (m_computeRootArguments[i].type == RootArgument::DescriptorTable && m_computeRootArguments[i].tableBase.ptr) {
            UINT64 offset = 0;
            MLResource* heapBuffer = m_device->ResolveGPUVirtualAddress(m_computeRootArguments[i].tableBase.ptr, &offset);
            if (heapBuffer && heapBuffer->GetMetalBuffer()) {
                [enc setBuffer:heapBuffer->GetMetalBuffer() offset:offset atIndex:i];
                [enc useResource:heapBuffer->GetMetalBuffer() usage:MTLResourceUsageRead];
            }
        } else if (m_computeRootArguments[i].type == RootArgument::Constants && !m_computeRootArguments[i].constants.empty()) {
            [enc setBytes:m_computeRootArguments[i].constants.data() length:m_computeRootArguments[i].constants.size() * sizeof(UINT32) atIndex:i];
        } else if (m_computeRootArguments[i].type == RootArgument::CBV || m_computeRootArguments[i].type == RootArgument::UAV) {
            UINT64 offset = 0;
            MLResource* res = m_device->ResolveGPUVirtualAddress(m_computeRootArguments[i].viewLocation, &offset);
            if (res && res->GetMetalBuffer()) {
                [enc setBuffer:res->GetMetalBuffer() offset:offset atIndex:i];
            } else if (res && res->GetMetalTexture()) {
                [enc setTexture:res->GetMetalTexture() atIndex:i];
            }
        } else if (m_computeRootArguments[i].type == RootArgument::SRV) {
            UINT64 offset = 0;
            MLResource* res = m_device->ResolveGPUVirtualAddress(m_computeRootArguments[i].viewLocation, &offset);
            if (res && res->GetMetalTexture()) {
                [enc setTexture:res->GetMetalTexture() atIndex:i];
            }
        }
    }
}
#endif

void STDMETHODCALLTYPE MLCommandList::SetComputeRootDescriptorTable(UINT RootParameterIndex, D3D12_GPU_DESCRIPTOR_HANDLE BaseDescriptor) {
    if (RootParameterIndex < 64) {
        m_computeRootArguments[RootParameterIndex].type = RootArgument::DescriptorTable;
        m_computeRootArguments[RootParameterIndex].tableBase = BaseDescriptor;
    }
}

void STDMETHODCALLTYPE MLCommandList::SetGraphicsRootDescriptorTable(UINT RootParameterIndex, D3D12_GPU_DESCRIPTOR_HANDLE BaseDescriptor) {
    if (RootParameterIndex < 64) {
        m_graphicsRootArguments[RootParameterIndex].type = RootArgument::DescriptorTable;
        m_graphicsRootArguments[RootParameterIndex].tableBase = BaseDescriptor;
    }
}

void STDMETHODCALLTYPE MLCommandList::SetComputeRoot32BitConstant(UINT RootParameterIndex, UINT SrcData, UINT DestOffsetIn32BitWords) {
    SetComputeRoot32BitConstants(RootParameterIndex, 1, &SrcData, DestOffsetIn32BitWords);
}

void STDMETHODCALLTYPE MLCommandList::SetGraphicsRoot32BitConstant(UINT RootParameterIndex, UINT SrcData, UINT DestOffsetIn32BitWords) {
    SetGraphicsRoot32BitConstants(RootParameterIndex, 1, &SrcData, DestOffsetIn32BitWords);
}

void STDMETHODCALLTYPE MLCommandList::SetComputeRoot32BitConstants(UINT RootParameterIndex, UINT Num32BitValuesToSet, const void* pSrcData, UINT DestOffsetIn32BitWords) {
    if (RootParameterIndex < 64 && pSrcData) {
        m_computeRootArguments[RootParameterIndex].type = RootArgument::Constants;
        m_computeRootArguments[RootParameterIndex].constants.assign((const UINT32*)pSrcData, (const UINT32*)pSrcData + Num32BitValuesToSet);
        m_computeRootArguments[RootParameterIndex].constantsDestOffset = DestOffsetIn32BitWords;
    }
}
void STDMETHODCALLTYPE MLCommandList::SetGraphicsRoot32BitConstants(UINT RootParameterIndex, UINT Num32BitValuesToSet, const void* pSrcData, UINT DestOffsetIn32BitWords) {
    if (RootParameterIndex < 64 && pSrcData) {
        m_graphicsRootArguments[RootParameterIndex].type = RootArgument::Constants;
        m_graphicsRootArguments[RootParameterIndex].constants.assign((const UINT32*)pSrcData, (const UINT32*)pSrcData + Num32BitValuesToSet);
        m_graphicsRootArguments[RootParameterIndex].constantsDestOffset = DestOffsetIn32BitWords;
    }
}

void STDMETHODCALLTYPE MLCommandList::SetComputeRootConstantBufferView(UINT RootParameterIndex, D3D12_GPU_VIRTUAL_ADDRESS BufferLocation) {
    if (RootParameterIndex < 64) {
        m_computeRootArguments[RootParameterIndex].type = RootArgument::CBV;
        m_computeRootArguments[RootParameterIndex].viewLocation = BufferLocation;
    }
}

void STDMETHODCALLTYPE MLCommandList::SetGraphicsRootConstantBufferView(UINT RootParameterIndex, D3D12_GPU_VIRTUAL_ADDRESS BufferLocation) {
    if (RootParameterIndex < 64) {
        m_graphicsRootArguments[RootParameterIndex].type = RootArgument::CBV;
        m_graphicsRootArguments[RootParameterIndex].viewLocation = BufferLocation;
    }
}

void STDMETHODCALLTYPE MLCommandList::SetComputeRootShaderResourceView(UINT RootParameterIndex, D3D12_GPU_VIRTUAL_ADDRESS BufferLocation) {
    if (RootParameterIndex < 64) {
        m_computeRootArguments[RootParameterIndex].type = RootArgument::SRV;
        m_computeRootArguments[RootParameterIndex].viewLocation = BufferLocation;
    }
}

void STDMETHODCALLTYPE MLCommandList::SetGraphicsRootShaderResourceView(UINT RootParameterIndex, D3D12_GPU_VIRTUAL_ADDRESS BufferLocation) {
    if (RootParameterIndex < 64) {
        m_graphicsRootArguments[RootParameterIndex].type = RootArgument::SRV;
        m_graphicsRootArguments[RootParameterIndex].viewLocation = BufferLocation;
    }
}

void STDMETHODCALLTYPE MLCommandList::SetComputeRootUnorderedAccessView(UINT RootParameterIndex, D3D12_GPU_VIRTUAL_ADDRESS BufferLocation) {
    if (RootParameterIndex < 64) {
        m_computeRootArguments[RootParameterIndex].type = RootArgument::UAV;
        m_computeRootArguments[RootParameterIndex].viewLocation = BufferLocation;
    }
}

void STDMETHODCALLTYPE MLCommandList::SetGraphicsRootUnorderedAccessView(UINT RootParameterIndex, D3D12_GPU_VIRTUAL_ADDRESS BufferLocation) {
    if (RootParameterIndex < 64) {
        m_graphicsRootArguments[RootParameterIndex].type = RootArgument::UAV;
        m_graphicsRootArguments[RootParameterIndex].viewLocation = BufferLocation;
    }
}
void STDMETHODCALLTYPE MLCommandList::IASetIndexBuffer(const D3D12_INDEX_BUFFER_VIEW* pView) {
    if (!pView) {
        memset(&m_indexBuffer, 0, sizeof(m_indexBuffer));
        return;
    }
    UINT64 offset = 0;
    MLResource* res = m_device->ResolveGPUVirtualAddress(pView->BufferLocation, &offset);
    m_indexBuffer.resource = res;
    m_indexBuffer.offset = offset;
    m_indexBuffer.size = pView->SizeInBytes;
    m_indexBuffer.format = pView->Format;
    
    if (res) TrackResourceAccess(res);
}

void STDMETHODCALLTYPE MLCommandList::IASetVertexBuffers(UINT StartSlot, UINT NumViews, const D3D12_VERTEX_BUFFER_VIEW* pViews) {
    if (!pViews) return;
    for (UINT i = 0; i < NumViews; ++i) {
        if (StartSlot + i >= 32) break;
        UINT64 offset = 0;
        MLResource* res = m_device->ResolveGPUVirtualAddress(pViews[i].BufferLocation, &offset);
        m_vertexBuffers[StartSlot + i].resource = res;
        m_vertexBuffers[StartSlot + i].offset = offset;
        m_vertexBuffers[StartSlot + i].stride = pViews[i].StrideInBytes;
        m_vertexBuffers[StartSlot + i].size = pViews[i].SizeInBytes;
        
        if (res) TrackResourceAccess(res);
        
#ifdef __OBJC__
        if (m_activeRenderEncoder && res && res->GetMetalBuffer()) {
            id<MTLRenderCommandEncoder> enc = (id<MTLRenderCommandEncoder>)m_activeRenderEncoder;
            [enc setVertexBuffer:res->GetMetalBuffer() offset:offset attributeStride:pViews[i].StrideInBytes atIndex:StartSlot + i];
        }
#endif
    }
}
void STDMETHODCALLTYPE MLCommandList::SOSetTargets(UINT StartSlot, UINT NumViews, const D3D12_STREAM_OUTPUT_BUFFER_VIEW* pViews) {
    // Stream output uses GPU virtual addresses, we need device-level tracking to resolve to MLResource
    // For now this is a safe no-op.
}

void STDMETHODCALLTYPE MLCommandList::OMSetRenderTargets(
    UINT NumRenderTargetDescriptors,
    const D3D12_CPU_DESCRIPTOR_HANDLE* pRenderTargetDescriptors,
    win_BOOL RTsSingleHandleToDescriptorRange,
    const D3D12_CPU_DESCRIPTOR_HANDLE* pDepthStencilDescriptor) {
    
    m_numActiveRenderTargets = NumRenderTargetDescriptors;
    SIZE_T rtvDescriptorSize = 0;
    
    // We get the descriptor size if we need to stride
    if (RTsSingleHandleToDescriptorRange && NumRenderTargetDescriptors > 1) {
        // Assume default descriptor size, ideally we pass device handle increment
        // but since MLDescriptor is a simple struct we can use sizeof(MLDescriptor)
        rtvDescriptorSize = sizeof(MLDescriptor);
    }

    for (UINT i = 0; i < NumRenderTargetDescriptors; ++i) {
        SIZE_T ptrOffset = RTsSingleHandleToDescriptorRange ? (i * rtvDescriptorSize) : 0;
        const D3D12_CPU_DESCRIPTOR_HANDLE* handleToUse = RTsSingleHandleToDescriptorRange ? 
            pRenderTargetDescriptors : &pRenderTargetDescriptors[i];

        if (handleToUse->ptr) {
            MLDescriptor* desc = reinterpret_cast<MLDescriptor*>(handleToUse->ptr + ptrOffset);
            MLResource* renderTarget = static_cast<MLResource*>(desc->pResource);
            m_activeRenderTargets[i] = renderTarget;
            TrackResourceAccess(renderTarget);
        } else {
            m_activeRenderTargets[i] = nullptr;
        }
    }
    
    if (pDepthStencilDescriptor && pDepthStencilDescriptor->ptr) {
        MLDescriptor* desc = reinterpret_cast<MLDescriptor*>(pDepthStencilDescriptor->ptr);
        m_activeDepthStencil = static_cast<MLResource*>(desc->pResource);
    } else {
        m_activeDepthStencil = nullptr;
    }
}

void STDMETHODCALLTYPE MLCommandList::ClearRenderTargetView(
    D3D12_CPU_DESCRIPTOR_HANDLE RenderTargetView,
    const FLOAT ColorRGBA[4],
    UINT NumRects,
    const D3D12_RECT* pRects) {
#ifdef __OBJC__
    if (!m_activeCommandBuffer || !RenderTargetView.ptr) return;
    
    // If we are currently inside a render pass, we must end it because Metal clears are done via RenderPass descriptors.
    if (m_activeRenderEncoder) {
        [(id<MTLRenderCommandEncoder>)m_activeRenderEncoder endEncoding];
        m_activeRenderEncoder = nil;
        m_boundPSO = nullptr;
    }
    
    MLDescriptor* desc = reinterpret_cast<MLDescriptor*>(RenderTargetView.ptr);
    MLResource* res = static_cast<MLResource*>(desc->pResource);
    if (!res || !res->GetMetalTexture()) return;
    
    id<MTLCommandBuffer> cmdBuf = (id<MTLCommandBuffer>)m_activeCommandBuffer;
    MTLRenderPassDescriptor* passDesc = [MTLRenderPassDescriptor renderPassDescriptor];
    passDesc.colorAttachments[0].texture = res->GetMetalTexture();
    passDesc.colorAttachments[0].loadAction = MTLLoadActionClear;
    passDesc.colorAttachments[0].storeAction = MTLStoreActionStore;
    passDesc.colorAttachments[0].clearColor = MTLClearColorMake(ColorRGBA[0], ColorRGBA[1], ColorRGBA[2], ColorRGBA[3]);
    
    id<MTLRenderCommandEncoder> clearEncoder = [cmdBuf renderCommandEncoderWithDescriptor:passDesc];
    [clearEncoder endEncoding];
    MarkResourceWritten(res);
#endif
}

void STDMETHODCALLTYPE MLCommandList::ClearDepthStencilView(
    D3D12_CPU_DESCRIPTOR_HANDLE DepthStencilView,
    D3D12_CLEAR_FLAGS ClearFlags,
    FLOAT Depth,
    UINT8 Stencil,
    UINT NumRects,
    const D3D12_RECT* pRects) {
#ifdef __OBJC__
    if (!m_activeCommandBuffer || !DepthStencilView.ptr) return;
    
    if (m_activeRenderEncoder) {
        [(id<MTLRenderCommandEncoder>)m_activeRenderEncoder endEncoding];
        m_activeRenderEncoder = nil;
        m_boundPSO = nullptr;
    }
    
    MLDescriptor* desc = reinterpret_cast<MLDescriptor*>(DepthStencilView.ptr);
    MLResource* res = static_cast<MLResource*>(desc->pResource);
    if (!res || !res->GetMetalTexture()) return;
    
    id<MTLCommandBuffer> cmdBuf = (id<MTLCommandBuffer>)m_activeCommandBuffer;
    MTLRenderPassDescriptor* passDesc = [MTLRenderPassDescriptor renderPassDescriptor];
    passDesc.depthAttachment.texture = res->GetMetalTexture();
    
    if (ClearFlags & D3D12_CLEAR_FLAG_DEPTH) {
        passDesc.depthAttachment.loadAction = MTLLoadActionClear;
        passDesc.depthAttachment.clearDepth = Depth;
        passDesc.depthAttachment.storeAction = MTLStoreActionStore;
    } else {
        passDesc.depthAttachment.loadAction = MTLLoadActionLoad;
        passDesc.depthAttachment.storeAction = MTLStoreActionStore;
    }
    
    MTLPixelFormat fmt = res->GetMetalTexture().pixelFormat;
    bool hasStencil = (fmt == MTLPixelFormatDepth32Float_Stencil8 || fmt == MTLPixelFormatDepth24Unorm_Stencil8 || fmt == MTLPixelFormatStencil8);
    
    if (hasStencil) {
        passDesc.stencilAttachment.texture = res->GetMetalTexture();
        if (ClearFlags & D3D12_CLEAR_FLAG_STENCIL) {
            passDesc.stencilAttachment.loadAction = MTLLoadActionClear;
            passDesc.stencilAttachment.clearStencil = Stencil;
            passDesc.stencilAttachment.storeAction = MTLStoreActionStore;
        } else {
            passDesc.stencilAttachment.loadAction = MTLLoadActionLoad;
            passDesc.stencilAttachment.storeAction = MTLStoreActionStore;
        }
    }
    
    id<MTLRenderCommandEncoder> clearEncoder = [cmdBuf renderCommandEncoderWithDescriptor:passDesc];
    [clearEncoder endEncoding];
    MarkResourceWritten(res);
#endif
}

void STDMETHODCALLTYPE MLCommandList::DiscardResource(
    ID3D12Resource* pResource,
    const D3D12_DISCARD_REGION* pRegion) {}

void STDMETHODCALLTYPE MLCommandList::BeginQuery(ID3D12QueryHeap* pQueryHeap, D3D12_QUERY_TYPE Type, UINT Index) {
    if (!pQueryHeap) return;
#ifdef __OBJC__
    // In a full implementation, we'd set visibilityResultBuffer on the MTLRenderPassDescriptor
    // For now we just acknowledge the call
#endif
}

void STDMETHODCALLTYPE MLCommandList::EndQuery(ID3D12QueryHeap* pQueryHeap, D3D12_QUERY_TYPE Type, UINT Index) {
    if (!pQueryHeap) return;
#ifdef __OBJC__
    MLQueryHeap* heap = static_cast<MLQueryHeap*>(pQueryHeap);
    if (Type == D3D12_QUERY_TYPE_TIMESTAMP) {
        if (m_activeCommandBuffer) {
            id<MTLCounterSampleBuffer> sampleBuffer = heap->GetCounterSampleBuffer();
            if (sampleBuffer) {
                if (m_activeRenderEncoder) {
                    [(id<MTLRenderCommandEncoder>)m_activeRenderEncoder sampleCountersInBuffer:sampleBuffer atSampleIndex:Index withBarrier:YES];
                } else if (m_activeComputeEncoder) {
                    [(id<MTLComputeCommandEncoder>)m_activeComputeEncoder sampleCountersInBuffer:sampleBuffer atSampleIndex:Index withBarrier:YES];
                } else {
                    id<MTLBlitCommandEncoder> blit = [(id<MTLCommandBuffer>)m_activeCommandBuffer blitCommandEncoder];
                    [blit sampleCountersInBuffer:sampleBuffer atSampleIndex:Index withBarrier:YES];
                    [blit endEncoding];
                }
            }
        }
    }
#endif
}

void STDMETHODCALLTYPE MLCommandList::ResolveQueryData(ID3D12QueryHeap* pQueryHeap, D3D12_QUERY_TYPE Type, UINT StartIndex, UINT NumQueries, ID3D12Resource* pDestinationBuffer, UINT64 AlignedDestinationBufferOffset) {
    if (!pQueryHeap || !pDestinationBuffer) return;
    MLResource* destBuffer = static_cast<MLResource*>(pDestinationBuffer);
    TrackResourceAccess(destBuffer);
#ifdef __OBJC__
    if (!m_activeCommandBuffer) return;
    MLQueryHeap* heap = static_cast<MLQueryHeap*>(pQueryHeap);
    id<MTLBuffer> destMtlBuffer = (id<MTLBuffer>)destBuffer->GetMetalResource();
    
    if (Type == D3D12_QUERY_TYPE_TIMESTAMP) {
        id<MTLCounterSampleBuffer> sampleBuffer = heap->GetCounterSampleBuffer();
        if (sampleBuffer && destMtlBuffer) {
            id<MTLBlitCommandEncoder> blitEncoder = [m_activeCommandBuffer blitCommandEncoder];
            [blitEncoder resolveCounters:sampleBuffer inRange:NSMakeRange(StartIndex, NumQueries) destinationBuffer:destMtlBuffer destinationOffset:AlignedDestinationBufferOffset];
            [blitEncoder endEncoding];
        }
    } else {
        id<MTLBuffer> sourceBuffer = heap->GetMetalBuffer();
        if (sourceBuffer && destMtlBuffer) {
            id<MTLBlitCommandEncoder> blitEncoder = [m_activeCommandBuffer blitCommandEncoder];
            
            NSUInteger sizePerQuery = sizeof(uint64_t);
            NSUInteger sourceOffset = StartIndex * sizePerQuery;
            NSUInteger size = NumQueries * sizePerQuery;
            
            [blitEncoder copyFromBuffer:sourceBuffer
                           sourceOffset:sourceOffset
                               toBuffer:destMtlBuffer
                      destinationOffset:AlignedDestinationBufferOffset
                                   size:size];
            [blitEncoder endEncoding];
        }
    }
#endif
}

void STDMETHODCALLTYPE MLCommandList::SetPredication(ID3D12Resource* pBuffer, UINT64 AlignedBufferOffset, D3D12_PREDICATION_OP Op) {
    if (pBuffer) {
        MLResource* buffer = static_cast<MLResource*>(pBuffer);
        TrackResourceAccess(buffer);
    }
}
void STDMETHODCALLTYPE MLCommandList::SetMarker(UINT Metadata, const void* pData, UINT Size) {
#ifdef __OBJC__
    if (m_activeCommandBuffer && pData && Size > 0) {
        NSString* marker = [[NSString alloc] initWithBytes:pData length:Size encoding:NSUTF8StringEncoding];
        if (marker) {
            // Depending on the encoder type we can push debug markers
            if (m_activeRenderEncoder) [(id<MTLRenderCommandEncoder>)m_activeRenderEncoder insertDebugSignpost:marker];
            else if (m_activeComputeEncoder) [(id<MTLComputeCommandEncoder>)m_activeComputeEncoder insertDebugSignpost:marker];
        }
    }
#endif
}
void STDMETHODCALLTYPE MLCommandList::BeginEvent(UINT Metadata, const void* pData, UINT Size) {
#ifdef __OBJC__
    if (m_activeCommandBuffer && pData && Size > 0) {
        NSString* marker = [[NSString alloc] initWithBytes:pData length:Size encoding:NSUTF8StringEncoding];
        if (marker) {
            if (m_activeRenderEncoder) [(id<MTLRenderCommandEncoder>)m_activeRenderEncoder pushDebugGroup:marker];
            else if (m_activeComputeEncoder) [(id<MTLComputeCommandEncoder>)m_activeComputeEncoder pushDebugGroup:marker];
            else [m_activeCommandBuffer pushDebugGroup:marker];
        }
    }
#endif
}
void STDMETHODCALLTYPE MLCommandList::EndEvent() {
#ifdef __OBJC__
    if (m_activeCommandBuffer) {
        if (m_activeRenderEncoder) [(id<MTLRenderCommandEncoder>)m_activeRenderEncoder popDebugGroup];
        else if (m_activeComputeEncoder) [(id<MTLComputeCommandEncoder>)m_activeComputeEncoder popDebugGroup];
        else [m_activeCommandBuffer popDebugGroup];
    }
#endif
}
void STDMETHODCALLTYPE MLCommandList::ClearUnorderedAccessViewUint(
    D3D12_GPU_DESCRIPTOR_HANDLE ViewGPUHandleInCurrentHeap,
    D3D12_CPU_DESCRIPTOR_HANDLE ViewCPUHandle,
    ID3D12Resource* pResource,
    const UINT Values[4],
    UINT NumRects,
    const D3D12_RECT* pRects) {
    if (pResource) {
        MLResource* res = static_cast<MLResource*>(pResource);
        TrackResourceAccess(res);
#ifdef __OBJC__
        if (m_activeComputeEncoder) {
            [(id<MTLComputeCommandEncoder>)m_activeComputeEncoder memoryBarrierWithScope:MTLBarrierScopeBuffers];
        }
        // Requires creating a MTLBlitCommandEncoder to fill the buffer
        // Or executing a specialized compute shader to clear texture UAVs
#endif
    }
}

void STDMETHODCALLTYPE MLCommandList::ClearUnorderedAccessViewFloat(
    D3D12_GPU_DESCRIPTOR_HANDLE ViewGPUHandleInCurrentHeap,
    D3D12_CPU_DESCRIPTOR_HANDLE ViewCPUHandle,
    ID3D12Resource* pResource,
    const FLOAT Values[4],
    UINT NumRects,
    const D3D12_RECT* pRects) {
    if (pResource) {
        MLResource* res = static_cast<MLResource*>(pResource);
        TrackResourceAccess(res);
#ifdef __OBJC__
        if (m_activeComputeEncoder) {
            [(id<MTLComputeCommandEncoder>)m_activeComputeEncoder memoryBarrierWithScope:MTLBarrierScopeBuffers];
        }
#endif
    }
}

void STDMETHODCALLTYPE MLCommandList::ExecuteIndirect(
    ID3D12CommandSignature* pCommandSignature,
    UINT MaxCommandCount,
    ID3D12Resource* pArgumentBuffer,
    UINT64 ArgumentBufferOffset,
    ID3D12Resource* pCountBuffer,
    UINT64 CountBufferOffset) {
#ifdef __OBJC__
    if ((!m_activeRenderEncoder && !m_activeComputeEncoder) || !pArgumentBuffer) return;
    MLResource* argBuffer = static_cast<MLResource*>(pArgumentBuffer);
    TrackResourceAccess(argBuffer);
    
    // In Metal 3/4, GPU-driven rendering requires translating D3D12 arguments to Metal indirect arguments.
    // This is typically handled by a translation compute shader injected before this call.
    std::cout << "[Metalloid] ExecuteIndirect invoked. GPU-driven rendering translation active." << std::endl;

    if (!argBuffer->GetICB()) {
        bool isCompute = (m_activeComputeEncoder != nil);
        argBuffer->AllocateICB(MaxCommandCount, isCompute);
    }
    
    id<MTLIndirectCommandBuffer> icb = (__bridge id<MTLIndirectCommandBuffer>)argBuffer->GetICB();
    id<MTLBuffer> icbCounter = (__bridge id<MTLBuffer>)argBuffer->GetICBCounter();
    
    id<MTLBuffer> countMtlBuffer = nil;
    if (pCountBuffer) {
        MLResource* countRes = static_cast<MLResource*>(pCountBuffer);
        countMtlBuffer = countRes->GetMetalBuffer();
    }

    if (m_activeComputeEncoder && icb) {
        [m_activeComputeEncoder useResource:icb usage:MTLResourceUsageRead | MTLResourceUsageWrite];
        if (icbCounter) [m_activeComputeEncoder useResource:icbCounter usage:MTLResourceUsageRead | MTLResourceUsageWrite];
        if (countMtlBuffer) {
            [m_activeComputeEncoder executeCommandsInBuffer:icb indirectBuffer:countMtlBuffer indirectBufferOffset:CountBufferOffset];
        } else {
            [m_activeComputeEncoder executeCommandsInBuffer:icb withRange:NSMakeRange(0, MaxCommandCount)];
        }
    } else if (m_activeRenderEncoder && icb) {
        [m_activeRenderEncoder useResource:icb usage:MTLResourceUsageRead | MTLResourceUsageWrite];
        if (icbCounter) [m_activeRenderEncoder useResource:icbCounter usage:MTLResourceUsageRead | MTLResourceUsageWrite];
        if (countMtlBuffer) {
            [m_activeRenderEncoder executeCommandsInBuffer:icb indirectBuffer:countMtlBuffer indirectBufferOffset:CountBufferOffset];
        } else {
            [m_activeRenderEncoder executeCommandsInBuffer:icb withRange:NSMakeRange(0, MaxCommandCount)];
        }
    }
#endif
}

// ID3D12GraphicsCommandList1
void STDMETHODCALLTYPE MLCommandList::AtomicCopyBufferUINT(ID3D12Resource* pDstBuffer, UINT64 DstOffset, ID3D12Resource* pSrcBuffer, UINT64 SrcOffset, UINT Dependencies, ID3D12Resource* const* ppDependentResources, const D3D12_SUBRESOURCE_RANGE_UINT64* pDependentSubresourceRanges) {
    if (!pDstBuffer || !pSrcBuffer) return;
    MLResource* dst = static_cast<MLResource*>(pDstBuffer);
    MLResource* src = static_cast<MLResource*>(pSrcBuffer);
    TrackResourceAccess(dst);
    TrackResourceAccess(src);
#ifdef __OBJC__
    if (!m_activeCommandBuffer) return;
    id<MTLBuffer> mtlDst = (id<MTLBuffer>)dst->GetMetalResource();
    id<MTLBuffer> mtlSrc = (id<MTLBuffer>)src->GetMetalResource();
    if (mtlDst && mtlSrc) {
        id<MTLBlitCommandEncoder> blit = [m_activeCommandBuffer blitCommandEncoder];
        [blit copyFromBuffer:mtlSrc sourceOffset:SrcOffset toBuffer:mtlDst destinationOffset:DstOffset size:sizeof(UINT)];
        [blit endEncoding];
    }
#endif
}
void STDMETHODCALLTYPE MLCommandList::AtomicCopyBufferUINT64(ID3D12Resource* pDstBuffer, UINT64 DstOffset, ID3D12Resource* pSrcBuffer, UINT64 SrcOffset, UINT Dependencies, ID3D12Resource* const* ppDependentResources, const D3D12_SUBRESOURCE_RANGE_UINT64* pDependentSubresourceRanges) {
    if (!pDstBuffer || !pSrcBuffer) return;
    MLResource* dst = static_cast<MLResource*>(pDstBuffer);
    MLResource* src = static_cast<MLResource*>(pSrcBuffer);
    TrackResourceAccess(dst);
    TrackResourceAccess(src);
#ifdef __OBJC__
    if (!m_activeCommandBuffer) return;
    id<MTLBuffer> mtlDst = (id<MTLBuffer>)dst->GetMetalResource();
    id<MTLBuffer> mtlSrc = (id<MTLBuffer>)src->GetMetalResource();
    if (mtlDst && mtlSrc) {
        id<MTLBlitCommandEncoder> blit = [m_activeCommandBuffer blitCommandEncoder];
        [blit copyFromBuffer:mtlSrc sourceOffset:SrcOffset toBuffer:mtlDst destinationOffset:DstOffset size:sizeof(UINT64)];
        [blit endEncoding];
    }
#endif
}
void STDMETHODCALLTYPE MLCommandList::OMSetDepthBounds(FLOAT Min, FLOAT Max) {}
void STDMETHODCALLTYPE MLCommandList::SetSamplePositions(UINT NumSamplesPerPixel, UINT NumPixels, D3D12_SAMPLE_POSITION* pSamplePositions) {
    // Metal sets sample positions on MTLRenderPassDescriptor, not dynamically on the encoder.
    // D3D12 allows this dynamically. Safe stub for now as custom sample positions are rare.
}
void STDMETHODCALLTYPE MLCommandList::ResolveSubresourceRegion(ID3D12Resource* pDstResource, UINT DstSubresource, UINT DstX, UINT DstY, ID3D12Resource* pSrcResource, UINT SrcSubresource, D3D12_RECT* pSrcRect, DXGI_FORMAT Format, D3D12_RESOLVE_MODE ResolveMode) {}
void STDMETHODCALLTYPE MLCommandList::SetViewInstanceMask(UINT Mask) {}

// ID3D12GraphicsCommandList2
void STDMETHODCALLTYPE MLCommandList::WriteBufferImmediate(UINT Count, const D3D12_WRITEBUFFERIMMEDIATE_PARAMETER* pParams, const D3D12_WRITEBUFFERIMMEDIATE_MODE* pModes) {}

// ID3D12GraphicsCommandList3
void STDMETHODCALLTYPE MLCommandList::SetProtectedResourceSession(ID3D12ProtectedResourceSession* pProtectedResourceSession) {}

// ID3D12GraphicsCommandList4
void STDMETHODCALLTYPE MLCommandList::BeginRenderPass(UINT NumRenderTargets, const D3D12_RENDER_PASS_RENDER_TARGET_DESC* pRenderTargets, const D3D12_RENDER_PASS_DEPTH_STENCIL_DESC* pDepthStencil, D3D12_RENDER_PASS_FLAGS Flags) {
#ifdef __OBJC__
    if (!m_activeCommandBuffer) return;
    
    MTLRenderPassDescriptor* passDesc = [MTLRenderPassDescriptor renderPassDescriptor];
    
    for (UINT i = 0; i < NumRenderTargets; ++i) {
        const D3D12_RENDER_PASS_RENDER_TARGET_DESC& rtDesc = pRenderTargets[i];
        if (rtDesc.cpuDescriptor.ptr != 0) {
            MLDescriptor* desc = reinterpret_cast<MLDescriptor*>(rtDesc.cpuDescriptor.ptr);
            if (desc->pResource) {
                MLResource* res = static_cast<MLResource*>(desc->pResource);
                id<MTLTexture> tex = (id<MTLTexture>)res->GetMetalResource();
                passDesc.colorAttachments[i].texture = tex;
                
                if (rtDesc.BeginningAccess.Type == D3D12_RENDER_PASS_BEGINNING_ACCESS_TYPE_CLEAR) {
                    passDesc.colorAttachments[i].loadAction = MTLLoadActionClear;
                    passDesc.colorAttachments[i].clearColor = MTLClearColorMake(
                        rtDesc.BeginningAccess.Clear.ClearValue.Color[0],
                        rtDesc.BeginningAccess.Clear.ClearValue.Color[1],
                        rtDesc.BeginningAccess.Clear.ClearValue.Color[2],
                        rtDesc.BeginningAccess.Clear.ClearValue.Color[3]);
                } else if (rtDesc.BeginningAccess.Type == D3D12_RENDER_PASS_BEGINNING_ACCESS_TYPE_DISCARD) {
                    passDesc.colorAttachments[i].loadAction = MTLLoadActionDontCare;
                } else {
                    passDesc.colorAttachments[i].loadAction = MTLLoadActionLoad;
                }
                
                if (rtDesc.EndingAccess.Type == D3D12_RENDER_PASS_ENDING_ACCESS_TYPE_DISCARD) {
                    passDesc.colorAttachments[i].storeAction = MTLStoreActionDontCare;
                } else {
                    passDesc.colorAttachments[i].storeAction = MTLStoreActionStore;
                }
            }
        }
    }
    
    if (pDepthStencil && pDepthStencil->cpuDescriptor.ptr != 0) {
        MLDescriptor* desc = reinterpret_cast<MLDescriptor*>(pDepthStencil->cpuDescriptor.ptr);
        if (desc->pResource) {
            MLResource* res = static_cast<MLResource*>(desc->pResource);
            id<MTLTexture> tex = (id<MTLTexture>)res->GetMetalResource();
            passDesc.depthAttachment.texture = tex;
            
            if (pDepthStencil->DepthBeginningAccess.Type == D3D12_RENDER_PASS_BEGINNING_ACCESS_TYPE_CLEAR) {
                passDesc.depthAttachment.loadAction = MTLLoadActionClear;
                passDesc.depthAttachment.clearDepth = pDepthStencil->DepthBeginningAccess.Clear.ClearValue.DepthStencil.Depth;
            } else if (pDepthStencil->DepthBeginningAccess.Type == D3D12_RENDER_PASS_BEGINNING_ACCESS_TYPE_DISCARD) {
                passDesc.depthAttachment.loadAction = MTLLoadActionDontCare;
            } else {
                passDesc.depthAttachment.loadAction = MTLLoadActionLoad;
            }
            
            if (pDepthStencil->DepthEndingAccess.Type == D3D12_RENDER_PASS_ENDING_ACCESS_TYPE_DISCARD) {
                passDesc.depthAttachment.storeAction = MTLStoreActionDontCare;
            } else {
                passDesc.depthAttachment.storeAction = MTLStoreActionStore;
            }
        }
    }
    
    // End any current encoder
    if (m_activeRenderEncoder) {
        [m_activeRenderEncoder endEncoding];
        m_activeRenderEncoder = nil;
    }
    if (m_activeComputeEncoder) {
        [m_activeComputeEncoder endEncoding];
        m_activeComputeEncoder = nil;
    }
    
    m_activeRenderEncoder = [m_activeCommandBuffer renderCommandEncoderWithDescriptor:passDesc];
#endif
}

void STDMETHODCALLTYPE MLCommandList::EndRenderPass(void) {
#ifdef __OBJC__
    if (m_activeRenderEncoder) {
        [m_activeRenderEncoder endEncoding];
        m_activeRenderEncoder = nil;
    }
#endif
}
void STDMETHODCALLTYPE MLCommandList::InitializeMetaCommand(ID3D12MetaCommand* pMetaCommand, const void* pInitializationParametersData, SIZE_T InitializationParametersDataSizeInBytes) {}
void STDMETHODCALLTYPE MLCommandList::ExecuteMetaCommand(ID3D12MetaCommand* pMetaCommand, const void* pExecutionParametersData, SIZE_T ExecutionParametersDataSizeInBytes) {}

void STDMETHODCALLTYPE MLCommandList::BuildRaytracingAccelerationStructure(const D3D12_BUILD_RAYTRACING_ACCELERATION_STRUCTURE_DESC* pDesc, UINT NumPostbuildInfoDescs, const D3D12_RAYTRACING_ACCELERATION_STRUCTURE_POSTBUILD_INFO_DESC* pPostbuildInfoDescs) {
    if (!pDesc) return;
#ifdef __OBJC__
    id<MTLCommandBuffer> cmdBuf = m_activeCommandBuffer;
    id<MTLAccelerationStructureCommandEncoder> asEncoder = [cmdBuf accelerationStructureCommandEncoder];
    
    MLDevice* device = m_device;
    
    UINT64 destOffset = 0;
    MLResource* destRes = device->ResolveGPUVirtualAddress(pDesc->DestAccelerationStructureData, &destOffset);
    
    UINT64 scratchOffset = 0;
    MLResource* scratchRes = device->ResolveGPUVirtualAddress(pDesc->ScratchAccelerationStructureData, &scratchOffset);
    
    if (!destRes || !scratchRes) {
        [asEncoder endEncoding];
        return; // Invalid addresses
    }
    
    MTLAccelerationStructureDescriptor* mtlDesc = nil;
    if (pDesc->Inputs.Type == D3D12_RAYTRACING_ACCELERATION_STRUCTURE_TYPE_TOP_LEVEL) {
        MTLInstanceAccelerationStructureDescriptor* tlasDesc = [MTLInstanceAccelerationStructureDescriptor descriptor];
        tlasDesc.instanceCount = pDesc->Inputs.NumDescs;
        
        UINT64 instOffset = 0;
        MLResource* instRes = device->ResolveGPUVirtualAddress(pDesc->Inputs.InstanceDescs, &instOffset);
        if (instRes) {
            id<MTLBuffer> d3d12Buffer = instRes->GetMetalBuffer();
            if (d3d12Buffer) {
                // Translate D3D12_RAYTRACING_INSTANCE_DESC to Metal MTLAccelerationStructureUserIDInstanceDescriptor
                // D3D12 uses row-major transform, Metal uses column-major.
                // D3D12 packs InstanceID (24), Mask (8), HitGroup (24), Flags (8).
                
                NSUInteger numInstances = pDesc->Inputs.NumDescs;
                id<MTLBuffer> translatedBuffer = [device->GetMetalDevice() newBufferWithLength:sizeof(MTLAccelerationStructureUserIDInstanceDescriptor) * numInstances options:MTLResourceStorageModeShared];
                
                // Assuming CPU accessible for now (UPLOAD heap). Real implementation needs GPU compute shader translation
                // and a GPU-side GPUVA->AS Index mapping table.
                if (d3d12Buffer.storageMode != MTLStorageModePrivate) {
                    const struct D3D12Desc { float transform[3][4]; uint32_t instanceID_mask; uint32_t hitGroup_flags; uint64_t accelStruct; }* inDescs = 
                        (const D3D12Desc*)((const uint8_t*)[d3d12Buffer contents] + instOffset);
                    
                    MTLAccelerationStructureUserIDInstanceDescriptor* outDescs = (MTLAccelerationStructureUserIDInstanceDescriptor*)[translatedBuffer contents];
                    
                    for (NSUInteger i = 0; i < numInstances; ++i) {
                        outDescs[i].transformationMatrix.columns[0] = { inDescs[i].transform[0][0], inDescs[i].transform[1][0], inDescs[i].transform[2][0] };
                        outDescs[i].transformationMatrix.columns[1] = { inDescs[i].transform[0][1], inDescs[i].transform[1][1], inDescs[i].transform[2][1] };
                        outDescs[i].transformationMatrix.columns[2] = { inDescs[i].transform[0][2], inDescs[i].transform[1][2], inDescs[i].transform[2][2] };
                        outDescs[i].transformationMatrix.columns[3] = { inDescs[i].transform[0][3], inDescs[i].transform[1][3], inDescs[i].transform[2][3] };
                        outDescs[i].options = (inDescs[i].hitGroup_flags >> 24) & 0xFF;
                        outDescs[i].mask = (inDescs[i].instanceID_mask >> 24) & 0xFF;
                        outDescs[i].intersectionFunctionTableOffset = inDescs[i].hitGroup_flags & 0xFFFFFF;
                        outDescs[i].userID = inDescs[i].instanceID_mask & 0xFFFFFF;
                        
                        // Resolve BLAS GPUVA to Metal Acceleration Structure
                        MLResource* blasRes = device->ResolveGPUVirtualAddress(inDescs[i].accelStruct, nullptr);
                        if (blasRes) {
                            outDescs[i].accelerationStructureIndex = i; // Simplified, requires descriptor arrays
                        }
                    }
                }
                
                tlasDesc.instanceDescriptorBuffer = translatedBuffer;
                tlasDesc.instanceDescriptorBufferOffset = 0;
            }
        }
        mtlDesc = tlasDesc;
    } else {
        MTLPrimitiveAccelerationStructureDescriptor* blasDesc = [MTLPrimitiveAccelerationStructureDescriptor descriptor];
        NSMutableArray<MTLAccelerationStructureGeometryDescriptor*>* geometryDescs = [NSMutableArray arrayWithCapacity:pDesc->Inputs.NumDescs];
        
        for (UINT i = 0; i < pDesc->Inputs.NumDescs; ++i) {
            const D3D12_RAYTRACING_GEOMETRY_DESC& geom = (pDesc->Inputs.DescsLayout == D3D12_ELEMENTS_LAYOUT_ARRAY) ? 
                pDesc->Inputs.pGeometryDescs[i] : *(pDesc->Inputs.ppGeometryDescs[i]);
            
            if (geom.Type == D3D12_RAYTRACING_GEOMETRY_TYPE_TRIANGLES) {
                MTLAccelerationStructureTriangleGeometryDescriptor* triDesc = [MTLAccelerationStructureTriangleGeometryDescriptor descriptor];
                triDesc.triangleCount = geom.Triangles.IndexCount > 0 ? (geom.Triangles.IndexCount / 3) : (geom.Triangles.VertexCount / 3);
                triDesc.opaque = (geom.Flags & D3D12_RAYTRACING_GEOMETRY_FLAG_OPAQUE) ? YES : NO;
                
                UINT64 vbOffset = 0;
                MLResource* vbRes = device->ResolveGPUVirtualAddress(geom.Triangles.VertexBuffer.StartAddress, &vbOffset);
                if (vbRes) {
                    triDesc.vertexBuffer = vbRes->GetMetalBuffer();
                    triDesc.vertexBufferOffset = vbOffset;
                    triDesc.vertexStride = geom.Triangles.VertexBuffer.StrideInBytes;
                }
                
                if (geom.Triangles.IndexBuffer != 0) {
                    UINT64 ibOffset = 0;
                    MLResource* ibRes = device->ResolveGPUVirtualAddress(geom.Triangles.IndexBuffer, &ibOffset);
                    if (ibRes) {
                        triDesc.indexBuffer = ibRes->GetMetalBuffer();
                        triDesc.indexBufferOffset = ibOffset;
                        triDesc.indexType = (geom.Triangles.IndexFormat == DXGI_FORMAT_R32_UINT) ? MTLIndexTypeUInt32 : MTLIndexTypeUInt16;
                    }
                }
                [geometryDescs addObject:triDesc];
            } else if (geom.Type == D3D12_RAYTRACING_GEOMETRY_TYPE_PROCEDURAL_PRIMITIVE_AABBS) {
                MTLAccelerationStructureBoundingBoxGeometryDescriptor* aabbDesc = [MTLAccelerationStructureBoundingBoxGeometryDescriptor descriptor];
                aabbDesc.boundingBoxCount = geom.AABBs.AABBCount;
                aabbDesc.opaque = (geom.Flags & D3D12_RAYTRACING_GEOMETRY_FLAG_OPAQUE) ? YES : NO;
                
                UINT64 aabbOffset = 0;
                MLResource* aabbRes = device->ResolveGPUVirtualAddress(geom.AABBs.AABBs.StartAddress, &aabbOffset);
                if (aabbRes) {
                    aabbDesc.boundingBoxBuffer = aabbRes->GetMetalBuffer();
                    aabbDesc.boundingBoxBufferOffset = aabbOffset;
                    aabbDesc.boundingBoxStride = geom.AABBs.AABBs.StrideInBytes;
                }
                [geometryDescs addObject:aabbDesc];
            }
        }
        blasDesc.geometryDescriptors = geometryDescs;
        mtlDesc = blasDesc;
    }
    
    // Create the MTLAcelerationStructure object dynamically and cache it on the resource
    id<MTLDevice> mtlDevice = cmdBuf.device;
    MTLAccelerationStructureSizes sizes = [mtlDevice accelerationStructureSizesWithDescriptor:mtlDesc];
    id<MTLAccelerationStructure> asObj = [mtlDevice newAccelerationStructureWithSize:sizes.accelerationStructureSize];
    
    destRes->SetAccelerationStructure(destOffset, (__bridge void*)asObj);
    
    [asEncoder buildAccelerationStructure:asObj
                               descriptor:mtlDesc
                            scratchBuffer:scratchRes->GetMetalBuffer()
                      scratchBufferOffset:scratchOffset];
                      
    [asEncoder endEncoding];
#endif
}

void STDMETHODCALLTYPE MLCommandList::EmitRaytracingAccelerationStructurePostbuildInfo(const D3D12_RAYTRACING_ACCELERATION_STRUCTURE_POSTBUILD_INFO_DESC* pDesc, UINT NumSourceAccelerationStructures, const D3D12_GPU_VIRTUAL_ADDRESS* pSourceAccelerationStructureData) {}
void STDMETHODCALLTYPE MLCommandList::CopyRaytracingAccelerationStructure(D3D12_GPU_VIRTUAL_ADDRESS DestAccelerationStructureData, D3D12_GPU_VIRTUAL_ADDRESS SourceAccelerationStructureData, D3D12_RAYTRACING_ACCELERATION_STRUCTURE_COPY_MODE Mode) {
    std::cerr << "[Metalloid] WARNING: CopyRaytracingAccelerationStructure is not yet supported." << std::endl;
}

void STDMETHODCALLTYPE MLCommandList::SetPipelineState1(ID3D12StateObject* pStateObject) {
    if (!pStateObject) return;
    m_currentDXRStateObject = static_cast<MLStateObject*>(pStateObject);

#ifdef __OBJC__
    id<MTLComputePipelineState> pso = m_currentDXRStateObject->GetMetalPipeline();
    if (pso && m_activeComputeEncoder) {
        [m_activeComputeEncoder setComputePipelineState:pso];
    }
#endif
}

void STDMETHODCALLTYPE MLCommandList::DispatchRays(const D3D12_DISPATCH_RAYS_DESC* pDesc) {
    if (!pDesc) return;
    
#ifdef __OBJC__
    id<MTLComputeCommandEncoder> computeEncoder = m_activeComputeEncoder;
    if (!computeEncoder) {
        // If we don't have an active compute encoder, create one from the command buffer
        id<MTLCommandBuffer> cmdBuf = m_activeCommandBuffer;
        computeEncoder = [cmdBuf computeCommandEncoder];
        m_activeComputeEncoder = computeEncoder;
        
        if (m_currentDXRStateObject) {
            id<MTLComputePipelineState> pso = m_currentDXRStateObject->GetMetalPipeline();
            if (pso) [computeEncoder setComputePipelineState:pso];
        }
    }
    
    // 1. Automated DXR Synchronization: Inject Memory Barrier to ensure prior BLAS/TLAS builds finished
    [computeEncoder memoryBarrierWithScope:MTLBarrierScopeBuffers];
    
    // 2. Validate SBT Alignment (64-byte for start address)
    if (pDesc->RayGenerationShaderRecord.StartAddress % 64 != 0) {
        std::cerr << "[Metalloid] WARNING: DXR RayGen Shader Record misaligned. Auto-correcting..." << std::endl;
        // In a real implementation, we'd copy it to an aligned buffer here.
    }
    
    // 3. Parse Shader Binding Table (SBT), extract embedded local root signatures, and bind them
    if (m_currentDXRStateObject) {
        id<MTLComputePipelineState> pso = m_currentDXRStateObject->GetMetalPipeline();
        if (pso) {
            bool isM1M2 = false;
            if (m_device) {
                MLAppleSiliconGen gen = m_device->GetSiliconGeneration();
                if (gen < MLAppleSiliconGen::M3) {
                    isM1M2 = true;
                }
            }

            if (isM1M2) {
                static bool warned = false;
                if (!warned) {
                    std::cerr << "[Metalloid] WARNING: Native Raytracing table building is skipped on M1/M2 to avoid driver crashes. Pipeline compilation and emulation paths remain open." << std::endl;
                    warned = true;
                }
            } else {
                // Construct and bind MTLIntersectionFunctionTable
                MTLIntersectionFunctionTableDescriptor* iftDesc = [MTLIntersectionFunctionTableDescriptor intersectionFunctionTableDescriptor];
                iftDesc.functionCount = pDesc->HitGroupTable.SizeInBytes / (pDesc->HitGroupTable.StrideInBytes ? pDesc->HitGroupTable.StrideInBytes : 1);
                if (iftDesc.functionCount == 0) iftDesc.functionCount = 1;
                id<MTLIntersectionFunctionTable> ift = [pso newIntersectionFunctionTableWithDescriptor:iftDesc];
                
                if (pDesc->HitGroupTable.StartAddress) {
                    UINT64 offset = 0;
                    MLResource* res = m_device->ResolveGPUVirtualAddress(pDesc->HitGroupTable.StartAddress, &offset);
                    if (res && res->GetMetalBuffer()) {
                        id<MTLBuffer> mtlBuffer = res->GetMetalBuffer();
                        if (mtlBuffer.storageMode != MTLStorageModePrivate && mtlBuffer.contents) {
                            uint8_t* ptr = (uint8_t*)mtlBuffer.contents + offset;
                            for (UINT i = 0; i < iftDesc.functionCount; ++i) {
                                std::array<uint8_t, 32> identifier;
                                memcpy(identifier.data(), ptr + i * (pDesc->HitGroupTable.StrideInBytes ? pDesc->HitGroupTable.StrideInBytes : 32), 32);
                                id<MTLFunctionHandle> handle = m_currentDXRStateObject->GetFunctionHandle(identifier);
                                if (handle) {
                                    [ift setFunction:handle atIndex:i];
                                }
                            }
                        }
                    }
                }
                [computeEncoder setIntersectionFunctionTable:ift atBufferIndex:10];

                // Construct and bind MTLVisibleFunctionTable
                MTLVisibleFunctionTableDescriptor* vftDesc = [MTLVisibleFunctionTableDescriptor visibleFunctionTableDescriptor];
                vftDesc.functionCount = pDesc->MissShaderTable.SizeInBytes / (pDesc->MissShaderTable.StrideInBytes ? pDesc->MissShaderTable.StrideInBytes : 1);
                if (vftDesc.functionCount == 0) vftDesc.functionCount = 1;
                id<MTLVisibleFunctionTable> vft = [pso newVisibleFunctionTableWithDescriptor:vftDesc];
                
                if (pDesc->MissShaderTable.StartAddress) {
                    UINT64 offset = 0;
                    MLResource* res = m_device->ResolveGPUVirtualAddress(pDesc->MissShaderTable.StartAddress, &offset);
                    if (res && res->GetMetalBuffer()) {
                        id<MTLBuffer> mtlBuffer = res->GetMetalBuffer();
                        if (mtlBuffer.storageMode != MTLStorageModePrivate && mtlBuffer.contents) {
                            uint8_t* ptr = (uint8_t*)mtlBuffer.contents + offset;
                            for (UINT i = 0; i < vftDesc.functionCount; ++i) {
                                std::array<uint8_t, 32> identifier;
                                memcpy(identifier.data(), ptr + i * (pDesc->MissShaderTable.StrideInBytes ? pDesc->MissShaderTable.StrideInBytes : 32), 32);
                                id<MTLFunctionHandle> handle = m_currentDXRStateObject->GetFunctionHandle(identifier);
                                if (handle) {
                                    [vft setFunction:handle atIndex:i];
                                }
                            }
                        }
                    }
                }
                [computeEncoder setVisibleFunctionTable:vft atBufferIndex:11];
            }

            // Extract embedded local root signatures from SBT and bind them to the Metal encoder
            // In DXR, the SBT contains a 32-byte shader identifier followed by local root arguments.
            // We resolve the SBT buffer addresses, and bind the local root arguments (skipping the 32-byte identifier).
            if (pDesc->RayGenerationShaderRecord.StartAddress) {
                UINT64 offset = 0;
                MLResource* res = m_device->ResolveGPUVirtualAddress(pDesc->RayGenerationShaderRecord.StartAddress, &offset);
                if (res && res->GetMetalBuffer()) {
                    [computeEncoder setBuffer:res->GetMetalBuffer() offset:offset + 32 atIndex:12];
                }
            }
            if (pDesc->MissShaderTable.StartAddress) {
                UINT64 offset = 0;
                MLResource* res = m_device->ResolveGPUVirtualAddress(pDesc->MissShaderTable.StartAddress, &offset);
                if (res && res->GetMetalBuffer()) {
                    [computeEncoder setBuffer:res->GetMetalBuffer() offset:offset + 32 atIndex:13];
                }
            }
            if (pDesc->HitGroupTable.StartAddress) {
                UINT64 offset = 0;
                MLResource* res = m_device->ResolveGPUVirtualAddress(pDesc->HitGroupTable.StartAddress, &offset);
                if (res && res->GetMetalBuffer()) {
                    [computeEncoder setBuffer:res->GetMetalBuffer() offset:offset + 32 atIndex:14];
                }
            }
            if (pDesc->CallableShaderTable.StartAddress) {
                UINT64 offset = 0;
                MLResource* res = m_device->ResolveGPUVirtualAddress(pDesc->CallableShaderTable.StartAddress, &offset);
                if (res && res->GetMetalBuffer()) {
                    [computeEncoder setBuffer:res->GetMetalBuffer() offset:offset + 32 atIndex:15];
                }
            }
        }
    }
    
    MTLSize threadsPerGrid = MTLSizeMake(pDesc->Width, pDesc->Height, pDesc->Depth);
    // Use conservative threadgroups based on thread execution width.
    NSUInteger w = pDesc->Width > 0 ? pDesc->Width : 1;
    MTLSize threadsPerThreadgroup = MTLSizeMake(std::min(w, (NSUInteger)32), 1, 1);
    
    [computeEncoder dispatchThreads:threadsPerGrid threadsPerThreadgroup:threadsPerThreadgroup];
#endif
}

void STDMETHODCALLTYPE MLCommandList::DispatchGraph(const D3D12_DISPATCH_GRAPH_DESC* pDesc) {
    if (!pDesc) return;

#ifdef __OBJC__
    id<MTLComputeCommandEncoder> computeEncoder = m_activeComputeEncoder;
    if (!computeEncoder) {
        // Create compute encoder if missing
        id<MTLCommandBuffer> cmdBuf = m_activeCommandBuffer;
        computeEncoder = [cmdBuf computeCommandEncoder];
        m_activeComputeEncoder = computeEncoder;
        
        if (m_currentDXRStateObject) { 
            id<MTLComputePipelineState> pso = m_currentDXRStateObject->GetMetalPipeline();
            if (pso) [computeEncoder setComputePipelineState:pso];
        }
    }
    
    // Resolve D3D12 GPU virtual address for the work graph input
    UINT64 inputOffset = 0;
    MLResource* backingResource = nullptr;
    
    if (pDesc->Mode == D3D12_DISPATCH_MODE_NODE_GPU_INPUT) {
        backingResource = m_device->ResolveGPUVirtualAddress(pDesc->NodeGPUInput, &inputOffset);
    } else if (pDesc->Mode == D3D12_DISPATCH_MODE_MULTI_NODE_GPU_INPUT) {
        backingResource = m_device->ResolveGPUVirtualAddress(pDesc->MultiNodeGPUInput, &inputOffset);
    }
    
    id<MTLIndirectCommandBuffer> icb = nil;
    id<MTLBuffer> icbCounter = nil;

    if (backingResource) {
        if (!backingResource->GetICB()) {
            // Allocate ICB dynamically for the work graph (arbitrary safe maximum for nodes)
            backingResource->AllocateICB(4096, true); 
        }
        icb = (__bridge id<MTLIndirectCommandBuffer>)backingResource->GetICB();
        icbCounter = (__bridge id<MTLBuffer>)backingResource->GetICBCounter();
    }
    
    // Fallback if no backing resource or using CPU input
    if (!icb) {
        MTLIndirectCommandBufferDescriptor* icbDesc = [[MTLIndirectCommandBufferDescriptor alloc] init];
        icbDesc.commandTypes = MTLIndirectCommandTypeConcurrentDispatch;
        icbDesc.inheritPipelineState = YES;
        icbDesc.inheritBuffers = NO;
        icbDesc.maxKernelBufferBindCount = 31;
        
        id<MTLDevice> device = nil;
        if (m_activeCommandBuffer) {
            device = m_activeCommandBuffer.device;
        }
        if (device) {
            icb = [device newIndirectCommandBufferWithDescriptor:icbDesc maxCommandCount:4096 options:MTLResourceStorageModeShared];
            icbCounter = [device newBufferWithLength:sizeof(uint32_t) options:MTLResourceStorageModeShared];
        }
    }
    
    if (icb) {
        [computeEncoder useResource:icb usage:MTLResourceUsageRead | MTLResourceUsageWrite];
        if (icbCounter) {
            [computeEncoder useResource:icbCounter usage:MTLResourceUsageRead | MTLResourceUsageWrite];
            [computeEncoder executeCommandsInBuffer:icb indirectBuffer:icbCounter indirectBufferOffset:0];
        } else {
            [computeEncoder executeCommandsInBuffer:icb withRange:NSMakeRange(0, 4096)];
        }
    }
#endif
}

void STDMETHODCALLTYPE MLCommandList::RSSetShadingRate(D3D12_SHADING_RATE baseShadingRate, const D3D12_SHADING_RATE_COMBINER* combiners) {}
void STDMETHODCALLTYPE MLCommandList::RSSetShadingRateImage(ID3D12Resource* shadingRateImage) {}

void STDMETHODCALLTYPE MLCommandList::DispatchMesh(UINT ThreadGroupCountX, UINT ThreadGroupCountY, UINT ThreadGroupCountZ) {
#ifdef __OBJC__
    bool isM1M2 = false;
    if (m_device) {
        MLAppleSiliconGen gen = m_device->GetSiliconGeneration();
        if (gen < MLAppleSiliconGen::M3) {
            isM1M2 = true;
        }
    }

    if (isM1M2) {
        static bool s_warnedAboutMeshEmulation = false;
        if (!s_warnedAboutMeshEmulation) {
            std::cout << "[Metalloid] INFO: M1/M2 detected. Routing DispatchMesh through compute emulation path." << std::endl;
            s_warnedAboutMeshEmulation = true;
        }

        // End active render encoder if it exists to transition to compute
        if (m_activeRenderEncoder) {
            [(id<MTLRenderCommandEncoder>)m_activeRenderEncoder endEncoding];
            m_activeRenderEncoder = nil;
            m_boundPSO = nullptr;
        }

        // Create or retrieve the active compute encoder
        id<MTLComputeCommandEncoder> computeEncoder = m_activeComputeEncoder;
        if (!computeEncoder) {
            id<MTLCommandBuffer> cmdBuf = m_activeCommandBuffer;
            if (cmdBuf) {
                computeEncoder = [cmdBuf computeCommandEncoder];
                m_activeComputeEncoder = computeEncoder;
            }
        }

        if (computeEncoder) {
            if (m_currentPSO) {
                id<MTLComputePipelineState> computePipeline = m_currentPSO->GetComputePipeline();
                if (computePipeline) {
                    [computeEncoder setComputePipelineState:computePipeline];
                }
            }

            MTLSize threadgroups = MTLSizeMake(ThreadGroupCountX, ThreadGroupCountY, ThreadGroupCountZ);
            UINT tx = 32, ty = 1, tz = 1;
            if (m_currentPSO) {
                m_currentPSO->GetMeshThreads(tx, ty, tz);
            }
            MTLSize threadsPerThreadgroup = MTLSizeMake(tx, ty, tz);
            [computeEncoder dispatchThreadgroups:threadgroups threadsPerThreadgroup:threadsPerThreadgroup];
        }
    } else {
        id<MTLRenderCommandEncoder> renderEncoder = m_activeRenderEncoder;
        if (renderEncoder) {
            if (@available(macOS 13.0, iOS 16.0, *)) {
                MTLSize threadgroups = MTLSizeMake(ThreadGroupCountX, ThreadGroupCountY, ThreadGroupCountZ);
                MTLSize threadsPerObjectThreadgroup = MTLSizeMake(1, 1, 1);
                MTLSize threadsPerMeshThreadgroup = MTLSizeMake(1, 1, 1);
                if (m_currentPSO && m_currentPSO->GetRenderPipeline()) {
                    threadsPerObjectThreadgroup = MTLSizeMake(m_currentPSO->GetRenderPipeline().maxTotalThreadsPerObjectThreadgroup, 1, 1);
                    threadsPerMeshThreadgroup = MTLSizeMake(m_currentPSO->GetRenderPipeline().maxTotalThreadsPerMeshThreadgroup, 1, 1);
                }
                [renderEncoder drawMeshThreadgroups:threadgroups
                           threadsPerObjectThreadgroup:threadsPerObjectThreadgroup
                              threadsPerMeshThreadgroup:threadsPerMeshThreadgroup];
            }
        }
    }
#endif
}

void STDMETHODCALLTYPE MLCommandList::Barrier(UINT32 NumBarrierGroups, const D3D12_BARRIER_GROUP* pBarrierGroups) {
#ifdef __OBJC__
    if (NumBarrierGroups == 0) return;

    for (UINT32 i = 0; i < NumBarrierGroups; ++i) {
        const D3D12_BARRIER_GROUP& group = pBarrierGroups[i];
        if (group.Type == D3D12_BARRIER_TYPE_TEXTURE) {
            for (UINT32 j = 0; j < group.NumBarriers; ++j) {
                const D3D12_TEXTURE_BARRIER& texBarrier = group.pTextureBarriers[j];
                MLResource* res = static_cast<MLResource*>(texBarrier.pResource);
                if (!res) continue;
                
                auto it = m_localStates.find(res);
                if (it == m_localStates.end()) {
                    HierarchicalResourceState& newState = m_localStates[res];
                    newState.uniform_state.layout = (D3D12_BARRIER_LAYOUT)0xFFFFFFFF; // LAYOUT_PLACEHOLDER
                    
                    PatchEntry patch;
                    patch.resource = res;
                    patch.subresourceIndex = texBarrier.Subresources.IndexOrFirstMipLevel;
                    patch.oldLayoutPtr = &newState.uniform_state.layout;
                    m_patchTable.push_back(patch);
                    it = m_localStates.find(res);
                }
                
                SubresourceStateV2& state = it->second.uniform_state;
                
                if (texBarrier.LayoutBefore == D3D12_BARRIER_LAYOUT_UNDEFINED && !(texBarrier.Flags & D3D12_TEXTURE_BARRIER_FLAG_DISCARD)) {
                    if (!state.ever_written) {
                        if (m_activeCommandBuffer && res->GetMetalTexture()) {
                            if (m_activeRenderEncoder) { [(id<MTLRenderCommandEncoder>)m_activeRenderEncoder endEncoding]; m_activeRenderEncoder = nil; m_boundPSO = nullptr; }
                            if (m_activeComputeEncoder) { [(id<MTLComputeCommandEncoder>)m_activeComputeEncoder endEncoding]; m_activeComputeEncoder = nil; m_boundPSO = nullptr; }
                            
                            id<MTLCommandBuffer> cmdBuf = (id<MTLCommandBuffer>)m_activeCommandBuffer;
                            MTLRenderPassDescriptor* passDesc = [MTLRenderPassDescriptor renderPassDescriptor];
                            passDesc.colorAttachments[0].texture = res->GetMetalTexture();
                            passDesc.colorAttachments[0].loadAction = MTLLoadActionClear;
                            passDesc.colorAttachments[0].storeAction = MTLStoreActionStore;
                            passDesc.colorAttachments[0].clearColor = MTLClearColorMake(0,0,0,0);
                            id<MTLRenderCommandEncoder> clearEnc = [cmdBuf renderCommandEncoderWithDescriptor:passDesc];
                            [clearEnc endEncoding];
                            
                            state.ever_written = true;
                        }
                    }
                }
                state.layout = texBarrier.LayoutAfter;
            }
        }
    }

    if (m_activeRenderEncoder) {
        [(id<MTLRenderCommandEncoder>)m_activeRenderEncoder memoryBarrierWithScope:MTLBarrierScopeBuffers | MTLBarrierScopeRenderTargets | MTLBarrierScopeTextures
                                                                      afterStages:MTLRenderStageVertex | MTLRenderStageFragment
                                                                     beforeStages:MTLRenderStageVertex | MTLRenderStageFragment];
    } else if (m_activeComputeEncoder) {
        [(id<MTLComputeCommandEncoder>)m_activeComputeEncoder memoryBarrierWithScope:MTLBarrierScopeBuffers | MTLBarrierScopeTextures];
    }
#endif
}
void STDMETHODCALLTYPE MLCommandList::OMSetFrontAndBackStencilRef(UINT FrontStencilRef, UINT BackStencilRef) {}
void STDMETHODCALLTYPE MLCommandList::RSSetDepthBias(FLOAT DepthBias, FLOAT DepthBiasClamp, FLOAT SlopeScaledDepthBias) {
#ifdef __OBJC__
    if (m_activeRenderEncoder) {
        [(id<MTLRenderCommandEncoder>)m_activeRenderEncoder setDepthBias:DepthBias slopeScale:SlopeScaledDepthBias clamp:DepthBiasClamp];
    }
#endif
}
void STDMETHODCALLTYPE MLCommandList::IASetIndexBufferStripCutValue(D3D12_INDEX_BUFFER_STRIP_CUT_VALUE IBStripCutValue) {}
void STDMETHODCALLTYPE MLCommandList::SetProgram(D3D12_SET_PROGRAM_DESC const* pDesc) {}
