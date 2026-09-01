# Author: @CharlesPhan66 (Charrles Phan)
# This file is to define fixtures for pytest, which are reusable components that can be used across multiple test cases.
# Fixtures is a way to provide a fixed baseline upon which tests can reliably and repeatedly execute. They help to reduce code duplication and improve test maintainability.
# Let's say we need to use separate object of UserManager for each test case, we can define a fixture for it and use it in multiple test cases.
# Acknowldegement:
# - https://youtu.be/EgpLj86ZHFQ?t=767&si=xturFnwdORqB_E-S
# - From the official pytest documentation: https://docs.pytest.org/en/7.4.x/fixture.html
import pytest

# This fixture provides a Django APIClient that can be used to simulate HTTP requests to the application
# It allows us to test our views and APIs without running a live server
# Is is equivalent to (context: you are writing a test function and you want to use the APIClient):
# def test_api():
# client = APIClient()
# response = client.get('/api/products/')
# now you just need to use the fixture in your test function like this:
# def test_api(api):
# response = api.get('/api/products/')
# db is used as parameter meaning that this fixture requires access to the test database
# And db is a built-in fixture provided by pytest-django that sets up a test database for the duration of the test run.
# Therefore we don't have to touch the real database
# Note: api depends on db here
# fixture placed in conftest.py cuz it's used across multiple test files, so we don't have to define it in each test file
# Sorry to have such a long comment, but I want to make the team to understand the purpose of this fixture and how it works in case you are in charged of other tasks and still want to understand the test code
@pytest.fixture
def api(db):
    """DRF client; fixture `db` grant access to the test database."""
    from rest_framework.test import APIClient
    return APIClient()
