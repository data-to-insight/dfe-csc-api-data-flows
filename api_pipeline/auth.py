import requests

from .config import CLIENT_ID, CLIENT_SECRET, SCOPE, TOKEN_ENDPOINT
from .utils import log_debug


def get_oauth_token():
    payload = {
        "client_id": CLIENT_ID,
        "client_secret": CLIENT_SECRET,
        "scope": SCOPE,
        "grant_type": "client_credentials"
    }

    try:
        response = requests.post(TOKEN_ENDPOINT, data=payload)
        response.raise_for_status()
        token = response.json()["access_token"]
        print("OAuth token retrieved.")
        
        log_debug(f"TOKEN (first 10 chars): {token[:10]}...")
        
        return token
    except Exception as e:
        print(f"OAuth Token Error: {e}")
        return None
