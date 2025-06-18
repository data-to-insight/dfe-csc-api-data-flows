import json


from .config import REQUIRED_FIELDS, ALLOWED_PURGE_BLOCKS
from .utils import benchmark_section




# [DIAG] Add diagnostics
from time import perf_counter  # [DIAG]
_recursive_diff_call_count = 0  # [DIAG]
_recursive_diff_total_time = 0  # [DIAG]

_prune_call_count = 0  # [DIAG]
_prune_total_time = 0  # [DIAG]


@benchmark_section("generate_partial_payload()")  # Performance monitor
def generate_partial_payload(current, previous):
    """
    Create partial payload with required and changed fields

    Args:
        current: Current full JSON payload
        previous: Previous full JSON payload

    Returns:
        Partial payload with required identifiers and detected changes
    """
    # Copy required fields
    partial = {k: current[k] for k in REQUIRED_FIELDS if k in current}

    # Compute structural differences
    diff = recursive_diff(current, previous)

    # Add new fields not already present
    for k, v in diff.items():
        if k not in partial:
            partial[k] = v

    return partial


@benchmark_section("generate_deletion_payload()")  # Performance monitor
def generate_deletion_payload(previous):
    """
    Create deletion payload using identifiers and purge flag

    Args:
        previous: Previous full JSON payload

    Returns:
        Minimal payload with identifiers and deletion marker
    """
    return {
        "la_child_id": previous.get("la_child_id"),  # Unique child identifier
        "mis_child_id": previous.get("mis_child_id"),  # MIS identifier
        "purge": True  # Purge signal for deletion
    }


@benchmark_section("recursive_diff()")  # Performance monitor
def recursive_diff(curr, prev):
    # [DIAG] Start timing and count
    global _recursive_diff_call_count, _recursive_diff_total_time  # [DIAG]
    _recursive_diff_call_count += 1  # [DIAG]
    _start = perf_counter()  # [DIAG]

    if isinstance(curr, dict) and isinstance(prev, dict):
        diff = {}

        for key in curr:
            # Skip if key unchanged
            if key not in prev or curr[key] != prev[key]:

                # Recurse into nested dicts
                if isinstance(curr[key], dict) and isinstance(prev.get(key), dict):
                    nested = recursive_diff(curr[key], prev[key])
                    if nested:
                        diff[key] = nested  # Include only if changes present

                # Recurse into lists
                elif isinstance(curr[key], list) and isinstance(prev.get(key), list):
                    if curr[key] != prev[key]:
                        # Pass parent key to control 'purge' inclusion
                        diff[key] = prune_unchanged_list(
                            curr[key], prev[key], parent_key=key
                        )

                # Handle scalars or mismatched types
                else:
                    diff[key] = curr[key]

        _recursive_diff_total_time += perf_counter() - _start  # [DIAG]
        return diff  # Return dict of differences

    # Return scalar diff, or empty if no change
    result = {} if curr == prev else curr
    _recursive_diff_total_time += perf_counter() - _start  # [DIAG]
    return result


@benchmark_section("prune_unchanged_list()")  # Performance monitor
def prune_unchanged_list(curr_list, prev_list, parent_key=None):
    # [DIAG] Start timing and count
    global _prune_call_count, _prune_total_time  # [DIAG]
    _prune_call_count += 1  # [DIAG]
    _start = perf_counter()  # [DIAG]

    result = []

    for curr_item in curr_list:
        matched_prev = None

        # Detect ID key
        id_key = next((k for k in curr_item if k.endswith("_id")), None)

        if id_key:
            # Find match in previous by ID
            for prev_item in prev_list:
                if prev_item.get(id_key) == curr_item.get(id_key):
                    matched_prev = prev_item
                    break

        if matched_prev:
            # Diff current item against matched previous
            item_diff = recursive_diff(curr_item, matched_prev)

            # Always retain ID key
            if id_key:
                item_diff[id_key] = curr_item[id_key]

            if item_diff:
                # Set 'purge' flag only for allowed blocks
                if parent_key in ALLOWED_PURGE_BLOCKS:
                    item_diff["purge"] = False
                result.append(item_diff)

        else:
            # Unmatched: treat as new item
            result.append(curr_item)

    _prune_total_time += perf_counter() - _start  # [DIAG]
    return result


# [DIAG] Function to summarise usage and timings
def print_diff_stats():
    print(f"\n[DIAG] recursive_diff() calls: {_recursive_diff_call_count}")
    print(f"[DIAG] Total time in recursive_diff(): {_recursive_diff_total_time:.2f}s")
    if _recursive_diff_call_count:
        print(f"[DIAG] Avg time per recursive_diff(): {_recursive_diff_total_time / _recursive_diff_call_count:.6f}s")

    print(f"\n[DIAG] prune_unchanged_list() calls: {_prune_call_count}")
    print(f"[DIAG] Total time in prune_unchanged_list(): {_prune_total_time:.2f}s")
    if _prune_call_count:
        print(f"[DIAG] Avg time per prune_unchanged_list(): {_prune_total_time / _prune_call_count:.6f}s")







# import json
# from config import REQUIRED_FIELDS, ALLOWED_PURGE_BLOCKS
# from utils import benchmark_section


# # PEP 484 signature:
# # def generate_partial_payload(current: Dict[str, Any], previous: Dict[str, Any]) -> Dict[str, Any]:
# @benchmark_section("generate_partial_payload()")  # Performance monitor
# def generate_partial_payload(current, previous):
#     """
#     Create partial payload with required and changed fields

#     Args:
#         current: Current full JSON payload
#         previous: Previous full JSON payload

#     Returns:
#         Partial payload with required identifiers and detected changes
#     """
#     # Copy required fields
#     partial = {k: current[k] for k in REQUIRED_FIELDS if k in current}

#     # Compute structural differences
#     diff = recursive_diff(current, previous)

#     # Add new fields not already present
#     for k, v in diff.items():
#         if k not in partial:
#             partial[k] = v

#     return partial


# # PEP 484 signature:
# # def generate_deletion_payload(previous: Dict[str, Any]) -> Dict[str, Any]:
# @benchmark_section("generate_deletion_payload()")  # Performance monitor
# def generate_deletion_payload(previous):
#     """
#     Create deletion payload using identifiers and purge flag

#     Args:
#         previous: Previous full JSON payload

#     Returns:
#         Minimal payload with identifiers and deletion marker
#     """
#     return {
#         "la_child_id": previous.get("la_child_id"),  # Unique child identifier
#         "mis_child_id": previous.get("mis_child_id"),  # MIS identifier
#         "purge": True  # Purge signal for deletion
#     }


# # ---- DIFF + JSON LOGIC ----
# # PEP 484 signature:
# # def recursive_diff(curr: Any, prev: Any) -> Any:
# @benchmark_section("recursive_diff()")  # Performance monitor
# def recursive_diff(curr, prev):
#     """
#     Compare nested structures, return dict of changed fields only

#     Args:
#         curr: Current structure (dict, list, or scalar)
#         prev: Previous structure (dict, list, or scalar)

#     Returns:
#         Dict or value representing structural differences
#     """
#     if isinstance(curr, dict) and isinstance(prev, dict):
#         diff = {}

#         for key in curr:
#             # Skip if key unchanged
#             if key not in prev or curr[key] != prev[key]:

#                 # Recurse into nested dicts
#                 if isinstance(curr[key], dict) and isinstance(prev.get(key), dict):
#                     nested = recursive_diff(curr[key], prev[key])
#                     if nested:
#                         diff[key] = nested  # Include only if changes present

#                 # Recurse into lists
#                 elif isinstance(curr[key], list) and isinstance(prev.get(key), list):
#                     if curr[key] != prev[key]:
#                         # Pass parent key to control 'purge' inclusion
#                         diff[key] = prune_unchanged_list(
#                             curr[key], prev[key], parent_key=key
#                         )

#                 # Handle scalars or mismatched types
#                 else:
#                     diff[key] = curr[key]

#         return diff  # Return dict of differences

#     # Return scalar diff, or empty if no change
#     return {} if curr == prev else curr




# # PEP 484 signature:
# # def prune_unchanged_list(curr_list: List[Dict[str, Any]], prev_list: List[Dict[str, Any]], parent_key: Optional[str] = None) -> List[Dict[str, Any]]:
# @benchmark_section("prune_unchanged_list()")  # Performance monitor
# def prune_unchanged_list(curr_list, prev_list, parent_key=None):
#     """
#     Compare lists of dicts, remove unchanged items

#     Args:
#         curr_list: Current list of records
#         prev_list: Previous list of records
#         parent_key: Optional block name to control 'purge' field

#     Returns:
#         List with changed or unmatched items only
#     """
#     result = []

#     for curr_item in curr_list:
#         matched_prev = None

#         # Detect ID key
#         id_key = next((k for k in curr_item if k.endswith("_id")), None)

#         if id_key:
#             # Find match in previous by ID
#             for prev_item in prev_list:
#                 if prev_item.get(id_key) == curr_item.get(id_key):
#                     matched_prev = prev_item
#                     break

#         if matched_prev:
#             # Diff current item against matched previous
#             item_diff = recursive_diff(curr_item, matched_prev)

#             # Always retain ID key
#             if id_key:
#                 item_diff[id_key] = curr_item[id_key]

#             if item_diff:
#                 # Set 'purge' flag only for allowed blocks
#                 if parent_key in ALLOWED_PURGE_BLOCKS:
#                     item_diff["purge"] = False
#                 result.append(item_diff)

#         else:
#             # Unmatched: treat as new item
#             result.append(curr_item)

#     return result


