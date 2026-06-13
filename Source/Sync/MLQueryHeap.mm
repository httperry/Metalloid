#include "Metalloid/Sync/MLQueryHeap.h"
#include "Metalloid/Device/MLDevice.h"
#include <iostream>

#ifdef __OBJC__
#import <Metal/Metal.h>
#endif

MLQueryHeap::MLQueryHeap(ID3D12Device* parentDevice, MetalBufferType queryBuffer, const D3D12_QUERY_HEAP_DESC& desc)
    : m_refCount(1), m_parentDevice(parentDevice), m_queryBuffer(queryBuffer), m_desc(desc), m_counterSampleBuffer(nullptr) {
    std::cout << "[Metalloid] ID3D12QueryHeap created (Type: " << desc.Type << ", Count: " << desc.Count << ")." << std::endl;

#ifdef __OBJC__
    if (desc.Type == D3D12_QUERY_HEAP_TYPE_TIMESTAMP) {
        id<MTLDevice> metalDevice = ((MLDevice*)parentDevice)->GetMetalDevice();
        if ([metalDevice supportsCounterSampling:MTLCounterSamplingPointAtStageBoundary]) {
            NSError* error = nil;
            MTLCounterSampleBufferDescriptor* csbDesc = [[MTLCounterSampleBufferDescriptor alloc] init];
            csbDesc.counterSet = nullptr; // Initialize with a counter set later if required
            NSArray<id<MTLCounterSet>>* counterSets = [metalDevice counterSets];
            for (id<MTLCounterSet> cs in counterSets) {
                if ([cs.name isEqualToString:MTLCommonCounterSetTimestamp]) {
                    csbDesc.counterSet = cs;
                    break;
                }
            }
            if (csbDesc.counterSet) {
                csbDesc.sampleCount = desc.Count;
                csbDesc.storageMode = MTLStorageModeShared;
                m_counterSampleBuffer = [metalDevice newCounterSampleBufferWithDescriptor:csbDesc error:&error];
                if (error) {
                    std::cerr << "[Metalloid] Failed to create counter sample buffer: " << [[error localizedDescription] UTF8String] << std::endl;
                }
            }
        } else {
            std::cerr << "[Metalloid] Counter sampling not supported on this device." << std::endl;
        }
    }
#endif
}

MLQueryHeap::~MLQueryHeap() {
#ifdef __OBJC__
    if (m_queryBuffer) {
        m_queryBuffer = nil;
    }
    if (m_counterSampleBuffer) {
        m_counterSampleBuffer = nil;
    }
#endif
}

HRESULT STDMETHODCALLTYPE MLQueryHeap::QueryInterface(REFIID riid, void** ppvObject) {
    if (!ppvObject) return E_POINTER;
    if (riid == __uuidof(ID3D12QueryHeap) || riid == __uuidof(ID3D12Pageable) || riid == __uuidof(ID3D12DeviceChild) || riid == __uuidof(ID3D12Object) || riid == __uuidof(IUnknown)) {
        *ppvObject = static_cast<ID3D12QueryHeap*>(this);
        AddRef();
        return S_OK;
    }
    *ppvObject = nullptr;
    return E_NOINTERFACE;
}

ULONG STDMETHODCALLTYPE MLQueryHeap::AddRef() {
    return ++m_refCount;
}

ULONG STDMETHODCALLTYPE MLQueryHeap::Release() {
    ULONG count = --m_refCount;
    if (count == 0) {
        delete this;
    }
    return count;
}

ML_IMPL_PRIVATE_DATA(MLQueryHeap)
HRESULT STDMETHODCALLTYPE MLQueryHeap::SetName(LPCWSTR Name) {
    if (Name) {
        UINT size = (UINT)(wcslen(Name) * sizeof(wchar_t));
        SetPrivateData(WKPDID_D3DDebugObjectNameW, size, Name);
#ifdef __OBJC__
        if (m_queryBuffer) {
            NSString* nameStr = [[NSString alloc] initWithBytes:Name length:size encoding:NSUTF32LittleEndianStringEncoding];
            [(id<MTLBuffer>)m_queryBuffer setLabel:nameStr];
        }
#endif
    } else {
        SetPrivateData(WKPDID_D3DDebugObjectNameW, 0, nullptr);
#ifdef __OBJC__
        if (m_queryBuffer) {
            [(id<MTLBuffer>)m_queryBuffer setLabel:nil];
        }
#endif
    }
    return S_OK;
}

HRESULT STDMETHODCALLTYPE MLQueryHeap::GetDevice(REFIID riid, void** ppvDevice) {
    if (!ppvDevice) return E_POINTER;
    if (m_parentDevice) {
        return m_parentDevice->QueryInterface(riid, ppvDevice);
    }
    return E_NOINTERFACE;
}
