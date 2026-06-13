cmake_minimum_required(VERSION 3.15)
project(Metalloid LANGUAGES C CXX OBJCXX)

# Require C++20
set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# Enable Objective-C Automatic Reference Counting (ARC)
set(CMAKE_OBJCXX_FLAGS "${CMAKE_OBJCXX_FLAGS} -fobjc-arc")

# Fetch Microsoft DirectX Headers
include(FetchContent)
FetchContent_Declare(
    DirectX-Headers
    GIT_REPOSITORY https://github.com/microsoft/DirectX-Headers.git
    GIT_TAG        v1.613.1
)
FetchContent_MakeAvailable(DirectX-Headers)

# Configure include directories
include_directories(
    ${CMAKE_CURRENT_SOURCE_DIR}/Include
)

# DXGI Shared Library
add_library(dxgi SHARED
    Source/DXGI/MLFactory.mm
    Source/DXGI/MLSwapChain.mm
    Source/Resources/MLResource.mm
)
target_link_libraries(dxgi PRIVATE
    Microsoft::DirectX-Headers
    Microsoft::DirectX-Guids
    "-framework Metal"
    "-framework Foundation"
    "-framework QuartzCore"
    "-framework AppKit"
)
# Ensure the output filename is dxgi.dylib without the lib prefix
set_target_properties(dxgi PROPERTIES
    PREFIX ""
    SUFFIX ".dylib"
)

# D3D12 Shared Library
add_library(d3d12 SHARED
    Source/Device/MLDevice.mm
    Source/Device/d3d12_entry.mm
    Source/Commands/MLCommandQueue.mm
    Source/Commands/MLCommandAllocator.mm
    Source/Commands/MLCommandList.mm
    Source/Pipelines/MLStateObject.mm
    Source/Resources/MLResource.mm
    Source/Resources/MLDescriptorHeap.mm
    Source/Pipelines/MLShaderCompiler.mm
    Source/Pipelines/MLPipelineState.mm
    Source/Video/MLVideoDevice.mm
    Source/Video/MLVideoDecoder.mm
    Source/Video/MLVideoDecodeCommandList.mm
    Source/Sync/MLFence.mm
    Source/Resources/MLHeap.mm
    Source/Sync/MLQueryHeap.mm
    Source/Pipelines/MLRootSignature.mm
    Source/Thunks/unix_thunks.mm
)
target_link_libraries(d3d12 PRIVATE
    dxgi
    Microsoft::DirectX-Headers
    Microsoft::DirectX-Guids
    "-framework Metal"
    "-framework Foundation"
    "-framework QuartzCore"
    "-framework VideoToolbox"
    "-framework CoreMedia"
    "-framework CoreVideo"
    "-framework IOSurface"
)
# Ensure the output filename is d3d12.dylib without the lib prefix
set_target_properties(d3d12 PROPERTIES
    PREFIX ""
    SUFFIX ".dylib"
)

# Apply Wine headers and Unix definitions ONLY to the boundary file to prevent MS header collisions
set_source_files_properties(Source/Thunks/unix_thunks.mm PROPERTIES 
    COMPILE_FLAGS "-I${CMAKE_CURRENT_SOURCE_DIR}/Dependencies/wine/include -DWINE_UNIX_LIB"
)

# Compile the Windows PE DLL using MinGW cross-compiler
add_custom_command(
    TARGET d3d12 POST_BUILD
    COMMAND x86_64-w64-mingw32-g++ -shared -static-libgcc -static-libstdc++ 
            ${CMAKE_CURRENT_SOURCE_DIR}/Source/Thunks/d3d12_pe.cpp 
            -o ${CMAKE_CURRENT_BINARY_DIR}/d3d12.dll
            -I${CMAKE_CURRENT_SOURCE_DIR}/Dependencies/wine/include
    COMMENT "Building d3d12.dll PE Stub"
)


