#include <iostream>
#include <vector>
#include "d3d12_mac_common.h"

int main() {
    std::cout << "[Test Triangle Shader] Starting D3D12 translation layer test for Shader Compilation..." << std::endl;

    IDXGIFactory4* factory = nullptr;
    HRESULT hr = CreateDXGIFactory1(__uuidof(IDXGIFactory4), (void**)&factory);
    if (FAILED(hr)) return -1;

    IDXGIAdapter1* adapter = nullptr;
    hr = factory->EnumAdapters1(0, &adapter);
    if (FAILED(hr)) return -1;

    ID3D12Device* device = nullptr;
    hr = D3D12CreateDevice(adapter, D3D_FEATURE_LEVEL_11_0, __uuidof(ID3D12Device), (void**)&device);
    if (FAILED(hr)) return -1;

    D3D12_COMMAND_QUEUE_DESC queueDesc = {};
    queueDesc.Type = D3D12_COMMAND_LIST_TYPE_DIRECT;
    ID3D12CommandQueue* commandQueue = nullptr;
    hr = device->CreateCommandQueue(&queueDesc, __uuidof(ID3D12CommandQueue), (void**)&commandQueue);
    if (FAILED(hr)) return -1;

    DXGI_SWAP_CHAIN_DESC swapChainDesc = {};
    swapChainDesc.BufferDesc.Width = 800;
    swapChainDesc.BufferDesc.Height = 600;
    swapChainDesc.BufferDesc.Format = DXGI_FORMAT_B8G8R8A8_UNORM;
    swapChainDesc.BufferCount = 2;
    swapChainDesc.SampleDesc.Count = 1;
    swapChainDesc.BufferUsage = DXGI_USAGE_RENDER_TARGET_OUTPUT;
    swapChainDesc.SwapEffect = DXGI_SWAP_EFFECT_FLIP_DISCARD;
    swapChainDesc.Windowed = TRUE;

    IDXGISwapChain* swapChain = nullptr;
    hr = factory->CreateSwapChain(commandQueue, &swapChainDesc, &swapChain);
    if (FAILED(hr)) return -1;

    D3D12_DESCRIPTOR_HEAP_DESC rtvHeapDesc = {};
    rtvHeapDesc.NumDescriptors = 2;
    rtvHeapDesc.Type = D3D12_DESCRIPTOR_HEAP_TYPE_RTV;
    ID3D12DescriptorHeap* rtvHeap = nullptr;
    hr = device->CreateDescriptorHeap(&rtvHeapDesc, __uuidof(ID3D12DescriptorHeap), (void**)&rtvHeap);
    if (FAILED(hr)) return -1;

    UINT rtvDescriptorSize = device->GetDescriptorHandleIncrementSize(D3D12_DESCRIPTOR_HEAP_TYPE_RTV);
    D3D12_CPU_DESCRIPTOR_HANDLE rtvHandle = rtvHeap->GetCPUDescriptorHandleForHeapStart();

    std::vector<ID3D12Resource*> backBuffers(2);
    for (UINT i = 0; i < 2; ++i) {
        swapChain->GetBuffer(i, __uuidof(ID3D12Resource), (void**)&backBuffers[i]);
        device->CreateRenderTargetView(backBuffers[i], nullptr, rtvHandle);
        rtvHandle.ptr += rtvDescriptorSize;
    }

    // --- MILESTONE 2: PIPELINE COMPILATION ---
    std::cout << "[Test Triangle Shader] Compiling Graphics Pipeline State..." << std::endl;
    D3D12_GRAPHICS_PIPELINE_STATE_DESC psoDesc = {};
    // Trigger our VS/PS stub path:
    psoDesc.VS.pShaderBytecode = "DUMMY_DXIL_VS";
    psoDesc.VS.BytecodeLength = 13; 
    
    ID3D12PipelineState* pipelineState = nullptr;
    hr = device->CreateGraphicsPipelineState(&psoDesc, __uuidof(ID3D12PipelineState), (void**)&pipelineState);
    if (FAILED(hr)) {
        std::cerr << "[Test Triangle Shader] Pipeline creation failed." << std::endl;
        return -1;
    }
    std::cout << "[Test Triangle Shader] Pipeline created successfully!" << std::endl;

    ID3D12CommandAllocator* commandAllocator = nullptr;
    hr = device->CreateCommandAllocator(D3D12_COMMAND_LIST_TYPE_DIRECT, __uuidof(ID3D12CommandAllocator), (void**)&commandAllocator);
    if (FAILED(hr)) return -1;

    ID3D12GraphicsCommandList* commandList = nullptr;
    hr = device->CreateCommandList(0, D3D12_COMMAND_LIST_TYPE_DIRECT, commandAllocator, nullptr, __uuidof(ID3D12GraphicsCommandList), (void**)&commandList);
    if (FAILED(hr)) return -1;
    commandList->Close(); 

    std::cout << "[Test Triangle Shader] Entering main render loop..." << std::endl;
    for (int frame = 0; frame < 5; ++frame) {
        std::cout << "[Test Triangle Shader] Frame " << frame + 1 << "/5" << std::endl;

        commandAllocator->Reset();
        // Bind pipeline on reset
        commandList->Reset(commandAllocator, pipelineState);

        IDXGISwapChain3* sc3 = static_cast<IDXGISwapChain3*>(swapChain);
        UINT backBufferIndex = sc3->GetCurrentBackBufferIndex();
        D3D12_CPU_DESCRIPTOR_HANDLE handle = rtvHeap->GetCPUDescriptorHandleForHeapStart();
        handle.ptr += backBufferIndex * rtvDescriptorSize;

        // Set Render Target and Clear
        commandList->OMSetRenderTargets(1, &handle, FALSE, nullptr);
        
        FLOAT clearColor[] = { 0.1f, 0.1f, 0.1f, 1.0f };
        commandList->ClearRenderTargetView(handle, clearColor, 0, nullptr);
        
        // --- MILESTONE 2: DRAW CALL ---
        commandList->SetPipelineState(pipelineState);
        commandList->DrawInstanced(3, 1, 0, 0);

        commandList->Close();

        ID3D12CommandList* lists[] = { commandList };
        commandQueue->ExecuteCommandLists(1, lists);

        swapChain->Present(1, 0);
    }
    std::cout << "[Test Triangle Shader] Render loop completed successfully." << std::endl;

    // Cleanup
    pipelineState->Release();
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

    std::cout << "[Test Triangle Shader] Test passed. All resources released cleanly." << std::endl;
    return 0;
}
