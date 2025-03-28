/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree.
 */

#include "common.cuh"

using Tensor = at::Tensor;

namespace fbgemm_gpu {

// A: m, batch_size, k
// B: batch_size, k, n
// C: m, batch_size, n
// bias: batch_size, n
DLL_PUBLIC Tensor permute102_baddbmm_permute102_cuda(
    const Tensor& bias,
    const Tensor& A,
    const Tensor& B) {
  TENSOR_CONTIGUOUS_AND_ON_CUDA_GPU(A);
  TENSOR_CONTIGUOUS_AND_ON_CUDA_GPU(B);
  TENSOR_CONTIGUOUS_AND_ON_CUDA_GPU(bias);

  at::cuda::OptionalCUDAGuard device_guard;
  device_guard.set_index(A.get_device());

  TENSORS_ON_SAME_DEVICE(A, B);
  TENSORS_ON_SAME_DEVICE(A, bias);
  TENSOR_NDIM_EQUALS(A, 3);
  TENSOR_NDIM_EQUALS(B, 3);

  const auto m = A.size(0);
  const auto batch_size = A.size(1);
  const auto k = A.size(2);
  const auto n = B.size(2);
  TORCH_CHECK(B.size(0) == batch_size);
  TORCH_CHECK(B.size(1) == k);
  TORCH_CHECK(bias.size(0) == batch_size);
  TORCH_CHECK(bias.size(1) == n);

  // auto C = at::empty({m, batch_size, n}, A.options());
  // auto C = at::broadcast_to(bias, {m, batch_size, n}).contiguous();
  auto C = bias.unsqueeze(0).broadcast_to({m, batch_size, n}).contiguous();

  auto handle = at::cuda::getCurrentCUDABlasHandle();
  cublasSetStream(handle, c10::cuda::getCurrentCUDAStream());

  // C (m, b, n) = A (m, b, k) * B (b, k, n) ---> row major
  // C (m, b, n) = (B^T (b, k, n) * A^T (m, b, k))^T ---> column major

#ifdef __HIP_PLATFORM_HCC__
  float alpha = 1.0f;
  float beta = 1.0f;

  auto Btype = HIPBLAS_R_16F;
  auto ldb = n;
  auto strideB = n * k;

  auto Atype = HIPBLAS_R_16F;
  auto lda = k * batch_size;
  auto strideA = k;

  auto Ctype = HIPBLAS_R_16F;
  auto ldc = n * batch_size;
  auto strideC = n;

  auto computeType = HIPBLAS_R_32F;

  auto result = hipblasGemmStridedBatchedEx(
      handle,
      HIPBLAS_OP_N,
      HIPBLAS_OP_N,
      n,
      m,
      k,
      &alpha,
      B.data_ptr<at::Half>(),
      Btype,
      ldb,
      strideB,
      A.data_ptr<at::Half>(),
      Atype,
      lda,
      strideA,
      &beta,
      C.data_ptr<at::Half>(),
      Ctype,
      ldc,
      strideC,
      batch_size,
      computeType,
      HIPBLAS_GEMM_DEFAULT);
  TORCH_CHECK(result == CUBLAS_STATUS_SUCCESS);
  return C;
}
#else
  float alpha = 1.0f;
  float beta = 1.0f;

  auto Btype = CUDA_R_16F;
  auto ldb = n;
  auto strideB = n * k;

  auto Atype = CUDA_R_16F;
  auto lda = k * batch_size;
  auto strideA = k;

  auto Ctype = CUDA_R_16F;
  auto ldc = n * batch_size;
  auto strideC = n;

  auto computeType = CUBLAS_COMPUTE_32F;

  auto result = cublasGemmStridedBatchedEx(
      handle,
      CUBLAS_OP_N,
      CUBLAS_OP_N,
      n,
      m,
      k,
      &alpha,
      B.data_ptr<at::Half>(),
      Btype,
      ldb,
      strideB,
      A.data_ptr<at::Half>(),
      Atype,
      lda,
      strideA,
      &beta,
      C.data_ptr<at::Half>(),
      Ctype,
      ldc,
      strideC,
      batch_size,
      computeType,
      CUBLAS_GEMM_DEFAULT);
  TORCH_CHECK(result == CUBLAS_STATUS_SUCCESS);
  return C;
}
#endif

} // namespace fbgemm_gpu

FBGEMM_OP_DISPATCH(
    CUDA,
    "permute102_baddbmm_permute102",
    fbgemm_gpu::permute102_baddbmm_permute102_cuda);
