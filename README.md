# CUDA Containers for NVIDIA DGX Spark

This repository contains Dockerfiles and build recipes for CUDA-based containers optimized for **NVIDIA DGX Spark**
systems, with a focus on **vLLM**, **PyTorch**, and multi-node inference workloads.

The primary goal of this project is to provide **stable, well-versioned, prebuilt images** that work out-of-the-box on
DGX Spark (Blackwell-ready), while still being suitable as **base images** for custom builds.

---

## Why This Repo Exists

The official NVIDIA images tend to run too far behind the latest releases. Other community images prioritize bleeding
edge over versioning and stability.

The goal of this repo is to provide a **stable, well-versioned, prebuilt images** that work out-of-the-box on DGX
Spark (Blackwell-ready).

The main architectural difference from other builds (e.g. eugr's repo (link below) -- which is pretty much the community
standard) is:

- **NCCL and PyTorch are built first**, in a dedicated base image
- vLLM and related tooling are layered on top
- Versioning follows **vLLM releases** as the primary axis

If you need the *absolute latest vLLM features from git right now*, I still strongly recommend:
https://github.com/eugr/spark-vllm-docker

---

## Available Images

### vLLM Images

All vLLM images:

- Are optimized for DGX Spark
- Include **Ray** for multi-node / cluster deployments
- Rebuild PyTorch, Triton, and vLLM against updated NCCL
- Support tensor parallelism (`-tp`) and multi-node inference
- are hosted on Docker Hub: [https://hub.docker.com/r/scitrera/dgx-spark-vllm](https://hub.docker.com/r/scitrera/dgx-spark-vllm)

#### Latest Releases

##### vLLM 0.15.0

- `scitrera/dgx-spark-vllm:0.15.0-t4`
    - vLLM 0.15.0
    - PyTorch 2.10.0 (with torchvision + torchaudio)
    - CUDA 13.1.0
    - Transformers 4.57.6
    - Triton 3.5.1 *(3.6.0 not yet compatible)*
    - NCCL 2.29.2-1
    - FlashInfer 0.6.2

- `scitrera/dgx-spark-vllm:0.15.0-t5`
    - Same as above, but with **Transformers 5.0.0**

##### vLLM 0.14.1

- `scitrera/dgx-spark-vllm:0.14.1-t4`
- `scitrera/dgx-spark-vllm:0.14.1-t5`

##### Earlier Builds

- `scitrera/dgx-spark-vllm:0.14.0-t4`
- `scitrera/dgx-spark-vllm:0.14.0-t5`
    - Includes a patch to `is_deepseek_mla()` for **GLM-4.7-Flash**
    - Tested successfully with Ray and `-tp4` on a 4-node DGX Spark cluster

- `scitrera/dgx-spark-vllm:0.13.0-t4`

---

### PyTorch Development Base Image

If you want to build your own inference stack:

- **`scitrera/dgx-spark-pytorch-dev:2.10.0-cu131`**
    - PyTorch 2.10.0
    - CUDA 13.1.0
    - NCCL 2.29.2-1
    - Built on `nvidia/cuda:13.1.0-devel-ubuntu24.04`
    - Includes standard build tooling

This is the recommended base image if you want to:

- Build vLLM yourself
- Add custom kernels or extensions
- Experiment with alternative runtimes (e.g. sglang)

---

## Tag Semantics

Tags follow this pattern for vllm containers:

```

<vllm-version>-t<transformers-major>

````

Examples:

- `0.13.0-t4` → vLLM 0.13.0 + Transformers 4.x
- `0.14.1-t5` → vLLM 0.14.1 + Transformers 5.x (pre-release or early)

---

## Example Usage

```bash
docker run \
  --privileged \
  --gpus all \
  -it --rm \
  --network host --ipc=host \
  -v ~/.cache/huggingface:/root/.cache/huggingface \
  scitrera/dgx-spark-vllm:0.13.0-t4 \
  vllm serve \
    Qwen/Qwen3-1.7B \
    --gpu-memory-utilization 0.7
````

---

## Inspecting Component Versions

Major component versions are embedded as Docker labels.

```bash
docker inspect scitrera/dgx-spark-vllm:0.14.0rc2-t4 \
  --format '{{json .Config.Labels}}' | jq
```

Example output:

```json
{
  "dev.scitrera.cuda_version": "13.1.0",
  "dev.scitrera.flashinfer_version": "0.6.1",
  "dev.scitrera.nccl_version": "2.28.9-1",
  "dev.scitrera.torch_version": "2.10.0-rc6",
  "dev.scitrera.transformers_version": "4.57.5",
  "dev.scitrera.triton_version": "3.5.1",
  "dev.scitrera.vllm_version": "0.14.0rc2"
}
```

---

## Notes & Caveats

* NCCL is upgraded relative to upstream PyTorch builds
* PyTorch, Triton, and vLLM are rebuilt accordingly
* Image sizes could still be optimized further
* Version combinations are chosen to be as new as possible but limited by **stability** (not guaranteed to have the latest features if they might break things)

---

## Roadmap (Loose)

* sglang images
* Better size optimization
* More documentation/support for DGX Spark newcomers

---

## Acknowledgements

This work is inspired by and complementary to:

* @eugr’s DGX Spark vLLM images
  [https://github.com/eugr/spark-vllm-docker](https://github.com/eugr/spark-vllm-docker)
* Everyone else who contributed to the NVIDIA DGX spark forums, especially in the first two months after the DGX Spark's
  release. Getting things to work was really a mess!

This project is not affiliated with NVIDIA. This project is sponsored and maintained by [scitrera.ai](https://scitrera.ai/).

If you need the very latest vLLM feature added four hours ago, start with eugr's repo.
If you want stable, prebuilt images with predictable versioning, use the docker images built from this repo.