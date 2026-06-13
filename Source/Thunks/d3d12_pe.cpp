typedef int D3D_FEATURE_LEVEL;
typedef int HRESULT;
typedef int BOOL;
typedef unsigned int DWORD;
typedef void* HINSTANCE;
typedef void* LPVOID;
typedef void* IUnknown;
typedef void* REFIID;
typedef void* HANDLE;
typedef unsigned long long SIZE_T;

#define WINAPI __stdcall
#define DLL_PROCESS_ATTACH 1
#define TRUE 1

typedef unsigned long long unixlib_handle_t;

extern "C" {
    HINSTANCE __stdcall GetModuleHandleA(const char* lpModuleName);
    void* __stdcall GetProcAddress(HINSTANCE hModule, const char* lpProcName);
    HANDLE __stdcall GetCurrentProcess(void);
}

typedef int (__stdcall *pNtQueryVirtualMemory)(HANDLE ProcessHandle, LPVOID BaseAddress, int MemoryInformationClass, LPVOID MemoryInformation, SIZE_T MemoryInformationLength, SIZE_T *ReturnLength);
typedef unsigned int (__stdcall *p__wine_unix_call)(unixlib_handle_t handle, unsigned int code, void *args);

static p__wine_unix_call wine_unix_call_ptr = 0;
static unixlib_handle_t d3d12_unix_handle = 0;

#define MemoryWineUnixFuncs 1004

#include "../../Include/Metalloid/Thunks/d3d12_thunks.h"

extern "C" BOOL WINAPI DllMain(HINSTANCE hinstDLL, DWORD fdwReason, LPVOID lpvReserved)
{
    if (fdwReason == DLL_PROCESS_ATTACH)
    {
        HINSTANCE ntdll = GetModuleHandleA("ntdll.dll");
        pNtQueryVirtualMemory NtQueryVirtualMemory_ptr = (pNtQueryVirtualMemory)GetProcAddress(ntdll, "NtQueryVirtualMemory");
        wine_unix_call_ptr = (p__wine_unix_call)GetProcAddress(ntdll, "__wine_unix_call");

        if (NtQueryVirtualMemory_ptr) {
            NtQueryVirtualMemory_ptr(GetCurrentProcess(), hinstDLL, MemoryWineUnixFuncs,
                                     &d3d12_unix_handle, sizeof(d3d12_unix_handle), 0);
        }
    }
    return TRUE;
}

extern "C" __declspec(dllexport) HRESULT WINAPI D3D12CreateDevice(IUnknown* pAdapter, D3D_FEATURE_LEVEL MinimumFeatureLevel, REFIID riid, void** ppDevice)
{
    int hr = 0;
    struct d3d12_create_device_args args = { (void*)pAdapter, (int)MinimumFeatureLevel, (void*)&riid, ppDevice, &hr };
    if (wine_unix_call_ptr) {
        wine_unix_call_ptr(d3d12_unix_handle, unix_D3D12CreateDevice, &args);
    }
    return (HRESULT)hr;
}
