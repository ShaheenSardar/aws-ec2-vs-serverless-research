import hashlib

WORKLOAD_VERSION = "sha256-v1"
DEFAULT_ITERATIONS = 25000


def perform_computation(iterations: int = DEFAULT_ITERATIONS) -> dict:
    value = b"aws-architecture-research-v1"

    for _ in range(iterations):
        value = hashlib.sha256(value).digest()

    return {
        "workload_version": WORKLOAD_VERSION,
        "iterations": iterations,
        "result": value.hex(),
    }
