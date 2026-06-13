#pragma once
#include "Metalloid/Common/MLPrivateData.h"

#include "d3d12_mac_common.h"
#include <atomic>

#include <unordered_map>
#include <string>
#include <array>

#ifdef __OBJC__
@protocol MTLComputePipelineState;
@protocol MTLFunctionHandle;
@protocol MTLIndirectCommandBuffer;
typedef id<MTLComputePipelineState> MetalComputePipelineState;
typedef id<MTLFunctionHandle> MetalFunctionHandle;
#else
typedef void* MetalComputePipelineState;
typedef void* MetalFunctionHandle;
#endif

struct ArrayHasher {
    std::size_t operator()(const std::array<uint8_t, 32>& a) const {
        std::size_t h = 0;
        for (auto e : a) {
            h ^= std::hash<uint8_t>{}(e) + 0x9e3779b9 + (h << 6) + (h >> 2);
        }
        return h;
    }
};

class MLStateObject : public ID3D12StateObject, public ID3D12StateObjectProperties, public ID3D12WorkGraphProperties {
    ML_DECL_PRIVATE_DATA()
private:
    std::atomic<ULONG> m_refCount{1};
    ID3D12Device* m_parentDevice;

    MetalComputePipelineState m_metalPipeline;
    std::unordered_map<std::wstring, MetalComputePipelineState> m_workGraphPipelines;
    std::unordered_map<std::wstring, std::array<uint8_t, 32>> m_shaderIdentifiers;
    std::unordered_map<std::array<uint8_t, 32>, MetalFunctionHandle, ArrayHasher> m_functionHandles;
    UINT64 m_pipelineStackSize = 0;
    void* m_icb = nullptr;
    void* m_icbCounter = nullptr;

public:
    MLStateObject(ID3D12Device* parentDevice);
    void SetMetalPipeline(MetalComputePipelineState pipeline) { m_metalPipeline = pipeline; }
    MetalComputePipelineState GetMetalPipeline() const { return m_metalPipeline; }
    void AddWorkGraphPipeline(const std::wstring& name, MetalComputePipelineState pipeline) { m_workGraphPipelines[name] = pipeline; }
    MetalComputePipelineState GetWorkGraphPipeline(const std::wstring& name) const { auto it = m_workGraphPipelines.find(name); return it != m_workGraphPipelines.end() ? it->second : nullptr; }
    void AllocateICB(UINT maxCommandCount);
#ifdef __OBJC__
    void* GetICB() const { return m_icb; }
    void* GetICBCounter() const { return m_icbCounter; }
#else
    void* GetICB() const { return m_icb; }
    void* GetICBCounter() const { return m_icbCounter; }
#endif
    void CloneFrom(const MLStateObject* other) {
        m_metalPipeline = other->m_metalPipeline;
        m_workGraphPipelines = other->m_workGraphPipelines;
        m_shaderIdentifiers = other->m_shaderIdentifiers;
        m_functionHandles = other->m_functionHandles;
    }
    void AddShaderIdentifier(const std::wstring& exportName, const std::array<uint8_t, 32>& identifier) {
        m_shaderIdentifiers[exportName] = identifier;
    }
    void AddFunctionHandle(const std::array<uint8_t, 32>& identifier, MetalFunctionHandle handle) {
        m_functionHandles[identifier] = handle;
    }
    MetalFunctionHandle GetFunctionHandle(const std::array<uint8_t, 32>& identifier) const {
        auto it = m_functionHandles.find(identifier);
        return it != m_functionHandles.end() ? it->second : nullptr;
    }
    MLStateObject();
    virtual ~MLStateObject();

    // Resolve ambiguous IUnknown base
    operator IUnknown*() { return static_cast<ID3D12StateObject*>(this); }
    operator const IUnknown*() const { return static_cast<const ID3D12StateObject*>(this); }

    // IUnknown
    virtual HRESULT STDMETHODCALLTYPE QueryInterface(REFIID riid, void** ppvObject) override;
    virtual ULONG STDMETHODCALLTYPE AddRef() override;
    virtual ULONG STDMETHODCALLTYPE Release() override;

    // ID3D12Object
    virtual HRESULT STDMETHODCALLTYPE GetPrivateData(REFGUID guid, UINT* pDataSize, void* pData) override;
    virtual HRESULT STDMETHODCALLTYPE SetPrivateData(REFGUID guid, UINT DataSize, const void* pData) override;
    virtual HRESULT STDMETHODCALLTYPE SetPrivateDataInterface(REFGUID guid, const IUnknown* pData) override;
    virtual HRESULT STDMETHODCALLTYPE SetName(LPCWSTR Name) override;

    // ID3D12DeviceChild
    virtual HRESULT STDMETHODCALLTYPE GetDevice(REFIID riid, void** ppvDevice) override;

    // ID3D12StateObjectProperties
    virtual void* STDMETHODCALLTYPE GetShaderIdentifier(LPCWSTR pExportName) override;
    virtual UINT64 STDMETHODCALLTYPE GetShaderStackSize(LPCWSTR pExportName) override;
    virtual UINT64 STDMETHODCALLTYPE GetPipelineStackSize(void) override;
    virtual void STDMETHODCALLTYPE SetPipelineStackSize(UINT64 PipelineStackSizeInBytes) override;

    // ID3D12WorkGraphProperties
    virtual UINT STDMETHODCALLTYPE GetNumWorkGraphs(void) override;
    virtual LPCWSTR STDMETHODCALLTYPE GetProgramName(UINT WorkGraphIndex) override;
    virtual UINT STDMETHODCALLTYPE GetWorkGraphIndex(LPCWSTR pProgramName) override;
    virtual UINT STDMETHODCALLTYPE GetNumNodes(UINT WorkGraphIndex) override;
#if !defined(_WIN32)
    virtual D3D12_NODE_ID STDMETHODCALLTYPE GetNodeID(UINT WorkGraphIndex, UINT NodeIndex) override;
#else
    virtual D3D12_NODE_ID* STDMETHODCALLTYPE GetNodeID(D3D12_NODE_ID* RetVal, UINT WorkGraphIndex, UINT NodeIndex) override;
#endif
    virtual UINT STDMETHODCALLTYPE GetNodeIndex(UINT WorkGraphIndex, D3D12_NODE_ID NodeID) override;
    virtual UINT STDMETHODCALLTYPE GetNodeLocalRootArgumentsTableIndex(UINT WorkGraphIndex, UINT NodeIndex) override;
    virtual UINT STDMETHODCALLTYPE GetNumEntrypoints(UINT WorkGraphIndex) override;
#if !defined(_WIN32)
    virtual D3D12_NODE_ID STDMETHODCALLTYPE GetEntrypointID(UINT WorkGraphIndex, UINT EntrypointIndex) override;
#else
    virtual D3D12_NODE_ID* STDMETHODCALLTYPE GetEntrypointID(D3D12_NODE_ID* RetVal, UINT WorkGraphIndex, UINT EntrypointIndex) override;
#endif
    virtual UINT STDMETHODCALLTYPE GetEntrypointIndex(UINT WorkGraphIndex, D3D12_NODE_ID NodeID) override;
    virtual UINT STDMETHODCALLTYPE GetEntrypointRecordSizeInBytes(UINT WorkGraphIndex, UINT EntrypointIndex) override;
    virtual void STDMETHODCALLTYPE GetWorkGraphMemoryRequirements(UINT WorkGraphIndex, D3D12_WORK_GRAPH_MEMORY_REQUIREMENTS* pWorkGraphMemoryRequirements) override;
    virtual UINT STDMETHODCALLTYPE GetEntrypointRecordAlignmentInBytes(UINT WorkGraphIndex, UINT EntrypointIndex) override;
};
