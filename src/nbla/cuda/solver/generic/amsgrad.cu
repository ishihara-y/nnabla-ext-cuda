// Copyright (c) 2017 Sony Corporation. All Rights Reserved.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

#include <nbla/cuda/common.hpp>
#include <nbla/cuda/solver/amsgrad.hpp>

#include "./weight_decay.cuh"

namespace nbla {

template <typename T>
__global__ void kernel_amsgrad_update(const int num, T *theta, T *m, T *v,
                                      T *v_hat, const T *g, const float alpha_t,
                                      const float beta1, const float beta2,
                                      const float eps) {
  NBLA_CUDA_KERNEL_LOOP(s, num) {
    // Updating running mean and var.
    m[s] = beta1 * m[s] + (1 - beta1) * g[s];
    v[s] = beta2 * v[s] + (1 - beta2) * g[s] * g[s];
    v_hat[s] = max(v_hat[s], v[s]);
    // Update parameters.
    theta[s] = theta[s] - alpha_t * m[s] / (std::sqrt(v_hat[s]) + eps);
  }
}

template <typename T>
void AMSGRADCuda<T>::update_impl(const string &key, VariablePtr param) {
  cuda_set_device(std::stoi(this->ctx_.device_id));
  Size_t size = param->size();
  auto &state = this->state_.at(key);
  int &t = state.t;
  const T *g = param->get_grad_pointer<T>(this->ctx_);
  shared_ptr<Variable> mean_ = state.mean;       // To prevent compile error.
  shared_ptr<Variable> var_ = state.var;         // To prevent compile error.
  shared_ptr<Variable> var_hat_ = state.var_hat; // To prevent compile error.
  T *m = mean_->cast_data_and_get_pointer<T>(this->ctx_);
  T *v = var_->cast_data_and_get_pointer<T>(this->ctx_);
  T *v_hat = var_hat_->cast_data_and_get_pointer<T>(this->ctx_);
  T *theta = param->cast_data_and_get_pointer<T>(this->ctx_);
  t = std::min(t + 1, std::numeric_limits<int>::max());
  const T bias_correction = std::sqrt(1 - std::pow(this->beta2_, t)) /
                            (1 - std::pow(this->beta1_, t));
  const T alpha_t =
      this->alpha_ * (this->bias_correction_ ? bias_correction : 1);
  NBLA_CUDA_LAUNCH_KERNEL_SIMPLE(kernel_amsgrad_update, size, theta, m, v,
                                 v_hat, g, alpha_t, this->beta1_, this->beta2_,
                                 this->eps_);
}
NBLA_DEF_WEIGHT_DECAY(AMSGRADCuda, weight_decay_cuda);
}
