<div align="center">
  <h1>Metalloid</h1>
  <p><strong>A high-performance Direct3D 12 to Apple Metal translation layer for Apple Silicon.</strong></p>

  <p>
    <img src="https://img.shields.io/badge/Platform-macOS%2026%2B-blue?style=for-the-badge&logo=apple" alt="macOS" />
    <img src="https://img.shields.io/badge/API-Metal%204-000000?style=for-the-badge" alt="Metal 4" />
    <img src="https://img.shields.io/badge/Build-CMake-green?style=for-the-badge&logo=cmake" alt="CMake" />
    <img src="https://img.shields.io/badge/License-MIT-yellow?style=for-the-badge" alt="License" />
  </p>
</div>

---

## Overview

**Metalloid** is an advanced translation layer engineered specifically for Apple Silicon hardware. It maps **Direct3D 12 API** calls directly to **Apple's Metal framework**, allowing complex DirectX 12 engines—such as **Unreal Engine 5**—to run natively on macOS with zero-overhead translation.

By utilizing modern Metal 4 features and dynamic shader compilation, Metalloid delivers a fluid, high-fidelity gaming experience without the traditional emulation penalties.

---

## Performance & Compatibility

Metalloid has been heavily optimized for complex rendering pipelines. When benchmarking the **Unreal Engine 5 London Demo**, Metalloid achieved **56 FPS at 17.84ms**, demonstrating a staggering **311% performance uplift** compared to Apple's native D3DMetal layer (which averaged 18 FPS at 55ms on the exact same hardware and workload).

![Metalloid UE5 London Demo Performance](Documentation/Images/performance_56fps.jpg)

### Core Advancements:
- **DirectX 12 Enhanced Barriers:** Fully compliant fix implemented, ensuring flawless synchronization and preventing pipeline stalls typically associated with state-transition emulation.
- **Native Metal Translation:** Direct mapping of D3D12 device interfaces, command lists, and synchronization primitives to their exact Metal counterparts.
- **Metal Shader Converter Integration:** Dynamic, runtime conversion of DXIL bytecode to Metal IR via Apple's `metal_irconverter`.
- **Zero-Overhead Shader Caching:** Highly optimized, disk-backed caching system for LLVM IR pipelines, eliminating compilation stutter after the first run.
- **Dynamic Descriptor Binding:** Fully mapped descriptor heaps utilizing Metal Tier 2 Argument Buffers.

---

## Build Requirements

Ensure your system meets the following prerequisites before compiling:

- **OS:** macOS 26+ (Metal 4 supported hardware)
- **Compiler:** Xcode 15 or later (Apple Clang)
- **Build System:** CMake 3.24+
- **Toolkit:** `metal_irconverter` (Apple Metal Shader Converter)

### Compiling

```bash
mkdir build && cd build
cmake ..
make -j$(sysctl -n hw.logicalcpu)
```

This will produce the `d3d12.dylib` and `dxgi.dylib` files required for injection via Wine or CrossOver.

---

## Disclaimer

*This project is an independent translation layer and is not officially affiliated with, nor endorsed by, Microsoft Corporation or Apple Inc.*
