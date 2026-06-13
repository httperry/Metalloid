#pragma once

#include <unordered_map>
#include <vector>
#include <mutex>
#include <string.h>
#include "d3d12_mac_common.h"

struct GUIDHasher {
    size_t operator()(const GUID& guid) const {
        const uint64_t* p = reinterpret_cast<const uint64_t*>(&guid);
        return p[0] ^ p[1];
    }
};

struct GUIDComparer {
    bool operator()(const GUID& a, const GUID& b) const {
        return memcmp(&a, &b, sizeof(GUID)) == 0;
    }
};

class MLPrivateData {
private:
    std::mutex m_mutex;
    struct DataEntry {
        std::vector<uint8_t> data;
        IUnknown* interfacePtr = nullptr;
    };
    std::unordered_map<GUID, DataEntry, GUIDHasher, GUIDComparer> m_dataMap;

public:
    HRESULT GetPrivateData(REFGUID guid, UINT* pDataSize, void* pData) {
        if (!pDataSize) return E_POINTER;
        std::lock_guard<std::mutex> lock(m_mutex);
        auto it = m_dataMap.find(guid);
        if (it == m_dataMap.end()) {
            return DXGI_ERROR_NOT_FOUND; // Standard D3D12 return code
        }

        if (it->second.interfacePtr) {
            if (*pDataSize < sizeof(IUnknown*)) {
                *pDataSize = sizeof(IUnknown*);
                return DXGI_ERROR_MORE_DATA;
            }
            if (pData) {
                *pDataSize = sizeof(IUnknown*);
                IUnknown* ptr = it->second.interfacePtr;
                ptr->AddRef();
                memcpy(pData, &ptr, sizeof(IUnknown*));
            } else {
                *pDataSize = sizeof(IUnknown*);
            }
        } else {
            if (*pDataSize < it->second.data.size()) {
                *pDataSize = (UINT)it->second.data.size();
                return DXGI_ERROR_MORE_DATA;
            }
            if (pData) {
                *pDataSize = (UINT)it->second.data.size();
                memcpy(pData, it->second.data.data(), *pDataSize);
            } else {
                *pDataSize = (UINT)it->second.data.size();
            }
        }
        return S_OK;
    }

    HRESULT SetPrivateData(REFGUID guid, UINT DataSize, const void* pData) {
        std::lock_guard<std::mutex> lock(m_mutex);
        if (pData == nullptr) {
            auto it = m_dataMap.find(guid);
            if (it != m_dataMap.end()) {
                if (it->second.interfacePtr) {
                    it->second.interfacePtr->Release();
                }
                m_dataMap.erase(it);
            }
            return S_OK;
        }

        DataEntry& entry = m_dataMap[guid];
        if (entry.interfacePtr) {
            entry.interfacePtr->Release();
            entry.interfacePtr = nullptr;
        }
        entry.data.assign((const uint8_t*)pData, ((const uint8_t*)pData) + DataSize);
        return S_OK;
    }

    HRESULT SetPrivateDataInterface(REFGUID guid, const IUnknown* pData) {
        std::lock_guard<std::mutex> lock(m_mutex);
        if (pData == nullptr) {
            auto it = m_dataMap.find(guid);
            if (it != m_dataMap.end()) {
                if (it->second.interfacePtr) {
                    it->second.interfacePtr->Release();
                }
                m_dataMap.erase(it);
            }
            return S_OK;
        }

        DataEntry& entry = m_dataMap[guid];
        if (entry.interfacePtr) {
            entry.interfacePtr->Release();
        }
        entry.interfacePtr = const_cast<IUnknown*>(pData);
        entry.interfacePtr->AddRef();
        entry.data.clear();
        return S_OK;
    }

    ~MLPrivateData() {
        std::lock_guard<std::mutex> lock(m_mutex);
        for (auto& pair : m_dataMap) {
            if (pair.second.interfacePtr) {
                pair.second.interfacePtr->Release();
            }
        }
        m_dataMap.clear();
    }
};

#define ML_DECL_PRIVATE_DATA() \
    private: MLPrivateData m_privateData;

#define ML_IMPL_PRIVATE_DATA(ClassName) \
    HRESULT STDMETHODCALLTYPE ClassName::GetPrivateData(REFGUID guid, UINT* pDataSize, void* pData) { \
        return m_privateData.GetPrivateData(guid, pDataSize, pData); \
    } \
    HRESULT STDMETHODCALLTYPE ClassName::SetPrivateData(REFGUID guid, UINT DataSize, const void* pData) { \
        return m_privateData.SetPrivateData(guid, DataSize, pData); \
    } \
    HRESULT STDMETHODCALLTYPE ClassName::SetPrivateDataInterface(REFGUID guid, const IUnknown* pData) { \
        return m_privateData.SetPrivateDataInterface(guid, pData); \
    }
