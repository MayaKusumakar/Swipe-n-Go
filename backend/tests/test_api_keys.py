import os

from services.api_keys import SECRET_NAME, load_anthropic_key


def fake_secret(value):
    calls = []

    def access(name):
        calls.append(name)
        if isinstance(value, Exception):
            raise value
        return value
    access.calls = calls
    return access


def on_app_engine(monkeypatch, key=None):
    monkeypatch.setenv("GAE_ENV", "standard")
    monkeypatch.setenv("GOOGLE_CLOUD_PROJECT", "test-project")
    if key is None:
        monkeypatch.delenv("ANTHROPIC_API_KEY", raising=False)
    else:
        monkeypatch.setenv("ANTHROPIC_API_KEY", key)


def test_loads_the_key_from_secret_manager_on_app_engine(monkeypatch):
    on_app_engine(monkeypatch)
    access = fake_secret("sk-ant-test\n")

    assert load_anthropic_key(access) is True
    assert access.calls == [f"projects/test-project/secrets/{SECRET_NAME}/versions/latest"]
    assert os.environ["ANTHROPIC_API_KEY"] == "sk-ant-test"


def test_no_secret_leaves_ai_off(monkeypatch):
    on_app_engine(monkeypatch)

    assert load_anthropic_key(fake_secret(LookupError("not found"))) is False
    assert "ANTHROPIC_API_KEY" not in os.environ


def test_does_nothing_locally_or_when_a_key_is_already_set(monkeypatch):
    monkeypatch.delenv("GAE_ENV", raising=False)
    monkeypatch.delenv("ANTHROPIC_API_KEY", raising=False)
    local = fake_secret("sk-ant-test")
    assert load_anthropic_key(local) is False
    assert local.calls == []

    on_app_engine(monkeypatch, key="sk-ant-from-env")
    already_set = fake_secret("sk-ant-test")
    assert load_anthropic_key(already_set) is False
    assert already_set.calls == []
