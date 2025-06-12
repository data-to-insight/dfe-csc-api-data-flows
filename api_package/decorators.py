
import time
import tracemalloc
import logging
from memory_profiler import memory_usage

logger = logging.getLogger(__name__)

def timed_section(label):
    """
    Decorator for timing, memory tracking.

    Args:
        label: Section identifier for logging.
    
    Returns:
        Wrapped function with logging.
    """
    def decorator(func):
        def wrapper(*args, **kwargs):
            logger.info(f"Starting {label}...")
            start = time.time()
            tracemalloc.start()
            mem_before = memory_usage()[0]

            result = func(*args, **kwargs)

            mem_after = memory_usage()[0]
            current, peak = tracemalloc.get_traced_memory()
            tracemalloc.stop()
            elapsed = time.time() - start

            logger.info(
                f"Finished {label}: {elapsed:.2f}s | "
                f"Mem delta: {mem_after - mem_before:.2f} MiB | "
                f"Peak mem: {peak / 1024**2:.2f} MiB"
            )

            return result
        return wrapper
    return decorator
