# Metalloid

**Metalloid** is a high-performance translation layer designed to map Direct3D 12 API calls to Apple's Metal framework. Engineered specifically for Apple Silicon, Metalloid enables advanced DirectX 12 applications and engines—such as Unreal Engine 5—to run natively on macOS with zero-overhead translation.

### Key Features
- **Native Metal Translation:** Direct mapping of D3D12 device interfaces, command lists, and synchronization primitives to Metal equivalents.
- **Metal Shader Converter Integration:** Dynamic, runtime conversion of DXIL bytecode to Metal intermediate representation (IR) using Apple's `metal_irconverter`.
- **Zero-Overhead Shader Caching:** Highly optimized disk-backed caching system for LLVM IR pipelines, eliminating compilation stutter on subsequent executions.
- **Dynamic Descriptor Binding:** Fully mapped descriptor heaps and root signatures matching D3D12 bindless resource models to Metal Tier 2 Argument Buffers.

### Architecture
The translation layer acts as a drop-in replacement for `d3d12.dll` and `dxgi.dll`. It intercepts application rendering calls, manages GPU memory boundaries via Metal private storage modes, and dynamically orchestrates the asynchronous compilation of graphics and compute pipelines.

### Build Requirements
- macOS 14.0 or later
- Xcode 15 or later (Apple Clang)
- CMake 3.24+
- `metal_irconverter` (Apple Metal Shader Converter toolkit)

### Disclaimer
This project is an independent translation layer and is not officially affiliated with Microsoft or Apple.
