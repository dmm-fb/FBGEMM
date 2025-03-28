/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree.
 */

#pragma once

#ifdef FBGEMM_GPU_ENABLE_DUMMY_IA32_SERIALIZE
// Workaround the missing __builtin_ia32_serialize issue
#if defined(__NVCC__) && \
    (__CUDACC_VER_MAJOR__ > 11 || __CUDACC_VER_MINOR__ >= 4)
static __inline void __attribute__((
    __gnu_inline__,
    __always_inline__,
    __artificial__,
    __target__("serialize"))) __builtin_ia32_serialize(void) {
  abort();
}
#endif // __NVCC__
#endif // FBGEMM_GPU_ENABLE_DUMMY_IA32_SERIALIZE

#include <ATen/core/op_registration/op_registration.h>
#include <torch/library.h>
