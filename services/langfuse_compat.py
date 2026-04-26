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

def _noop_observe(_func=None, **_kw):  # type: ignore
    if _func is not None:
        return _func
    def _d(f): return f
    return _d


if _keys_set:
    try:
        # langfuse 3.x / 4.x: observe moved to top-level; openai is a wrapped module
        from langfuse import observe          # type: ignore
        from langfuse.openai import openai as _lf_openai  # type: ignore
        OpenAI = _lf_openai.OpenAI           # type: ignore
        logger.info("Langfuse tracing enabled (v3+ API).")
    except Exception:
        try:
            # langfuse 2.x fallback
            from langfuse.openai import OpenAI   # type: ignore  # noqa: F811
            from langfuse.decorators import observe  # type: ignore  # noqa: F811
            logger.info("Langfuse tracing enabled (v2 API).")
        except Exception as exc:
            logger.warning("Langfuse import failed (%s); tracing disabled.", exc)
            from openai import OpenAI  # type: ignore  # noqa: F811
            observe = _noop_observe  # type: ignore
else:
    from openai import OpenAI  # type: ignore
    observe = _noop_observe  # type: ignore
    logger.info("LANGFUSE_PUBLIC_KEY not set — tracing disabled.")
