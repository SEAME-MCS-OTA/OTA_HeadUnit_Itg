from app.ota_logic import download_with_retries

class Resp:
    def __init__(self, status):
        self.status_code = status
        self.response = self
    def __enter__(self):
        return self
    def __exit__(self, exc_type, exc, tb):
        return False
    def iter_content(self, chunk_size=1024):
        yield b""
    def raise_for_status(self):
        if self.status_code >= 400:
            raise Exception("http error")


def test_download_http_5xx(monkeypatch, tmp_path):
    def fake_get(url, stream, timeout):
        return Resp(503)
    monkeypatch.setattr("requests.get", fake_get)

    logs = []
    err, status = download_with_retries("http://x", tmp_path / "b.raucb", 2, 1, logs.append)
    assert err == "HTTP_5XX"
    assert status == 503
