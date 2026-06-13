#!/bin/bash
set -e

cd /Users/niranjana/System/Metalloid

# 1. Create Source folders
mkdir -p Source/Device Source/Commands Source/Resources Source/Pipelines Source/Sync Source/Video Source/Common

# 2. Move Source files
mv Source/Core/MLDevice.mm Source/Device/
mv Source/Core/d3d12_entry.mm Source/Device/
mv Source/Core/MLCommandQueue.mm Source/Commands/
mv Source/Core/MLCommandAllocator.mm Source/Commands/
mv Source/Core/MLCommandList.mm Source/Commands/
mv Source/Core/MLResource.mm Source/Resources/
mv Source/Core/MLHeap.mm Source/Resources/
mv Source/Core/MLDescriptorHeap.mm Source/Resources/
mv Source/Core/MLPipelineState.mm Source/Pipelines/
mv Source/Core/MLRootSignature.mm Source/Pipelines/
mv Source/Core/MLStateObject.mm Source/Pipelines/
mv Source/Core/MLShaderCompiler.mm Source/Pipelines/
mv Source/Core/MLFence.mm Source/Sync/
mv Source/Core/MLQueryHeap.mm Source/Sync/
mv Source/Core/MLVideoDevice.mm Source/Video/
mv Source/Core/MLVideoDecoder.mm Source/Video/
mv Source/Core/MLVideoDecodeCommandList.mm Source/Video/

rmdir Source/Core || true

# 3. Create Include folders
mkdir -p Include/Metalloid/Device Include/Metalloid/Commands Include/Metalloid/Resources Include/Metalloid/Pipelines Include/Metalloid/Sync Include/Metalloid/Video Include/Metalloid/Common Include/Metalloid/DXGI

# 4. Move Include files
mv Include/Metalloid/MLDevice.h Include/Metalloid/Device/
mv Include/Metalloid/MLCommandQueue.h Include/Metalloid/Commands/
mv Include/Metalloid/MLCommandAllocator.h Include/Metalloid/Commands/
mv Include/Metalloid/MLCommandList.h Include/Metalloid/Commands/
mv Include/Metalloid/MLResource.h Include/Metalloid/Resources/
mv Include/Metalloid/MLHeap.h Include/Metalloid/Resources/
mv Include/Metalloid/MLDescriptor.h Include/Metalloid/Resources/
mv Include/Metalloid/MLDescriptorHeap.h Include/Metalloid/Resources/
mv Include/Metalloid/MLPipelineState.h Include/Metalloid/Pipelines/
mv Include/Metalloid/MLRootSignature.h Include/Metalloid/Pipelines/
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

# 5. Fix #include statements globally using perl
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
' {} +

echo "Done restructuring."
