
// ID3D12Device6
HRESULT STDMETHODCALLTYPE MLDevice::SetBackgroundProcessingMode(D3D12_BACKGROUND_PROCESSING_MODE Mode, D3D12_MEASUREMENTS_ACTION MeasurementsAction, HANDLE hEventToSignalUponCompletion, BOOL* pbFurtherMeasurementsDesired) {
    if (pbFurtherMeasurementsDesired) *pbFurtherMeasurementsDesired = FALSE;
    return S_OK;
}

// ID3D12Device7
HRESULT STDMETHODCALLTYPE MLDevice::AddToStateObject(const D3D12_STATE_OBJECT_DESC* pAddition, ID3D12StateObject* pStateObjectToGrowFrom, REFIID riid, void** ppNewStateObject) {
    if (!pAddition || !pStateObjectToGrowFrom || !ppNewStateObject) return E_POINTER;
    
    MLStateObject* original = static_cast<MLStateObject*>(pStateObjectToGrowFrom);
    MLStateObject* stateObj = new MLStateObject(this);
    stateObj->CloneFrom(original);

#ifdef __OBJC__
    id<MTLDevice> device = m_metalDevice;
    std::unordered_map<std::wstring, id<MTLFunction>> functionMap;
    NSMutableArray<id<MTLFunction>>* linkedFunctionsList = [NSMutableArray array];
    const D3D12_WORK_GRAPH_DESC* workGraphDesc = nullptr;

    for (UINT i = 0; i < pAddition->NumSubobjects; ++i) {
        const auto& subobj = pAddition->pSubobjects[i];
        if (subobj.Type == D3D12_STATE_SUBOBJECT_TYPE_DXIL_LIBRARY) {
            const auto* dxilLib = static_cast<const D3D12_DXIL_LIBRARY_DESC*>(subobj.pDesc);
            std::string mslSource = Metalloid::MLShaderCompiler::TranslateDXILToMSL(
                dxilLib->DXILLibrary.pShaderBytecode, dxilLib->DXILLibrary.BytecodeLength, "", "lib");
            NSString* sourceStr = [NSString stringWithUTF8String:mslSource.c_str()];
            NSError* compileError = nil;
            id<MTLLibrary> library = [device newLibraryWithSource:sourceStr options:nil error:&compileError];
            
            if (library) {
                if (dxilLib->NumExports > 0) {
                    for (UINT j = 0; j < dxilLib->NumExports; ++j) {
                        std::wstring wname = dxilLib->pExports[j].Name;
                        std::string nameStr(wname.begin(), wname.end());
                        id<MTLFunction> func = [library newFunctionWithName:[NSString stringWithUTF8String:nameStr.c_str()]];
                        if (!func) func = [library newFunctionWithName:@"cs_main"];
                        if (func) {
                            functionMap[wname] = func;
                            [linkedFunctionsList addObject:func];
                        }
                    }
                } else {
                    for (NSString* nsName in library.functionNames) {
                        id<MTLFunction> func = [library newFunctionWithName:nsName];
                        if (func) {
                            const char* utf8String = [nsName UTF8String];
                            std::string s(utf8String ? utf8String : "");
                            std::wstring wname(s.begin(), s.end());
                            functionMap[wname] = func;
                            [linkedFunctionsList addObject:func];
                        }
                    }
                }
            } else {
                std::cerr << "[Metalloid] DXIL library compile failed in AddToStateObject: " << [[compileError localizedDescription] UTF8String] << std::endl;
            }
        } else if (subobj.Type == D3D12_STATE_SUBOBJECT_TYPE_WORK_GRAPH) {
            workGraphDesc = static_cast<const D3D12_WORK_GRAPH_DESC*>(subobj.pDesc);
        }
    }

    if (workGraphDesc) {
        for (UINT i = 0; i < workGraphDesc->NumEntrypoints; ++i) {
            std::wstring entryName = workGraphDesc->pEntrypoints[i].Name;
            auto it = functionMap.find(entryName);
            if (it != functionMap.end()) {
                MTLComputePipelineDescriptor* wgDesc = [[MTLComputePipelineDescriptor alloc] init];
                wgDesc.computeFunction = it->second;
                if (linkedFunctionsList.count > 0) {
                    if (@available(macOS 11.0, iOS 14.0, *)) {
                        MTLLinkedFunctions* mtlLinked = [[MTLLinkedFunctions alloc] init];
                        mtlLinked.functions = linkedFunctionsList;
                        wgDesc.linkedFunctions = mtlLinked;
                    }
                }
                NSError* error = nil;
                id<MTLComputePipelineState> pso = [device newComputePipelineStateWithDescriptor:wgDesc options:0 reflection:nil error:&error];
                if (pso) stateObj->AddWorkGraphPipeline(entryName, pso);
            }
        }
        for (UINT i = 0; i < workGraphDesc->NumExplicitlyDefinedNodes; ++i) {
            std::wstring nodeName = workGraphDesc->pExplicitlyDefinedNodes[i].Name;
            auto it = functionMap.find(nodeName);
            if (it != functionMap.end()) {
                MTLComputePipelineDescriptor* wgDesc = [[MTLComputePipelineDescriptor alloc] init];
                wgDesc.computeFunction = it->second;
                if (linkedFunctionsList.count > 0) {
                    if (@available(macOS 11.0, iOS 14.0, *)) {
                        MTLLinkedFunctions* mtlLinked = [[MTLLinkedFunctions alloc] init];
                        mtlLinked.functions = linkedFunctionsList;
                        wgDesc.linkedFunctions = mtlLinked;
                    }
                }
                NSError* error = nil;
                id<MTLComputePipelineState> pso = [device newComputePipelineStateWithDescriptor:wgDesc options:0 reflection:nil error:&error];
                if (pso) stateObj->AddWorkGraphPipeline(nodeName, pso);
            }
        }
    }
#endif

    HRESULT hr = stateObj->QueryInterface(riid, ppNewStateObject);
    stateObj->Release();
    return hr;
}

HRESULT STDMETHODCALLTYPE MLDevice::CreateProtectedResourceSession1(const D3D12_PROTECTED_RESOURCE_SESSION_DESC1* pDesc, REFIID riid, void** ppSession) {
    return E_NOTIMPL;
}

// ID3D12Device8
D3D12_RESOURCE_ALLOCATION_INFO STDMETHODCALLTYPE MLDevice::GetResourceAllocationInfo2(UINT visibleMask, UINT numResourceDescs, const D3D12_RESOURCE_DESC1* pResourceDescs, D3D12_RESOURCE_ALLOCATION_INFO1* pResourceAllocationInfo1) {
    D3D12_RESOURCE_ALLOCATION_INFO info = {};
    if (pResourceAllocationInfo1) {
        memset(pResourceAllocationInfo1, 0, sizeof(D3D12_RESOURCE_ALLOCATION_INFO1) * numResourceDescs);
    }
    return info;
}

HRESULT STDMETHODCALLTYPE MLDevice::CreateCommittedResource2(const D3D12_HEAP_PROPERTIES* pHeapProperties, D3D12_HEAP_FLAGS HeapFlags, const D3D12_RESOURCE_DESC1* pDesc, D3D12_RESOURCE_STATES InitialResourceState, const D3D12_CLEAR_VALUE* pOptimizedClearValue, ID3D12ProtectedResourceSession* pProtectedSession, REFIID riid, void** ppvResource) {
    return E_NOTIMPL;
}

HRESULT STDMETHODCALLTYPE MLDevice::CreatePlacedResource1(ID3D12Heap* pHeap, UINT64 HeapOffset, const D3D12_RESOURCE_DESC1* pDesc, D3D12_RESOURCE_STATES InitialState, const D3D12_CLEAR_VALUE* pOptimizedClearValue, REFIID riid, void** ppvResource) {
    return E_NOTIMPL;
}

void STDMETHODCALLTYPE MLDevice::CreateSampler1(const D3D12_SAMPLER_DESC* pDesc, D3D12_CPU_DESCRIPTOR_HANDLE DestDescriptor) {
    CreateSampler(pDesc, DestDescriptor);
}

void STDMETHODCALLTYPE MLDevice::GetCopyableFootprints1(const D3D12_RESOURCE_DESC1* pResourceDesc, UINT FirstSubresource, UINT NumSubresources, UINT64 BaseOffset, D3D12_PLACED_SUBRESOURCE_FOOTPRINT* pLayouts, UINT* pNumRows, UINT64* pRowSizesInBytes, UINT64* pTotalBytes) {
}

// ID3D12Device9
HRESULT STDMETHODCALLTYPE MLDevice::CreateShaderCacheSession(const D3D12_SHADER_CACHE_SESSION_DESC* pDesc, REFIID riid, void** ppvSession) {
    return E_NOTIMPL;
}

HRESULT STDMETHODCALLTYPE MLDevice::ShaderCacheControl(D3D12_SHADER_CACHE_KIND_FLAGS Kinds, D3D12_SHADER_CACHE_CONTROL_FLAGS Control) {
    return S_OK;
}

HRESULT STDMETHODCALLTYPE MLDevice::CreateCommandQueue1(const D3D12_COMMAND_QUEUE_DESC* pDesc, REFIID CreatorID, REFIID riid, void** ppCommandQueue) {
    return CreateCommandQueue(pDesc, riid, ppCommandQueue);
}

// ID3D12Device10
HRESULT STDMETHODCALLTYPE MLDevice::CreateCommittedResource3(const D3D12_HEAP_PROPERTIES* pHeapProperties, D3D12_HEAP_FLAGS HeapFlags, const D3D12_RESOURCE_DESC1* pDesc, D3D12_BARRIER_LAYOUT InitialLayout, const D3D12_CLEAR_VALUE* pOptimizedClearValue, ID3D12ProtectedResourceSession* pProtectedSession, UINT32 NumCastableFormats, const DXGI_FORMAT *pCastableFormats, REFIID riidResource, void** ppvResource) {
    return E_NOTIMPL;
}

HRESULT STDMETHODCALLTYPE MLDevice::CreatePlacedResource2(ID3D12Heap* pHeap, UINT64 HeapOffset, const D3D12_RESOURCE_DESC1* pDesc, D3D12_BARRIER_LAYOUT InitialLayout, const D3D12_CLEAR_VALUE* pOptimizedClearValue, UINT32 NumCastableFormats, const DXGI_FORMAT *pCastableFormats, REFIID riid, void** ppvResource) {
    return E_NOTIMPL;
}

HRESULT STDMETHODCALLTYPE MLDevice::CreateReservedResource2(const D3D12_RESOURCE_DESC* pDesc, D3D12_BARRIER_LAYOUT InitialLayout, const D3D12_CLEAR_VALUE* pOptimizedClearValue, ID3D12ProtectedResourceSession *pProtectedSession, UINT32 NumCastableFormats, const DXGI_FORMAT *pCastableFormats, REFIID riid, void** ppvResource) {
    return E_NOTIMPL;
}

// ID3D12Device11
void STDMETHODCALLTYPE MLDevice::CreateSampler2(const D3D12_SAMPLER_DESC2* pDesc, D3D12_CPU_DESCRIPTOR_HANDLE DestDescriptor) {
}

// ID3D12Device12
D3D12_RESOURCE_ALLOCATION_INFO STDMETHODCALLTYPE MLDevice::GetResourceAllocationInfo3(UINT visibleMask, UINT numResourceDescs, const D3D12_RESOURCE_DESC1* pResourceDescs, const UINT32* pNumCastableFormats, const DXGI_FORMAT *const *ppCastableFormats, D3D12_RESOURCE_ALLOCATION_INFO1* pResourceAllocationInfo1) {
    return GetResourceAllocationInfo2(visibleMask, numResourceDescs, pResourceDescs, pResourceAllocationInfo1);
}

// ID3D12Device13
HRESULT STDMETHODCALLTYPE MLDevice::OpenExistingHeapFromAddress1(const void* pAddress, SIZE_T size, REFIID riid, void** ppvHeap) {
    return E_NOTIMPL;
}

// ID3D12Device14
HRESULT STDMETHODCALLTYPE MLDevice::CreateRootSignatureFromSubobjectInLibrary(UINT nodeMask, const void* pLibraryBlob, SIZE_T blobLengthInBytes, LPCWSTR subobjectName, REFIID riid, void** ppvRootSignature) {
    return E_NOTIMPL;
}
