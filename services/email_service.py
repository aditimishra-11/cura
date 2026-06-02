"""
Email service for Cura — sends via Resend API (HTTP, works on Render free tier).

Required env vars:
    RESEND_API_KEY         — API key from resend.com
    RESEND_FROM            — sender address (must be verified in Resend dashboard)
                             e.g. "Cura <cura@yourdomain.com>"
                             For testing without a domain, use Resend's default:
                             "Cura <onboarding@resend.dev>"
    DIGEST_EMAIL_RECIPIENTS — comma-separated recipient emails
                              e.g. "mehmathur@gmail.com,gmataditi2023@gmail.com"
"""

from __future__ import annotations

import logging
import os

logger = logging.getLogger(__name__)


def get_recipients() -> list[str]:
    raw = os.environ.get("DIGEST_EMAIL_RECIPIENTS", "")
    return [e.strip() for e in raw.split(",") if e.strip()]


def send_email(subject: str, html_body: str, text_body: str = "") -> bool:
    """
    Send an HTML email to all DIGEST_EMAIL_RECIPIENTS via Resend.
    Returns True if at least one recipient received it successfully.
    """
    import resend

    api_key    = os.environ.get("RESEND_API_KEY")
    from_addr  = os.environ.get("RESEND_FROM", "Cura <onboarding@resend.dev>")
    recipients = get_recipients()

    if not api_key:
        logger.warning("Email not configured — set RESEND_API_KEY")
        return False

    if not recipients:
        logger.warning("No recipients — set DIGEST_EMAIL_RECIPIENTS")
        return False

    resend.api_key = api_key
    success = False

    for recipient in recipients:
        try:
            params = {
                "from":    from_addr,
                "to":      [recipient],
                "subject": subject,
                "html":    html_body,
            }
            if text_body:
                params["text"] = text_body

            resend.Emails.send(params)
            logger.info("Email sent to %s: %s", recipient, subject)
            success = True

        except Exception as e:
            logger.error("Email failed for %s: %s", recipient, e)

    return success
