#pragma once

#include <stdint.h>

enum d3d12_unix_funcs {
    unix_D3D12CreateDevice,
    unix_D3D12GetDebugInterface,
    unix_D3D12SerializeRootSignature,
    unix_funcs_count
};

struct d3d12_create_device_args {
    void* pAdapter;
    int MinimumFeatureLevel;
    void* riid;
    void** ppDevice;
    int* pResult;
};
