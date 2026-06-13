#pragma once
#include "d3d12_mac_common.h"
#ifdef __OBJC__
#import <Metal/Metal.h>
#import <IOSurface/IOSurface.h>
#endif

struct MLSharedHandle {
#ifdef __OBJC__
    MTLSharedEventHandle* eventHandle = nil;
    IOSurfaceID surfaceId = 0;
#else
    void* eventHandle = nullptr;
    uint32_t surfaceId = 0;
#endif
};
