from datetime import datetime

from sqlalchemy import Boolean, Column, DateTime, Float, ForeignKey, Integer, String
from sqlalchemy.orm import relationship

from .db import Base


class User(Base):
    __tablename__ = "users"

    id = Column(Integer, primary_key=True, index=True)
    username = Column(String(64), unique=True, index=True, nullable=False)
    password_hash = Column(String(255), nullable=False)
    role = Column(String(16), default="user", nullable=False)
    created_at = Column(DateTime, default=datetime.utcnow)

    markers = relationship("Marker", back_populates="owner")


class Marker(Base):
    __tablename__ = "markers"

    id = Column(Integer, primary_key=True, index=True)
    owner_id = Column(Integer, ForeignKey("users.id"), nullable=False, index=True)
    title = Column(String(128), nullable=False)
    note = Column(String(255), default="")
    lat = Column(Float, nullable=False)
    lng = Column(Float, nullable=False)
    visible = Column(Boolean, default=True)
    created_at = Column(DateTime, default=datetime.utcnow)
    updated_at = Column(DateTime, default=datetime.utcnow)

    owner = relationship("User", back_populates="markers")
