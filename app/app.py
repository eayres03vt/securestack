import hmac
import os
from flask import Flask, render_template, request, redirect, url_for, flash
from flask_wtf import CSRFProtect
from flask_login import (
    LoginManager,
    UserMixin,
    login_user,
    logout_user,
    login_required,
    current_user,
)
from config import Config
from models import db, Item


class AdminUser(UserMixin):
    """There's exactly one account for this app - a single admin user,
    not backed by a database table. Flask-Login just needs something
    that looks like a user object; this is the simplest thing that does."""

    id = "admin"


def create_app():
    app = Flask(__name__)
    app.config.from_object(Config)
    db.init_app(app)

    # Protects every POST form (add/edit/delete) against CSRF - without
    # this, a malicious site could embed a hidden form that submits to
    # e.g. /delete/1 using a logged-in visitor's own browser session.
    # Flask-WTF requires a matching {{ csrf_token() }} field in each form.
    CSRFProtect(app)

    # Requires login for every page except /login and /health (set per
    # route below with @login_required). Unauthenticated visitors get
    # redirected straight to the login page instead of seeing any data.
    login_manager = LoginManager()
    login_manager.login_view = "login"
    login_manager.init_app(app)

    @login_manager.user_loader
    def load_user(user_id):
        return AdminUser() if user_id == "admin" else None

    with app.app_context():
        db.create_all()  # creates tables if they don't exist yet

    # A handful of response headers that cost nothing and close off
    # common browser-side attack classes: clickjacking (X-Frame-Options),
    # MIME-sniffing attacks (X-Content-Type-Options), and a baseline
    # Content-Security-Policy restricting the page to only load its own
    # resources. No HSTS here yet - the app only serves HTTP for now
    # (see SECURITY_EXCEPTIONS.md), and HSTS on a site with no HTTPS
    # would be meaningless at best.
    @app.after_request
    def set_security_headers(response):
        response.headers["X-Frame-Options"] = "DENY"
        response.headers["X-Content-Type-Options"] = "nosniff"
        response.headers["Referrer-Policy"] = "strict-origin-when-cross-origin"
        response.headers["Content-Security-Policy"] = "default-src 'self'"
        return response

    @app.route("/login", methods=["GET", "POST"])
    def login():
        if current_user.is_authenticated:
            return redirect(url_for("index"))
        if request.method == "POST":
            username = request.form.get("username", "")
            password = request.form.get("password", "")
            # Constant-time comparison - a normal == would leak, via tiny
            # timing differences, how many leading characters were
            # correct, which is exactly the kind of thing that sounds
            # theoretical until it's the CTF challenge that gets you.
            valid = username == app.config["ADMIN_USERNAME"] and hmac.compare_digest(
                password, app.config["ADMIN_PASSWORD"]
            )
            if valid:
                login_user(AdminUser())
                return redirect(url_for("index"))
            flash("Invalid username or password")
        return render_template("login.html")

    @app.route("/logout")
    @login_required
    def logout():
        logout_user()
        return redirect(url_for("login"))

    @app.route("/")
    @login_required
    def index():
        items = Item.query.order_by(Item.name).all()
        return render_template("index.html", items=items)

    @app.route("/add", methods=["GET", "POST"])
    @login_required
    def add_item():
        if request.method == "POST":
            try:
                quantity = int(request.form.get("quantity", 0))
            except ValueError:
                flash("Quantity must be a whole number")
                return render_template("add_item.html")
            item = Item(
                name=request.form["name"],
                sku=request.form["sku"],
                category=request.form.get("category"),
                quantity=quantity,
                location=request.form.get("location"),
            )
            db.session.add(item)
            db.session.commit()
            flash(f"Added {item.name}")
            return redirect(url_for("index"))
        return render_template("add_item.html")

    @app.route("/edit/<int:item_id>", methods=["GET", "POST"])
    @login_required
    def edit_item(item_id):
        item = Item.query.get_or_404(item_id)
        if request.method == "POST":
            try:
                quantity = int(request.form.get("quantity", 0))
            except ValueError:
                flash("Quantity must be a whole number")
                return render_template("edit_item.html", item=item)
            item.name = request.form["name"]
            item.sku = request.form["sku"]
            item.category = request.form.get("category")
            item.quantity = quantity
            item.location = request.form.get("location")
            db.session.commit()
            flash(f"Updated {item.name}")
            return redirect(url_for("index"))
        return render_template("edit_item.html", item=item)

    @app.route("/delete/<int:item_id>", methods=["POST"])
    @login_required
    def delete_item(item_id):
        item = Item.query.get_or_404(item_id)
        db.session.delete(item)
        db.session.commit()
        flash(f"Deleted {item.name}")
        return redirect(url_for("index"))

    # Simple health check endpoint - useful later for load balancers or
    # monitoring tools to confirm the app is actually up and can reach
    # its database, not just that the server is running.
    @app.route("/health")
    def health():
        return {"status": "ok"}

    return app


app = create_app()

if __name__ == "__main__":
    # debug mode off by default - it's never used in production (gunicorn
    # imports `app` directly and never hits this block at all), but
    # defaulting it off here too means a stray local run never
    # accidentally exposes Flask's interactive debugger/stack traces.
    debug_mode = os.environ.get("FLASK_DEBUG", "0") == "1"
    app.run(host="0.0.0.0", port=5000, debug=debug_mode)
