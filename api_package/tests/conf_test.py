import pytest

class FakeCursor:
    def __init__(self):
        self.commands = []
        self.data = []

    def execute(self, query, *params):
        self.commands.append((query, params))

    def fetchall(self):
        return self.data

@pytest.fixture
def mock_cursor():
    return FakeCursor()
