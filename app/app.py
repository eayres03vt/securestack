from flask import Flask, render_template, request, redirect, url_for, flash
from config import Config
from models import db, Item


def create_app():
    app = Flask(__name__)
    app.config.from_object(Config)
    db.init_app(app)

    with app.app_context():
        db.create_all()  # creates tables if they don't exist yet

    @app.route("/")
    def index():
        items = Item.query.order_by(Item.name).all()
        return render_template("index.html", items=items)

    @app.route("/add", methods=["GET", "POST"])
    def add_item():
        if request.method == "POST":
            item = Item(
                name=request.form["name"],
                sku=request.form["sku"],
                category=request.form.get("category"),
                quantity=int(request.form.get("quantity", 0)),
                location=request.form.get("location"),
            )
            db.session.add(item)
            db.session.commit()
            flash(f"Added {item.name}")
            return redirect(url_for("index"))
        return render_template("add_item.html")

    @app.route("/edit/<int:item_id>", methods=["GET", "POST"])
    def edit_item(item_id):
        item = Item.query.get_or_404(item_id)
        if request.method == "POST":
            item.name = request.form["name"]
            item.sku = request.form["sku"]
            item.category = request.form.get("category")
            item.quantity = int(request.form.get("quantity", 0))
            item.location = request.form.get("location")
            db.session.commit()
            flash(f"Updated {item.name}")
            return redirect(url_for("index"))
        return render_template("edit_item.html", item=item)

    @app.route("/delete/<int:item_id>", methods=["POST"])
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
    app.run(host="0.0.0.0", port=5000, debug=True)
