from datetime import datetime
from flask_sqlalchemy import SQLAlchemy

db = SQLAlchemy()


class Item(db.Model):
    """One row = one inventory item, similar to what the Richmond
    system tracked: what it is, how many, where it lives, and when
    it was last touched."""

    id = db.Column(db.Integer, primary_key=True)
    name = db.Column(db.String(120), nullable=False)
    sku = db.Column(db.String(50), unique=True, nullable=False)
    category = db.Column(db.String(80))
    quantity = db.Column(db.Integer, nullable=False, default=0)
    location = db.Column(db.String(120))
    last_updated = db.Column(
        db.DateTime, default=datetime.utcnow, onupdate=datetime.utcnow
    )

    def __repr__(self):
        return f"<Item {self.sku} - {self.name}>"
