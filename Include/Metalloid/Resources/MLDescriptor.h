#pragma once

#include "d3d12_mac_common.h"

struct MLDescriptor {
    ID3D12Resource* pResource;
    union {
        D3D12_RENDER_TARGET_VIEW_DESC rtvDesc;
        D3D12_DEPTH_STENCIL_VIEW_DESC dsvDesc;
        D3D12_SHADER_RESOURCE_VIEW_DESC srvDesc;
        D3D12_UNORDERED_ACCESS_VIEW_DESC uavDesc;
        D3D12_SAMPLER_DESC samplerDesc;
        D3D12_CONSTANT_BUFFER_VIEW_DESC cbvDesc;
    };
};
