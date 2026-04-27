-- Permite el estado 'maintenance' en la tabla devices.
-- Aplicar una sola vez sobre la base existente:
--   psql ... -f migrations/001_devices_allow_maintenance.sql

ALTER TABLE devices
    DROP CONSTRAINT IF EXISTS devices_status_check;

ALTER TABLE devices
    ADD CONSTRAINT devices_status_check
        CHECK (status IN ('available', 'in_use', 'out_of_service', 'maintenance'));
