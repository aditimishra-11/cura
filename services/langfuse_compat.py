"""
Langfuse compatibility shim.

Tries langfuse 2.x API (langfuse.decorators + langfuse.openai) first.
Falls back to plain openai + no-op @observe if langfuse isn't installed,
keys aren't set, or the import fails for any reason.
"""
from __future__ import annotations

import os
import logging

logger = logging.getLogger(__name__)

_keys_set = bool(
    os.environ.get("LANGFUSE_PUBLIC_KEY") and os.environ.get("LANGFUSE_SECRET_KEY")
)

if _keys_set:
    try:
        from langfuse.openai import OpenAI   # type: ignore
        from langfuse.decorators import observe  # type: ignore
        logger.info("Langfuse tracing enabled (langfuse.decorators API).")
    except Exception as exc:
        logger.warning("Langfuse import failed (%s); tracing disabled.", exc)
        from openai import OpenAI  # type: ignore  # noqa: F811

        def observe(_func=None, **_kw):  # type: ignore
            if _func is not None:
                return _func
            def _d(f): return f
            return _d
else:
    from openai import OpenAI  # type: ignore
    logger.info("LANGFUSE_PUBLIC_KEY not set — tracing disabled.")

    def observe(_func=None, **_kw):  # type: ignore
        if _func is not None:
            return _func
        def _d(f): return f
        return _d
