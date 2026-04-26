-- ============================================================
-- NRS - Notebook Reservation System
-- Schema v1.2 - ULID Edition (UPDATED)
-- ============================================================
-- NOTE: All IDs are ULID (TEXT)
-- Generate ULIDs in application layer (Dart)
-- ============================================================

CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- ------------------------------------------------------------
-- ADMINS
-- ------------------------------------------------------------
CREATE TABLE admins (
    id              TEXT PRIMARY KEY, -- ULID
    email           VARCHAR(255) NOT NULL UNIQUE,
    password_hash   VARCHAR(255) NOT NULL
);

-- ------------------------------------------------------------
-- STUDENTS
-- Login: email + dni
-- Activated on first checkout
-- Cleared on annual reset
-- ------------------------------------------------------------
CREATE TABLE students (
    id          TEXT PRIMARY KEY, -- ULID
    full_name   VARCHAR(255) NOT NULL,
    email       VARCHAR(255) NOT NULL UNIQUE,
    dni         VARCHAR(20)  NOT NULL UNIQUE,

    year        INT          NOT NULL CHECK (year BETWEEN 1 AND 7),
    division    INT          NOT NULL CHECK (division BETWEEN 1 AND 6),

    is_active   BOOLEAN      NOT NULL DEFAULT FALSE,
    created_at  TIMESTAMP    NOT NULL DEFAULT NOW()
);

-- ------------------------------------------------------------
-- TEACHERS
-- ------------------------------------------------------------
CREATE TABLE teachers (
    id              TEXT PRIMARY KEY, -- ULID
    email           VARCHAR(255) NOT NULL UNIQUE,
    dni             VARCHAR(20)  NOT NULL UNIQUE,
    full_name       VARCHAR(255) NOT NULL,
    password_hash   VARCHAR(255) NOT NULL,
    created_at      TIMESTAMP    NOT NULL DEFAULT NOW()
);

-- ------------------------------------------------------------
-- DEVICES
-- ------------------------------------------------------------
CREATE TABLE devices (
    id              TEXT PRIMARY KEY, -- ULID
    number          VARCHAR(20)  NOT NULL UNIQUE,
    type            VARCHAR(20)  NOT NULL
                        CHECK (type IN ('notebook', 'television')),
    status          VARCHAR(20)  NOT NULL DEFAULT 'available'
                        CHECK (status IN ('available', 'in_use', 'out_of_service')),
    status_notes    TEXT,
    created_at      TIMESTAMP    NOT NULL DEFAULT NOW()
);

-- ------------------------------------------------------------
-- RESERVATIONS
-- ------------------------------------------------------------
CREATE TABLE reservations (
    id              TEXT PRIMARY KEY, -- ULID
    booker_type     VARCHAR(10) NOT NULL
                        CHECK (booker_type IN ('student', 'teacher')),

    student_id      TEXT REFERENCES students(id) ON DELETE SET NULL,
    teacher_id      TEXT REFERENCES teachers(id) ON DELETE SET NULL,

    device_id       TEXT NOT NULL REFERENCES devices(id),

    date            DATE NOT NULL,
    start_time      TIME NOT NULL,
    end_time        TIME NOT NULL,

    status          VARCHAR(20) NOT NULL DEFAULT 'pending'
                        CHECK (status IN ('pending', 'confirmed', 'cancelled', 'expired', 'completed')),

    created_at      TIMESTAMP NOT NULL DEFAULT NOW(),

    CONSTRAINT chk_booker CHECK (
        (booker_type = 'student' AND student_id IS NOT NULL AND teacher_id IS NULL) OR
        (booker_type = 'teacher' AND teacher_id IS NOT NULL AND student_id IS NULL)
    )
);

-- ------------------------------------------------------------
-- TEACHER TOKENS
-- ------------------------------------------------------------
CREATE TABLE teacher_tokens (
    id              TEXT PRIMARY KEY, -- ULID
    reservation_id  TEXT NOT NULL REFERENCES reservations(id) ON DELETE CASCADE,
    token           VARCHAR(64) NOT NULL UNIQUE DEFAULT encode(gen_random_bytes(32), 'hex'),
    used            BOOLEAN NOT NULL DEFAULT FALSE,
    expires_at      TIMESTAMP NOT NULL
);

-- ------------------------------------------------------------
-- CHECKOUTS
-- ------------------------------------------------------------
CREATE TABLE checkouts (
    id              TEXT PRIMARY KEY, -- ULID
    reservation_id  TEXT NOT NULL UNIQUE REFERENCES reservations(id),
    admin_id        TEXT NOT NULL REFERENCES admins(id),
    device_notes    TEXT,
    checked_out_at  TIMESTAMP NOT NULL DEFAULT NOW()
);

-- ------------------------------------------------------------
-- RETURNS
-- ------------------------------------------------------------
CREATE TABLE returns (
    id              TEXT PRIMARY KEY, -- ULID
    checkout_id     TEXT NOT NULL UNIQUE REFERENCES checkouts(id),
    admin_id        TEXT NOT NULL REFERENCES admins(id),
    device_notes    TEXT,
    has_damage      BOOLEAN NOT NULL DEFAULT FALSE,
    returned_at     TIMESTAMP NOT NULL DEFAULT NOW()
);

-- ------------------------------------------------------------
-- WATCHLIST
-- ------------------------------------------------------------
CREATE TABLE watchlist (
    id              TEXT PRIMARY KEY, -- ULID
    dni             VARCHAR(20) NOT NULL UNIQUE,
    full_name       VARCHAR(255) NOT NULL,
    damage_count    INT NOT NULL DEFAULT 0,
    active          BOOLEAN NOT NULL DEFAULT TRUE,
    pardoned_by     TEXT REFERENCES admins(id) ON DELETE SET NULL,
    updated_at      TIMESTAMP NOT NULL DEFAULT NOW()
);

-- ------------------------------------------------------------
-- DAMAGES
-- ------------------------------------------------------------
CREATE TABLE damages (
    id              TEXT PRIMARY KEY, -- ULID
    dni             VARCHAR(20) NOT NULL,
    return_id       TEXT NOT NULL REFERENCES returns(id),
    description     TEXT NOT NULL,
    created_at      TIMESTAMP NOT NULL DEFAULT NOW()
);

-- ------------------------------------------------------------
-- NOTIFICATIONS
-- ------------------------------------------------------------
CREATE TABLE notifications (
    id              TEXT PRIMARY KEY, -- ULID
    recipient_email VARCHAR(255) NOT NULL,
    type            VARCHAR(30) NOT NULL
                        CHECK (type IN ('reservation_confirmed', 'reservation_cancelled', 'reminder')),
    reservation_id  TEXT REFERENCES reservations(id) ON DELETE SET NULL,
    sent            BOOLEAN NOT NULL DEFAULT FALSE,
    created_at      TIMESTAMP NOT NULL DEFAULT NOW()
);

-- ============================================================
-- INDEXES
-- ============================================================
CREATE INDEX idx_students_dni             ON students(dni);
CREATE INDEX idx_students_year             ON students(year);
CREATE INDEX idx_students_division         ON students(division);
CREATE INDEX idx_students_is_active        ON students(is_active);

CREATE INDEX idx_reservations_date        ON reservations(date);
CREATE INDEX idx_reservations_student     ON reservations(student_id);
CREATE INDEX idx_reservations_teacher     ON reservations(teacher_id);
CREATE INDEX idx_reservations_device      ON reservations(device_id);
CREATE INDEX idx_reservations_status      ON reservations(status);

CREATE INDEX idx_damages_dni              ON damages(dni);
CREATE INDEX idx_watchlist_dni            ON watchlist(dni);
CREATE INDEX idx_watchlist_active         ON watchlist(active);

CREATE INDEX idx_teacher_tokens_token     ON teacher_tokens(token);

CREATE INDEX idx_notifications_sent       ON notifications(sent);
CREATE INDEX idx_notifications_recipient  ON notifications(recipient_email);