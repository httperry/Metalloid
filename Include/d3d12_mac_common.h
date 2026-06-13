#pragma once

// Workaround for BOOL collision between Apple's Objective-C SDK (typedef bool BOOL) 
// and Microsoft's Windows SDK stubs (typedef uint32_t BOOL).
// We map BOOL to win_BOOL while parsing Windows/DirectX headers, then restore it.
#define BOOL win_BOOL
#include <wsl/winadapter.h>
#include <directx/d3d12.h>
#include <directx/d3d12video.h>
#include <dxgi1_4.h>
#include <dxguids/dxguids.h> // Defines template-based __uuidof mappings for D3D12/DXGI interfaces
#undef BOOL
#undef interface

#include <atomic>

typedef void* HMODULE;

#define ML_EXPORT __attribute__((visibility("default")))
