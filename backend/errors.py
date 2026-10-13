"""Domain errors returned by the conversion engine."""


class ConversionError(Exception):
    """A predictable error that can be safely presented to a client."""

    def __init__(self, code: str, message: str) -> None:
        super().__init__(message)
        self.code = code
        self.message = message


class ValidationError(ConversionError):
    """The conversion request or one of its paths is invalid."""

