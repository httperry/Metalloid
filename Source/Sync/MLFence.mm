#include "Metalloid/Sync/MLFence.h"
#include <iostream>
#include <pthread.h>

#ifdef __OBJC__
#import <Metal/Metal.h>
#endif

MLFence::MLFence(ID3D12Device* parentDevice, MetalSharedEventType sharedEvent, UINT64 initialValue, D3D12_FENCE_FLAGS flags)
    : m_refCount(1), m_parentDevice(parentDevice), m_sharedEvent(sharedEvent), m_currentValue(initialValue), m_flags(flags) {
#ifdef __OBJC__
    if (m_sharedEvent) {
        [(id<MTLSharedEvent>)m_sharedEvent setSignaledValue:initialValue];
    }
#endif
    std::cout << "[Metalloid] ID3D12Fence created with initial value " << initialValue << "." << std::endl;
}

MLFence::~MLFence() {
#ifdef __OBJC__
    if (m_sharedEvent) {
        // ARC will handle release if bridged correctly, but keeping raw pointer logic clean
        m_sharedEvent = nil;
    }
#endif
}

HRESULT STDMETHODCALLTYPE MLFence::QueryInterface(REFIID riid, void** ppvObject) {
    if (!ppvObject) return E_POINTER;
    if (riid == __uuidof(ID3D12Fence) || riid == __uuidof(ID3D12DeviceChild) || riid == __uuidof(ID3D12Object) || riid == __uuidof(IUnknown)) {
        *ppvObject = static_cast<ID3D12Fence*>(this);
        AddRef();
        return S_OK;
    }
    *ppvObject = nullptr;
    return E_NOINTERFACE;
}

ULONG STDMETHODCALLTYPE MLFence::AddRef() {
    return ++m_refCount;
}

ULONG STDMETHODCALLTYPE MLFence::Release() {
    ULONG count = --m_refCount;
    if (count == 0) {
        delete this;
    }
    return count;
}

ML_IMPL_PRIVATE_DATA(MLFence)
HRESULT STDMETHODCALLTYPE MLFence::SetName(LPCWSTR Name) {
    if (Name) {
        UINT size = (UINT)(wcslen(Name) * sizeof(wchar_t));
        SetPrivateData(WKPDID_D3DDebugObjectNameW, size, Name);
#ifdef __OBJC__
        if (m_sharedEvent) {
            NSString* nameStr = [[NSString alloc] initWithBytes:Name length:size encoding:NSUTF32LittleEndianStringEncoding];
            [(id<MTLSharedEvent>)m_sharedEvent setLabel:nameStr];
        }
#endif
    } else {
        SetPrivateData(WKPDID_D3DDebugObjectNameW, 0, nullptr);
#ifdef __OBJC__
        if (m_sharedEvent) {
            [(id<MTLSharedEvent>)m_sharedEvent setLabel:nil];
        }
#endif
    }
    return S_OK;
}

HRESULT STDMETHODCALLTYPE MLFence::GetDevice(REFIID riid, void** ppvDevice) {
    if (!ppvDevice) return E_POINTER;
    if (m_parentDevice) {
        return m_parentDevice->QueryInterface(riid, ppvDevice);
    }
    return E_NOINTERFACE;
}

UINT64 STDMETHODCALLTYPE MLFence::GetCompletedValue() {
#ifdef __OBJC__
    if (m_sharedEvent) {
        return [(id<MTLSharedEvent>)m_sharedEvent signaledValue];
    }
#endif
    return m_currentValue;
}

HRESULT STDMETHODCALLTYPE MLFence::SetEventOnCompletion(UINT64 Value, HANDLE hEvent) {
#ifdef __OBJC__
    if (!hEvent) return E_INVALIDARG;
    
    if (m_currentValue.load() >= Value) {
        MLEvent* ev = static_cast<MLEvent*>(hEvent);
        {
            std::lock_guard<std::mutex> lock(ev->mutex);
            ev->signaled = true;
        }
        ev->cond.notify_all();
        return S_OK;
    }

    if (m_sharedEvent) {
        static MTLSharedEventListener* s_globalListener = nil;
        static dispatch_once_t onceToken;
        dispatch_once(&onceToken, ^{
            dispatch_queue_t queue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0);
            s_globalListener = [[MTLSharedEventListener alloc] initWithDispatchQueue:queue];
        });
        
        [(id<MTLSharedEvent>)m_sharedEvent notifyListener:s_globalListener atValue:Value block:^(id<MTLSharedEvent> sharedEvent, uint64_t value) {
            MLEvent* ev = static_cast<MLEvent*>(hEvent);
            {
                std::lock_guard<std::mutex> lock(ev->mutex);
                ev->signaled = true;
            }
            ev->cond.notify_all();
        }];
        
        return S_OK;
    }
#endif

    std::lock_guard<std::mutex> lock(m_pendingEventsMutex);
    if (m_currentValue.load() >= Value) {
        MLEvent* ev = static_cast<MLEvent*>(hEvent);
        {
            std::lock_guard<std::mutex> evLock(ev->mutex);
            ev->signaled = true;
        }
        ev->cond.notify_all();
    } else {
        m_pendingEvents.push_back({Value, hEvent});
    }

    return S_OK;
}

HRESULT STDMETHODCALLTYPE MLFence::Signal(UINT64 Value) {
    m_currentValue.store(Value);
#ifdef __OBJC__
    if (m_sharedEvent) {
        [(id<MTLSharedEvent>)m_sharedEvent setSignaledValue:Value];
    }
#endif

    std::lock_guard<std::mutex> lock(m_pendingEventsMutex);
    for (auto it = m_pendingEvents.begin(); it != m_pendingEvents.end(); ) {
        if (Value >= it->value) {
            MLEvent* ev = static_cast<MLEvent*>(it->hEvent);
            {
                std::lock_guard<std::mutex> evLock(ev->mutex);
                ev->signaled = true;
            }
            ev->cond.notify_all();
            it = m_pendingEvents.erase(it);
        } else {
            ++it;
        }
    }

    return S_OK;
}
