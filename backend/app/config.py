from pydantic_settings import BaseSettings


class Settings(BaseSettings):
    app_env: str = "dev"
    jwt_secret: str = "change_me_please"
    jwt_expire_minutes: int = 10080

    mysql_host: str = "mysql"
    mysql_port: int = 3306
    mysql_db: str = "family_navi"
    mysql_user: str = "family_navi"
    mysql_password: str = "family_navi_pass"

    @property
    def database_url(self) -> str:
        return (
            f"mysql+pymysql://{self.mysql_user}:{self.mysql_password}"
            f"@{self.mysql_host}:{self.mysql_port}/{self.mysql_db}"
        )

    class Config:
        env_prefix = ""


settings = Settings()
