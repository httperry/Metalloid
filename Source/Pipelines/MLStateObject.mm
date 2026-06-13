#include "Metalloid/Pipelines/MLStateObject.h"
#ifdef __OBJC__
#import <CoreFoundation/CoreFoundation.h>
#endif
MLStateObject::MLStateObject(ID3D12Device* parentDevice) : m_parentDevice(parentDevice) {
    if (m_parentDevice) m_parentDevice->AddRef();
}

MLStateObject::~MLStateObject() {
    if (m_parentDevice) {
        m_parentDevice->Release();
        m_parentDevice = nullptr;
    }
#ifdef __OBJC__
    if (m_icb) {
        CFRelease(m_icb);
        m_icb = nullptr;
    }
    if (m_icbCounter) {
        CFRelease(m_icbCounter);
        m_icbCounter = nullptr;
    }
#endif
}

HRESULT STDMETHODCALLTYPE MLStateObject::QueryInterface(REFIID riid, void** ppvObject) {
    if (!ppvObject) return E_INVALIDARG;
    if (riid == __uuidof(ID3D12StateObject) || riid == __uuidof(IUnknown) || riid == __uuidof(ID3D12Object) || riid == __uuidof(ID3D12DeviceChild) || riid == __uuidof(ID3D12Pageable)) {
        *ppvObject = static_cast<ID3D12StateObject*>(this);
        AddRef();
        return S_OK;
    }
    if (riid == __uuidof(ID3D12StateObjectProperties)) {
        *ppvObject = static_cast<ID3D12StateObjectProperties*>(this);
        AddRef();
        return S_OK;
    }
    if (riid == IID_ID3D12WorkGraphProperties) {
        *ppvObject = static_cast<ID3D12WorkGraphProperties*>(this);
        AddRef();
        return S_OK;
    }
    *ppvObject = nullptr;
    return E_NOINTERFACE;
}

ULONG STDMETHODCALLTYPE MLStateObject::AddRef() {
    return ++m_refCount;
}

ULONG STDMETHODCALLTYPE MLStateObject::Release() {
    ULONG count = --m_refCount;
    if (count == 0) {
        delete this;
    }
    return count;
}

ML_IMPL_PRIVATE_DATA(MLStateObject)
HRESULT STDMETHODCALLTYPE MLStateObject::SetName(LPCWSTR Name) { return S_OK; }
HRESULT STDMETHODCALLTYPE MLStateObject::GetDevice(REFIID riid, void** ppvDevice) {
    if (!ppvDevice) return E_POINTER;
    if (m_parentDevice) {
        return m_parentDevice->QueryInterface(riid, ppvDevice);
    }
    return E_NOINTERFACE;
}

void* STDMETHODCALLTYPE MLStateObject::GetShaderIdentifier(LPCWSTR pExportName) {
    auto it = m_shaderIdentifiers.find(pExportName);
    if (it != m_shaderIdentifiers.end()) {
        return it->second.data();
    }
    return nullptr;
}

UINT64 STDMETHODCALLTYPE MLStateObject::GetShaderStackSize(LPCWSTR pExportName) {
    return 0; // Stack sizes are dynamically handled by Metal 4 IR
}

UINT64 STDMETHODCALLTYPE MLStateObject::GetPipelineStackSize(void) {
    return m_pipelineStackSize;
}

void STDMETHODCALLTYPE MLStateObject::SetPipelineStackSize(UINT64 PipelineStackSizeInBytes) {
    m_pipelineStackSize = PipelineStackSizeInBytes;
}

UINT STDMETHODCALLTYPE MLStateObject::GetNumWorkGraphs(void) {
    return 1; // Assuming 1 work graph for now
}

LPCWSTR STDMETHODCALLTYPE MLStateObject::GetProgramName(UINT WorkGraphIndex) {
    return L"WorkGraph";
}

UINT STDMETHODCALLTYPE MLStateObject::GetWorkGraphIndex(LPCWSTR pProgramName) {
    return 0;
}

UINT STDMETHODCALLTYPE MLStateObject::GetNumNodes(UINT WorkGraphIndex) {
    return 1;
}

#if !defined(_WIN32)
D3D12_NODE_ID STDMETHODCALLTYPE MLStateObject::GetNodeID(UINT WorkGraphIndex, UINT NodeIndex) {
    D3D12_NODE_ID node;
    node.Name = L"Node";
    node.ArrayIndex = 0;
    return node;
}
#else
D3D12_NODE_ID* STDMETHODCALLTYPE MLStateObject::GetNodeID(D3D12_NODE_ID* RetVal, UINT WorkGraphIndex, UINT NodeIndex) {
    if (RetVal) {
        RetVal->Name = L"Node";
        RetVal->ArrayIndex = 0;
    }
    return RetVal;
}
#endif

UINT STDMETHODCALLTYPE MLStateObject::GetNodeIndex(UINT WorkGraphIndex, D3D12_NODE_ID NodeID) {
    return 0;
}

UINT STDMETHODCALLTYPE MLStateObject::GetNodeLocalRootArgumentsTableIndex(UINT WorkGraphIndex, UINT NodeIndex) {
    return 0;
}

UINT STDMETHODCALLTYPE MLStateObject::GetNumEntrypoints(UINT WorkGraphIndex) {
    return 1;
}

#if !defined(_WIN32)
D3D12_NODE_ID STDMETHODCALLTYPE MLStateObject::GetEntrypointID(UINT WorkGraphIndex, UINT EntrypointIndex) {
    D3D12_NODE_ID node;
    node.Name = L"Entry";
    node.ArrayIndex = 0;
    return node;
}
#else
D3D12_NODE_ID* STDMETHODCALLTYPE MLStateObject::GetEntrypointID(D3D12_NODE_ID* RetVal, UINT WorkGraphIndex, UINT EntrypointIndex) {
    if (RetVal) {
        RetVal->Name = L"Entry";
        RetVal->ArrayIndex = 0;
    }
    return RetVal;
}
#endif

UINT STDMETHODCALLTYPE MLStateObject::GetEntrypointIndex(UINT WorkGraphIndex, D3D12_NODE_ID NodeID) {
    return 0;
}

UINT STDMETHODCALLTYPE MLStateObject::GetEntrypointRecordSizeInBytes(UINT WorkGraphIndex, UINT EntrypointIndex) {
    return 32;
}

void STDMETHODCALLTYPE MLStateObject::GetWorkGraphMemoryRequirements(UINT WorkGraphIndex, D3D12_WORK_GRAPH_MEMORY_REQUIREMENTS* pWorkGraphMemoryRequirements) {
    if (pWorkGraphMemoryRequirements) {
        pWorkGraphMemoryRequirements->MinSizeInBytes = 65536;
        pWorkGraphMemoryRequirements->MaxSizeInBytes = 1048576;
        pWorkGraphMemoryRequirements->SizeGranularityInBytes = 65536;
    }
}

UINT STDMETHODCALLTYPE MLStateObject::GetEntrypointRecordAlignmentInBytes(UINT WorkGraphIndex, UINT EntrypointIndex) {
    return 4;
}

#ifdef __OBJC__
#import <Metal/Metal.h>
#endif
#include "Metalloid/Device/MLDevice.h"

void MLStateObject::AllocateICB(UINT maxCommandCount) {
#ifdef __OBJC__
    if (!m_parentDevice) return;
    MLDevice* mlDevice = static_cast<MLDevice*>(m_parentDevice);
    id<MTLDevice> device = mlDevice->GetMetalDevice();
    
    MTLIndirectCommandBufferDescriptor* desc = [[MTLIndirectCommandBufferDescriptor alloc] init];
    desc.commandTypes = MTLIndirectCommandTypeConcurrentDispatch | MTLIndirectCommandTypeConcurrentDispatchThreads;
    desc.inheritPipelineState = NO;
    desc.inheritBuffers = NO;
    desc.maxKernelBufferBindCount = 31;
    
    m_icb = (__bridge_retained void*)[device newIndirectCommandBufferWithDescriptor:desc maxCommandCount:maxCommandCount options:MTLResourceStorageModePrivate];
    m_icbCounter = (__bridge_retained void*)[device newBufferWithLength:sizeof(uint32_t) options:MTLResourceStorageModePrivate];
#endif
}
