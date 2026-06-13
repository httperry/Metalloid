#include "Metalloid/DXGI/MLFactory.h"
#include "Metalloid/DXGI/MLSwapChain.h"
#include <iostream>
#include <cwchar>

#ifdef __OBJC__
#import <AppKit/AppKit.h>
#import <QuartzCore/CAMetalLayer.h>
#endif

// ============================================================================
// MLAdapter Implementation
// ============================================================================

static class MLAdapter* g_mlAdapter = nullptr;
static class MLOutput* g_mlOutput = nullptr;

MLAdapter::MLAdapter() : m_refCount(1) {
    std::cout << "[Metalloid] IDXGIAdapter1 initialized." << std::endl;
}

MLAdapter::~MLAdapter() {
    std::cout << "[Metalloid] IDXGIAdapter1 destroyed." << std::endl;
}

HRESULT STDMETHODCALLTYPE MLAdapter::QueryInterface(REFIID riid, void** ppvObject) {
    if (!ppvObject) return E_POINTER;

    if (riid == __uuidof(IUnknown) ||
        riid == __uuidof(IDXGIObject) ||
        riid == __uuidof(IDXGIAdapter) ||
        riid == __uuidof(IDXGIAdapter1) ||
        riid == __uuidof(IDXGIAdapter2) ||
        riid == __uuidof(IDXGIAdapter3) ||
        riid == __uuidof(IDXGIAdapter4)) {
        *ppvObject = static_cast<IDXGIAdapter4*>(this);
        AddRef();
        return S_OK;
    }

    *ppvObject = nullptr;
    return E_NOINTERFACE;
}

ULONG STDMETHODCALLTYPE MLAdapter::AddRef() {
    return ++m_refCount;
}

ULONG STDMETHODCALLTYPE MLAdapter::Release() {
    ULONG count = --m_refCount;
    if (count == 0) {
        if (g_mlAdapter == this) g_mlAdapter = nullptr;
        delete this;
    }
    return count;
}

ML_IMPL_PRIVATE_DATA(MLAdapter)

HRESULT STDMETHODCALLTYPE MLAdapter::GetParent(REFIID riid, void** ppParent) {
    if (!ppParent) return E_POINTER;
    MLFactory* pFactory = new MLFactory();
    HRESULT hr = pFactory->QueryInterface(riid, ppParent);
    pFactory->Release();
    return hr;
}

// ============================================================================
// MLOutput Implementation
// ============================================================================

MLOutput::MLOutput() {
    std::cout << "[Metalloid] IDXGIOutput created." << std::endl;
}

MLOutput::~MLOutput() {
    std::cout << "[Metalloid] IDXGIOutput destroyed." << std::endl;
}

HRESULT STDMETHODCALLTYPE MLOutput::QueryInterface(REFIID riid, void** ppvObject) {
    if (!ppvObject) return E_INVALIDARG;
    if (riid == __uuidof(IUnknown) || riid == __uuidof(IDXGIObject) || riid == __uuidof(IDXGIOutput)) {
        *ppvObject = this;
        AddRef();
        return S_OK;
    }
    *ppvObject = nullptr;
    return E_NOINTERFACE;
}

ULONG STDMETHODCALLTYPE MLOutput::AddRef() {
    return m_refCount.fetch_add(1) + 1;
}

ULONG STDMETHODCALLTYPE MLOutput::Release() {
    ULONG count = m_refCount.fetch_sub(1) - 1;
    if (count == 0) {
        if (g_mlOutput == this) g_mlOutput = nullptr;
        delete this;
    }
    return count;
}

ML_IMPL_PRIVATE_DATA(MLOutput)
HRESULT STDMETHODCALLTYPE MLOutput::GetParent(REFIID riid, void** ppParent) {
    if (!ppParent) return E_POINTER;
    if (!g_mlAdapter) {
        g_mlAdapter = new MLAdapter();
    }
    g_mlAdapter->AddRef();
    HRESULT hr = g_mlAdapter->QueryInterface(riid, ppParent);
    g_mlAdapter->Release();
    return hr;
}

HRESULT STDMETHODCALLTYPE MLOutput::GetDesc(DXGI_OUTPUT_DESC *pDesc) {
    if (!pDesc) return E_INVALIDARG;
    std::wcscpy(pDesc->DeviceName, L"Apple Display");
    pDesc->DesktopCoordinates = {0, 0, 1920, 1080};
    pDesc->AttachedToDesktop = TRUE;
    pDesc->Rotation = DXGI_MODE_ROTATION_UNSPECIFIED;
    pDesc->Monitor = nullptr;
    return S_OK;
}

HRESULT STDMETHODCALLTYPE MLOutput::GetDisplayModeList(DXGI_FORMAT EnumFormat, UINT Flags, UINT *pNumModes, DXGI_MODE_DESC *pDesc) {
    if (!pNumModes) return E_INVALIDARG;
    if (!pDesc) {
        *pNumModes = 1;
        return S_OK;
    }
    if (*pNumModes > 0) {
        pDesc[0].Width = 1920;
        pDesc[0].Height = 1080;
        pDesc[0].RefreshRate.Numerator = 60;
        pDesc[0].RefreshRate.Denominator = 1;
        pDesc[0].Format = EnumFormat;
        pDesc[0].ScanlineOrdering = DXGI_MODE_SCANLINE_ORDER_UNSPECIFIED;
        pDesc[0].Scaling = DXGI_MODE_SCALING_UNSPECIFIED;
        *pNumModes = 1;
        return S_OK;
    }
    return DXGI_ERROR_NOT_FOUND;
}

HRESULT STDMETHODCALLTYPE MLOutput::FindClosestMatchingMode(const DXGI_MODE_DESC *pModeToMatch, DXGI_MODE_DESC *pClosestMatch, IUnknown *pConcernedDevice) {
    if (!pModeToMatch || !pClosestMatch) return E_INVALIDARG;
    *pClosestMatch = *pModeToMatch;
    if (pClosestMatch->Format == DXGI_FORMAT_UNKNOWN) {
        pClosestMatch->Format = DXGI_FORMAT_R8G8B8A8_UNORM;
    }
    if (pClosestMatch->Width == 0) pClosestMatch->Width = 1920;
    if (pClosestMatch->Height == 0) pClosestMatch->Height = 1080;
    if (pClosestMatch->RefreshRate.Numerator == 0) {
        pClosestMatch->RefreshRate.Numerator = 60;
        pClosestMatch->RefreshRate.Denominator = 1;
    }
    return S_OK;
}
HRESULT STDMETHODCALLTYPE MLOutput::WaitForVBlank() { return S_OK; }
HRESULT STDMETHODCALLTYPE MLOutput::TakeOwnership(IUnknown *pDevice, win_BOOL Exclusive) { return S_OK; }
void STDMETHODCALLTYPE MLOutput::ReleaseOwnership() {}
HRESULT STDMETHODCALLTYPE MLOutput::GetGammaControlCapabilities(DXGI_GAMMA_CONTROL_CAPABILITIES *pGammaCaps) { return DXGI_ERROR_UNSUPPORTED; }
HRESULT STDMETHODCALLTYPE MLOutput::SetGammaControl(const DXGI_GAMMA_CONTROL *pArray) { return DXGI_ERROR_UNSUPPORTED; }
HRESULT STDMETHODCALLTYPE MLOutput::GetGammaControl(DXGI_GAMMA_CONTROL *pArray) { return DXGI_ERROR_UNSUPPORTED; }
HRESULT STDMETHODCALLTYPE MLOutput::SetDisplaySurface(IDXGISurface *pScanoutSurface) { return DXGI_ERROR_UNSUPPORTED; }
HRESULT STDMETHODCALLTYPE MLOutput::GetDisplaySurfaceData(IDXGISurface *pDestination) { return DXGI_ERROR_UNSUPPORTED; }
HRESULT STDMETHODCALLTYPE MLOutput::GetFrameStatistics(DXGI_FRAME_STATISTICS *pStats) { return DXGI_ERROR_UNSUPPORTED; }

HRESULT STDMETHODCALLTYPE MLAdapter::EnumOutputs(UINT Output, IDXGIOutput** ppOutput) {
    if (!ppOutput) return E_INVALIDARG;
    if (Output == 0) {
        if (!g_mlOutput) {
            g_mlOutput = new MLOutput();
        } else {
            g_mlOutput->AddRef();
        }
        *ppOutput = g_mlOutput;
        return S_OK;
    }
    *ppOutput = nullptr;
    return DXGI_ERROR_NOT_FOUND;
}

HRESULT STDMETHODCALLTYPE MLAdapter::GetDesc(DXGI_ADAPTER_DESC* pDesc) {
    if (!pDesc) return E_INVALIDARG;
    
    std::wcscpy(pDesc->Description, L"Apple Silicon GPU");
    pDesc->VendorId = 0x106B; // Apple PCI Vendor ID
    pDesc->DeviceId = 0x0001;
    pDesc->SubSysId = 0;
    pDesc->Revision = 0;
    pDesc->DedicatedVideoMemory = 16ULL * 1024 * 1024 * 1024; // Mock 16GB
    pDesc->DedicatedSystemMemory = 0;
    pDesc->SharedSystemMemory = 0;
    pDesc->AdapterLuid = LUID{0, 1};
    
    return S_OK;
}

HRESULT STDMETHODCALLTYPE MLAdapter::CheckInterfaceSupport(REFGUID Name, LARGE_INTEGER *pUMDVersion) {
    if (pUMDVersion) {
        pUMDVersion->QuadPart = 0;
        
    }
    return S_OK;
}

HRESULT STDMETHODCALLTYPE MLAdapter::GetDesc1(DXGI_ADAPTER_DESC1* pDesc) {
    if (!pDesc) return E_INVALIDARG;
    
    std::wcscpy(pDesc->Description, L"Apple Silicon GPU");
    pDesc->VendorId = 0x106B; // Apple PCI Vendor ID
    pDesc->DeviceId = 0x0001;
    pDesc->SubSysId = 0;
    pDesc->Revision = 0;
    pDesc->DedicatedVideoMemory = 16ULL * 1024 * 1024 * 1024;
    pDesc->DedicatedSystemMemory = 0;
    pDesc->SharedSystemMemory = 0;
    pDesc->AdapterLuid = LUID{0, 1};
    pDesc->Flags = DXGI_ADAPTER_FLAG_NONE;
    
    return S_OK;
}

HRESULT STDMETHODCALLTYPE MLAdapter::GetDesc2(DXGI_ADAPTER_DESC2* pDesc) {
    if (!pDesc) return E_INVALIDARG;
    DXGI_ADAPTER_DESC1 desc1;
    GetDesc1(&desc1);
    memcpy(pDesc->Description, desc1.Description, sizeof(pDesc->Description));
    pDesc->VendorId = desc1.VendorId;
    pDesc->DeviceId = desc1.DeviceId;
    pDesc->SubSysId = desc1.SubSysId;
    pDesc->Revision = desc1.Revision;
    pDesc->DedicatedVideoMemory = desc1.DedicatedVideoMemory;
    pDesc->DedicatedSystemMemory = desc1.DedicatedSystemMemory;
    pDesc->SharedSystemMemory = desc1.SharedSystemMemory;
    pDesc->AdapterLuid = desc1.AdapterLuid;
    pDesc->Flags = desc1.Flags;
    pDesc->GraphicsPreemptionGranularity = DXGI_GRAPHICS_PREEMPTION_DMA_BUFFER_BOUNDARY;
    pDesc->ComputePreemptionGranularity = DXGI_COMPUTE_PREEMPTION_DMA_BUFFER_BOUNDARY;
    return S_OK;
}

HRESULT STDMETHODCALLTYPE MLAdapter::RegisterHardwareContentProtectionTeardownStatusEvent(HANDLE hEvent, DWORD* pdwCookie) {
    if (pdwCookie) *pdwCookie = 0;
    return DXGI_ERROR_UNSUPPORTED;
}
void STDMETHODCALLTYPE MLAdapter::UnregisterHardwareContentProtectionTeardownStatus(DWORD dwCookie) {}
HRESULT STDMETHODCALLTYPE MLAdapter::QueryVideoMemoryInfo(UINT NodeIndex, DXGI_MEMORY_SEGMENT_GROUP MemorySegmentGroup, DXGI_QUERY_VIDEO_MEMORY_INFO* pVideoMemoryInfo) {
    if (pVideoMemoryInfo) {
        pVideoMemoryInfo->Budget = 16ULL * 1024 * 1024 * 1024; // 16GB
        pVideoMemoryInfo->CurrentUsage = 0;
        pVideoMemoryInfo->AvailableForReservation = pVideoMemoryInfo->Budget / 2;
        pVideoMemoryInfo->CurrentReservation = 0;
    }
    return S_OK;
}
HRESULT STDMETHODCALLTYPE MLAdapter::SetVideoMemoryReservation(UINT NodeIndex, DXGI_MEMORY_SEGMENT_GROUP MemorySegmentGroup, UINT64 Reservation) { return S_OK; }
HRESULT STDMETHODCALLTYPE MLAdapter::RegisterVideoMemoryBudgetChangeNotificationEvent(HANDLE hEvent, DWORD* pdwCookie) {
    if (pdwCookie) *pdwCookie = 0;
    return S_OK;
}
void STDMETHODCALLTYPE MLAdapter::UnregisterVideoMemoryBudgetChangeNotification(DWORD dwCookie) {}

HRESULT STDMETHODCALLTYPE MLAdapter::GetDesc3(DXGI_ADAPTER_DESC3* pDesc) {
    if (!pDesc) return E_INVALIDARG;
    DXGI_ADAPTER_DESC2 desc2;
    GetDesc2(&desc2);
    memcpy(pDesc->Description, desc2.Description, sizeof(pDesc->Description));
    pDesc->VendorId = desc2.VendorId;
    pDesc->DeviceId = desc2.DeviceId;
    pDesc->SubSysId = desc2.SubSysId;
    pDesc->Revision = desc2.Revision;
    pDesc->DedicatedVideoMemory = desc2.DedicatedVideoMemory;
    pDesc->DedicatedSystemMemory = desc2.DedicatedSystemMemory;
    pDesc->SharedSystemMemory = desc2.SharedSystemMemory;
    pDesc->AdapterLuid = desc2.AdapterLuid;
    pDesc->Flags = desc2.Flags;
    pDesc->GraphicsPreemptionGranularity = desc2.GraphicsPreemptionGranularity;
    pDesc->ComputePreemptionGranularity = desc2.ComputePreemptionGranularity;
    return S_OK;
}

// ============================================================================
// MLFactory Implementation
// ============================================================================

MLFactory::MLFactory() : m_refCount(1) {
    std::cout << "[Metalloid] IDXGIFactory4 initialized." << std::endl;
}

MLFactory::~MLFactory() {
    std::cout << "[Metalloid] IDXGIFactory4 destroyed." << std::endl;
}

HRESULT STDMETHODCALLTYPE MLFactory::QueryInterface(REFIID riid, void** ppvObject) {
    if (!ppvObject) return E_POINTER;

    if (riid == __uuidof(IUnknown) ||
        riid == __uuidof(IDXGIObject) ||
        riid == __uuidof(IDXGIFactory) ||
        riid == __uuidof(IDXGIFactory1) ||
        riid == __uuidof(IDXGIFactory2) ||
        riid == __uuidof(IDXGIFactory3) ||
        riid == __uuidof(IDXGIFactory4)) {
        *ppvObject = static_cast<IDXGIFactory4*>(this);
        AddRef();
        return S_OK;
    }

    *ppvObject = nullptr;
    return E_NOINTERFACE;
}

ULONG STDMETHODCALLTYPE MLFactory::AddRef() {
    return ++m_refCount;
}

ULONG STDMETHODCALLTYPE MLFactory::Release() {
    ULONG count = --m_refCount;
    if (count == 0) {
        delete this;
    }
    return count;
}

ML_IMPL_PRIVATE_DATA(MLFactory)

HRESULT STDMETHODCALLTYPE MLFactory::GetParent(REFIID riid, void** ppParent) {
    if (ppParent) *ppParent = nullptr;
    return E_NOINTERFACE;
}

HRESULT STDMETHODCALLTYPE MLFactory::EnumAdapters(UINT Adapter, IDXGIAdapter** ppAdapter) {
    if (!ppAdapter) return E_INVALIDARG;
    if (Adapter > 0) {
        *ppAdapter = nullptr;
        return DXGI_ERROR_NOT_FOUND;
    }
    if (!g_mlAdapter) {
        g_mlAdapter = new MLAdapter();
    } else {
        g_mlAdapter->AddRef();
    }
    *ppAdapter = g_mlAdapter;
    return S_OK;
}

HRESULT STDMETHODCALLTYPE MLFactory::MakeWindowAssociation(HWND WindowHandle, UINT Flags) {
    return S_OK;
}

HRESULT STDMETHODCALLTYPE MLFactory::GetWindowAssociation(HWND* pWindowHandle) {
    if (pWindowHandle) *pWindowHandle = 0;
    return S_OK;
}

HRESULT STDMETHODCALLTYPE MLFactory::CreateSwapChain(
    IUnknown* pDevice,
    DXGI_SWAP_CHAIN_DESC* pDesc,
    IDXGISwapChain** ppSwapChain) {
    if (!ppSwapChain || !pDesc) return E_INVALIDARG;
    MLSwapChain* sc = new MLSwapChain(pDevice, pDesc->BufferDesc.Width, pDesc->BufferDesc.Height, pDesc->BufferCount, pDesc->BufferDesc.Format);
    HRESULT hr = sc->QueryInterface(__uuidof(IDXGISwapChain), (void**)ppSwapChain);
    sc->Release();
    return hr;
}

HRESULT STDMETHODCALLTYPE MLFactory::CreateSoftwareAdapter(HMODULE Module, IDXGIAdapter** ppAdapter) {
    if (ppAdapter) {
        *ppAdapter = nullptr;
    }
    return DXGI_ERROR_UNSUPPORTED;
}

HRESULT STDMETHODCALLTYPE MLFactory::EnumAdapters1(UINT Adapter, IDXGIAdapter1** ppAdapter) {
    if (!ppAdapter) return E_INVALIDARG;
    if (Adapter > 0) {
        *ppAdapter = nullptr;
        return DXGI_ERROR_NOT_FOUND;
    }
    if (!g_mlAdapter) {
        g_mlAdapter = new MLAdapter();
    } else {
        g_mlAdapter->AddRef();
    }
    *ppAdapter = g_mlAdapter;
    return S_OK;
}

win_BOOL STDMETHODCALLTYPE MLFactory::IsCurrent() {
    return TRUE;
}

win_BOOL STDMETHODCALLTYPE MLFactory::IsWindowedStereoEnabled() {
    return FALSE;
}

HRESULT STDMETHODCALLTYPE MLFactory::CreateSwapChainForHwnd(
    IUnknown* pDevice,
    HWND hWnd,
    const DXGI_SWAP_CHAIN_DESC1* pDesc,
    const DXGI_SWAP_CHAIN_FULLSCREEN_DESC* pFullscreenDesc,
    IDXGIOutput* pRestrictToOutput,
    IDXGISwapChain1** ppSwapChain) {
    if (!ppSwapChain || !pDesc) return E_INVALIDARG;
    MLSwapChain* sc = new MLSwapChain(pDevice, pDesc->Width, pDesc->Height, pDesc->BufferCount, pDesc->Format);
    
#ifdef __OBJC__
    if (hWnd) {
        NSView* view = (__bridge NSView*)(void*)hWnd;
        CAMetalLayer* layer = sc->GetMetalLayer();
        view.wantsLayer = YES;
        [view.layer addSublayer:layer];
        layer.frame = view.bounds;
        layer.autoresizingMask = kCALayerWidthSizable | kCALayerHeightSizable;
    }
#endif

    HRESULT hr = sc->QueryInterface(__uuidof(IDXGISwapChain1), (void**)ppSwapChain);
    sc->Release();
    return hr;
}

HRESULT STDMETHODCALLTYPE MLFactory::CreateSwapChainForCoreWindow(
    IUnknown* pDevice,
    IUnknown* pWindow,
    const DXGI_SWAP_CHAIN_DESC1* pDesc,
    IDXGIOutput* pRestrictToOutput,
    IDXGISwapChain1** ppSwapChain) {
    if (ppSwapChain) *ppSwapChain = nullptr;
    return DXGI_ERROR_UNSUPPORTED;
}

HRESULT STDMETHODCALLTYPE MLFactory::GetSharedResourceAdapterLuid(HANDLE hResource, LUID* pLuid) {
    return DXGI_ERROR_UNSUPPORTED;
}

HRESULT STDMETHODCALLTYPE MLFactory::RegisterOcclusionStatusWindow(HWND WindowHandle, UINT wMsg, DWORD* pdwCookie) {
    return DXGI_ERROR_UNSUPPORTED;
}

HRESULT STDMETHODCALLTYPE MLFactory::RegisterOcclusionStatusEvent(HANDLE hEvent, DWORD* pdwCookie) {
    return DXGI_ERROR_UNSUPPORTED;
}

void STDMETHODCALLTYPE MLFactory::UnregisterOcclusionStatus(DWORD dwCookie) {
}

HRESULT STDMETHODCALLTYPE MLFactory::RegisterStereoStatusWindow(HWND WindowHandle, UINT wMsg, DWORD* pdwCookie) {
    return DXGI_ERROR_UNSUPPORTED;
}

HRESULT STDMETHODCALLTYPE MLFactory::RegisterStereoStatusEvent(HANDLE hEvent, DWORD* pdwCookie) {
    return DXGI_ERROR_UNSUPPORTED;
}

void STDMETHODCALLTYPE MLFactory::UnregisterStereoStatus(DWORD dwCookie) {
}

UINT STDMETHODCALLTYPE MLFactory::GetCreationFlags() {
    return 0;
}

HRESULT STDMETHODCALLTYPE MLFactory::EnumAdapterByLuid(LUID AdapterLuid, REFIID riid, void** ppAdapter) {
    if (!ppAdapter) return E_INVALIDARG;
    if (!g_mlAdapter) {
        g_mlAdapter = new MLAdapter();
    } else {
        g_mlAdapter->AddRef();
    }
    HRESULT hr = g_mlAdapter->QueryInterface(riid, ppAdapter);
    g_mlAdapter->Release();
    return hr;
}

HRESULT STDMETHODCALLTYPE MLFactory::EnumWarpAdapter(REFIID riid, void** ppAdapter) {
    if (ppAdapter) {
        *ppAdapter = nullptr;
    }
    return DXGI_ERROR_UNSUPPORTED;
}

// ============================================================================
// DXGI Entry Points
// ============================================================================

extern "C" ML_EXPORT HRESULT WINAPI CreateDXGIFactory(REFIID riid, void** ppFactory) {
    if (!ppFactory) return E_INVALIDARG;
    MLFactory* factory = new MLFactory();
    HRESULT hr = factory->QueryInterface(riid, ppFactory);
    factory->Release();
    return hr;
}

extern "C" ML_EXPORT HRESULT WINAPI CreateDXGIFactory1(REFIID riid, void** ppFactory) {
    if (!ppFactory) return E_INVALIDARG;
    MLFactory* factory = new MLFactory();
    HRESULT hr = factory->QueryInterface(riid, ppFactory);
    factory->Release();
    return hr;
}

extern "C" ML_EXPORT HRESULT WINAPI CreateDXGIFactory2(UINT Flags, REFIID riid, void** ppFactory) {
    if (!ppFactory) return E_INVALIDARG;
    MLFactory* factory = new MLFactory();
    HRESULT hr = factory->QueryInterface(riid, ppFactory);
    factory->Release();
    return hr;
}
