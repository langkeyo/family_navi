from datetime import datetime

from fastapi import Depends, FastAPI, HTTPException, status
from fastapi.middleware.cors import CORSMiddleware
from fastapi.security import OAuth2PasswordRequestForm
from sqlalchemy.orm import Session

from .auth import create_access_token, get_current_user, hash_password, verify_password
from .config import settings
from .db import Base, engine, get_db
from .models import Marker, User
from .schemas import MarkerCreate, MarkerOut, MarkerUpdate, TokenOut, UserCreate, UserOut

app = FastAPI(title="Family Navi API")

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


@app.get("/health")
def health():
    return {"status": "ok", "env": settings.app_env}


@app.post("/auth/register", response_model=UserOut)
def register(payload: UserCreate, db: Session = Depends(get_db)):
    existing = db.query(User).filter(User.username == payload.username).first()
    if existing:
        raise HTTPException(status_code=409, detail="username already exists")
    user = User(
        username=payload.username,
        password_hash=hash_password(payload.password),
        role="user",
    )
    db.add(user)
    db.commit()
    db.refresh(user)
    return user


@app.post("/auth/login", response_model=TokenOut)
def login(form: OAuth2PasswordRequestForm = Depends(), db: Session = Depends(get_db)):
    user = db.query(User).filter(User.username == form.username).first()
    if not user or not verify_password(form.password, user.password_hash):
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="bad credentials")
    token = create_access_token({"sub": str(user.id)})
    return TokenOut(access_token=token)


@app.get("/markers", response_model=list[MarkerOut])
def list_markers(
    current: User = Depends(get_current_user), db: Session = Depends(get_db)
):
    return db.query(Marker).filter(Marker.owner_id == current.id).all()


@app.post("/markers", response_model=MarkerOut)
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
    return marker


@app.put("/markers/{marker_id}", response_model=MarkerOut)
def update_marker(
    marker_id: int,
    payload: MarkerUpdate,
    current: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    marker = db.query(Marker).filter(Marker.id == marker_id).first()
    if not marker or marker.owner_id != current.id:
        raise HTTPException(status_code=404, detail="marker not found")
    for field, value in payload.model_dump(exclude_unset=True).items():
        setattr(marker, field, value)
    marker.updated_at = datetime.utcnow()
    db.commit()
    db.refresh(marker)
    return marker


@app.delete("/markers/{marker_id}")
def delete_marker(
    marker_id: int,
    current: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    marker = db.query(Marker).filter(Marker.id == marker_id).first()
    if not marker or marker.owner_id != current.id:
        raise HTTPException(status_code=404, detail="marker not found")
    db.delete(marker)
    db.commit()
    return {"ok": True}
