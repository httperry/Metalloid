#include <iostream>
#include <vector>
#include "d3d12_mac_common.h"
#include <Metal/Metal.h>
#include "Metalloid/Resources/MLResource.h"
#include "Metalloid/Sync/MLFence.h"
#include "Metalloid/Common/MLSharedHandle.h"

int main() {
    std::cout << "[Test UMA & IPC] Starting Hardware Verification Suite..." << std::endl;

    // 1. Create DXGI Factory
    IDXGIFactory4* factory = nullptr;
    HRESULT hr = CreateDXGIFactory1(__uuidof(IDXGIFactory4), (void**)&factory);
    if (FAILED(hr)) {
        std::cerr << "Failed to create DXGI Factory: " << std::hex << hr << std::endl;
        return -1;
    }

    // 2. Enum Adapter
    IDXGIAdapter1* adapter = nullptr;
    if (FAILED(factory->EnumAdapters1(0, &adapter))) {
        std::cerr << "Failed to enum adapter" << std::endl;
        return -1;
    }

    // 3. Create Device
    ID3D12Device* device = nullptr;
    if (FAILED(D3D12CreateDevice(adapter, D3D_FEATURE_LEVEL_11_0, __uuidof(ID3D12Device), (void**)&device))) {
        std::cerr << "Failed to create Device" << std::endl;
        return -1;
    }

    // ==========================================
    // Test 1: UMA Zero-Copy Routing Validation
    // ==========================================
    std::cout << "[Test UMA] Verifying Zero-Copy Buffer Allocations..." << std::endl;
    
    D3D12_HEAP_PROPERTIES uploadHeapProp = {};
    uploadHeapProp.Type = D3D12_HEAP_TYPE_UPLOAD;
    
    D3D12_HEAP_PROPERTIES defaultHeapProp = {};
    defaultHeapProp.Type = D3D12_HEAP_TYPE_DEFAULT;

    D3D12_RESOURCE_DESC bufferDesc = {};
    bufferDesc.Dimension = D3D12_RESOURCE_DIMENSION_BUFFER;
    bufferDesc.Width = 1024;
    bufferDesc.Height = 1;
    bufferDesc.DepthOrArraySize = 1;
    bufferDesc.MipLevels = 1;
    bufferDesc.SampleDesc.Count = 1;
    bufferDesc.Layout = D3D12_TEXTURE_LAYOUT_ROW_MAJOR;

    ID3D12Resource* uploadBuffer = nullptr;
    if (FAILED(device->CreateCommittedResource(&uploadHeapProp, D3D12_HEAP_FLAG_NONE, &bufferDesc, D3D12_RESOURCE_STATE_GENERIC_READ, nullptr, __uuidof(ID3D12Resource), (void**)&uploadBuffer))) {
        std::cerr << "Failed to create UPLOAD buffer" << std::endl;
        return -1;
    }

    ID3D12Resource* defaultBuffer = nullptr;
    if (FAILED(device->CreateCommittedResource(&defaultHeapProp, D3D12_HEAP_FLAG_NONE, &bufferDesc, D3D12_RESOURCE_STATE_COMMON, nullptr, __uuidof(ID3D12Resource), (void**)&defaultBuffer))) {
        std::cerr << "Failed to create DEFAULT buffer" << std::endl;
        return -1;
    }

    MLResource* mlUpload = static_cast<MLResource*>(uploadBuffer);
    MLResource* mlDefault = static_cast<MLResource*>(defaultBuffer);

    id<MTLBuffer> mtlUpload = (id<MTLBuffer>)mlUpload->GetMetalResource();
    id<MTLBuffer> mtlDefault = (id<MTLBuffer>)mlDefault->GetMetalResource();

    if (mtlUpload.storageMode != MTLStorageModeShared) {
        std::cerr << "[FAIL] UPLOAD heap is not mapped to Shared Memory!" << std::endl;
        return -1;
    }
    std::cout << "[PASS] UPLOAD heap mapped to MTLStorageModeShared successfully." << std::endl;

    if (mtlDefault.storageMode != MTLStorageModePrivate) {
        std::cerr << "[FAIL] DEFAULT heap is not mapped to Private Memory!" << std::endl;
        return -1;
    }
    std::cout << "[PASS] DEFAULT heap mapped to MTLStorageModePrivate successfully." << std::endl;

    // ==========================================
    // Test 2: Mach-O IPC Handle Verification
    // ==========================================
    std::cout << "[Test IPC] Verifying Mach-O Shared Event encoding..." << std::endl;

    ID3D12Fence* fence = nullptr;
    if (FAILED(device->CreateFence(0, D3D12_FENCE_FLAG_SHARED, __uuidof(ID3D12Fence), (void**)&fence))) {
        std::cerr << "Failed to create shared fence" << std::endl;
        return -1;
    }

    HANDLE sharedHandle = nullptr;
    if (FAILED(device->CreateSharedHandle(fence, nullptr, 0, nullptr, &sharedHandle))) {
        std::cerr << "Failed to export NT Shared Handle" << std::endl;
        return -1;
    }

    if (!sharedHandle) {
        std::cerr << "[FAIL] CreateSharedHandle returned a null handle!" << std::endl;
        return -1;
    }

    ID3D12Fence* reconstructedFence = nullptr;
    if (FAILED(device->OpenSharedHandle(sharedHandle, __uuidof(ID3D12Fence), (void**)&reconstructedFence))) {
        std::cerr << "[FAIL] Failed to open NT Shared Handle and reconstruct fence" << std::endl;
        return -1;
    }

    MLFence* mlReconstructed = static_cast<MLFence*>(reconstructedFence);
    id<MTLSharedEvent> sharedEvent = mlReconstructed->GetMetalSharedEvent();

    if (!sharedEvent) {
        std::cerr << "[FAIL] Reconstructed fence does not hold a valid MTLSharedEvent!" << std::endl;
        return -1;
    }

    std::cout << "[PASS] Mach-O IPC Handle encoded and decoded seamlessly across abstraction bounds." << std::endl;

    std::cout << "[SUCCESS] Hardware Verification Suite completed flawlessly." << std::endl;

    reconstructedFence->Release();
    fence->Release();
    uploadBuffer->Release();
    defaultBuffer->Release();
    device->Release();
    adapter->Release();
    factory->Release();

    return 0;
}
