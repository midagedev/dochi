"""Dochi <-> Hermes Agent local bridge.

A small WebSocket gateway adapter that lets the Dochi macOS app act as the
voice + 3D-character front-end for a Nous Research Hermes Agent backend.

See README.md for the architecture and install instructions.
"""

from .protocol import PROTOCOL_VERSION

__all__ = ["PROTOCOL_VERSION"]
__version__ = "0.1.0"
