#include "Metalloid/Pipelines/MLPipelineState.h"
#include <string.h>

#ifdef __OBJC__
#import <Metal/Metal.h>
#import <Foundation/Foundation.h>
#endif

class MLBlob : public ID3DBlob {
private:
    std::atomic<ULONG> m_refCount{1};
    void* m_data;
    SIZE_T m_size;
public:
    MLBlob(void* data, SIZE_T size) : m_size(size) {
        m_data = malloc(size);
        if (data && size > 0) memcpy(m_data, data, size);
    }
    virtual ~MLBlob() { free(m_data); }
    virtual HRESULT STDMETHODCALLTYPE QueryInterface(REFIID riid, void** ppvObject) override {
        if (!ppvObject) return E_POINTER;
        const GUID IID_ID3D10Blob_Local = { 0x8ba5fb08, 0x5195, 0x40e2, { 0xac, 0x58, 0x0d, 0x98, 0x9c, 0x3a, 0x01, 0x02 } };
        const GUID IID_IUnknown_Local = { 0x00000000, 0x0000, 0x0000, { 0xC0, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x46 } };
        
        if (memcmp(&riid, &IID_IUnknown_Local, sizeof(GUID)) == 0 || memcmp(&riid, &IID_ID3D10Blob_Local, sizeof(GUID)) == 0) {
            *ppvObject = this;
            AddRef();
            return S_OK;
        }
        return E_NOINTERFACE;
    }
    virtual ULONG STDMETHODCALLTYPE AddRef() override { return ++m_refCount; }
    virtual ULONG STDMETHODCALLTYPE Release() override {
        ULONG count = --m_refCount;
        if (count == 0) delete this;
        return count;
    }
    virtual LPVOID STDMETHODCALLTYPE GetBufferPointer() override { return m_data; }
    virtual SIZE_T STDMETHODCALLTYPE GetBufferSize() override { return m_size; }
};

MLPipelineState::MLPipelineState(ID3D12Device* parentDevice, MetalRenderPipelineType renderPipeline) 
    : m_parentDevice(parentDevice), m_metalRenderPipeline(renderPipeline), m_isCompute(false) {
    if (m_parentDevice) m_parentDevice->AddRef();
}

MLPipelineState::MLPipelineState(ID3D12Device* parentDevice, MetalComputePipelineType computePipeline) 
    : m_parentDevice(parentDevice), m_metalComputePipeline(computePipeline), m_isCompute(true) {
    if (m_parentDevice) m_parentDevice->AddRef();
}

MLPipelineState::~MLPipelineState() {
    if (m_parentDevice) {
        m_parentDevice->Release();
        m_parentDevice = nullptr;
    }
#ifdef __OBJC__
    if (m_binaryArchive) {
        CFRelease(m_binaryArchive);
        m_binaryArchive = nullptr;
    }
#endif
}

HRESULT STDMETHODCALLTYPE MLPipelineState::QueryInterface(REFIID riid, void** ppvObject) {
    if (!ppvObject) return E_POINTER;
    if (riid == __uuidof(ID3D12PipelineState) ||
        riid == __uuidof(ID3D12Pageable) ||
        riid == __uuidof(ID3D12DeviceChild) ||
        riid == __uuidof(ID3D12Object) ||
        riid == __uuidof(IUnknown)) {
        *ppvObject = static_cast<ID3D12PipelineState*>(this);
        AddRef();
        return S_OK;
    }
    *ppvObject = nullptr;
    return E_NOINTERFACE;
}

ULONG STDMETHODCALLTYPE MLPipelineState::AddRef() {
    return ++m_refCount;
}

ULONG STDMETHODCALLTYPE MLPipelineState::Release() {
    ULONG count = --m_refCount;
    if (count == 0) {
        delete this;
    }
    return count;
}

ML_IMPL_PRIVATE_DATA(MLPipelineState)

HRESULT STDMETHODCALLTYPE MLPipelineState::SetName(LPCWSTR Name) {
    return S_OK;
}

HRESULT STDMETHODCALLTYPE MLPipelineState::GetDevice(REFIID riid, void** ppvDevice) {
    if (!ppvDevice) return E_POINTER;
    if (m_parentDevice) {
        return m_parentDevice->QueryInterface(riid, ppvDevice);
    }
    return E_NOINTERFACE;
}

HRESULT STDMETHODCALLTYPE MLPipelineState::GetCachedBlob(ID3DBlob** ppBlob) {
    if (!ppBlob) return E_POINTER;
    *ppBlob = nullptr;
#ifdef __OBJC__
    if (m_binaryArchive) {
        id<MTLBinaryArchive> archive = (__bridge id<MTLBinaryArchive>)m_binaryArchive;
        NSURL* tempURL = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:[[NSUUID UUID] UUIDString]]];
        NSError* error = nil;
        if ([archive serializeToURL:tempURL error:&error]) {
            NSData* data = [NSData dataWithContentsOfURL:tempURL];
            [[NSFileManager defaultManager] removeItemAtURL:tempURL error:nil];
            if (data) {
                MLBlob* blob = new MLBlob((void*)[data bytes], [data length]);
                *ppBlob = blob;
                return S_OK;
            }
        }
    }
#endif
    return E_FAIL;
}
