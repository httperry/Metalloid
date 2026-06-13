#include "d3d12_mac_common.h"
#include <iostream>

int main() {
    ID3D12Device* device = nullptr;
    HRESULT hr = D3D12CreateDevice(nullptr, D3D_FEATURE_LEVEL_11_0, __uuidof(ID3D12Device), (void**)&device);
    if (FAILED(hr)) {
        std::cerr << "D3D12CreateDevice failed: " << std::hex << hr << std::endl;
        return 1;
    }
    std::cout << "Successfully created D3D12 Device." << std::endl;
    
    ID3D12VideoDevice* videoDevice = nullptr;
    hr = device->QueryInterface(__uuidof(ID3D12VideoDevice), (void**)&videoDevice);
    if (FAILED(hr)) {
        std::cerr << "QueryInterface for ID3D12VideoDevice failed: " << std::hex << hr << std::endl;
        device->Release();
        return 1;
    }
    std::cout << "Successfully queried ID3D12VideoDevice interface." << std::endl;
    
    // Check feature support for AV1
    D3D12_FEATURE_DATA_VIDEO_DECODE_SUPPORT decodeSupport = {};
    decodeSupport.Configuration.DecodeProfile = D3D12_VIDEO_DECODE_PROFILE_AV1_PROFILE0;
    
    hr = videoDevice->CheckFeatureSupport(D3D12_FEATURE_VIDEO_DECODE_SUPPORT, &decodeSupport, sizeof(decodeSupport));
    if (FAILED(hr)) {
        std::cerr << "CheckFeatureSupport failed: " << std::hex << hr << std::endl;
    } else {
        std::cout << "AV1 Profile 0 support flag: " << decodeSupport.SupportFlags 
                  << " (Supported: " << (decodeSupport.SupportFlags & D3D12_VIDEO_DECODE_SUPPORT_FLAG_SUPPORTED ? "YES" : "NO") 
                  << ")" << std::endl;
    }
    
    // Try to create a decoder with AV1 profile
    D3D12_VIDEO_DECODER_DESC decoderDesc = {};
    decoderDesc.Configuration.DecodeProfile = D3D12_VIDEO_DECODE_PROFILE_AV1_PROFILE0;
    
    ID3D12VideoDecoder* decoder = nullptr;
    hr = videoDevice->CreateVideoDecoder(&decoderDesc, __uuidof(ID3D12VideoDecoder), (void**)&decoder);
    std::cout << "CreateVideoDecoder with AV1 Profile 0 returned: 0x" << std::hex << hr << std::endl;
    if (SUCCEEDED(hr)) {
        std::cout << "Decoder successfully created." << std::endl;
        decoder->Release();
    } else {
        std::cout << "Decoder creation was blocked as expected or failed." << std::endl;
    }
    
    videoDevice->Release();
    device->Release();
    return 0;
}
