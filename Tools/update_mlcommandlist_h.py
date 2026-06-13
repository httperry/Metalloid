import re

with open('/Users/niranjana/System/Metalloid/Include/Metalloid/MLCommandList.h', 'r') as f:
    content = f.read()

content = content.replace('class MLCommandList : public ID3D12GraphicsCommandList4 {',
'''#ifndef ID3D12GraphicsCommandList14_DEFINED
#define ID3D12GraphicsCommandList14_DEFINED
typedef ID3D12GraphicsCommandList10 ID3D12GraphicsCommandList14;
#endif

class MLCommandList : public ID3D12GraphicsCommandList14 {''')

methods = """
    // ID3D12GraphicsCommandList5
    virtual void STDMETHODCALLTYPE RSSetShadingRate(D3D12_SHADING_RATE baseShadingRate, const D3D12_SHADING_RATE_COMBINER *combiners) override;
    virtual void STDMETHODCALLTYPE RSSetShadingRateImage(ID3D12Resource *shadingRateImage) override;

    // ID3D12GraphicsCommandList6
    virtual void STDMETHODCALLTYPE DispatchMesh(UINT ThreadGroupCountX, UINT ThreadGroupCountY, UINT ThreadGroupCountZ) override;

    // ID3D12GraphicsCommandList7
    virtual void STDMETHODCALLTYPE Barrier(UINT NumBarrierGroups, const D3D12_BARRIER_GROUP *pBarrierGroups) override;

    // ID3D12GraphicsCommandList8
    virtual void STDMETHODCALLTYPE OMSetFrontAndBackStencilRef(UINT FrontStencilRef, UINT BackStencilRef) override;

    // ID3D12GraphicsCommandList9
    virtual void STDMETHODCALLTYPE RSSetDepthBias(FLOAT DepthBias, FLOAT DepthBiasClamp, FLOAT SlopeScaledDepthBias) override;
    virtual void STDMETHODCALLTYPE IASetIndexBufferStripCutValue(D3D12_INDEX_BUFFER_STRIP_CUT_VALUE IBStripCutValue) override;

    // ID3D12GraphicsCommandList10
    virtual void STDMETHODCALLTYPE SetProgram(const D3D12_SET_PROGRAM_DESC *pDesc) override;
    virtual void STDMETHODCALLTYPE DispatchGraph(const D3D12_DISPATCH_GRAPH_DESC *pDesc) override;
};
"""
content = content.replace('    virtual void STDMETHODCALLTYPE DispatchRays(const D3D12_DISPATCH_RAYS_DESC* pDesc) override;\n};', 
                          '    virtual void STDMETHODCALLTYPE DispatchRays(const D3D12_DISPATCH_RAYS_DESC* pDesc) override;\n' + methods)

# Also we need to add fields for Work Graph tracking
fields = """    // Work Graph State
    class MLStateObject* m_activeWorkGraphStateObject = nullptr;
    D3D12_GPU_VIRTUAL_ADDRESS_RANGE m_activeWorkGraphBackingMemory = {0};
"""
content = content.replace('    class MLStateObject* m_currentDXRStateObject;',
                          '    class MLStateObject* m_currentDXRStateObject;\n' + fields)

with open('/Users/niranjana/System/Metalloid/Include/Metalloid/MLCommandList.h', 'w') as f:
    f.write(content)
