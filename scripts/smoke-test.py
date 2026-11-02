#!/usr/bin/env python3
"""Functional check of a running site; creates two disposable lab accounts."""
import argparse
from http.cookiejar import CookieJar
import re
import secrets
import urllib.error
import urllib.parse
import urllib.request

p = argparse.ArgumentParser()
p.add_argument("base_url", help="Single server HTTP URL or Cloudflare HTTPS URL")
a = p.parse_args()
base = a.base_url.rstrip("/")


def client():
    return urllib.request.build_opener(urllib.request.HTTPCookieProcessor(CookieJar()))


def request(opener, path, data=None):
    payload = None if data is None else urllib.parse.urlencode(data).encode()
    try:
        with opener.open(base + path, data=payload, timeout=30) as r:
            return r.status, r.read().decode()
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode()


def token(page):
    return re.search(r'name="csrf" value="([a-f0-9]+)"', page).group(1)


password = secrets.token_hex(16)
suffix = secrets.token_hex(5)
marker = f"smoketest_{suffix} <script>alert(1)</script>"
alice, bob = client(), client()
for user, opener in (("alice", alice), ("bob", bob)):
    name = f"{user}_{suffix}"
    status, page = request(opener, "/register")
    assert status == 200, f"registration GET failed: {status}"
    status, page = request(opener, "/register", {"username": name, "password": password, "csrf": token(page)})
    assert status == 200 and "Account created" in page, "registration failed"
    status, page = request(opener, "/login", {"username": name, "password": password, "csrf": token(page)})
    assert status == 200 and "notebook" in page, "login failed"
print("PASS registration and login for two users")

status, page = request(alice, "/")
status, page = request(alice, "/notes", {"body": marker, "csrf": token(page)})
assert status == 200 and f"smoketest_{suffix}" in page, "record write/read failed"
assert "&lt;script&gt;" in page and marker not in page, "stored content was not escaped"
note_id = re.search(r'/notes/(\d+)/delete', page).group(1)
print("PASS persistent record write and HTML escaping")

status, page = request(bob, "/")
assert f"smoketest_{suffix}" not in page, "another user can read the note"
status, _ = request(bob, f"/notes/{note_id}/delete", {"csrf": token(page)})
status, page = request(alice, "/")
assert f"smoketest_{suffix}" in page, "another user deleted the note"
status, _ = request(alice, "/notes", {"body": "must not be saved"})
assert status == 400, "missing CSRF token was accepted"
print("PASS user isolation and CSRF rejection")

status, page = request(alice, "/logout", {"csrf": token(page)})
status, page = request(alice, "/login", {"username": f"alice_{suffix}", "password": password, "csrf": token(page)})
assert f"smoketest_{suffix}" in page, "record did not survive logout/login"
print("PASS persistence after logout and login")
print("All checks passed. Two disposable test accounts and one test note remain in the lab database.")
