#include <stdarg.h>
#include <stdlib.h>
#include <windef.h>
#include <winbase.h>
#include <winternl.h>
#include <wine/unixlib.h>

#include "Metalloid/Thunks/d3d12_thunks.h"

extern "C" int MLDevice_CreateDevice(void* pAdapter, int featureLevel, const void* riid, void** ppDevice);

static NTSTATUS thunk_D3D12CreateDevice(void *args)
{
    struct d3d12_create_device_args *a = (struct d3d12_create_device_args *)args;
    *a->pResult = MLDevice_CreateDevice(
        a->pAdapter,
        a->MinimumFeatureLevel,
        a->riid,
        a->ppDevice
    );
    return 0; // STATUS_SUCCESS is 0
}

static NTSTATUS thunk_D3D12GetDebugInterface(void *args)
{
    return 0;
}

static NTSTATUS thunk_D3D12SerializeRootSignature(void *args)
{
    return 0;
}

const unixlib_entry_t __wine_unix_call_funcs[] = {
    thunk_D3D12CreateDevice,
    thunk_D3D12GetDebugInterface,
    thunk_D3D12SerializeRootSignature
};

CDECL NTSTATUS __wine_init_unix_call(HMODULE module, DWORD reason, const void *ptr_in, void *ptr_out)
{
    if (reason == DLL_PROCESS_ATTACH)
    {
        *(const unixlib_entry_t **)ptr_out = __wine_unix_call_funcs;
    }
    return 0; // STATUS_SUCCESS
}
