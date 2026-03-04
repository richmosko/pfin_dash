-- ============================
-- Migration 001: Invite Codes
--
-- Adds invite code (passphrase) gating for user signup.
-- A BEFORE INSERT trigger on auth.users validates the invite code
-- from raw_user_meta_data before allowing the row to be created.
-- ============================

-- Invite codes table: per-email passphrases that gate signup access
CREATE TABLE pfin.invite_codes (
    id SERIAL PRIMARY KEY,
    email VARCHAR (254) NOT NULL,
    code VARCHAR (128) NOT NULL,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    notes TEXT,
    CONSTRAINT uq_invite_codes_email_code UNIQUE (email, code)
);
COMMENT ON TABLE pfin.invite_codes IS 'Per-email invite passphrases that control who can sign up';

-- Prevent anon/authenticated from querying codes via the REST API
REVOKE ALL ON pfin.invite_codes FROM anon, authenticated;

-- Validate invite code + email on signup via BEFORE INSERT trigger
CREATE OR REPLACE FUNCTION pfin.fn_validate_invite_code()
RETURNS TRIGGER AS $$
DECLARE
    invite_code_value TEXT;
    signup_email TEXT;
    code_valid BOOLEAN;
BEGIN
    invite_code_value := NEW.raw_user_meta_data ->> 'invite_code';
    signup_email := NEW.email;

    IF invite_code_value IS NULL OR invite_code_value = '' THEN
        RAISE EXCEPTION 'Invite code is required for signup';
    END IF;

    SELECT EXISTS (
        SELECT 1 FROM pfin.invite_codes
        WHERE email = signup_email
        AND code = invite_code_value
        AND is_active = TRUE
    ) INTO code_valid;

    IF NOT code_valid THEN
        RAISE EXCEPTION 'Invalid or inactive invite code';
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER
SET search_path = '';

CREATE TRIGGER trg_validate_invite_code
    BEFORE INSERT ON auth.users
    FOR EACH ROW
    EXECUTE FUNCTION pfin.fn_validate_invite_code();

-- Seed initial invite
INSERT INTO pfin.invite_codes (email, code, notes)
VALUES ('richmosko@gmail.com', 'Git-Er-Done!', 'Initial invite for bootstrap user');

-- Track migration version
INSERT INTO pfin.schema_version (
    major_release, minor_release, point_release, script_name
) VALUES (
    '00', '06', '0001', 'sql/migration/001_invite_codes.sql'
);
