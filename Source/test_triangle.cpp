#include <iostream>
#include <vector>
#include "d3d12_mac_common.h"

int main() {
    std::cout << "[Test Triangle] Starting D3D12 translation layer test..." << std::endl;

    // 1. Create DXGI Factory
    IDXGIFactory4* factory = nullptr;
    HRESULT hr = CreateDXGIFactory1(__uuidof(IDXGIFactory4), (void**)&factory);
    if (FAILED(hr)) {
        std::cerr << "[Test Triangle] Failed to create DXGI Factory. Error: " << std::hex << hr << std::endl;
        return -1;
    }
    std::cout << "[Test Triangle] DXGI Factory created successfully." << std::endl;

    // 2. Enum Adapter
    IDXGIAdapter1* adapter = nullptr;
    hr = factory->EnumAdapters1(0, &adapter);
    if (FAILED(hr)) {
        std::cerr << "[Test Triangle] Failed to enum adapter. Error: " << std::hex << hr << std::endl;
        factory->Release();
        return -1;
    }
    std::cout << "[Test Triangle] Adapter obtained successfully." << std::endl;

    // 3. Create Device
    ID3D12Device* device = nullptr;
    hr = D3D12CreateDevice(adapter, D3D_FEATURE_LEVEL_11_0, __uuidof(ID3D12Device), (void**)&device);
    if (FAILED(hr)) {
        std::cerr << "[Test Triangle] Failed to create D3D12 Device. Error: " << std::hex << hr << std::endl;
        adapter->Release();
        factory->Release();
        return -1;
    }
    std::cout << "[Test Triangle] D3D12 Device created successfully." << std::endl;

    // 4. Create Command Queue
    D3D12_COMMAND_QUEUE_DESC queueDesc = {};
    queueDesc.Type = D3D12_COMMAND_LIST_TYPE_DIRECT;
    queueDesc.Priority = D3D12_COMMAND_QUEUE_PRIORITY_NORMAL;
    queueDesc.Flags = D3D12_COMMAND_QUEUE_FLAG_NONE;
    queueDesc.NodeMask = 0;

    ID3D12CommandQueue* commandQueue = nullptr;
    hr = device->CreateCommandQueue(&queueDesc, __uuidof(ID3D12CommandQueue), (void**)&commandQueue);
    if (FAILED(hr)) {
        std::cerr << "[Test Triangle] Failed to create Command Queue. Error: " << std::hex << hr << std::endl;
        device->Release();
        adapter->Release();
        factory->Release();
        return -1;
    }
    std::cout << "[Test Triangle] Command Queue created successfully." << std::endl;

    // 5. Create Swapchain
    DXGI_SWAP_CHAIN_DESC swapChainDesc = {};
    swapChainDesc.BufferDesc.Width = 800;
    swapChainDesc.BufferDesc.Height = 600;
    swapChainDesc.BufferDesc.Format = DXGI_FORMAT_R8G8B8A8_UNORM;
    swapChainDesc.BufferCount = 2;
    swapChainDesc.SampleDesc.Count = 1;
    swapChainDesc.BufferUsage = DXGI_USAGE_RENDER_TARGET_OUTPUT;
    swapChainDesc.SwapEffect = DXGI_SWAP_EFFECT_FLIP_DISCARD;
    swapChainDesc.Windowed = TRUE;

    IDXGISwapChain* swapChain = nullptr;
    hr = factory->CreateSwapChain(commandQueue, &swapChainDesc, &swapChain);
    if (FAILED(hr)) {
        std::cerr << "[Test Triangle] Failed to create Swapchain. Error: " << std::hex << hr << std::endl;
        commandQueue->Release();
        device->Release();
        adapter->Release();
        factory->Release();
        return -1;
    }
    std::cout << "[Test Triangle] Swapchain created successfully." << std::endl;

    // 6. Create Descriptor Heap for Render Target Views (RTV)
    D3D12_DESCRIPTOR_HEAP_DESC rtvHeapDesc = {};
    rtvHeapDesc.NumDescriptors = 2;
    rtvHeapDesc.Type = D3D12_DESCRIPTOR_HEAP_TYPE_RTV;
    rtvHeapDesc.Flags = D3D12_DESCRIPTOR_HEAP_FLAG_NONE;

    ID3D12DescriptorHeap* rtvHeap = nullptr;
    hr = device->CreateDescriptorHeap(&rtvHeapDesc, __uuidof(ID3D12DescriptorHeap), (void**)&rtvHeap);
    if (FAILED(hr)) {
        std::cerr << "[Test Triangle] Failed to create RTV Descriptor Heap. Error: " << std::hex << hr << std::endl;
        swapChain->Release();
        commandQueue->Release();
        device->Release();
        adapter->Release();
        factory->Release();
        return -1;
    }
    std::cout << "[Test Triangle] RTV Descriptor Heap created successfully." << std::endl;

    // 7. Create Render Target Views (RTV) for backbuffers
    UINT rtvDescriptorSize = device->GetDescriptorHandleIncrementSize(D3D12_DESCRIPTOR_HEAP_TYPE_RTV);
    D3D12_CPU_DESCRIPTOR_HANDLE rtvHandle = rtvHeap->GetCPUDescriptorHandleForHeapStart();

    std::vector<ID3D12Resource*> backBuffers(2);
    for (UINT i = 0; i < 2; ++i) {
        hr = swapChain->GetBuffer(i, __uuidof(ID3D12Resource), (void**)&backBuffers[i]);
        if (FAILED(hr)) {
            std::cerr << "[Test Triangle] Failed to get backbuffer " << i << ". Error: " << std::hex << hr << std::endl;
            return -1;
        }
        device->CreateRenderTargetView(backBuffers[i], nullptr, rtvHandle);
        rtvHandle.ptr += rtvDescriptorSize;
    }
    std::cout << "[Test Triangle] RTVs created successfully." << std::endl;

    // 8. Create Command Allocator
    ID3D12CommandAllocator* commandAllocator = nullptr;
    hr = device->CreateCommandAllocator(D3D12_COMMAND_LIST_TYPE_DIRECT, __uuidof(ID3D12CommandAllocator), (void**)&commandAllocator);
    if (FAILED(hr)) {
        std::cerr << "[Test Triangle] Failed to create Command Allocator. Error: " << std::hex << hr << std::endl;
        return -1;
    }
    std::cout << "[Test Triangle] Command Allocator created successfully." << std::endl;

    // 9. Create Command List
    ID3D12GraphicsCommandList* commandList = nullptr;
    hr = device->CreateCommandList(0, D3D12_COMMAND_LIST_TYPE_DIRECT, commandAllocator, nullptr, __uuidof(ID3D12GraphicsCommandList), (void**)&commandList);
    if (FAILED(hr)) {
        std::cerr << "[Test Triangle] Failed to create Command List. Error: " << std::hex << hr << std::endl;
        return -1;
    }
    std::cout << "[Test Triangle] Command List created successfully." << std::endl;
    commandList->Close(); // Command lists are created in recording state; close it first.

    // 10. Simple Render Loop (5 frames)
    std::cout << "[Test Triangle] Entering main render loop..." << std::endl;
    const FLOAT clearColors[5][4] = {
        {1.0f, 0.0f, 0.0f, 1.0f}, // Red
        {0.0f, 1.0f, 0.0f, 1.0f}, // Green
        {0.0f, 0.0f, 1.0f, 1.0f}, // Blue
        {1.0f, 1.0f, 0.0f, 1.0f}, // Yellow
        {0.5f, 0.0f, 0.5f, 1.0f}  // Purple
    };

    for (int frame = 0; frame < 5; ++frame) {
        std::cout << "[Test Triangle] Frame " << frame + 1 << "/5" << std::endl;

        // Reset allocator and list
        commandAllocator->Reset();
        commandList->Reset(commandAllocator, nullptr);

        // Get current backbuffer index and descriptor handle
        IDXGISwapChain3* sc3 = static_cast<IDXGISwapChain3*>(swapChain);
        UINT backBufferIndex = sc3->GetCurrentBackBufferIndex();
        D3D12_CPU_DESCRIPTOR_HANDLE handle = rtvHeap->GetCPUDescriptorHandleForHeapStart();
        handle.ptr += backBufferIndex * rtvDescriptorSize;

        // Record clear commands
        commandList->OMSetRenderTargets(1, &handle, FALSE, nullptr);
        commandList->ClearRenderTargetView(handle, clearColors[frame], 0, nullptr);
        commandList->Close();

        // Execute commands
        ID3D12CommandList* lists[] = { commandList };
        commandQueue->ExecuteCommandLists(1, lists);

        // Present frame
        swapChain->Present(1, 0);
    }
    std::cout << "[Test Triangle] Render loop completed successfully." << std::endl;

    // Cleanup
    commandList->Release();
    commandAllocator->Release();
    for (auto* buf : backBuffers) {
        buf->Release();
    }
    rtvHeap->Release();
    swapChain->Release();
    commandQueue->Release();
    device->Release();
    adapter->Release();
    factory->Release();

    std::cout << "[Test Triangle] Test passed. All resources released cleanly." << std::endl;
    return 0;
}
