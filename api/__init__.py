from fastapi import FastAPI
from .routes import router


def build_app() -> FastAPI:
    app = FastAPI(title="Personal Knowledge Assistant API")
    app.include_router(router)
    return app
