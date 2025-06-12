import json
import pytest
from unittest.mock import MagicMock
from api_package.update import update_partial_payloads

@pytest.fixture
def mock_conn_and_cursor():
    cursor = MagicMock()
    conn = MagicMock()
    conn.cursor.return_value = cursor

    sample_json = {
        "la_child_id": "Child1234",
        "mis_child_id": "Supplier-Child-1234",
        "child_details": {
            "unique_pupil_number": "ABC0123456789",
            "former_unique_pupil_number": "DEF0123456789",
            "unique_pupil_number_unknown_reason": "UN1",
            "first_name": "John",
            "surname": "Doe",
            "date_of_birth": "2022-06-14",
            "expected_date_of_birth": "2022-06-14",
            "sex": "M",
            "ethnicity": "WBRI",
            "disabilities": ["HAND", "VIS"],
            "postcode": "AB12 3DE",
            "uasc_flag": True,
            "uasc_end_date": "2022-06-14",
            "purge": False
        },
        "health_and_wellbeing": {
            "sdq_assessments": [{"date": "2022-06-14", "score": 20}],
            "purge": False
        },
        "social_care_episodes": [{
            "social_care_episode_id": "ABC123456",
            "referral_date": "2022-06-14",
            "referral_source": "1C",
            "referral_no_further_action_flag": False,
            "care_worker_details": [
                {"worker_id": "ABC456", "start_date": "2025-03-10"},
                {"worker_id": "ABC123", "start_date": "2022-06-14", "end_date": "2023-06-11"}
            ],
            "child_and_family_assessments": [{
                "child_and_family_assessment_id": "ABC123456",
                "start_date": "2022-06-14",
                "authorisation_date": "2022-06-14",
                "factors": ["1C", "4A"],
                "purge": False
            }],
            "child_in_need_plans": [{
                "child_in_need_plan_id": "ABC123456",
                "start_date": "2022-06-14",
                "end_date": "2022-06-14",
                "purge": False
            }],
            "section_47_assessments": [{
                "section_47_assessment_id": "ABC123456",
                "start_date": "2022-06-14",
                "icpc_required_flag": True,
                "icpc_date": "2022-06-14",
                "end_date": "2022-06-14",
                "purge": False
            }],
            "child_protection_plans": [
                {"child_protection_plan_id": "CBA654321", "start_date": "2025-01-01", "end_date": "2025-04-14", "purge": False},
                {"child_protection_plan_id": "ABC123456", "start_date": "2021-06-01", "end_date": "2022-06-02", "purge": False}
            ],
            "child_looked_after_placements": [{
                "child_looked_after_placement_id": "ABC123456",
                "start_date": "2022-06-14",
                "start_reason": "S",
                "placement_type": "K1",
                "postcode": "AB12 3DE",
                "end_date": "2022-06-14",
                "end_reason": "E3",
                "change_reason": "CHILD",
                "purge": False
            }],
            "adoption": {
                "initial_decision_date": "2022-06-14",
                "matched_date": "2022-06-14",
                "placed_date": "2022-06-14",
                "purge": False
            },
            "care_leavers": {
                "contact_date": "2022-06-14",
                "activity": "F2",
                "accommodation": "D",
                "purge": False
            },
            "closure_date": "2022-06-14",
            "closure_reason": "RC7",
            "purge": False
        }],
        "purge": False
    }

    cursor.fetchall.return_value = [
        ("Child1234", "updated", json.dumps(sample_json), json.dumps({**sample_json, "child_details": {**sample_json["child_details"], "first_name": "Jack"}})),
        ("Child1234", "deleted", json.dumps(sample_json), json.dumps(sample_json))
    ]

    return conn, cursor

def test_update_partial_payloads_executes_updates(mock_conn_and_cursor):
    conn, cursor = mock_conn_and_cursor
    update_partial_payloads(conn)

    assert cursor.execute.call_count == 3  # 1 SELECT + 2 UPDATE
    assert conn.commit.called


def test_update_partial_payloads_with_malformed_json(mock_conn_and_cursor):
    conn, cursor = mock_conn_and_cursor
    # Simulate a malformed current JSON string
    cursor.fetchall.return_value = [
        ("ChildMalformed", "updated", "{invalid_json", json.dumps({"la_child_id": "ChildMalformed"}))
    ]

    update_partial_payloads(conn)

    # Still attempts SELECT but no valid update
    assert cursor.execute.call_count == 1  # Just the SELECT
    assert conn.commit.called is False


def test_update_partial_payloads_with_empty_payload(mock_conn_and_cursor):
    conn, cursor = mock_conn_and_cursor
    cursor.fetchall.return_value = [
        ("Empty123", "updated", "{}", "{}")
    ]

    update_partial_payloads(conn)

    # Should skip update since nothing changed
    assert cursor.execute.call_count == 1  # Only SELECT
    assert conn.commit.called is False



def test_partial_json_payload_content(mock_conn_and_cursor):
    conn, cursor = mock_conn_and_cursor

    base_json = {
        "la_child_id": "ChildX",
        "mis_child_id": "MISX",
        "child_details": {"first_name": "Alice", "purge": False}
    }

    modified_json = {
        "la_child_id": "ChildX",
        "mis_child_id": "MISX",
        "child_details": {"first_name": "Bob", "purge": False}
    }

    cursor.fetchall.return_value = [
        ("ChildX", "updated", json.dumps(modified_json), json.dumps(base_json))
    ]

    update_partial_payloads(conn)

    update_calls = [call for call in cursor.execute.call_args_list if "UPDATE" in call.args[0]]
    assert len(update_calls) == 1

    update_sql, params = update_calls[0].args
    updated_payload = json.loads(params[0])

    assert updated_payload["la_child_id"] == "ChildX"
    assert updated_payload["child_details"]["first_name"] == "Bob"



def test_partial_json_payload_structure(mock_conn_and_cursor):
    conn, cursor = mock_conn_and_cursor

    original = {
        "la_child_id": "ChildX",
        "mis_child_id": "MISX",
        "child_details": {"first_name": "Alice", "purge": False},
        "health_and_wellbeing": {"sdq_assessments": [{"date": "2022-01-01", "score": 20}], "purge": False}
    }

    modified = {
        "la_child_id": "ChildX",
        "mis_child_id": "MISX",
        "child_details": {"first_name": "Bob", "purge": False},
        "health_and_wellbeing": {"sdq_assessments": [{"date": "2022-01-01", "score": 30}], "purge": False}
    }

    cursor.fetchall.return_value = [("ChildX", "updated", json.dumps(modified), json.dumps(original))]

    update_partial_payloads(conn)

    update_calls = [call for call in cursor.execute.call_args_list if "UPDATE" in call.args[0]]
    assert len(update_calls) == 1

    _, params = update_calls[0].args
    payload = json.loads(params[0])

    assert "la_child_id" in payload
    assert "mis_child_id" in payload
    assert "child_details" in payload
    assert "health_and_wellbeing" in payload
    assert payload["child_details"]["first_name"] == "Bob"
    assert payload["health_and_wellbeing"]["sdq_assessments"][0]["score"] == 30



def test_payload_only_purge_change(mock_conn_and_cursor):
    conn, cursor = mock_conn_and_cursor

    original = {
        "la_child_id": "ChildY",
        "mis_child_id": "MISY",
        "child_details": {"first_name": "Jill", "purge": False}
    }

    modified = {
        "la_child_id": "ChildY",
        "mis_child_id": "MISY",
        "child_details": {"first_name": "Jill", "purge": True}
    }

    cursor.fetchall.return_value = [("ChildY", "updated", json.dumps(modified), json.dumps(original))]

    update_partial_payloads(conn)

    update_calls = [call for call in cursor.execute.call_args_list if "UPDATE" in call.args[0]]
    assert len(update_calls) == 1

    _, params = update_calls[0].args
    payload = json.loads(params[0])
    assert payload["child_details"]["purge"] is True




def test_empty_payload_skipped(mock_conn_and_cursor):
    conn, cursor = mock_conn_and_cursor
    cursor.fetchall.return_value = [("ChildZ", "updated", "{}", "{}")]

    update_partial_payloads(conn)

    update_calls = [call for call in cursor.execute.call_args_list if "UPDATE" in call.args[0]]
    assert len(update_calls) == 0
