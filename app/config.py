import os


def _get_db_password_from_ssm(project_name: str) -> str:
    """Fetches the database password from AWS SSM Parameter Store using
    the EC2 instance's IAM role - no access key, no secret file, no
    manual copying. boto3 automatically finds credentials via the
    instance's attached role (the same role that also grants exactly
    ssm:GetParameter on this one parameter and nothing else)."""
    import boto3

    region = os.environ.get("AWS_REGION", "us-east-1")
    ssm = boto3.client("ssm", region_name=region)
    response = ssm.get_parameter(
        Name=f"/{project_name}/db_password", WithDecryption=True
    )
    return response["Parameter"]["Value"]


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

    return f"postgresql+psycopg2://{db_user}:{password}@{db_host}/{db_name}"


class Config:
    SQLALCHEMY_DATABASE_URI = _build_database_uri()
    SQLALCHEMY_TRACK_MODIFICATIONS = False
    SECRET_KEY = os.environ.get("SECRET_KEY", "dev-only-not-for-production")
