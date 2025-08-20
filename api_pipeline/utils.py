# api_pipeline/utils.py

import time
import tracemalloc
import pyodbc  # for notebook/test_db_connection snippet(end block)

# --- Optional memory_profiler support ----------------------------------------
# If memory_profiler not installed (e.g., in PyInstaller EXE), degrade
# gracefully and omit "Mem delta" from benchmark output
try:
    from memory_profiler import memory_usage as _memory_usage
except Exception:
    _memory_usage = None

def _safe_memory_usage_first_sample():
    """
    Returns the first memory usage sample in MiB if memory_profiler is available,
    otherwise returns None. Never raises.
    """
    if _memory_usage is None:
        return None
    try:
        samples = _memory_usage()
        return samples[0] if samples else None
    except Exception:
        return None

# --- Config imports (package + script contexts) -----------------------------
try:
    # running as proper package
    from .config import DEBUG, USE_PARTIAL_PAYLOAD
except ImportError:
    try:
        # Fallback -running loose scripts
        from config import DEBUG, USE_PARTIAL_PAYLOAD
    except Exception:
        # Last‑ditch -defaults avoid import‑time crashes in --help or EXE smoke tests
        DEBUG = False
        USE_PARTIAL_PAYLOAD = False

# --- Logging / mode helpers ---------------------------------------------------
def log_debug(msg: str):
    if DEBUG:
        print(msg)

def announce_mode():
    print("Running in development mode" if DEBUG else "▶ Running in production mode")
    print("Partial delta payload mode enabled" if USE_PARTIAL_PAYLOAD else "▶ Full non-delta payload mode only")

# --- Benchmark decorator ------------------------------------------------------
def benchmark_section(label: str):
    """
    Decorator to benchmark a function section.
    - Always measures elapsed time and tracemalloc peak memory.
    - If memory_profiler is available, also reports process "Mem delta" in MiB.
    """
    def decorator(func):
        def wrapper(*args, **kwargs):
            print(f"Starting {label}...")
            start = time.time()
            tracemalloc.start()

            mem_before = _safe_memory_usage_first_sample()

            result = func(*args, **kwargs)

            mem_after = _safe_memory_usage_first_sample()
            current, peak = tracemalloc.get_traced_memory()
            tracemalloc.stop()

            elapsed = time.time() - start

            if DEBUG:
                peak_mib = peak / (1024 ** 2)
                if mem_before is not None and mem_after is not None:
                    mem_delta = mem_after - mem_before
                    print(f"Finished {label}: {elapsed:.2f}s | Mem delta: {mem_delta:.2f} MiB | Peak mem: {peak_mib:.2f} MiB")
                else:
                    # memory_profiler not present (or failed): omit Mem delta
                    print(f"Finished {label}: {elapsed:.2f}s | Peak mem: {peak_mib:.2f} MiB")

            return result
        return wrapper
    return decorator

# ----------------------------------------------------------------------
# # Test DB connection
# # Quick drop-in block to .ipynb or main()
# import sys
# from .config import SQL_CONN_STR  # or: from config import SQL_CONN_STR
# from utils import test_db_connection
# if not test_db_connection(SQL_CONN_STR):
#     sys.exit(1)  # Stop
