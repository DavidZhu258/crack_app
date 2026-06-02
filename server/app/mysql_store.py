from __future__ import annotations

import json
import os
from datetime import datetime, timezone
from typing import Any
from uuid import uuid4

from sqlalchemy import create_engine, text
from sqlalchemy.engine import Engine

UTC = timezone.utc


class MySqlRecordStore:
    def __init__(self, dsn: str | None = None) -> None:
        resolved_dsn = dsn or os.environ.get("CRACK_MYSQL_DSN", "")
        if not resolved_dsn:
            raise RuntimeError(
                "CRACK_MYSQL_DSN is required when CRACK_RECORD_STORE=mysql"
            )
        self.engine = create_engine(resolved_dsn, pool_pre_ping=True)
        self._ensure_extensions()

    def upsert_user(self, user: dict[str, Any]) -> None:
        now = _now()
        with self.engine.begin() as connection:
            connection.execute(
                text(
                    """
                    INSERT INTO users
                      (oidc_sub, username, display_name, role, created_at, updated_at)
                    VALUES
                      (:oidc_sub, :username, :display_name, :role, :now, :now)
                    ON DUPLICATE KEY UPDATE
                      username = VALUES(username),
                      display_name = VALUES(display_name),
                      role = VALUES(role),
                      updated_at = VALUES(updated_at)
                    """,
                ),
                {
                    "oidc_sub": user["id"],
                    "username": user["username"],
                    "display_name": user["displayName"],
                    "role": user["role"],
                    "now": now,
                },
            )

    def sync_record(
        self,
        record: dict[str, Any],
        idempotency_key: str,
    ) -> dict[str, Any]:
        now = _now()
        with self.engine.begin() as connection:
            existing_remote_id = connection.execute(
                text(
                    "SELECT remote_record_id FROM idempotency_keys "
                    "WHERE idempotency_key = :idempotency_key",
                ),
                {"idempotency_key": idempotency_key},
            ).scalar_one_or_none()
            if existing_remote_id:
                return self._get_record_in_connection(
                    connection, str(existing_remote_id)
                )

            normalized_record, remote_record_id = _normalized_record(record, now)
            engineering = normalized_record.get("engineeringInfo") or {}
            indicators = (
                normalized_record.get("indicators")
                or normalized_record.get("extractedParams")
                or {}
            )
            timestamp = _parse_datetime(normalized_record.get("timestamp"), now)
            connection.execute(
                text(
                    """
                    INSERT INTO detection_records
                      (
                        remote_record_id, local_record_id, owner_oidc_sub, timestamp,
                        project_location, project_name, worker_name, rock_type,
                        elevation, has_seepage, inference_mode, model_version,
                        indicators_json, formula_snapshot_json, classification_json,
                        support_plan_json, sync_status, record_json, created_at, updated_at
                      )
                    VALUES
                      (
                        :remote_record_id, :local_record_id, :owner_oidc_sub, :timestamp,
                        :project_location, :project_name, :worker_name, :rock_type,
                        :elevation, :has_seepage, :inference_mode, :model_version,
                        :indicators_json, :formula_snapshot_json, :classification_json,
                        :support_plan_json, :sync_status, :record_json, :now, :now
                      )
                    ON DUPLICATE KEY UPDATE
                      owner_oidc_sub = VALUES(owner_oidc_sub),
                      timestamp = VALUES(timestamp),
                      project_location = VALUES(project_location),
                      project_name = VALUES(project_name),
                      worker_name = VALUES(worker_name),
                      rock_type = VALUES(rock_type),
                      elevation = VALUES(elevation),
                      has_seepage = VALUES(has_seepage),
                      inference_mode = VALUES(inference_mode),
                      model_version = VALUES(model_version),
                      indicators_json = VALUES(indicators_json),
                      formula_snapshot_json = VALUES(formula_snapshot_json),
                      classification_json = VALUES(classification_json),
                      support_plan_json = VALUES(support_plan_json),
                      sync_status = VALUES(sync_status),
                      record_json = VALUES(record_json),
                      updated_at = VALUES(updated_at)
                    """,
                ),
                {
                    "remote_record_id": remote_record_id,
                    "local_record_id": normalized_record["id"],
                    "owner_oidc_sub": normalized_record.get("operatorUserId")
                    or "unknown",
                    "timestamp": timestamp,
                    "project_location": engineering.get("projectLocation")
                    or engineering.get("location")
                    or "",
                    "project_name": engineering.get("projectName") or "",
                    "worker_name": engineering.get("workerName")
                    or engineering.get("inspector")
                    or "",
                    "rock_type": engineering.get("rockType") or "unknown",
                    "elevation": float(
                        engineering.get("elevation") or engineering.get("depth") or 0,
                    ),
                    "has_seepage": bool(engineering.get("hasSeepage") or False),
                    "inference_mode": normalized_record.get("inferenceMode")
                    or "offline",
                    "model_version": normalized_record.get("modelVersion"),
                    "indicators_json": _json(indicators),
                    "formula_snapshot_json": _json(
                        normalized_record.get("formulaSnapshot") or {},
                    ),
                    "classification_json": _json(
                        normalized_record.get("classification") or {},
                    ),
                    "support_plan_json": _json(
                        normalized_record.get("supportPlan") or {},
                    ),
                    "sync_status": normalized_record.get("syncStatus") or "uploaded",
                    "record_json": _json(normalized_record),
                    "now": now,
                },
            )
            connection.execute(
                text(
                    """
                    INSERT INTO idempotency_keys
                      (idempotency_key, remote_record_id, created_at)
                    VALUES (:idempotency_key, :remote_record_id, :now)
                    ON DUPLICATE KEY UPDATE remote_record_id = VALUES(remote_record_id)
                    """,
                ),
                {
                    "idempotency_key": idempotency_key,
                    "remote_record_id": remote_record_id,
                    "now": now,
                },
            )
            self._upsert_assets(connection, remote_record_id, normalized_record)
            manual_review = normalized_record.get("manualReview")
            if isinstance(manual_review, dict):
                self._upsert_manual_review(
                    connection,
                    remote_record_id,
                    manual_review,
                    reviewer_user_id=normalized_record.get("operatorUserId")
                    or "unknown",
                    now=now,
                )
            return {
                "remoteRecordId": remote_record_id,
                "syncedAt": now.isoformat().replace("+00:00", "Z"),
                "record": normalized_record,
            }

    def list_records(self, owner_id: str | None = None) -> list[dict[str, Any]]:
        query = (
            "SELECT remote_record_id, updated_at, record_json FROM detection_records"
        )
        params: dict[str, Any] = {}
        if owner_id:
            query += " WHERE owner_oidc_sub = :owner_id"
            params["owner_id"] = owner_id
        query += " ORDER BY timestamp DESC, updated_at DESC"
        with self.engine.begin() as connection:
            rows = connection.execute(text(query), params).mappings().all()
        return [_snapshot_from_row(row) for row in rows]

    def list_reports(
        self, *, owner_id: str | None = None, presigner: Any
    ) -> list[dict[str, Any]]:
        query = """
            SELECT
              r.remote_record_id,
              r.owner_oidc_sub,
              r.timestamp,
              r.project_name,
              a.object_key,
              u.username,
              u.display_name
            FROM detection_records r
            JOIN record_assets a
              ON a.remote_record_id = r.remote_record_id
             AND a.kind = 'report'
            LEFT JOIN users u
              ON u.oidc_sub = r.owner_oidc_sub
        """
        params: dict[str, Any] = {}
        if owner_id:
            query += " WHERE r.owner_oidc_sub = :owner_id"
            params["owner_id"] = owner_id
        query += " ORDER BY r.timestamp DESC, r.updated_at DESC"
        with self.engine.begin() as connection:
            rows = connection.execute(text(query), params).mappings().all()
        reports: list[dict[str, Any]] = []
        for row in rows:
            timestamp = row["timestamp"]
            if isinstance(timestamp, datetime):
                timestamp_value = (
                    timestamp.replace(tzinfo=UTC)
                    .isoformat()
                    .replace(
                        "+00:00",
                        "Z",
                    )
                )
            else:
                timestamp_value = str(timestamp)
            username = row["username"] or row["owner_oidc_sub"]
            reports.append(
                {
                    "userId": row["owner_oidc_sub"],
                    "username": username,
                    "displayName": row["display_name"] or username,
                    "remoteRecordId": row["remote_record_id"],
                    "timestamp": timestamp_value,
                    "projectName": row["project_name"] or "",
                    "downloadUrl": presigner.download_url(row["object_key"]),
                }
            )
        return reports

    def get_record(self, remote_record_id: str) -> dict[str, Any] | None:
        with self.engine.begin() as connection:
            return self._get_record_in_connection(connection, remote_record_id)

    def update_manual_review(
        self,
        remote_record_id: str,
        manual_review: dict[str, Any],
        *,
        reviewer_user_id: str,
    ) -> dict[str, Any] | None:
        now = _now()
        with self.engine.begin() as connection:
            snapshot = self._get_record_in_connection(connection, remote_record_id)
            if snapshot is None:
                return None
            record = snapshot["record"]
            record["manualReview"] = {
                **manual_review,
                "reviewerUserId": reviewer_user_id,
            }
            record["updatedAt"] = now.isoformat().replace("+00:00", "Z")
            connection.execute(
                text(
                    """
                    UPDATE detection_records
                    SET record_json = :record_json, updated_at = :now
                    WHERE remote_record_id = :remote_record_id
                    """,
                ),
                {
                    "record_json": _json(record),
                    "now": now,
                    "remote_record_id": remote_record_id,
                },
            )
            self._upsert_manual_review(
                connection,
                remote_record_id,
                record["manualReview"],
                reviewer_user_id=reviewer_user_id,
                now=now,
            )
            return {
                "remoteRecordId": remote_record_id,
                "syncedAt": now.isoformat().replace("+00:00", "Z"),
                "record": record,
            }

    def _get_record_in_connection(
        self,
        connection: Any,
        remote_record_id: str,
    ) -> dict[str, Any] | None:
        row = (
            connection.execute(
                text(
                    """
                SELECT remote_record_id, updated_at, record_json
                FROM detection_records
                WHERE remote_record_id = :remote_record_id
                """,
                ),
                {"remote_record_id": remote_record_id},
            )
            .mappings()
            .first()
        )
        if row is None:
            return None
        return _snapshot_from_row(row)

    def _upsert_assets(
        self,
        connection: Any,
        remote_record_id: str,
        record: dict[str, Any],
    ) -> None:
        for asset in record.get("assets") or []:
            if not isinstance(asset, dict) or not asset.get("objectKey"):
                continue
            connection.execute(
                text(
                    """
                    INSERT INTO record_assets
                      (
                        remote_record_id, kind, bucket, object_key, sha256,
                        content_type, size_bytes, width, height
                      )
                    VALUES
                      (
                        :remote_record_id, :kind, :bucket, :object_key, :sha256,
                        :content_type, :size_bytes, :width, :height
                      )
                    ON DUPLICATE KEY UPDATE
                      remote_record_id = VALUES(remote_record_id),
                      kind = VALUES(kind),
                      bucket = VALUES(bucket),
                      sha256 = VALUES(sha256),
                      content_type = VALUES(content_type),
                      size_bytes = VALUES(size_bytes),
                      width = VALUES(width),
                      height = VALUES(height)
                    """,
                ),
                {
                    "remote_record_id": remote_record_id,
                    "kind": asset.get("kind") or "asset",
                    "bucket": asset.get("bucket")
                    or os.environ.get(
                        "CRACK_OBJECT_BUCKET",
                        "crack-record-assets",
                    ),
                    "object_key": asset["objectKey"],
                    "sha256": asset.get("sha256"),
                    "content_type": asset.get("contentType")
                    or "application/octet-stream",
                    "size_bytes": asset.get("sizeBytes"),
                    "width": asset.get("width"),
                    "height": asset.get("height"),
                },
            )

    def _upsert_manual_review(
        self,
        connection: Any,
        remote_record_id: str,
        manual_review: dict[str, Any],
        *,
        reviewer_user_id: str,
        now: datetime,
    ) -> None:
        reviewed_at = _parse_datetime(manual_review.get("reviewedAt"), now)
        connection.execute(
            text(
                """
                INSERT INTO manual_reviews
                  (
                    remote_record_id, reviewer_oidc_sub,
                    accepted_recognition_result, manual_grade,
                    selected_support_plan_json, reviewer_name, note, reviewed_at
                  )
                VALUES
                  (
                    :remote_record_id, :reviewer_oidc_sub,
                    :accepted_recognition_result, :manual_grade,
                    :selected_support_plan_json, :reviewer_name, :note, :reviewed_at
                  )
                ON DUPLICATE KEY UPDATE
                  reviewer_oidc_sub = VALUES(reviewer_oidc_sub),
                  accepted_recognition_result = VALUES(accepted_recognition_result),
                  manual_grade = VALUES(manual_grade),
                  selected_support_plan_json = VALUES(selected_support_plan_json),
                  reviewer_name = VALUES(reviewer_name),
                  note = VALUES(note),
                  reviewed_at = VALUES(reviewed_at)
                """,
            ),
            {
                "remote_record_id": remote_record_id,
                "reviewer_oidc_sub": reviewer_user_id,
                "accepted_recognition_result": bool(
                    manual_review.get("acceptedRecognitionResult"),
                ),
                "manual_grade": manual_review.get("manualGrade"),
                "selected_support_plan_json": (
                    _json(
                        manual_review.get("selectedSupportPlan"),
                    )
                    if manual_review.get("selectedSupportPlan") is not None
                    else None
                ),
                "reviewer_name": manual_review.get("reviewerName") or "",
                "note": manual_review.get("note"),
                "reviewed_at": reviewed_at,
            },
        )

    def _ensure_extensions(self) -> None:
        with self.engine.begin() as connection:
            _add_column_if_missing(
                connection,
                "detection_records",
                "record_json",
                "JSON NULL",
            )


def _add_column_if_missing(
    connection: Any,
    table_name: str,
    column_name: str,
    definition: str,
) -> None:
    exists = connection.execute(
        text(
            """
            SELECT COUNT(*)
            FROM information_schema.columns
            WHERE table_schema = DATABASE()
              AND table_name = :table_name
              AND column_name = :column_name
            """,
        ),
        {"table_name": table_name, "column_name": column_name},
    ).scalar_one()
    if not exists:
        connection.execute(
            text(f"ALTER TABLE {table_name} ADD COLUMN {column_name} {definition}"),
        )


def _normalized_record(
    record: dict[str, Any], now: datetime
) -> tuple[dict[str, Any], str]:
    record_id = str(record.get("id") or record.get("recordId") or uuid4().hex)
    remote_record_id = str(record.get("remoteRecordId") or f"cloud_{record_id}")
    timestamp = record.get("timestamp") or now.isoformat().replace("+00:00", "Z")
    normalized = {
        **record,
        "id": record_id,
        "remoteRecordId": remote_record_id,
        "timestamp": timestamp,
        "syncStatus": "uploaded",
        "syncError": "",
        "updatedAt": record.get("updatedAt") or now.isoformat().replace("+00:00", "Z"),
    }
    return normalized, remote_record_id


def _snapshot_from_row(row: Any) -> dict[str, Any]:
    record_json = row["record_json"]
    if isinstance(record_json, str):
        record = json.loads(record_json)
    else:
        record = record_json
    updated_at = row["updated_at"]
    if isinstance(updated_at, datetime):
        synced_at = updated_at.astimezone(UTC).isoformat().replace("+00:00", "Z")
    else:
        synced_at = str(updated_at)
    return {
        "remoteRecordId": row["remote_record_id"],
        "syncedAt": synced_at,
        "record": record,
    }


def _now() -> datetime:
    return datetime.now(UTC).replace(tzinfo=None)


def _parse_datetime(value: Any, fallback: datetime) -> datetime:
    if value is None:
        return fallback
    if isinstance(value, datetime):
        return value.replace(tzinfo=None)
    text_value = str(value).replace("Z", "+00:00")
    try:
        return datetime.fromisoformat(text_value).astimezone(UTC).replace(tzinfo=None)
    except ValueError:
        return fallback


def _json(value: Any) -> str:
    return json.dumps(value if value is not None else {}, ensure_ascii=False)
