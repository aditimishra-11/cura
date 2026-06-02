"""
Email service for Cura — sends via Gmail SMTP.

Required env vars:
    GMAIL_USER         — sender Gmail address (e.g. cura.assistant@gmail.com)
    GMAIL_APP_PASSWORD — Gmail app password (not your account password)
                         Generate at: myaccount.google.com/apppasswords
    DIGEST_EMAIL_RECIPIENTS — comma-separated list of recipient emails
                               e.g. "mehmathur@gmail.com,gmataditi2023@gmail.com"
"""

from __future__ import annotations

import logging
import os
import smtplib
from email.mime.multipart import MIMEMultipart
from email.mime.text import MIMEText

logger = logging.getLogger(__name__)


def get_recipients() -> list[str]:
    raw = os.environ.get("DIGEST_EMAIL_RECIPIENTS", "")
    return [e.strip() for e in raw.split(",") if e.strip()]


def send_email(subject: str, html_body: str, text_body: str = "") -> bool:
    """
    Send an HTML email to all DIGEST_EMAIL_RECIPIENTS.
    Returns True if at least one recipient received it successfully.
    """
    gmail_user     = os.environ.get("GMAIL_USER")
    gmail_password = os.environ.get("GMAIL_APP_PASSWORD")
    recipients     = get_recipients()

    if not gmail_user or not gmail_password:
        logger.warning("Email not configured — set GMAIL_USER and GMAIL_APP_PASSWORD")
        return False

    if not recipients:
        logger.warning("No recipients — set DIGEST_EMAIL_RECIPIENTS")
        return False

    success = False
    for recipient in recipients:
        try:
            msg = MIMEMultipart("alternative")
            msg["Subject"] = subject
            msg["From"]    = f"Cura <{gmail_user}>"
            msg["To"]      = recipient

            if text_body:
                msg.attach(MIMEText(text_body, "plain"))
            msg.attach(MIMEText(html_body, "html"))

            with smtplib.SMTP_SSL("smtp.gmail.com", 465) as server:
                server.login(gmail_user, gmail_password)
                server.sendmail(gmail_user, recipient, msg.as_string())

            logger.info("Email sent to %s: %s", recipient, subject)
            success = True

        except Exception as e:
            logger.error("Email failed for %s: %s", recipient, e)

    return success
