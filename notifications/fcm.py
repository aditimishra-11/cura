import json
import logging
import os

logger = logging.getLogger(__name__)

_firebase_app = None


def _get_app():
    global _firebase_app
    if _firebase_app:
        return _firebase_app

    import firebase_admin
    from firebase_admin import credentials

    creds_path = os.environ.get("FIREBASE_CREDENTIALS_PATH")
    creds_json = os.environ.get("FIREBASE_CREDENTIALS_JSON")

    if creds_json:
        cred = credentials.Certificate(json.loads(creds_json))
    elif creds_path:
        cred = credentials.Certificate(creds_path)
    else:
        raise RuntimeError("FIREBASE_CREDENTIALS_JSON or FIREBASE_CREDENTIALS_PATH must be set")

    _firebase_app = firebase_admin.initialize_app(cred)
    return _firebase_app


def send_reminder(fcm_token: str, title: str, body: str, item_id: str):
    from firebase_admin import messaging
    _get_app()

    message = messaging.Message(
        notification=messaging.Notification(title=title, body=body),
        data={"item_id": item_id, "type": "reminder"},
        android=messaging.AndroidConfig(
            priority="high",
            notification=messaging.AndroidNotification(
                channel_id="reminders",
                priority="high",
            ),
        ),
        token=fcm_token,
    )
    try:
        response = messaging.send(message)
        logger.info(f"FCM sent: {response}")
        return True
    except Exception as e:
        logger.error(f"FCM send failed for token {fcm_token[:20]}...: {e}")
        return False


def send_to_all_devices(title: str, body: str, item_id: str):
    import os
    from supabase import create_client
    supabase = create_client(os.environ["SUPABASE_URL"], os.environ["SUPABASE_KEY"])
    result = supabase.table("devices").select("fcm_token").execute()
    tokens = [r["fcm_token"] for r in (result.data or [])]
    for token in tokens:
        send_reminder(token, title, body, item_id)
