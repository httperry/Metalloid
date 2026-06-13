#include "Metalloid/Resources/MLHeap.h"
#include <iostream>

#ifdef __OBJC__
#import <Metal/Metal.h>
#endif

MLHeap::MLHeap(ID3D12Device* parentDevice, MetalHeapType metalHeap, const D3D12_HEAP_DESC& desc)
    : m_refCount(1), m_parentDevice(parentDevice), m_metalHeap(metalHeap), m_desc(desc) {
    std::cout << "[Metalloid] ID3D12Heap created (Size: " << desc.SizeInBytes << ")." << std::endl;
}

MLHeap::~MLHeap() {
#ifdef __OBJC__
    if (m_metalHeap) {
        m_metalHeap = nil;
    }
#endif
}

HRESULT STDMETHODCALLTYPE MLHeap::QueryInterface(REFIID riid, void** ppvObject) {
    if (!ppvObject) return E_POINTER;
    if (riid == __uuidof(ID3D12Heap) || riid == __uuidof(ID3D12Pageable) || riid == __uuidof(ID3D12DeviceChild) || riid == __uuidof(ID3D12Object) || riid == __uuidof(IUnknown)) {
        *ppvObject = static_cast<ID3D12Heap*>(this);
        AddRef();
        return S_OK;
    }
    *ppvObject = nullptr;
    return E_NOINTERFACE;
}

ULONG STDMETHODCALLTYPE MLHeap::AddRef() {
    return ++m_refCount;
}

ULONG STDMETHODCALLTYPE MLHeap::Release() {
    ULONG count = --m_refCount;
    if (count == 0) {
        delete this;
    }
    return count;
}

ML_IMPL_PRIVATE_DATA(MLHeap)
HRESULT STDMETHODCALLTYPE MLHeap::SetName(LPCWSTR Name) {
#ifdef __OBJC__
    if (m_metalHeap && Name) {
        NSString* nameStr = [[NSString alloc] initWithBytes:Name length:wcslen(Name)*sizeof(wchar_t) encoding:(sizeof(wchar_t) == 4 ? NSUTF32LittleEndianStringEncoding : NSUTF16LittleEndianStringEncoding)];
        m_metalHeap.label = nameStr;
    }
#endif
    return S_OK;
}

HRESULT STDMETHODCALLTYPE MLHeap::GetDevice(REFIID riid, void** ppvDevice) {
    if (!ppvDevice) return E_POINTER;
    if (m_parentDevice) {
        return m_parentDevice->QueryInterface(riid, ppvDevice);
    }
    return E_NOINTERFACE;
}

D3D12_HEAP_DESC STDMETHODCALLTYPE MLHeap::GetDesc() {
    return m_desc;
}

UINT64 MLHeap::GetOrCreateGenerationForRange(UINT64 offset, UINT64 size) {
    std::lock_guard<std::mutex> lock(m_heapMutex);
    
    bool overlapFound = false;
    for (const auto& range : m_memoryRanges) {
        if (offset < range.offset + range.size && range.offset < offset + size) {
            overlapFound = true;
            break;
        }
    }
    
    if (overlapFound) {
        m_globalHeapGen++;
    }
    
    PhysicalMemoryRange newRange;
    newRange.offset = offset;
    newRange.size = size;
    newRange.generationId = m_globalHeapGen;
    
    m_memoryRanges.push_back(newRange);
    return m_globalHeapGen;
}

void MLHeap::InvalidateRange(UINT64 offset, UINT64 size) {
    std::lock_guard<std::mutex> lock(m_heapMutex);
    for (auto it = m_memoryRanges.begin(); it != m_memoryRanges.end(); ) {
        if (it->offset == offset && it->size == size) {
            it = m_memoryRanges.erase(it);
            break;
        } else {
            ++it;
        }
    }
}
