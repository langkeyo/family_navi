from datetime import datetime
import logging
import time
import uuid

from fastapi import Depends, FastAPI, HTTPException, Request, status
from fastapi.exceptions import RequestValidationError
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from fastapi.security import OAuth2PasswordRequestForm
from sqlalchemy.orm import Session

from .auth import create_access_token, get_current_user, hash_password, verify_password
from .config import settings
from .db import Base, engine, get_db
from .models import Marker, MarkerShare, User
from .schemas import (
    MarkerCreate,
    MarkerOut,
    MarkerShareCreate,
    MarkerUpdate,
    TokenOut,
    UserCreate,
    UserOut,
)

app = FastAPI(title="Family Navi API")
logger = logging.getLogger("family_navi_api")
logging.basicConfig(level=logging.INFO)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.on_event("startup")
def on_startup() -> None:
    Base.metadata.create_all(bind=engine)


def ok_response(data=None, message: str = "ok", code: str = "OK"):
    return {"code": code, "message": message, "data": data}


def error_code_from_status(status_code: int) -> str:
    mapping = {
        400: "BAD_REQUEST",
        401: "UNAUTHORIZED",
        403: "FORBIDDEN",
        404: "NOT_FOUND",
        409: "CONFLICT",
        422: "VALIDATION_ERROR",
    }
    return mapping.get(status_code, "INTERNAL_ERROR")


def marker_to_dict(marker: Marker, owner_username: str, can_edit: bool, can_delete: bool):
    base = MarkerOut.model_validate(marker).model_dump()
    base["owner_username"] = owner_username
    base["can_edit"] = can_edit
    base["can_delete"] = can_delete
    return base


@app.middleware("http")
async def request_logging_middleware(request: Request, call_next):
    request_id = request.headers.get("X-Request-Id", str(uuid.uuid4()))
    start = time.perf_counter()
    response = await call_next(request)
    duration_ms = (time.perf_counter() - start) * 1000
    response.headers["X-Request-Id"] = request_id
    response.headers["X-Process-Time-Ms"] = f"{duration_ms:.2f}"
    logger.info(
        "request_id=%s method=%s path=%s status=%s duration_ms=%.2f",
        request_id,
        request.method,
        request.url.path,
        response.status_code,
        duration_ms,
    )
    return response


@app.exception_handler(HTTPException)
async def http_exception_handler(request: Request, exc: HTTPException):
    detail = exc.detail
    message = detail.get("message") if isinstance(detail, dict) else str(detail)
    code = (
        detail.get("code")
        if isinstance(detail, dict) and isinstance(detail.get("code"), str)
        else error_code_from_status(exc.status_code)
    )
    return JSONResponse(
        status_code=exc.status_code,
        content=ok_response(data=None, message=message, code=code),
    )


@app.exception_handler(RequestValidationError)
async def validation_exception_handler(request: Request, exc: RequestValidationError):
    return JSONResponse(
        status_code=422,
        content=ok_response(
            data=exc.errors(),
            message="请求参数不合法",
            code="VALIDATION_ERROR",
        ),
    )


@app.exception_handler(Exception)
async def unhandled_exception_handler(request: Request, exc: Exception):
    logger.exception("unhandled_exception path=%s", request.url.path)
    return JSONResponse(
        status_code=500,
        content=ok_response(data=None, message="服务器内部错误", code="INTERNAL_ERROR"),
    )


@app.get("/health")
def health():
    return ok_response({"status": "ok", "env": settings.app_env})


@app.post("/auth/register")
def register(payload: UserCreate, db: Session = Depends(get_db)):
    existing = db.query(User).filter(User.username == payload.username).first()
    if existing:
        raise HTTPException(
            status_code=409,
            detail={"code": "USERNAME_EXISTS", "message": "用户名已存在"},
        )
    user = User(
        username=payload.username,
        password_hash=hash_password(payload.password),
        role="user",
    )
    db.add(user)
    db.commit()
    db.refresh(user)
    return ok_response(UserOut.model_validate(user).model_dump(), message="注册成功")


@app.post("/auth/login")
def login(form: OAuth2PasswordRequestForm = Depends(), db: Session = Depends(get_db)):
    user = db.query(User).filter(User.username == form.username).first()
    if not user or not verify_password(form.password, user.password_hash):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail={"code": "BAD_CREDENTIALS", "message": "用户名或密码错误"},
        )
    token = create_access_token({"sub": str(user.id)})
    return ok_response(TokenOut(access_token=token).model_dump(), message="登录成功")


@app.get("/markers")
def list_markers(
    current: User = Depends(get_current_user), db: Session = Depends(get_db)
):
    own_markers = db.query(Marker).filter(Marker.owner_id == current.id).all()
    own_items = [
        marker_to_dict(
            marker=item,
            owner_username=current.username,
            can_edit=True,
            can_delete=True,
        )
        for item in own_markers
    ]

    shared_rows = (
        db.query(MarkerShare, Marker, User)
        .join(Marker, MarkerShare.marker_id == Marker.id)
        .join(User, Marker.owner_id == User.id)
        .filter(MarkerShare.user_id == current.id)
        .all()
    )
    shared_items = [
        marker_to_dict(
            marker=marker,
            owner_username=owner.username,
            can_edit=share.can_edit,
            can_delete=False,
        )
        for share, marker, owner in shared_rows
    ]

    all_items = own_items + shared_items
    all_items.sort(key=lambda item: item["updated_at"], reverse=True)
    return ok_response(all_items, message="加载成功")


@app.post("/markers")
def create_marker(
    payload: MarkerCreate,
    current: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    marker = Marker(
        owner_id=current.id,
        title=payload.title,
        note=payload.note or "",
        lat=payload.lat,
        lng=payload.lng,
        visible=payload.visible,
        created_at=datetime.utcnow(),
        updated_at=datetime.utcnow(),
    )
    db.add(marker)
    db.commit()
    db.refresh(marker)
    return ok_response(
        marker_to_dict(
            marker=marker,
            owner_username=current.username,
            can_edit=True,
            can_delete=True,
        ),
        message="创建成功",
    )


@app.put("/markers/{marker_id}")
def update_marker(
    marker_id: int,
    payload: MarkerUpdate,
    current: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    marker = db.query(Marker).filter(Marker.id == marker_id).first()
    share = (
        db.query(MarkerShare)
        .filter(MarkerShare.marker_id == marker_id, MarkerShare.user_id == current.id)
        .first()
    )
    can_edit = marker and (marker.owner_id == current.id or (share and share.can_edit))
    if not marker or not can_edit:
        raise HTTPException(
            status_code=404,
            detail={"code": "MARKER_NOT_FOUND", "message": "标记不存在"},
        )
    for field, value in payload.model_dump(exclude_unset=True).items():
        setattr(marker, field, value)
    marker.updated_at = datetime.utcnow()
    db.commit()
    db.refresh(marker)
    return ok_response(
        marker_to_dict(
            marker=marker,
            owner_username=marker.owner.username,
            can_edit=True if marker.owner_id == current.id else bool(share and share.can_edit),
            can_delete=marker.owner_id == current.id,
        ),
        message="更新成功",
    )


@app.delete("/markers/{marker_id}")
def delete_marker(
    marker_id: int,
    current: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    marker = db.query(Marker).filter(Marker.id == marker_id).first()
    if not marker or marker.owner_id != current.id:
        raise HTTPException(
            status_code=404,
            detail={"code": "MARKER_NOT_FOUND", "message": "标记不存在"},
        )
    db.delete(marker)
    db.commit()
    return ok_response({"deleted": True}, message="删除成功")


@app.post("/markers/{marker_id}/share")
def share_marker(
    marker_id: int,
    payload: MarkerShareCreate,
    current: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    marker = db.query(Marker).filter(Marker.id == marker_id).first()
    if not marker or marker.owner_id != current.id:
        raise HTTPException(
            status_code=404,
            detail={"code": "MARKER_NOT_FOUND", "message": "标记不存在"},
        )

    target_user = db.query(User).filter(User.username == payload.username).first()
    if not target_user:
        raise HTTPException(
            status_code=404,
            detail={"code": "USER_NOT_FOUND", "message": "目标用户不存在"},
        )
    if target_user.id == current.id:
        raise HTTPException(
            status_code=400,
            detail={"code": "BAD_REQUEST", "message": "无需共享给自己"},
        )

    share = (
        db.query(MarkerShare)
        .filter(MarkerShare.marker_id == marker_id, MarkerShare.user_id == target_user.id)
        .first()
    )
    if share:
        share.can_edit = payload.can_edit
    else:
        share = MarkerShare(
            marker_id=marker_id,
            user_id=target_user.id,
            can_edit=payload.can_edit,
            created_at=datetime.utcnow(),
        )
        db.add(share)
    db.commit()
    return ok_response(
        {
            "marker_id": marker_id,
            "username": target_user.username,
            "can_edit": share.can_edit,
        },
        message="共享成功",
    )


@app.get("/markers/{marker_id}/shares")
def list_marker_shares(
    marker_id: int,
    current: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    marker = db.query(Marker).filter(Marker.id == marker_id).first()
    if not marker or marker.owner_id != current.id:
        raise HTTPException(
            status_code=404,
            detail={"code": "MARKER_NOT_FOUND", "message": "标记不存在"},
        )

    rows = (
        db.query(MarkerShare, User)
        .join(User, MarkerShare.user_id == User.id)
        .filter(MarkerShare.marker_id == marker_id)
        .all()
    )
    return ok_response(
        [
            {
                "share_id": share.id,
                "user_id": user.id,
                "username": user.username,
                "can_edit": share.can_edit,
            }
            for share, user in rows
        ],
        message="加载共享列表成功",
    )


@app.delete("/markers/{marker_id}/share/{user_id}")
def remove_marker_share(
    marker_id: int,
    user_id: int,
    current: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    marker = db.query(Marker).filter(Marker.id == marker_id).first()
    if not marker or marker.owner_id != current.id:
        raise HTTPException(
            status_code=404,
            detail={"code": "MARKER_NOT_FOUND", "message": "标记不存在"},
        )
    share = (
        db.query(MarkerShare)
        .filter(MarkerShare.marker_id == marker_id, MarkerShare.user_id == user_id)
        .first()
    )
    if not share:
        raise HTTPException(
            status_code=404,
            detail={"code": "SHARE_NOT_FOUND", "message": "共享记录不存在"},
        )
    db.delete(share)
    db.commit()
    return ok_response({"removed": True}, message="取消共享成功")
