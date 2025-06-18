import time
import tracemalloc
from memory_profiler import memory_usage
import pyodbc

from .config import DEBUG, USE_PARTIAL_PAYLOAD



def log_debug(msg):
    if DEBUG:
        print(msg)

def announce_mode():
    print("▶ Running in development mode" if DEBUG else "▶ Running in production mode")
    print("▶ Partial delta payload mode enabled" if USE_PARTIAL_PAYLOAD else "▶ Full non-delta payload mode only")



def benchmark_section(label):
    def decorator(func):
        def wrapper(*args, **kwargs):
            print(f"Starting {label}...")
            start = time.time()
            tracemalloc.start()
            mem_before = memory_usage()[0]
            result = func(*args, **kwargs)
            mem_after = memory_usage()[0]
            current, peak = tracemalloc.get_traced_memory()
            tracemalloc.stop()
            elapsed = time.time() - start
            
            if DEBUG:
                print(f"Finished {label}: {elapsed:.2f}s | Mem delta: {mem_after - mem_before:.2f} MiB | Peak mem: {peak / 1024**2:.2f} MiB")

            return result
        return wrapper
    return decorator



def test_db_connection(conn_str):
    try:
        conn = pyodbc.connect(conn_str, timeout=10)
        print("[OK] DB connected.")
        conn.close()
        return True
    except Exception as e:
        print("[Fail] DB connection test:", e)
        return False

# # Test DB connection
# # Quick drop-in block to .ipynb or main()
# import sys
# from utils import test_db_connection
# if not test_db_connection(SQL_CONN_STR):
#     sys.exit(1)  # Stop
