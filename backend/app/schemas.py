from datetime import datetime
from typing import Optional

from pydantic import BaseModel


class TokenOut(BaseModel):
    access_token: str
    token_type: str = "bearer"


class UserCreate(BaseModel):
    username: str
    password: str


class UserOut(BaseModel):
    id: int
    username: str
    role: str
    created_at: datetime

    class Config:
        from_attributes = True


class MarkerCreate(BaseModel):
    title: str
    note: Optional[str] = ""
    lat: float
    lng: float
    visible: bool = True


class MarkerUpdate(BaseModel):
    title: Optional[str] = None
    note: Optional[str] = None
    lat: Optional[float] = None
    lng: Optional[float] = None
    visible: Optional[bool] = None


class MarkerOut(BaseModel):
    id: int
    owner_id: int
    title: str
    note: str
    lat: float
    lng: float
    visible: bool
    created_at: datetime
    updated_at: datetime

    class Config:
        from_attributes = True


class MarkerShareCreate(BaseModel):
    username: str
    can_edit: bool = False
