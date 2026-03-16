from pydantic import BaseModel, Field
from typing import List, Optional, Dict, Any

class OtaStartRequest(BaseModel):
    ota_id: str
    url: str
    target_version: str

class SlotInfo(BaseModel):
    name: str
    state: str
    bootname: Optional[str] = None
    device: Optional[str] = None

class OtaStatus(BaseModel):
    ts: Optional[str] = None
    compatible: Optional[str] = None
    current_slot: Optional[str] = None
    slots: List[SlotInfo] = Field(default_factory=list)
    ota_id: Optional[str] = None
    ota_log: List[str] = Field(default_factory=list)
    current_version: Optional[str] = None
    target_version: Optional[str] = None
    phase: Optional[str] = None
    event: Optional[str] = None
    last_error: Optional[str] = None
    ip_address: Optional[str] = None
    device_id: Optional[str] = None

class OtaEvent(BaseModel):
    ts: str
    device: Dict[str, Any]
    ota: Dict[str, Any]
    context: Dict[str, Any]
    error: Dict[str, Any]
    evidence: Dict[str, Any]
