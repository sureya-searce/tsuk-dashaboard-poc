"""Thin GCS helper. Centralises auth + download semantics."""

from google.cloud import storage

_client: storage.Client | None = None


def _get_client() -> storage.Client:
    global _client
    if _client is None:
        _client = storage.Client()
    return _client


def download_bytes(bucket: str, object_name: str) -> bytes:
    blob = _get_client().bucket(bucket).blob(object_name)
    return blob.download_as_bytes()
