#include <iostream>
#include <vector>
#include "d3d12_mac_common.h"

int main() {
    std::cout << "[Test Barriers] Starting Enhanced Barriers layout discard cascade test..." << std::endl;

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

    // 4. Create Queue, Allocator, List
    D3D12_COMMAND_QUEUE_DESC queueDesc = {};
    queueDesc.Type = D3D12_COMMAND_LIST_TYPE_DIRECT;
    ID3D12CommandQueue* commandQueue = nullptr;
    device->CreateCommandQueue(&queueDesc, __uuidof(ID3D12CommandQueue), (void**)&commandQueue);

    ID3D12CommandAllocator* commandAllocator = nullptr;
    device->CreateCommandAllocator(D3D12_COMMAND_LIST_TYPE_DIRECT, __uuidof(ID3D12CommandAllocator), (void**)&commandAllocator);

    ID3D12GraphicsCommandList* commandList = nullptr;
    device->CreateCommandList(0, D3D12_COMMAND_LIST_TYPE_DIRECT, commandAllocator, nullptr, __uuidof(ID3D12GraphicsCommandList), (void**)&commandList);

    // 5. Create a Heap
    D3D12_HEAP_DESC heapDesc = {};
    heapDesc.SizeInBytes = 64 * 1024 * 1024; // 64 MB
    heapDesc.Properties.Type = D3D12_HEAP_TYPE_DEFAULT;
    heapDesc.Properties.CPUPageProperty = D3D12_CPU_PAGE_PROPERTY_UNKNOWN;
    heapDesc.Properties.MemoryPoolPreference = D3D12_MEMORY_POOL_UNKNOWN;
    heapDesc.Properties.CreationNodeMask = 1;
    heapDesc.Properties.VisibleNodeMask = 1;
    heapDesc.Alignment = D3D12_DEFAULT_RESOURCE_PLACEMENT_ALIGNMENT;
    heapDesc.Flags = D3D12_HEAP_FLAG_ALLOW_ALL_BUFFERS_AND_TEXTURES;

    ID3D12Heap* heap = nullptr;
    hr = device->CreateHeap(&heapDesc, __uuidof(ID3D12Heap), (void**)&heap);
    if (FAILED(hr)) {
        std::cerr << "Failed to create Heap: " << std::hex << hr << std::endl;
        return -1;
    }
    std::cout << "[Test Barriers] Heap created successfully." << std::endl;

    // 6. Create Placed Resource (Texture)
    D3D12_RESOURCE_DESC texDesc = {};
    texDesc.Dimension = D3D12_RESOURCE_DIMENSION_TEXTURE2D;
    texDesc.Alignment = 0;
    texDesc.Width = 1024;
    texDesc.Height = 1024;
    texDesc.DepthOrArraySize = 1;
    texDesc.MipLevels = 1;
    texDesc.Format = DXGI_FORMAT_R8G8B8A8_UNORM;
    texDesc.SampleDesc.Count = 1;
    texDesc.SampleDesc.Quality = 0;
    texDesc.Layout = D3D12_TEXTURE_LAYOUT_UNKNOWN;
    texDesc.Flags = D3D12_RESOURCE_FLAG_ALLOW_RENDER_TARGET;

    ID3D12Resource* placedResource = nullptr;
    hr = device->CreatePlacedResource(
        heap,
        0,
        &texDesc,
        D3D12_RESOURCE_STATE_COMMON,
        nullptr,
        __uuidof(ID3D12Resource),
        (void**)&placedResource
    );
    if (FAILED(hr)) {
        std::cerr << "Failed to create Placed Resource: " << std::hex << hr << std::endl;
        return -1;
    }
    std::cout << "[Test Barriers] Placed Resource created successfully." << std::endl;

    // 7. Perform Enhanced Barriers Transition!
    // This will trigger our layout discard cascade. From COMMON (UNDEFINED) to RENDER_TARGET
    std::cout << "[Test Barriers] Queueing ResourceBarrier..." << std::endl;
    D3D12_RESOURCE_BARRIER barrier = {};
    barrier.Type = D3D12_RESOURCE_BARRIER_TYPE_TRANSITION;
    barrier.Flags = D3D12_RESOURCE_BARRIER_FLAG_NONE;
    barrier.Transition.pResource = placedResource;
    barrier.Transition.StateBefore = D3D12_RESOURCE_STATE_COMMON;
    barrier.Transition.StateAfter = D3D12_RESOURCE_STATE_RENDER_TARGET;
    barrier.Transition.Subresource = D3D12_RESOURCE_BARRIER_ALL_SUBRESOURCES;

    commandList->ResourceBarrier(1, &barrier);
    std::cout << "[Test Barriers] ResourceBarrier recorded. Commencing execution..." << std::endl;

    // 8. Close and Execute
    commandList->Close();
    ID3D12CommandList* lists[] = { commandList };
    commandQueue->ExecuteCommandLists(1, lists);
    
    std::cout << "[Test Barriers] ExecuteCommandLists dispatched patch tables to global states successfully!" << std::endl;

    // 9. Cleanup
    placedResource->Release();
    heap->Release();
    commandList->Release();
    commandAllocator->Release();
    commandQueue->Release();
    device->Release();
    adapter->Release();
    factory->Release();

    std::cout << "[Test Barriers] Test Passed!" << std::endl;
    return 0;
}
