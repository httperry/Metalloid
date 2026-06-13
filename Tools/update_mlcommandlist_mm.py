with open('/Users/niranjana/System/Metalloid/Source/Core/MLCommandList.mm', 'r') as f:
    content = f.read()

methods = """
// ID3D12GraphicsCommandList5
void STDMETHODCALLTYPE MLCommandList::RSSetShadingRate(D3D12_SHADING_RATE baseShadingRate, const D3D12_SHADING_RATE_COMBINER *combiners) {}
void STDMETHODCALLTYPE MLCommandList::RSSetShadingRateImage(ID3D12Resource *shadingRateImage) {}

// ID3D12GraphicsCommandList6
void STDMETHODCALLTYPE MLCommandList::DispatchMesh(UINT ThreadGroupCountX, UINT ThreadGroupCountY, UINT ThreadGroupCountZ) {}

// ID3D12GraphicsCommandList7
void STDMETHODCALLTYPE MLCommandList::Barrier(UINT NumBarrierGroups, const D3D12_BARRIER_GROUP *pBarrierGroups) {}

// ID3D12GraphicsCommandList8
void STDMETHODCALLTYPE MLCommandList::OMSetFrontAndBackStencilRef(UINT FrontStencilRef, UINT BackStencilRef) {}

// ID3D12GraphicsCommandList9
void STDMETHODCALLTYPE MLCommandList::RSSetDepthBias(FLOAT DepthBias, FLOAT DepthBiasClamp, FLOAT SlopeScaledDepthBias) {}
void STDMETHODCALLTYPE MLCommandList::IASetIndexBufferStripCutValue(D3D12_INDEX_BUFFER_STRIP_CUT_VALUE IBStripCutValue) {}

// ID3D12GraphicsCommandList10
void STDMETHODCALLTYPE MLCommandList::SetProgram(const D3D12_SET_PROGRAM_DESC *pDesc) {
    if (!pDesc) return;
    if (pDesc->Type == D3D12_PROGRAM_TYPE_WORK_GRAPH) {
        MLStateObject* pStateObject = (MLStateObject*)pDesc->WorkGraph.ProgramIdentifier.OpaqueData[0];
        m_activeWorkGraphStateObject = pStateObject;
        m_activeWorkGraphBackingMemory = pDesc->WorkGraph.BackingMemory;
    }
}

void STDMETHODCALLTYPE MLCommandList::DispatchGraph(const D3D12_DISPATCH_GRAPH_DESC *pDesc) {
#ifdef __OBJC__
    if (!pDesc || !m_activeCommandBuffer || !m_activeWorkGraphStateObject) return;
    
    // Obtain the ICB from the State Object or allocate it
    if (!m_activeWorkGraphStateObject->GetICB()) {
        m_activeWorkGraphStateObject->AllocateICB(1024);
    }
    
    id<MTLIndirectCommandBuffer> icb = (id<MTLIndirectCommandBuffer>)m_activeWorkGraphStateObject->GetICB();
    if (!icb) return;

    // We must execute the ICB on a compute encoder
    id<MTLComputeCommandEncoder> computeEncoder = m_activeComputeEncoder;
    if (!computeEncoder) {
        id<MTLCommandBuffer> cmdBuf = (id<MTLCommandBuffer>)m_activeCommandBuffer;
        computeEncoder = [cmdBuf computeCommandEncoder];
        m_activeComputeEncoder = computeEncoder;
    }
    
    // Ensure all state is flushed
    FlushComputeRootArguments();

    // Map Work Graphs to Metal Indirect Command Buffer execution
    MTLIndirectCommandBufferExecutionRange range;
    range.location = 0;
    
    // In a full implementation, we determine the number of commands from a GPU counter or CPU input.
    // For D3D12_DISPATCH_MODE_NODE_CPU_INPUT, we know the number of records.
    if (pDesc->Mode == D3D12_DISPATCH_MODE_NODE_CPU_INPUT) {
        range.length = pDesc->NodeCPUInput.NumRecords;
    } else {
        // Fallback for GPU input or other modes
        range.length = 1; 
    }
    
    // Execute the ICB
    [computeEncoder executeCommandsInBuffer:icb withRange:range];
    
    std::cout << "[Metalloid] DispatchGraph invoked for mode " << pDesc->Mode << " with " << range.length << " commands." << std::endl;
#endif
}
"""

if "void STDMETHODCALLTYPE MLCommandList::SetProgram" not in content:
    content += "\n" + methods

with open('/Users/niranjana/System/Metalloid/Source/Core/MLCommandList.mm', 'w') as f:
    f.write(content)
