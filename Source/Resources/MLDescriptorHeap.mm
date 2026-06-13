#include "Metalloid/Resources/MLDescriptorHeap.h"
#include <iostream>

MLDescriptorHeap::MLDescriptorHeap(ID3D12Device* parentDevice, const D3D12_DESCRIPTOR_HEAP_DESC& desc)
    : m_refCount(1), m_parentDevice(parentDevice), m_desc(desc) {
    m_descriptors.resize(desc.NumDescriptors);
    memset(m_descriptors.data(), 0, sizeof(MLDescriptor) * desc.NumDescriptors);
    std::cout << "[Metalloid] ID3D12DescriptorHeap created with " << desc.NumDescriptors << " descriptors." << std::endl;
}

MLDescriptorHeap::~MLDescriptorHeap() {
    std::cout << "[Metalloid] ID3D12DescriptorHeap destroyed." << std::endl;
}

HRESULT STDMETHODCALLTYPE MLDescriptorHeap::QueryInterface(REFIID riid, void** ppvObject) {
    if (!ppvObject) return E_POINTER;

    if (riid == __uuidof(IUnknown) ||
        riid == __uuidof(ID3D12Object) ||
        riid == __uuidof(ID3D12DeviceChild) ||
        riid == __uuidof(ID3D12Pageable) ||
        riid == __uuidof(ID3D12DescriptorHeap)) {
        *ppvObject = static_cast<ID3D12DescriptorHeap*>(this);
        AddRef();
        return S_OK;
    }

    *ppvObject = nullptr;
    return E_NOINTERFACE;
}

ULONG STDMETHODCALLTYPE MLDescriptorHeap::AddRef() {
    return ++m_refCount;
}

ULONG STDMETHODCALLTYPE MLDescriptorHeap::Release() {
    ULONG count = --m_refCount;
    if (count == 0) {
        delete this;
    }
    return count;
}

ML_IMPL_PRIVATE_DATA(MLDescriptorHeap)

HRESULT STDMETHODCALLTYPE MLDescriptorHeap::SetName(LPCWSTR Name) {
    return S_OK;
}

HRESULT STDMETHODCALLTYPE MLDescriptorHeap::GetDevice(REFIID riid, void** ppvDevice) {
    if (!ppvDevice) return E_POINTER;
    if (m_parentDevice) {
        return m_parentDevice->QueryInterface(riid, ppvDevice);
    }
    return E_NOINTERFACE;
}

D3D12_DESCRIPTOR_HEAP_DESC STDMETHODCALLTYPE MLDescriptorHeap::GetDesc() {
    return m_desc;
}

D3D12_CPU_DESCRIPTOR_HANDLE STDMETHODCALLTYPE MLDescriptorHeap::GetCPUDescriptorHandleForHeapStart() {
    D3D12_CPU_DESCRIPTOR_HANDLE handle;
    handle.ptr = reinterpret_cast<SIZE_T>(m_descriptors.data());
    return handle;
}

D3D12_GPU_DESCRIPTOR_HANDLE STDMETHODCALLTYPE MLDescriptorHeap::GetGPUDescriptorHandleForHeapStart() {
    D3D12_GPU_DESCRIPTOR_HANDLE handle;
    handle.ptr = reinterpret_cast<UINT64>(m_descriptors.data());
    return handle;
}
