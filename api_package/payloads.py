
import json
from api_package.db import update_api_failure
from .config import REQUIRED_FIELDS, ALLOWED_PURGE_BLOCKS




def recursive_diff(curr, prev):
    """
    Compare nested structures, return dict of changed fields only.

    Args:
        curr: Current structure (dict, list, or scalar).
        prev: Previous structure (dict, list, or scalar).

    Returns:
        Dict or value representing structural differences.
    """
    if isinstance(curr, dict) and isinstance(prev, dict):
        diff = {}
        for key in curr:
            if key not in prev or curr[key] != prev[key]:
                if isinstance(curr[key], dict) and isinstance(prev.get(key), dict):
                    nested = recursive_diff(curr[key], prev[key])
                    if nested:
                        diff[key] = nested
                elif isinstance(curr[key], list) and isinstance(prev.get(key), list):
                    if curr[key] != prev[key]:
                        diff[key] = prune_unchanged_list(curr[key], prev[key], parent_key=key)
                else:
                    diff[key] = curr[key]
        return diff
    return {} if curr == prev else curr


def prune_unchanged_list(curr_list, prev_list, parent_key=None):
    """
    Compare lists of dicts, remove unchanged items.

    Args:
        curr_list: Current list of records.
        prev_list: Previous list of records.
        parent_key: Optional block name to control 'purge' field.

    Returns:
        List with changed or unmatched items only.
    """
    result = []
    for curr_item in curr_list:
        matched_prev = None
        id_key = next((k for k in curr_item if k.endswith("_id")), None)
        if id_key:
            for prev_item in prev_list:
                if prev_item.get(id_key) == curr_item.get(id_key):
                    matched_prev = prev_item
                    break
        if matched_prev:
            item_diff = recursive_diff(curr_item, matched_prev)
            if id_key:
                item_diff[id_key] = curr_item[id_key]
            if item_diff:
                if parent_key in ALLOWED_PURGE_BLOCKS:
                    item_diff["purge"] = False
                result.append(item_diff)
        else:
            result.append(curr_item)
    return result


def generate_partial_payload(current, previous):
    """
    Create partial payload with required and changed fields.

    Args:
        current: Current full JSON payload.
        previous: Previous full JSON payload.

    Returns:
        Partial payload with required identifiers and detected changes.
    """
    partial = {k: current[k] for k in REQUIRED_FIELDS if k in current}
    diff = recursive_diff(current, previous)
    for k, v in diff.items():
        if k not in partial:
            partial[k] = v
    return partial


def generate_deletion_payload(previous):
    """
    Create deletion payload using identifiers and purge flag.

    Args:
        previous: Previous full JSON payload.

    Returns:
        Minimal payload with identifiers and deletion marker.
    """
    return {
        "la_child_id": previous.get("la_child_id"),
        "mis_child_id": previous.get("mis_child_id"),
        "purge": True
    }
