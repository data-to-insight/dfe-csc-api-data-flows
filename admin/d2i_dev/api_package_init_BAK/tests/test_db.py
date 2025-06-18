from api_package.payloads import update_api_failure

def test_update_api_failure_records_sql(mock_cursor):
    update_api_failure(mock_cursor, "child_001", "error message")
    assert len(mock_cursor.commands) == 1
    query, params = mock_cursor.commands[0]
    assert "UPDATE" in query
    assert params[1] == "child_001"
