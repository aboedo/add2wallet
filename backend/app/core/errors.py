from __future__ import annotations

from dataclasses import dataclass


@dataclass
class ConversionError(Exception):
    code: str
    message: str
    status_code: int = 400


class UnauthorizedError(ConversionError):
    def __init__(self) -> None:
        super().__init__("unauthorized", "Invalid API key", 401)


class UnsupportedFileError(ConversionError):
    def __init__(self, message: str) -> None:
        super().__init__("unsupported_file", message, 400)


class FileTooLargeError(ConversionError):
    def __init__(self, max_bytes: int) -> None:
        super().__init__(
            "file_too_large",
            f"File size exceeds {max_bytes // (1024 * 1024)}MB limit",
            413,
        )


class ProcessingError(ConversionError):
    def __init__(self, message: str) -> None:
        super().__init__("processing_failed", message, 422)


class UpstreamServiceError(ConversionError):
    def __init__(self, message: str) -> None:
        super().__init__("upstream_unavailable", message, 503)


class PaymentRequiredError(ConversionError):
    def __init__(self, message: str = "Insufficient PASS balance") -> None:
        super().__init__("payment_required", message, 402)

