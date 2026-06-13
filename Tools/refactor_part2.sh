#!/bin/bash
set -e

cd /Users/niranjana/System/Metalloid

mv Source/Core/MLRootSignature.h Include/Metalloid/Pipelines/ || true
rmdir Source/Core || true

mv Include/Metalloid/MLStateObject.h Include/Metalloid/Pipelines/
mv Include/Metalloid/MLShaderCompiler.h Include/Metalloid/Pipelines/
mv Include/Metalloid/MLFence.h Include/Metalloid/Sync/
mv Include/Metalloid/MLQueryHeap.h Include/Metalloid/Sync/
mv Include/Metalloid/MLVideoDevice.h Include/Metalloid/Video/
mv Include/Metalloid/MLVideoDecoder.h Include/Metalloid/Video/
mv Include/Metalloid/MLVideoDecodeCommandList.h Include/Metalloid/Video/
mv Include/Metalloid/MLFactory.h Include/Metalloid/DXGI/
mv Include/Metalloid/MLSwapChain.h Include/Metalloid/DXGI/
mv Include/Metalloid/MLPrivateData.h Include/Metalloid/Common/

find Source Include -type f \( -name "*.h" -o -name "*.mm" -o -name "*.cpp" \) -exec perl -pi -e '
s|#include "Metalloid/MLDevice\.h"|#include "Metalloid/Device/MLDevice.h"|g;
s|#include "Metalloid/MLCommandQueue\.h"|#include "Metalloid/Commands/MLCommandQueue.h"|g;
s|#include "Metalloid/MLCommandAllocator\.h"|#include "Metalloid/Commands/MLCommandAllocator.h"|g;
s|#include "Metalloid/MLCommandList\.h"|#include "Metalloid/Commands/MLCommandList.h"|g;
s|#include "Metalloid/MLResource\.h"|#include "Metalloid/Resources/MLResource.h"|g;
s|#include "Metalloid/MLHeap\.h"|#include "Metalloid/Resources/MLHeap.h"|g;
s|#include "Metalloid/MLDescriptor\.h"|#include "Metalloid/Resources/MLDescriptor.h"|g;
s|#include "Metalloid/MLDescriptorHeap\.h"|#include "Metalloid/Resources/MLDescriptorHeap.h"|g;
s|#include "Metalloid/MLPipelineState\.h"|#include "Metalloid/Pipelines/MLPipelineState.h"|g;
s|#include "Metalloid/MLRootSignature\.h"|#include "Metalloid/Pipelines/MLRootSignature.h"|g;
s|#include "Metalloid/MLStateObject\.h"|#include "Metalloid/Pipelines/MLStateObject.h"|g;
s|#include "Metalloid/MLShaderCompiler\.h"|#include "Metalloid/Pipelines/MLShaderCompiler.h"|g;
s|#include "Metalloid/MLFence\.h"|#include "Metalloid/Sync/MLFence.h"|g;
s|#include "Metalloid/MLQueryHeap\.h"|#include "Metalloid/Sync/MLQueryHeap.h"|g;
s|#include "Metalloid/MLVideoDevice\.h"|#include "Metalloid/Video/MLVideoDevice.h"|g;
s|#include "Metalloid/MLVideoDecoder\.h"|#include "Metalloid/Video/MLVideoDecoder.h"|g;
s|#include "Metalloid/MLVideoDecodeCommandList\.h"|#include "Metalloid/Video/MLVideoDecodeCommandList.h"|g;
s|#include "Metalloid/MLFactory\.h"|#include "Metalloid/DXGI/MLFactory.h"|g;
s|#include "Metalloid/MLSwapChain\.h"|#include "Metalloid/DXGI/MLSwapChain.h"|g;
s|#include "Metalloid/MLPrivateData\.h"|#include "Metalloid/Common/MLPrivateData.h"|g;

s|#include "MLPrivateData\.h"|#include "Metalloid/Common/MLPrivateData.h"|g;
s|#include "MLDevice\.h"|#include "Metalloid/Device/MLDevice.h"|g;
s|#include "MLStateObject\.h"|#include "Metalloid/Pipelines/MLStateObject.h"|g;
s|#include "MLFence\.h"|#include "Metalloid/Sync/MLFence.h"|g;
s|#include "MLResource\.h"|#include "Metalloid/Resources/MLResource.h"|g;
s|#include "MLCommandQueue\.h"|#include "Metalloid/Commands/MLCommandQueue.h"|g;
s|#include "MLCommandAllocator\.h"|#include "Metalloid/Commands/MLCommandAllocator.h"|g;
s|#include "MLCommandList\.h"|#include "Metalloid/Commands/MLCommandList.h"|g;
s|#include "MLDescriptorHeap\.h"|#include "Metalloid/Resources/MLDescriptorHeap.h"|g;
s|#include "MLPipelineState\.h"|#include "Metalloid/Pipelines/MLPipelineState.h"|g;
s|#include "MLVideoDevice\.h"|#include "Metalloid/Video/MLVideoDevice.h"|g;
s|#include "MLVideoDecoder\.h"|#include "Metalloid/Video/MLVideoDecoder.h"|g;
s|#include "MLVideoDecodeCommandList\.h"|#include "Metalloid/Video/MLVideoDecodeCommandList.h"|g;
s|#include "MLHeap\.h"|#include "Metalloid/Resources/MLHeap.h"|g;
s|#include "MLQueryHeap\.h"|#include "Metalloid/Sync/MLQueryHeap.h"|g;
s|#include "MLRootSignature\.h"|#include "Metalloid/Pipelines/MLRootSignature.h"|g;
s|#include "MLShaderCompiler\.h"|#include "Metalloid/Pipelines/MLShaderCompiler.h"|g;
s|#include "d3d12_mac_common\.h"|#include "d3d12_mac_common.h"|g;
' {} +

echo "Done restructuring."
