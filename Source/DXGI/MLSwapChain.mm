#include "Metalloid/DXGI/MLSwapChain.h"
#include "Metalloid/Resources/MLResource.h"
#include "Metalloid/Commands/MLCommandQueue.h"
#include <iostream>

#ifdef __OBJC__
#import <Metal/Metal.h>
#import <QuartzCore/CAMetalLayer.h>
#import <CoreGraphics/CoreGraphics.h>
#endif

extern "C" HRESULT WINAPI CreateDXGIFactory(REFIID riid, void** ppFactory);

MLSwapChain::MLSwapChain(IUnknown* pDevice, UINT width, UINT height, UINT bufferCount, DXGI_FORMAT format)
    : m_refCount(1),
      m_metalLayer(nil),
      m_backBufferCount(bufferCount),
      m_width(width),
      m_height(height),
      m_format(format),
      m_device(nullptr),
      m_currentBufferIndex(0),
      m_isFullscreen(FALSE),
      m_presentCount(0),
      m_parentDevice(nullptr) {
      
    if (pDevice) {
        ID3D12DeviceChild* pChild = nullptr;
        if (SUCCEEDED(pDevice->QueryInterface(__uuidof(ID3D12DeviceChild), (void**)&pChild))) {
            pChild->GetDevice(__uuidof(IUnknown), (void**)&m_parentDevice);
            pChild->Release();
        } else {
            pDevice->QueryInterface(__uuidof(IUnknown), (void**)&m_parentDevice);
        }
    }
      
#ifdef __OBJC__
    MLCommandQueue* mlQueue = static_cast<MLCommandQueue*>(pDevice);
    id<MTLCommandQueue> nativeQueue = mlQueue->GetMetalQueue();
    m_device = (__bridge_retained void*)nativeQueue;
    id<MTLDevice> mtlDevice = nativeQueue.device;
    
    m_metalLayer = [CAMetalLayer layer];
    m_metalLayer.device = mtlDevice;
    
    MTLPixelFormat metalPixelFormat = MTLPixelFormatRGBA8Unorm;
    CGColorSpaceRef colorSpace = nullptr;
    BOOL wantsEDR = NO;

    if (m_format == DXGI_FORMAT_R10G10B10A2_UNORM) {
        metalPixelFormat = MTLPixelFormatRGB10A2Unorm;
        colorSpace = CGColorSpaceCreateWithName(kCGColorSpaceITUR_2100_PQ);
        wantsEDR = YES;
    } else if (m_format == DXGI_FORMAT_R16G16B16A16_FLOAT) {
        metalPixelFormat = MTLPixelFormatRGBA16Float;
        colorSpace = CGColorSpaceCreateWithName(kCGColorSpaceExtendedLinearDisplayP3);
        wantsEDR = YES;
    } else if (m_format == DXGI_FORMAT_B8G8R8A8_UNORM) {
        metalPixelFormat = MTLPixelFormatBGRA8Unorm;
    }
    
    m_metalLayer.pixelFormat = metalPixelFormat;
    m_metalLayer.drawableSize = CGSizeMake(m_width, m_height);
    if (wantsEDR) {
        m_metalLayer.wantsExtendedDynamicRangeContent = YES;
        if (colorSpace) {
            m_metalLayer.colorspace = colorSpace;
        }
    }
    if (colorSpace) {
        CGColorSpaceRelease(colorSpace);
    }
    
    for (UINT i = 0; i < m_backBufferCount; ++i) {
        MTLTextureDescriptor* desc = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:metalPixelFormat
                                                                                       width:m_width
                                                                                      height:m_height
                                                                                   mipmapped:NO];
        desc.usage = MTLTextureUsageShaderRead | MTLTextureUsageRenderTarget;
        desc.storageMode = MTLStorageModePrivate;
        id<MTLTexture> tex = [mtlDevice newTextureWithDescriptor:desc];
        m_buffers.push_back((__bridge_retained void*)tex);
        
        // Cache the MLResource wrapper to eliminate runtime allocation
        D3D12_RESOURCE_DESC resDesc = {};
        resDesc.Dimension = D3D12_RESOURCE_DIMENSION_TEXTURE2D;
        resDesc.Width = m_width;
        resDesc.Height = m_height;
        resDesc.DepthOrArraySize = 1;
        resDesc.MipLevels = 1;
        resDesc.Format = m_format;
        resDesc.SampleDesc.Count = 1;
        resDesc.Layout = D3D12_TEXTURE_LAYOUT_UNKNOWN;
        resDesc.Flags = D3D12_RESOURCE_FLAG_ALLOW_RENDER_TARGET;
        
        MLResource* res = new MLResource(nullptr, nullptr, tex, resDesc);
        m_bufferResources.push_back(res);
    }
#endif

    std::cout << "[Metalloid] IDXGISwapChain3 initialized. (Size: " 
              << m_width << "x" << m_height 
              << ", Buffers: " << m_backBufferCount << ")" << std::endl;
}

MLSwapChain::~MLSwapChain() {
#ifdef __OBJC__
    for (MLResource* res : m_bufferResources) {
        res->Release();
    }
    m_bufferResources.clear();
    
    for (void* buf : m_buffers) {
        id<MTLTexture> tex = (__bridge_transfer id<MTLTexture>)buf;
    }
    m_buffers.clear();
    
    id<MTLCommandQueue> dev = (__bridge_transfer id<MTLCommandQueue>)m_device;
#endif
    if (m_parentDevice) {
        m_parentDevice->Release();
    }
    std::cout << "[Metalloid] IDXGISwapChain3 destroyed." << std::endl;
}

// IUnknown Methods
HRESULT STDMETHODCALLTYPE MLSwapChain::QueryInterface(REFIID riid, void** ppvObject) {
    if (!ppvObject) return E_POINTER;

    if (riid == __uuidof(IUnknown) ||
        riid == __uuidof(IDXGIObject) ||
        riid == __uuidof(IDXGIDeviceSubObject) ||
        riid == __uuidof(IDXGISwapChain) ||
        riid == __uuidof(IDXGISwapChain1) ||
        riid == __uuidof(IDXGISwapChain2) ||
        riid == __uuidof(IDXGISwapChain3)) {
        *ppvObject = static_cast<IDXGISwapChain3*>(this);
        AddRef();
        return S_OK;
    }

    *ppvObject = nullptr;
    return E_NOINTERFACE;
}

ULONG STDMETHODCALLTYPE MLSwapChain::AddRef() {
    return ++m_refCount;
}

ULONG STDMETHODCALLTYPE MLSwapChain::Release() {
    ULONG count = --m_refCount;
    if (count == 0) {
        delete this;
    }
    return count;
}

// IDXGIObject Methods
ML_IMPL_PRIVATE_DATA(MLSwapChain)

HRESULT STDMETHODCALLTYPE MLSwapChain::GetParent(REFIID riid, void** ppParent) {
    if (!ppParent) return E_POINTER;
    IDXGIFactory* pFactory = nullptr;
    CreateDXGIFactory(__uuidof(IDXGIFactory), (void**)&pFactory);
    if (pFactory) {
        HRESULT hr = pFactory->QueryInterface(riid, ppParent);
        pFactory->Release();
        return hr;
    }
    return E_NOINTERFACE;
}

// IDXGIDeviceSubObject Methods
HRESULT STDMETHODCALLTYPE MLSwapChain::GetDevice(REFIID riid, void** ppDevice) {
    if (!ppDevice) return E_POINTER;
    if (m_parentDevice) {
        return m_parentDevice->QueryInterface(riid, ppDevice);
    }
    return E_NOINTERFACE;
}

// IDXGISwapChain Methods
HRESULT STDMETHODCALLTYPE MLSwapChain::Present(UINT SyncInterval, UINT Flags) {
#ifdef __OBJC__
    @autoreleasepool {
        id<MTLCommandQueue> nativeQueue = (__bridge id<MTLCommandQueue>)m_device;
        id<MTLDevice> mtlDevice = nativeQueue.device;
        
        // 2. Obtain drawable
        m_metalLayer.displaySyncEnabled = (SyncInterval > 0);
        id<CAMetalDrawable> drawable = [m_metalLayer nextDrawable];
        if (!drawable) return E_FAIL;
        
        // 3. Create a command buffer from cached native queue
        id<MTLCommandBuffer> cmdBuf = [nativeQueue commandBuffer];
        
        // 4. Blit backbuffer copy to drawable
        id<MTLTexture> backBufferTex = (__bridge id<MTLTexture>)m_buffers[m_currentBufferIndex];
        id<MTLBlitCommandEncoder> blitEnc = [cmdBuf blitCommandEncoder];
        [blitEnc copyFromTexture:backBufferTex
                     sourceSlice:0
                     sourceLevel:0
                    sourceOrigin:MTLOriginMake(0, 0, 0)
                      sourceSize:MTLSizeMake(m_width, m_height, 1)
                       toTexture:drawable.texture
                destinationSlice:0
                destinationLevel:0
               destinationOrigin:MTLOriginMake(0, 0, 0)];
        [blitEnc endEncoding];
        
        // 5. Present and commit
        [cmdBuf presentDrawable:drawable];
        [cmdBuf commit];
        
        // 6. Advance index
        m_currentBufferIndex = (m_currentBufferIndex + 1) % m_backBufferCount;
        m_presentCount++;
    }
    return S_OK;
#else
    return E_FAIL;
#endif
}

HRESULT STDMETHODCALLTYPE MLSwapChain::GetBuffer(UINT Buffer, REFIID riid, void** ppSurface) {
    if (Buffer >= m_backBufferCount) return E_INVALIDARG;
    if (!ppSurface) return E_POINTER;

    MLResource* res = m_bufferResources[Buffer];
    if (!res) return E_FAIL;
    
    return res->QueryInterface(riid, ppSurface);
}

HRESULT STDMETHODCALLTYPE MLSwapChain::SetFullscreenState(win_BOOL Fullscreen, IDXGIOutput* pTarget) {
    m_isFullscreen = Fullscreen;
    return S_OK;
}

HRESULT STDMETHODCALLTYPE MLSwapChain::GetFullscreenState(win_BOOL* pFullscreen, IDXGIOutput** ppTarget) {
    if (pFullscreen) *pFullscreen = m_isFullscreen;
    if (ppTarget) *ppTarget = nullptr;
    return S_OK;
}

HRESULT STDMETHODCALLTYPE MLSwapChain::GetDesc(DXGI_SWAP_CHAIN_DESC* pDesc) {
    if (!pDesc) return E_INVALIDARG;
    pDesc->BufferDesc.Width = m_width;
    pDesc->BufferDesc.Height = m_height;
    pDesc->BufferDesc.RefreshRate.Numerator = 60;
    pDesc->BufferDesc.RefreshRate.Denominator = 1;
    pDesc->BufferDesc.Format = m_format;
    pDesc->BufferDesc.ScanlineOrdering = DXGI_MODE_SCANLINE_ORDER_UNSPECIFIED;
    pDesc->BufferDesc.Scaling = DXGI_MODE_SCALING_UNSPECIFIED;
    pDesc->SampleDesc.Count = 1;
    pDesc->SampleDesc.Quality = 0;
    pDesc->BufferUsage = DXGI_USAGE_RENDER_TARGET_OUTPUT;
    pDesc->BufferCount = m_backBufferCount;
    pDesc->OutputWindow = 0;
    pDesc->Windowed = TRUE;
    pDesc->SwapEffect = DXGI_SWAP_EFFECT_FLIP_DISCARD;
    pDesc->Flags = 0;
    return S_OK;
}

HRESULT STDMETHODCALLTYPE MLSwapChain::ResizeBuffers(
    UINT BufferCount,
    UINT Width,
    UINT Height,
    DXGI_FORMAT NewFormat,
    UINT SwapChainFlags) {
#ifdef __OBJC__
    for (MLResource* res : m_bufferResources) {
        res->Release();
    }
    m_bufferResources.clear();

    for (void* buf : m_buffers) {
        id<MTLTexture> tex = (__bridge_transfer id<MTLTexture>)buf;
    }
    m_buffers.clear();
#endif

    m_backBufferCount = BufferCount;
    m_width = Width;
    m_height = Height;
    m_format = NewFormat;
    m_currentBufferIndex = 0;

#ifdef __OBJC__
    MTLPixelFormat metalPixelFormat = MTLPixelFormatRGBA8Unorm;
    CGColorSpaceRef colorSpace = nullptr;
    BOOL wantsEDR = NO;

    if (m_format == DXGI_FORMAT_R10G10B10A2_UNORM) {
        metalPixelFormat = MTLPixelFormatRGB10A2Unorm;
        colorSpace = CGColorSpaceCreateWithName(kCGColorSpaceITUR_2100_PQ);
        wantsEDR = YES;
    } else if (m_format == DXGI_FORMAT_R16G16B16A16_FLOAT) {
        metalPixelFormat = MTLPixelFormatRGBA16Float;
        colorSpace = CGColorSpaceCreateWithName(kCGColorSpaceExtendedLinearDisplayP3);
        wantsEDR = YES;
    } else if (m_format == DXGI_FORMAT_B8G8R8A8_UNORM) {
        metalPixelFormat = MTLPixelFormatBGRA8Unorm;
    }

    if (m_metalLayer) {
        m_metalLayer.pixelFormat = metalPixelFormat;
        m_metalLayer.drawableSize = CGSizeMake(m_width, m_height);
        if (wantsEDR) {
            m_metalLayer.wantsExtendedDynamicRangeContent = YES;
            if (colorSpace) {
                m_metalLayer.colorspace = colorSpace;
            }
        }
    }
    
    if (colorSpace) {
        CGColorSpaceRelease(colorSpace);
    }

    id<MTLCommandQueue> nativeQueue = (__bridge id<MTLCommandQueue>)m_device;
    id<MTLDevice> mtlDevice = nativeQueue.device;
    
    for (UINT i = 0; i < m_backBufferCount; ++i) {
        MTLTextureDescriptor* desc = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:metalPixelFormat
                                                                                       width:m_width
                                                                                      height:m_height
                                                                                   mipmapped:NO];
        desc.usage = MTLTextureUsageShaderRead | MTLTextureUsageRenderTarget;
        desc.storageMode = MTLStorageModePrivate;
        id<MTLTexture> tex = [mtlDevice newTextureWithDescriptor:desc];
        m_buffers.push_back((__bridge_retained void*)tex);
        
        // Recreate and cache resource
        D3D12_RESOURCE_DESC resDesc = {};
        resDesc.Dimension = D3D12_RESOURCE_DIMENSION_TEXTURE2D;
        resDesc.Width = m_width;
        resDesc.Height = m_height;
        resDesc.DepthOrArraySize = 1;
        resDesc.MipLevels = 1;
        resDesc.Format = m_format;
        resDesc.SampleDesc.Count = 1;
        resDesc.Layout = D3D12_TEXTURE_LAYOUT_UNKNOWN;
        resDesc.Flags = D3D12_RESOURCE_FLAG_ALLOW_RENDER_TARGET;
        
        MLResource* res = new MLResource(nullptr, nullptr, tex, resDesc);
        m_bufferResources.push_back(res);
    }
#endif

    std::cout << "[Metalloid] ResizeBuffers called: " << m_width << "x" << m_height << std::endl;
    return S_OK;
}

HRESULT STDMETHODCALLTYPE MLSwapChain::ResizeTarget(const DXGI_MODE_DESC* pNewTargetParameters) {
    if (pNewTargetParameters) {
        m_width = pNewTargetParameters->Width;
        m_height = pNewTargetParameters->Height;
    }
    return S_OK;
}

HRESULT STDMETHODCALLTYPE MLSwapChain::GetContainingOutput(IDXGIOutput** ppOutput) {
    if (!ppOutput) return E_INVALIDARG;
    IDXGIFactory* pFactory = nullptr;
    CreateDXGIFactory(__uuidof(IDXGIFactory), (void**)&pFactory);
    if (pFactory) {
        IDXGIAdapter* pAdapter = nullptr;
        if (SUCCEEDED(pFactory->EnumAdapters(0, &pAdapter))) {
            pAdapter->EnumOutputs(0, ppOutput);
            pAdapter->Release();
        }
        pFactory->Release();
        return *ppOutput ? S_OK : DXGI_ERROR_NOT_FOUND;
    }
    return DXGI_ERROR_NOT_FOUND;
}

HRESULT STDMETHODCALLTYPE MLSwapChain::GetFrameStatistics(DXGI_FRAME_STATISTICS* pStats) {
    if (!pStats) return E_INVALIDARG;
    std::memset(pStats, 0, sizeof(DXGI_FRAME_STATISTICS));
    pStats->PresentCount = m_presentCount;
    pStats->PresentRefreshCount = m_presentCount;
    pStats->SyncRefreshCount = m_presentCount;
    return S_OK;
}

HRESULT STDMETHODCALLTYPE MLSwapChain::GetLastPresentCount(UINT* pLastPresentCount) {
    if (pLastPresentCount) *pLastPresentCount = m_presentCount;
    return S_OK;
}

// IDXGISwapChain1 Methods
HRESULT STDMETHODCALLTYPE MLSwapChain::GetDesc1(DXGI_SWAP_CHAIN_DESC1* pDesc) {
    if (!pDesc) return E_INVALIDARG;
    pDesc->Width = m_width;
    pDesc->Height = m_height;
    pDesc->Format = m_format;
    pDesc->Stereo = FALSE;
    pDesc->SampleDesc.Count = 1;
    pDesc->SampleDesc.Quality = 0;
    pDesc->BufferUsage = DXGI_USAGE_RENDER_TARGET_OUTPUT;
    pDesc->BufferCount = m_backBufferCount;
    pDesc->Scaling = DXGI_SCALING_NONE;
    pDesc->SwapEffect = DXGI_SWAP_EFFECT_FLIP_DISCARD;
    pDesc->AlphaMode = DXGI_ALPHA_MODE_UNSPECIFIED;
    pDesc->Flags = 0;
    return S_OK;
}

HRESULT STDMETHODCALLTYPE MLSwapChain::GetFullscreenDesc(DXGI_SWAP_CHAIN_FULLSCREEN_DESC* pDesc) {
    if (pDesc) {
        pDesc->RefreshRate.Numerator = 60;
        pDesc->RefreshRate.Denominator = 1;
        pDesc->ScanlineOrdering = DXGI_MODE_SCANLINE_ORDER_UNSPECIFIED;
        pDesc->Scaling = DXGI_MODE_SCALING_UNSPECIFIED;
        pDesc->Windowed = TRUE;
    }
    return S_OK;
}

HWND STDMETHODCALLTYPE MLSwapChain::GetHwnd() {
    return 0;
}

HRESULT STDMETHODCALLTYPE MLSwapChain::GetCoreWindow(REFIID riid, void** ppWindow) {
    if (ppWindow) *ppWindow = nullptr;
    return DXGI_ERROR_NOT_FOUND;
}

HRESULT STDMETHODCALLTYPE MLSwapChain::Present1(
    UINT SyncInterval,
    UINT PresentFlags,
    const DXGI_PRESENT_PARAMETERS* pPresentParameters) {
    return Present(SyncInterval, PresentFlags);
}

win_BOOL STDMETHODCALLTYPE MLSwapChain::IsTemporaryMonoSupported() {
    return FALSE;
}

HRESULT STDMETHODCALLTYPE MLSwapChain::GetRestrictToOutput(IDXGIOutput** ppRestrictToOutput) {
    if (ppRestrictToOutput) *ppRestrictToOutput = nullptr;
    return DXGI_ERROR_NOT_FOUND;
}

HRESULT STDMETHODCALLTYPE MLSwapChain::SetBackgroundColor(const DXGI_RGBA* pColor) {
    return S_OK;
}

HRESULT STDMETHODCALLTYPE MLSwapChain::GetBackgroundColor(DXGI_RGBA* pColor) {
    if (pColor) {
        pColor->r = pColor->g = pColor->b = pColor->a = 0.0f;
    }
    return S_OK;
}

HRESULT STDMETHODCALLTYPE MLSwapChain::SetRotation(DXGI_MODE_ROTATION Rotation) {
    return S_OK;
}

HRESULT STDMETHODCALLTYPE MLSwapChain::GetRotation(DXGI_MODE_ROTATION* pRotation) {
    if (pRotation) *pRotation = DXGI_MODE_ROTATION_IDENTITY;
    return S_OK;
}

// IDXGISwapChain2 Methods
HRESULT STDMETHODCALLTYPE MLSwapChain::SetSourceSize(UINT Width, UINT Height) {
    return S_OK;
}

HRESULT STDMETHODCALLTYPE MLSwapChain::GetSourceSize(UINT* pWidth, UINT* pHeight) {
    if (pWidth) *pWidth = m_width;
    if (pHeight) *pHeight = m_height;
    return S_OK;
}

HRESULT STDMETHODCALLTYPE MLSwapChain::SetMaximumFrameLatency(UINT MaxLatency) {
    return S_OK;
}

HRESULT STDMETHODCALLTYPE MLSwapChain::GetMaximumFrameLatency(UINT* pMaxLatency) {
    if (pMaxLatency) *pMaxLatency = 1;
    return S_OK;
}

HANDLE STDMETHODCALLTYPE MLSwapChain::GetFrameLatencyWaitableObject() {
    return nullptr;
}

HRESULT STDMETHODCALLTYPE MLSwapChain::SetMatrixTransform(const DXGI_MATRIX_TRANSFORM* pMatrix) {
    return S_OK;
}

HRESULT STDMETHODCALLTYPE MLSwapChain::GetMatrixTransform(DXGI_MATRIX_TRANSFORM* pMatrix) {
    if (pMatrix) {
        pMatrix->_11 = 1.0f; pMatrix->_12 = 0.0f;
        pMatrix->_21 = 0.0f; pMatrix->_22 = 1.0f;
        pMatrix->_31 = 0.0f; pMatrix->_32 = 0.0f;
    }
    return S_OK;
}

// IDXGISwapChain3 Methods
UINT STDMETHODCALLTYPE MLSwapChain::GetCurrentBackBufferIndex() {
    return m_currentBufferIndex;
}

HRESULT STDMETHODCALLTYPE MLSwapChain::CheckColorSpaceSupport(DXGI_COLOR_SPACE_TYPE ColorSpace, UINT* pColorSpaceSupport) {
    if (pColorSpaceSupport) {
        *pColorSpaceSupport = DXGI_SWAP_CHAIN_COLOR_SPACE_SUPPORT_FLAG_PRESENT;
    }
    return S_OK;
}

HRESULT STDMETHODCALLTYPE MLSwapChain::SetColorSpace1(DXGI_COLOR_SPACE_TYPE ColorSpace) {
    return S_OK;
}

HRESULT STDMETHODCALLTYPE MLSwapChain::ResizeBuffers1(
    UINT BufferCount,
    UINT Width,
    UINT Height,
    DXGI_FORMAT Format,
    UINT SwapChainFlags,
    const UINT* pCreationNodeMask,
    IUnknown* const* ppPresentQueue) {
    return ResizeBuffers(BufferCount, Width, Height, Format, SwapChainFlags);
}
