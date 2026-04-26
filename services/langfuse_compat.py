"""
Langfuse compatibility shim.

If LANGFUSE_PUBLIC_KEY and LANGFUSE_SECRET_KEY are set, use the langfuse-
instrumented OpenAI client and @observe decorator for full tracing.
Otherwise fall back to the plain openai client and a no-op decorator so
the app starts cleanly without Langfuse configured.
"""
from __future__ import annotations

import os
import logging

logger = logging.getLogger(__name__)

_langfuse_enabled = bool(
    os.environ.get("LANGFUSE_PUBLIC_KEY") and os.environ.get("LANGFUSE_SECRET_KEY")
)

if _langfuse_enabled:
    try:
        from langfuse.openai import OpenAI  # type: ignore
        from langfuse.decorators import observe  # type: ignore
        logger.info("Langfuse tracing enabled.")
    except Exception as exc:
        logger.warning("Langfuse import failed (%s); falling back to plain OpenAI.", exc)
        from openai import OpenAI  # type: ignore  # noqa: F811
        _langfuse_enabled = False

        def observe(_func=None, **_kwargs):  # type: ignore
            if _func is not None:
                return _func
            def _decorator(f):
                return f
            return _decorator
else:
    from openai import OpenAI  # type: ignore
    logger.info("Langfuse keys not set — tracing disabled, using plain OpenAI.")

    def observe(_func=None, **_kwargs):  # type: ignore
        if _func is not None:
            return _func
        def _decorator(f):
            return f
        return _decorator
