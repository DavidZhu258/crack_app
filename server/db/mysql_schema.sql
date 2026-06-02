CREATE DATABASE IF NOT EXISTS crack_app
  CHARACTER SET utf8mb4
  COLLATE utf8mb4_unicode_ci;

USE crack_app;

CREATE TABLE IF NOT EXISTS users (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  oidc_sub VARCHAR(191) NOT NULL,
  username VARCHAR(191) NOT NULL,
  display_name VARCHAR(191) NOT NULL,
  role VARCHAR(64) NOT NULL DEFAULT 'operator',
  created_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
  updated_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6)
    ON UPDATE CURRENT_TIMESTAMP(6),
  PRIMARY KEY (id),
  UNIQUE KEY uq_users_oidc_sub (oidc_sub),
  KEY ix_users_username (username)
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS detection_records (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  remote_record_id VARCHAR(191) NOT NULL,
  local_record_id VARCHAR(191) NOT NULL,
  owner_oidc_sub VARCHAR(191) NOT NULL,
  timestamp DATETIME(6) NOT NULL,
  project_location VARCHAR(255) NOT NULL DEFAULT '',
  project_name VARCHAR(255) NOT NULL DEFAULT '',
  worker_name VARCHAR(191) NOT NULL DEFAULT '',
  rock_type VARCHAR(64) NOT NULL,
  elevation DOUBLE NOT NULL,
  has_seepage BOOLEAN NOT NULL DEFAULT FALSE,
  inference_mode VARCHAR(64) NOT NULL DEFAULT 'offline',
  model_version VARCHAR(191) NULL,
  indicators_json JSON NOT NULL,
  formula_snapshot_json JSON NOT NULL,
  classification_json JSON NOT NULL,
  support_plan_json JSON NOT NULL,
  record_json JSON NULL,
  sync_status VARCHAR(64) NOT NULL DEFAULT 'uploaded',
  created_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
  updated_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6)
    ON UPDATE CURRENT_TIMESTAMP(6),
  PRIMARY KEY (id),
  UNIQUE KEY uq_detection_records_remote_id (remote_record_id),
  KEY ix_detection_records_owner_time (owner_oidc_sub, timestamp)
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS record_assets (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  remote_record_id VARCHAR(191) NOT NULL,
  kind VARCHAR(64) NOT NULL,
  bucket VARCHAR(191) NOT NULL,
  object_key VARCHAR(512) NOT NULL,
  sha256 CHAR(64) NULL,
  content_type VARCHAR(191) NOT NULL,
  size_bytes BIGINT UNSIGNED NULL,
  width INT UNSIGNED NULL,
  height INT UNSIGNED NULL,
  created_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
  PRIMARY KEY (id),
  UNIQUE KEY uq_record_assets_object_key (object_key),
  KEY ix_record_assets_record (remote_record_id, kind)
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS manual_reviews (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  remote_record_id VARCHAR(191) NOT NULL,
  reviewer_oidc_sub VARCHAR(191) NOT NULL,
  accepted_recognition_result BOOLEAN NOT NULL,
  manual_grade VARCHAR(32) NULL,
  selected_support_plan_json JSON NULL,
  reviewer_name VARCHAR(191) NOT NULL DEFAULT '',
  note TEXT NULL,
  reviewed_at DATETIME(6) NOT NULL,
  created_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
  PRIMARY KEY (id),
  UNIQUE KEY uq_manual_reviews_record (remote_record_id),
  KEY ix_manual_reviews_reviewer (reviewer_oidc_sub)
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS idempotency_keys (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  idempotency_key VARCHAR(255) NOT NULL,
  remote_record_id VARCHAR(191) NOT NULL,
  created_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
  PRIMARY KEY (id),
  UNIQUE KEY uq_idempotency_keys_key (idempotency_key)
) ENGINE=InnoDB;
