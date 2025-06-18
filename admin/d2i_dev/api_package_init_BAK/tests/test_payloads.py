import pytest
from api_package.payloads import recursive_diff, generate_partial_payload

def test_recursive_diff_basic_dict():
    curr = {"a": 1, "b": {"x": 2}}
    prev = {"a": 1, "b": {"x": 1}}
    diff = recursive_diff(curr, prev)
    assert diff == {"b": {"x": 2}}

def test_generate_partial_payload_required_only():
    curr = {
        "la_child_id": "abc", "mis_child_id": "xyz", "child_details": {},
        "extra": "something"
    }
    prev = {
        "la_child_id": "abc", "mis_child_id": "xyz", "child_details": {},
        "extra": "something"
    }
    result = generate_partial_payload(curr, prev)
    assert "extra" not in result
    assert set(result.keys()) == {"la_child_id", "mis_child_id", "child_details"}
