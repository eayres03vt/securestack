import os


def _get_ssm_parameter(project_name: str, param_name: str) -> str:
    """Fetches one SecureString parameter from SSM Parameter Store using
    the EC2 instance's IAM role - no access key, no secret file, no
    manual copying. boto3 automatically finds credentials via the
    instance's attached role (the same role that grants exactly
    ssm:GetParameter on these specific parameters and nothing else)."""
    import boto3

    region = os.environ.get("AWS_REGION", "us-east-1")
    ssm = boto3.client("ssm", region_name=region)
    response = ssm.get_parameter(
        Name=f"/{project_name}/{param_name}", WithDecryption=True
    )
    return response["Parameter"]["Value"]


def _get_db_password_from_ssm(project_name: str) -> str:
    return _get_ssm_parameter(project_name, "db_password")


def _get_secret_key() -> str:
    """SECRET_KEY signs session cookies and CSRF tokens. Locally (no
    DB_HOST set) it falls back to a fixed dev value - fine, since a
    laptop's SQLite dev session isn't a real security boundary. On the
    real deployment it's always fetched from SSM instead, so the app
    never signs anything in production with a value anyone could read
    in this public repo."""
    if not os.environ.get("DB_HOST"):
        return "dev-only-not-for-production"
    project_name = os.environ.get("PROJECT_NAME", "securestack")
    return _get_ssm_parameter(project_name, "flask_secret_key")


def _get_admin_password() -> str:
    """The one admin login's password. Same locally-fake / SSM-in-prod
    split as the secret key above - locally you can log in with
    admin/admin, in production it's the random value Terraform
    generated into SSM."""
    if not os.environ.get("DB_HOST"):
        return "admin"
    project_name = os.environ.get("PROJECT_NAME", "securestack")
    return _get_ssm_parameter(project_name, "admin_password")


def _build_database_uri() -> str:
    db_host = os.environ.get("DB_HOST")

    # DB_HOST only gets set on the real EC2 deployment (via the systemd
    # service file). If it's not set, we're running locally on a laptop,
    # so fall back to a local SQLite file - no AWS access needed at all
    # for local development.
    if not db_host:
        return "sqlite:///inventory.db"

    db_name = os.environ.get("DB_NAME", "securestack")
    db_user = os.environ.get("DB_USER", "dbadmin")
    project_name = os.environ.get("PROJECT_NAME", "securestack")
    password = _get_db_password_from_ssm(project_name)

    # sslmode=require matches the rds.force_ssl=1 setting on the database
    # side - the connection is encrypted in transit, not just at rest.
    return f"postgresql+psycopg2://{db_user}:{password}@{db_host}/{db_name}?sslmode=require"


class Config:
    SQLALCHEMY_DATABASE_URI = _build_database_uri()
    SQLALCHEMY_TRACK_MODIFICATIONS = False
    SECRET_KEY = _get_secret_key()
    ADMIN_USERNAME = "admin"
    ADMIN_PASSWORD = _get_admin_password()

    # Cookie hardening that doesn't require HTTPS to be worth doing:
    # HTTPONLY keeps JavaScript from ever reading the session cookie
    # (blocks cookie theft via XSS), SAMESITE=Lax stops the browser
    # from attaching the cookie to most cross-site requests (defense
    # in depth alongside the CSRF tokens already added). SESSION_COOKIE_
    # SECURE stays off for now since the app only serves HTTP - turning
    # it on today would mean the browser refuses to send the cookie at
    # all. Revisit once there's a domain + HTTPS in front of the ALB.
    SESSION_COOKIE_HTTPONLY = True
    SESSION_COOKIE_SAMESITE = "Lax"
