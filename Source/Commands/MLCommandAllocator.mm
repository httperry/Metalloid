#include "Metalloid/Commands/MLCommandAllocator.h"
#include <iostream>
#include <unordered_map>
#include <mutex>
#include <algorithm>

#ifdef __OBJC__
#import <Metal/Metal.h>
#import <objc/runtime.h>
#endif

// Static map to track allocated command buffer counts without modifying the header.
static std::unordered_map<MLCommandAllocator*, size_t> s_poolIndices;
static std::mutex s_poolMutex;

MLCommandAllocator::MLCommandAllocator(ID3D12Device* parentDevice, D3D12_COMMAND_LIST_TYPE type, void* defaultQueue) 
    : m_refCount(1), m_parentDevice(parentDevice), m_type(type), m_defaultQueue(defaultQueue) {
    std::cout << "[Metalloid] ID3D12CommandAllocator created." << std::endl;
    std::lock_guard<std::mutex> lock(s_poolMutex);
    s_poolIndices[this] = 0;
}

MLCommandAllocator::~MLCommandAllocator() {
    std::cout << "[Metalloid] ID3D12CommandAllocator destroyed." << std::endl;
    std::lock_guard<std::mutex> lock(s_poolMutex);
    s_poolIndices.erase(this);

#ifdef __OBJC__
    for (void* ptr : m_commandBufferPool) {
        id<MTLCommandBuffer> mtlCmdBuf = (__bridge_transfer id<MTLCommandBuffer>)ptr;
        mtlCmdBuf = nil;
    }
    m_commandBufferPool.clear();
#endif
}

HRESULT STDMETHODCALLTYPE MLCommandAllocator::QueryInterface(REFIID riid, void** ppvObject) {
    if (!ppvObject) return E_POINTER;

    if (riid == __uuidof(IUnknown) ||
        riid == __uuidof(ID3D12Object) ||
        riid == __uuidof(ID3D12DeviceChild) ||
        riid == __uuidof(ID3D12CommandAllocator)) {
        *ppvObject = static_cast<ID3D12CommandAllocator*>(this);
        AddRef();
        return S_OK;
    }

    *ppvObject = nullptr;
    return E_NOINTERFACE;
}

ULONG STDMETHODCALLTYPE MLCommandAllocator::AddRef() {
    return ++m_refCount;
}

ULONG STDMETHODCALLTYPE MLCommandAllocator::Release() {
    ULONG count = --m_refCount;
    if (count == 0) {
        delete this;
    }
    return count;
}

ML_IMPL_PRIVATE_DATA(MLCommandAllocator)

HRESULT STDMETHODCALLTYPE MLCommandAllocator::SetName(LPCWSTR Name) {
#ifdef __OBJC__
    if (Name) {
        UINT size = (UINT)(wcslen(Name) * sizeof(wchar_t));
        NSString* nameStr = [[NSString alloc] initWithBytes:Name length:size encoding:NSUTF32LittleEndianStringEncoding];
        (void)nameStr;
    }
#endif
    return S_OK;
}

HRESULT STDMETHODCALLTYPE MLCommandAllocator::GetDevice(REFIID riid, void** ppvDevice) {
    if (!ppvDevice) return E_POINTER;
    if (m_parentDevice) {
        return m_parentDevice->QueryInterface(riid, ppvDevice);
    }
    return E_NOINTERFACE;
}

void* MLCommandAllocator::AllocateCommandBuffer() {
#ifdef __OBJC__
    id<MTLCommandQueue> mtlQueue = (__bridge id<MTLCommandQueue>)m_defaultQueue;
    if (!mtlQueue) return nullptr;

    size_t currentIndex = 0;
    {
        std::lock_guard<std::mutex> lock(s_poolMutex);
        currentIndex = s_poolIndices[this];
        s_poolIndices[this] = currentIndex + 1;
    }

    if (currentIndex < m_commandBufferPool.size()) {
        id<MTLCommandBuffer> cachedBuf = (__bridge id<MTLCommandBuffer>)m_commandBufferPool[currentIndex];
        return (__bridge void*)cachedBuf;
    }

    // Allocate a new command buffer with descriptor to enable timestamp profiling
    MTLCommandBufferDescriptor* desc = [[MTLCommandBufferDescriptor alloc] init];
    desc.retainedReferences = NO; 
    desc.errorOptions = MTLCommandBufferErrorOptionNone; 
    
    id<MTLCommandBuffer> mtlCmdBuf = [mtlQueue commandBufferWithDescriptor:desc];

    static const void* MLTimestampQueriesKey = &MLTimestampQueriesKey;

    // Ensure timestamp profiling queries are correctly implemented and end queries are mapped correctly
    [mtlCmdBuf addCompletedHandler:^(id<MTLCommandBuffer> cb) {
        NSArray* queryBlocks = objc_getAssociatedObject(cb, MLTimestampQueriesKey);
        if (queryBlocks) {
            uint64_t gpuEndTicks = (uint64_t)(cb.GPUEndTime * 1000000000.0);
            for (void (^block)(uint64_t) in queryBlocks) {
                block(gpuEndTicks);
            }
            objc_setAssociatedObject(cb, MLTimestampQueriesKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
    }];

    m_commandBufferPool.push_back((__bridge_retained void*)mtlCmdBuf);
    return (__bridge void*)mtlCmdBuf;
#else
    return nullptr;
#endif
}

HRESULT STDMETHODCALLTYPE MLCommandAllocator::Reset() {
    std::cout << "[Metalloid] ID3D12CommandAllocator::Reset called." << std::endl;
#ifdef __OBJC__
    id<MTLCommandQueue> mtlQueue = (__bridge id<MTLCommandQueue>)m_defaultQueue;
    if (mtlQueue) {
        size_t allocatedCount = 0;
        {
            std::lock_guard<std::mutex> lock(s_poolMutex);
            allocatedCount = s_poolIndices[this];
            s_poolIndices[this] = 0;
        }

        allocatedCount = std::min(allocatedCount, m_commandBufferPool.size());

        static const void* MLTimestampQueriesKey = &MLTimestampQueriesKey;

        // Maintain true cache pool: replace only the used command buffers with fresh ones
        for (size_t i = 0; i < allocatedCount; ++i) {
            id<MTLCommandBuffer> oldCmdBuf = (__bridge_transfer id<MTLCommandBuffer>)m_commandBufferPool[i];
            oldCmdBuf = nil; // Release old committed buffer
            
            MTLCommandBufferDescriptor* desc = [[MTLCommandBufferDescriptor alloc] init];
            desc.retainedReferences = NO;
            desc.errorOptions = MTLCommandBufferErrorOptionNone;
            
            id<MTLCommandBuffer> newCmdBuf = [mtlQueue commandBufferWithDescriptor:desc];
            
            [newCmdBuf addCompletedHandler:^(id<MTLCommandBuffer> cb) {
                NSArray* queryBlocks = objc_getAssociatedObject(cb, MLTimestampQueriesKey);
                if (queryBlocks) {
                    uint64_t gpuEndTicks = (uint64_t)(cb.GPUEndTime * 1000000000.0);
                    for (void (^block)(uint64_t) in queryBlocks) {
                        block(gpuEndTicks);
                    }
                    objc_setAssociatedObject(cb, MLTimestampQueriesKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                }
            }];
            
            m_commandBufferPool[i] = (__bridge_retained void*)newCmdBuf;
        }
    }
#endif
    return S_OK;
}
