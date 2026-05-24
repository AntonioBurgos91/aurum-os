#!/usr/bin/env python3
# ==============================================================================
# AurumOS Deep Learning Stack Verification (Smoke Tests)
# Verifies PyTorch (CUDA), JAX (GPU), TensorFlow (GPU), and vLLM environments.
# ==============================================================================

import sys
import os

# Terminal colors for output
GREEN = "\033[92m"
RED = "\033[91m"
YELLOW = "\033[93m"
BLUE = "\033[94m"
BOLD = "\033[1m"
RESET = "\033[0m"

def print_header(title):
    print(f"\n{BOLD}{BLUE}=== {title} ==={RESET}")

def print_ok(msg):
    print(f"{GREEN}[OK] {msg}{RESET}")

def print_fail(msg):
    print(f"{RED}[FAIL] {msg}{RESET}")

def print_warn(msg):
    print(f"{YELLOW}[WARN] {msg}{RESET}")

def test_pytorch():
    print_header("Testing PyTorch Integration")
    try:
        import torch
        print_ok(f"PyTorch version: {torch.__version__}")
        
        cuda_available = torch.cuda.is_available()
        if not cuda_available:
            print_fail("CUDA is NOT available to PyTorch!")
            return False
            
        print_ok("CUDA is available.")
        device_count = torch.cuda.device_count()
        print_ok(f"GPU Count: {device_count}")
        for i in range(device_count):
            print_ok(f"  Device {i}: {torch.cuda.get_device_name(i)}")
            
        # Run a tensor operation on the GPU
        device = torch.device("cuda")
        x = torch.randn(1000, 1000, device=device)
        y = torch.randn(1000, 1000, device=device)
        z = torch.matmul(x, y)
        torch.cuda.synchronize()
        
        print_ok(f"Tensor matmul verified on GPU device. Output shape: {z.shape}")
        return True
    except Exception as e:
        print_fail(f"PyTorch test crashed: {e}")
        return False

def test_jax():
    print_header("Testing JAX Integration")
    try:
        import jax
        print_ok(f"JAX version: {jax.__version__}")
        
        devices = jax.devices()
        print_ok(f"JAX visible devices: {devices}")
        
        gpu_found = False
        for d in devices:
            if d.platform == 'gpu' or d.device_kind.startswith('NVIDIA') or d.device_kind.startswith('AMD'):
                gpu_found = True
                
        if not gpu_found:
            print_fail("No GPU devices detected by JAX!")
            return False
            
        # Run simple computation on JAX
        import jax.numpy as jnp
        x = jax.random.normal(jax.random.PRNGKey(0), (1000, 1000))
        y = jax.random.normal(jax.random.PRNGKey(1), (1000, 1000))
        z = jnp.dot(x, y)
        # Force evaluation
        z.block_until_ready()
        
        print_ok("JAX computation on GPU verified.")
        return True
    except Exception as e:
        print_fail(f"JAX test crashed: {e}")
        return False

def test_tensorflow():
    print_header("Testing TensorFlow Integration")
    try:
        # Suppress verbose TF logging
        os.environ['TF_CPP_MIN_LOG_LEVEL'] = '2'
        import tensorflow as tf
        print_ok(f"TensorFlow version: {tf.__version__}")
        
        gpus = tf.config.list_physical_devices('GPU')
        if not gpus:
            print_fail("No GPUs detected by TensorFlow!")
            return False
            
        print_ok(f"TensorFlow physical GPUs: {gpus}")
        
        # Test basic mathematical operations
        with tf.device('/GPU:0'):
            a = tf.random.normal([1000, 1000])
            b = tf.random.normal([1000, 1000])
            c = tf.matmul(a, b)
            
        print_ok(f"TensorFlow GPU calculation completed. Output shape: {c.shape}")
        return True
    except Exception as e:
        print_fail(f"TensorFlow test crashed: {e}")
        return False

def test_vllm():
    print_header("Testing vLLM Integration")
    try:
        import vllm
        print_ok(f"vLLM version: {vllm.__version__}")
        print_ok("vLLM package importing verified.")
        return True
    except Exception as e:
        print_fail(f"vLLM importing failed: {e}")
        return False

def main():
    print(f"\n{BOLD}{YELLOW}==========================================")
    print("   AurumOS DL Stack Smoke Test Runner     ")
    print(f"=========================================={RESET}")
    
    results = {
        "PyTorch": test_pytorch(),
        "JAX": test_jax(),
        "TensorFlow": test_tensorflow(),
        "vLLM": test_vllm()
    }
    
    print_header("Verification Summary")
    all_passed = True
    for name, passed in results.items():
        status = f"{GREEN}PASSED{RESET}" if passed else f"{RED}FAILED{RESET}"
        print(f"  - {name}: {status}")
        if not passed:
            all_passed = False
            
    print(f"\n{BOLD}{YELLOW}=========================================={RESET}")
    if all_passed:
        print(f"{BOLD}{GREEN}ALL SMOKE TESTS PASSED!{RESET}")
        sys.exit(0)
    else:
        print(f"{BOLD}{RED}SOME SMOKE TESTS FAILED! Check logs above.{RESET}")
        sys.exit(1)

if __name__ == "__main__":
    main()
