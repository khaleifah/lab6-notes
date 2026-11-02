"""Lab Notes: Flask authentication and per-user PostgreSQL records."""
import hmac
import os
import re
import secrets
from functools import wraps

import click
import psycopg
from flask import Flask, abort, flash, g, jsonify, redirect, render_template, request, session, url_for
from psycopg.rows import dict_row
from werkzeug.middleware.proxy_fix import ProxyFix
from werkzeug.security import check_password_hash, generate_password_hash


def create_app():
    app = Flask(__name__)
    app.config.update(
        SECRET_KEY=os.environ["SECRET_KEY"],
        SESSION_COOKIE_HTTPONLY=True,
        SESSION_COOKIE_SAMESITE="Lax",
        SESSION_COOKIE_SECURE=os.getenv("COOKIE_SECURE", "false").lower() == "true",
        MAX_CONTENT_LENGTH=32 * 1024,
    )
    # Only the local Nginx proxy can connect to the published app port.
    # It supplies one canonical X-Forwarded-Proto value. Host is preserved.
    app.wsgi_app = ProxyFix(app.wsgi_app, x_for=0, x_proto=1, x_host=0)
    instance = os.getenv("APP_INSTANCE", "web1")

    def db():
        if "db" not in g:
            g.db = psycopg.connect(os.environ["DATABASE_URL"], row_factory=dict_row, connect_timeout=3)
        return g.db

    @app.teardown_appcontext
    def close_db(_error):
        conn = g.pop("db", None)
        if conn is not None:
            conn.close()

    @app.cli.command("init-db")
    def init_db():
        """Run once before starting workers. Repeated calls preserve data."""
        with db() as conn:
            conn.execute("""CREATE TABLE IF NOT EXISTS users (
                id BIGSERIAL PRIMARY KEY, username VARCHAR(40) UNIQUE NOT NULL,
                password_hash TEXT NOT NULL)""")
            conn.execute("""CREATE TABLE IF NOT EXISTS notes (
                id BIGSERIAL PRIMARY KEY,
                user_id BIGINT NOT NULL REFERENCES users(id),
                body TEXT NOT NULL,
                created_at TIMESTAMPTZ NOT NULL DEFAULT now())""")
        click.echo("PostgreSQL schema is ready.")

    def csrf_token():
        if "csrf" not in session:
            session["csrf"] = secrets.token_hex(32)
        return session["csrf"]

    @app.context_processor
    def context():
        return {"csrf_token": csrf_token, "instance": instance}

    @app.before_request
    def csrf_check():
        if request.method == "POST":
            expected = session.get("csrf", "")
            actual = request.form.get("csrf", "")
            if not expected or not hmac.compare_digest(expected, actual):
                abort(400, "Form expired. Reload the page and try again.")

    @app.after_request
    def headers(response):
        response.headers["X-Served-By"] = instance
        response.headers["Cache-Control"] = "no-store"
        response.headers["X-Content-Type-Options"] = "nosniff"
        response.headers["Content-Security-Policy"] = (
            "default-src 'self'; style-src 'self' 'unsafe-inline'; "
            "frame-ancestors 'none'; form-action 'self'; base-uri 'none'"
        )
        return response

    def login_required(fn):
        @wraps(fn)
        def wrapped(*args, **kwargs):
            if "uid" not in session:
                return redirect(url_for("login"))
            return fn(*args, **kwargs)
        return wrapped

    @app.route("/register", methods=["GET", "POST"])
    def register():
        if request.method == "POST":
            username = request.form.get("username", "").strip().lower()
            password = request.form.get("password", "")
            if not re.fullmatch(r"[a-z0-9_]{3,40}", username) or not 10 <= len(password) <= 128:
                flash("Use a 3–40 character username (letters, numbers, underscore) and a 10–128 character password.")
            else:
                try:
                    with db() as conn:
                        conn.execute("INSERT INTO users (username,password_hash) VALUES (%s,%s)",
                                     (username, generate_password_hash(password)))
                except psycopg.errors.UniqueViolation:
                    flash("That username is already taken.")
                else:
                    flash("Account created. Sign in to save your first note.")
                    return redirect(url_for("login"))
        return render_template("auth.html", registering=True)

    @app.route("/login", methods=["GET", "POST"])
    def login():
        if request.method == "POST":
            user = db().execute("SELECT * FROM users WHERE username=%s",
                                (request.form.get("username", "").strip().lower(),)).fetchone()
            if user and check_password_hash(user["password_hash"], request.form.get("password", "")):
                session.clear()
                session.update(uid=user["id"], username=user["username"])
                return redirect(url_for("notes"))
            flash("Incorrect username or password.")
        return render_template("auth.html", registering=False)

    @app.get("/")
    @login_required
    def notes():
        records = db().execute("SELECT * FROM notes WHERE user_id=%s ORDER BY id DESC",
                               (session["uid"],)).fetchall()
        return render_template("notes.html", notes=records)

    @app.post("/notes")
    @login_required
    def add_note():
        body = request.form.get("body", "").strip()
        if not 1 <= len(body) <= 2000:
            abort(400, "Notes must contain 1–2000 characters.")
        with db() as conn:
            conn.execute("INSERT INTO notes (user_id,body) VALUES (%s,%s)", (session["uid"], body))
        return redirect(url_for("notes"))

    @app.post("/notes/<int:note_id>/delete")
    @login_required
    def delete_note(note_id):
        with db() as conn:
            # Ownership is enforced in SQL, even if a user changes the URL.
            conn.execute("DELETE FROM notes WHERE id=%s AND user_id=%s", (note_id, session["uid"]))
        return redirect(url_for("notes"))

    @app.post("/logout")
    def logout():
        session.clear()
        return redirect(url_for("login"))

    @app.get("/api/instance")
    def identity():
        return jsonify(instance=instance)

    @app.get("/health")
    def health():
        try:
            db().execute("SELECT 1")
        except psycopg.Error:
            return jsonify(status="unhealthy", instance=instance), 503
        return jsonify(status="ok", instance=instance)

    return app
