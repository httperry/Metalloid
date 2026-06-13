# Research Notes & Discoveries

This document chronicles our technical discoveries and architectural decisions while building the Metalloid translation layer for macOS.

## 1. Apple Silicon Implicit Layout Hazard
During Milestone 8, we discovered that transitioning a resource from an `UNDEFINED` layout without explicitly writing to it caused the GPU driver to implicitly execute a layout metadata initialization pass. This led to massive performance stalls when scaling draw calls. 

**Solution**: The "Shadow Layout State Machine". We implemented an `ever_written` tracker inside `HierarchicalResourceState`. If an `UNDEFINED` resource has never been written to, we intercept the barrier transition and inject a lightweight `MTLLoadActionClear` with `{0,0,0,0}`. This forcefully instantiates the physical memory mapping instantly on the CPU timeline without triggering the GPU driver's implicit fallback mechanism.

## 2. Command Recording vs Execution Timeline Drift
Because D3D12 command lists are recorded asynchronously and executed later via `ExecuteCommandLists`, local resource states inside the command list rapidly drifted from the global device truth.

**Solution**: We introduced a "Patch Table" mechanism. Local command lists track transitions in a `m_patchTable` using pointers. During queue execution, a `std::mutex` locks the global state tracker, and the patch tables are rapidly synchronized against the authoritative `m_globalResourceStates`, ensuring an air-tight layout discard cascade.

## 3. Zero-Copy Shared Memory (Upcoming UMA Optimization)
Unlike traditional discrete GPUs that require data to be copied across the PCIe bus from a CPU Upload Heap to GPU VRAM, Apple Silicon uses a Unified Memory Architecture (UMA). 
*   **Discovery**: We can completely eliminate the `CopyBufferRegion` staging pass by mapping `D3D12_HEAP_TYPE_UPLOAD` to `MTLStorageModeShared`. 
*   This approach promises up to a 50% reduction in VRAM footprint and zero copy latency for dynamically streaming assets like meshes and textures.
