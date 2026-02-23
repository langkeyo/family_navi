from datetime import datetime

from sqlalchemy import (
    Boolean,
    Column,
    DateTime,
    Float,
    ForeignKey,
    Integer,
    String,
    UniqueConstraint,
)
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
    shared_markers = relationship("MarkerShare", back_populates="user")


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
    shares = relationship("MarkerShare", back_populates="marker")


class MarkerShare(Base):
    __tablename__ = "marker_shares"
    __table_args__ = (
        UniqueConstraint("marker_id", "user_id", name="uq_marker_share_marker_user"),
    )

    id = Column(Integer, primary_key=True, index=True)
    marker_id = Column(Integer, ForeignKey("markers.id"), nullable=False, index=True)
    user_id = Column(Integer, ForeignKey("users.id"), nullable=False, index=True)
    can_edit = Column(Boolean, default=False, nullable=False)
    created_at = Column(DateTime, default=datetime.utcnow)

    marker = relationship("Marker", back_populates="shares")
    user = relationship("User", back_populates="shared_markers")
