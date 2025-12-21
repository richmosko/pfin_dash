-- ============================
-- Personal Finance - Dashboard
--
-- This project tracks user watchlists and accounts / transactions.
-- To be used to reconcile and summarize positions and Net Asset Values.
-- Also used to screen stocks for buy / sell opportunities.
-- More metrics TBD... but source data is from Financial Modeling Prep.
--
--   Schema namespace to reference pfin_dash project
-- ============================
CREATE SCHEMA pfin;


-- =========================
-- USERS AND ACCESS SECURITY
--   SUPABASE AUTH HYBRID APPROACH
--   * Supabase auth.users handles: authentication, password reset, social logins
--   * member table handles: business logic, app-specific data
--   * Automatic sync via triggers
-- 
-- =========================

-- List of Members (Users), linked to Supabase auth
CREATE TABLE pfin.member (
    id SERIAL PRIMARY KEY,
    supabase_user_id UUID UNIQUE NOT NULL,
    email VARCHAR(128) UNIQUE NOT NULL,
    -- Supabase auth.users handles all authentication
    token_version INTEGER NOT NULL DEFAULT 0,
    last_token_refresh TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    last_login TIMESTAMPTZ,
    CONSTRAINT fk_member_supabase_user_id
        FOREIGN KEY (supabase_user_id)
        REFERENCES auth.users(id) ON DELETE CASCADE
);
COMMENT ON TABLE pfin.member IS 'List of User/Members';

CREATE INDEX idx_member_email ON pfin.member(email);
CREATE INDEX idx_member_supabase_user_id ON pfin.member(supabase_user_id);

-- Function to allow trigger updates of 'updated_at' columns
CREATE OR REPLACE FUNCTION pfin.fn_update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Add a trigger to update updated_at timestamp
CREATE TRIGGER trg_update_pfinmember_updated_at
    BEFORE UPDATE ON pfin.member
    FOR EACH ROW
    EXECUTE FUNCTION pfin.fn_update_updated_at_column();

-- Auto-create member record when user signs up via Supabase
CREATE OR REPLACE FUNCTION pfin.fn_handle_new_user()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO pfin.member (supabase_user_id, email)
    VALUES (NEW.id, NEW.email);
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE TRIGGER trg_on_pfinauth_user_created
    AFTER INSERT ON auth.users
    FOR EACH ROW
    EXECUTE FUNCTION pfin.fn_handle_new_user();

-- Sync email changes from Supabase auth to member table
CREATE OR REPLACE FUNCTION pfin.fn_sync_user_email()
RETURNS TRIGGER AS $$
BEGIN
    UPDATE pfin.member 
    SET email = NEW.email,
        updated_at = NOW()
    WHERE supabase_user_id = NEW.id;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE TRIGGER trg_on_pfinauth_user_email_updated
    AFTER UPDATE OF email ON auth.users
    FOR EACH ROW
    WHEN (OLD.email IS DISTINCT FROM NEW.email)
    EXECUTE FUNCTION pfin.fn_sync_user_email();


-- ==================================================
-- DEFINED CATEGORIES / TYPES (INFREQUENTLY MODIFIED)
-- ==================================================

-- Account Types: Valid account types and associated tax and liability handling
CREATE TABLE pfin.account_type (
    id SERIAL PRIMARY KEY,
    name VARCHAR(128) UNIQUE NOT NULL,
    is_taxable BOOLEAN NOT NULL, -- [richmosko]: Will it ever be taxed? If so, track unrealized gains
    is_tax_deferred BOOLEAN NOT NULL, -- [richmosko]: Do sales count as realized gains?
    is_liability BOOLEAN NOT NULL,
    notes TEXT
);

-- Asset Categories: Valid assets to track. ie: cash, bonds, equity, alt, etc.
-- and associated sub-categories
CREATE TABLE pfin.asset_cat (
    id SERIAL PRIMARY KEY,
    cat VARCHAR(128) NOT NULL,
    sub_cat VARCHAR(128) NOT NULL,
    notes TEXT,
    CONSTRAINT uq_asset_cat UNIQUE(cat, sub_cat)
);

-- Transaction Categories: Valid transactions types
CREATE TABLE pfin.trans_cat (
    id SERIAL PRIMARY KEY,
    cat VARCHAR(128) NOT NULL,
    sub_cat VARCHAR(128) NOT NULL,
    notes TEXT,
    CONSTRAINT uq_trans_cat UNIQUE(cat, sub_cat)
);


-- ================================
-- ACCOUNT AND TRANSACTION TRACKING
-- ================================

-- List of Accounts
CREATE TABLE pfin.account (
    id SERIAL PRIMARY KEY,
    account_type_id INTEGER NOT NULL,
    acct_name VARCHAR(128) NOT NULL, -- Account Name (per-creator unique)
    acct_number VARCHAR(128),
    created_by INTEGER NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT fk_account_created_by
        FOREIGN KEY(created_by)
        REFERENCES pfin.member(id) ON DELETE CASCADE,
    CONSTRAINT fk_account_account_type_id
        FOREIGN KEY(account_type_id)
        REFERENCES pfin.account_type(id) ON DELETE RESTRICT,
    CONSTRAINT uq_account_namecreated
        UNIQUE (acct_name, created_by)
);
COMMENT ON TABLE pfin.account IS 'List of Accounts and associated who is the owner';

-- [richmosko]: a trigger to update the updated_at timestamp
CREATE TRIGGER trg_update_pfinaccount_updated_at
    BEFORE UPDATE ON pfin.account
    FOR EACH ROW
    EXECUTE FUNCTION pfin.fn_update_updated_at_column();

CREATE INDEX idx_account_created_by ON pfin.account(created_by);

-- Accounts Access: Who can access what
CREATE TABLE pfin.account_access (
    account_id INTEGER NOT NULL,
    member_id INTEGER NOT NULL,
    access_level VARCHAR(20) NOT NULL,
    nickname VARCHAR(128) NOT NULL,
    granted_by INTEGER,
    granted_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    notes TEXT,
    CONSTRAINT ck_access_level
        CHECK(access_level IN ('owner', 'editor', 'viewer')),
    CONSTRAINT fk_account_access_account_id
        FOREIGN KEY(account_id)
        REFERENCES pfin.account(id) ON DELETE CASCADE,
    CONSTRAINT fk_account_access_member_id
        FOREIGN KEY(member_id)
        REFERENCES pfin.member(id) ON DELETE CASCADE,
    CONSTRAINT fk_account_access_granted_by
        FOREIGN KEY(granted_by)
        REFERENCES pfin.member(id) ON DELETE SET NULL,
    CONSTRAINT pk_account_access
        PRIMARY KEY (account_id, member_id),
    CONSTRAINT uq_account_access_membernickname
        UNIQUE (member_id, nickname)
);
COMMENT ON TABLE pfin.account_access IS 'Defines what members can access which account';

CREATE INDEX idx_account_access_member_id ON pfin.account_access(member_id);

-- Trigger to automatically grant member access when account is created
CREATE OR REPLACE FUNCTION pfin.fn_grant_creator_access()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO pfin.account_access (account_id, member_id, access_level, granted_by, nickname)
    VALUES (NEW.id, NEW.created_by, 'owner', NEW.created_by, NEW.acct_name);
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- [richmosko]: nickname column defaults to account.acct_name
CREATE TRIGGER trg_pfinaccount_creator_access
AFTER INSERT ON pfin.account
FOR EACH ROW
EXECUTE FUNCTION pfin.fn_grant_creator_access();

-- List of Assets
--     [richmosko]: If "Equity" type, Company Information via the "stock-list" query
CREATE TABLE pfin.asset (
    id SERIAL PRIMARY KEY,
    symbol VARCHAR(16) UNIQUE NOT NULL,
    asset_cat_id INTEGER NOT NULL,
    description TEXT,
    exp_date DATE, -- [richmosko]: If NULL, then no expiration date
    CONSTRAINT fk_asset_asset_cat_id
        FOREIGN KEY(asset_cat_id)
        REFERENCES pfin.asset_cat(id) ON DELETE RESTRICT
);
COMMENT ON TABLE pfin.asset IS 'Assets can be stocks, bonds, or whatever is defined in asset_cat';

CREATE INDEX idx_asset_cat_id ON pfin.asset(asset_cat_id);

-- Account Transactions
--     [richmosko]: Reconciled holdings live here as well. they will show up as 'reconcile' trans_cat_id
CREATE TABLE pfin.account_trans (
    id SERIAL PRIMARY KEY,
    account_id INTEGER NOT NULL,
    asset_id INTEGER NOT NULL,
    trans_cat_id INTEGER NOT NULL,
    trans_date DATE NOT NULL,
    price NUMERIC(14, 4),
    qty NUMERIC(14, 4),
    amount NUMERIC(14, 2),
    cost NUMERIC(14, 2),
    balance NUMERIC(14, 2), -- [richmosko]: imported running CASH balance to use for reconcilliation
    description TEXT,
    import_text TEXT,
    import_hash VARCHAR(32) NOT NULL, -- [richmosko]: MD5 checksum of orig CSV columns... for transaction matching
    CONSTRAINT fk_account_trans_account_id
        FOREIGN KEY(account_id)
        REFERENCES pfin.account(id) ON DELETE CASCADE,
    CONSTRAINT fk_account_trans_asset_id
        FOREIGN KEY(asset_id)
        REFERENCES pfin.asset(id) ON DELETE RESTRICT,
    CONSTRAINT fk_account_trans_trans_cat_id
        FOREIGN KEY(trans_cat_id)
        REFERENCES pfin.trans_cat(id) ON DELETE RESTRICT,
    CONSTRAINT uq_account_trans_accounthash
        UNIQUE(account_id, import_hash)
);

CREATE INDEX idx_account_trans_account_id ON pfin.account_trans(account_id);
CREATE INDEX idx_account_trans_asset_id ON pfin.account_trans(asset_id);
CREATE INDEX idx_account_trans_date ON pfin.account_trans(trans_date);
CREATE INDEX idx_account_trans_import_hash ON pfin.account_trans(import_hash);
CREATE INDEX idx_account_trans_account_date ON pfin.account_trans(account_id, trans_date DESC);
CREATE INDEX idx_account_trans_date_account ON pfin.account_trans(trans_date DESC, account_id);

-- Member Watchlists
CREATE TABLE pfin.watchlist (
    member_id INTEGER NOT NULL,
    asset_id INTEGER NOT NULL,
    CONSTRAINT fk_member_watchlist_member_id
        FOREIGN KEY (member_id)
        REFERENCES pfin.member(id) ON DELETE CASCADE,
    CONSTRAINT fk_member_watchlist_asset_id
        FOREIGN KEY (asset_id)
        REFERENCES pfin.asset(id) ON DELETE RESTRICT,
    CONSTRAINT pk_member_watchlist
        PRIMARY KEY (member_id, asset_id)
);


-- ===============================================
-- ASSET TRACKING FOR ACCOUNTS AND STOCK SCREENING
-- ===============================================

-- List of Company Names: Extended Company Information
--     [richmosko]:  from FMP "profile" JSON query
CREATE TABLE pfin.stock_profile (
    asset_id INTEGER PRIMARY KEY,
    price NUMERIC(14, 2),
    market_cap BIGINT,
    beta NUMERIC(7, 2),
    last_dividend NUMERIC(14, 2),
    range VARCHAR(50),
    change NUMERIC(14, 2),
    change_percentage NUMERIC(14, 4),
    volume BIGINT,
    average_volume BIGINT,
    company_name VARCHAR(255),
    currency VARCHAR(3),
    cik VARCHAR(20),
    isin VARCHAR(12),
    cusip VARCHAR(9),
    exchange_full_name VARCHAR(100),
    exchange VARCHAR(20),
    industry VARCHAR(100),
    website VARCHAR(255),
    description TEXT,
    ceo VARCHAR(100),
    sector VARCHAR(50),
    country VARCHAR(2),
    full_time_employees INTEGER,
    phone VARCHAR(20),
    address VARCHAR(255),
    city VARCHAR(100),
    state VARCHAR(2),
    zip VARCHAR(10),
    image VARCHAR(255),
    ipo_date DATE,
    default_image BOOLEAN,
    is_etf BOOLEAN,
    is_actively_trading BOOLEAN,
    is_adr BOOLEAN,
    is_fund BOOLEAN,
    CONSTRAINT fk_stock_profile_asset_id
        FOREIGN KEY (asset_id)
        REFERENCES pfin.asset(id) ON DELETE CASCADE
);

-- Company Historical Price Data
--     [richmosko]:  from FMP "historical-price-eod/full" JSON query
CREATE TABLE pfin.eod_price (
    id SERIAL PRIMARY KEY,
    asset_id INTEGER NOT NULL,
    end_date DATE NOT NULL,
    open NUMERIC(14, 2),
    high NUMERIC(14, 2),
    low NUMERIC(14, 2),
    close NUMERIC(14, 2),
    volume BIGINT,
    change NUMERIC(14, 2),
    change_percent NUMERIC(14, 5),
    vwap NUMERIC(14, 4),
    CONSTRAINT fk_eod_price_asset_id
        FOREIGN KEY (asset_id)
        REFERENCES pfin.asset(id) ON DELETE CASCADE,
    CONSTRAINT uq_eod_price_assetdate
        UNIQUE (asset_id, end_date)
);

CREATE INDEX idx_eod_price_asset_date ON pfin.eod_price(asset_id, end_date DESC);
CREATE INDEX idx_eod_price_date ON pfin.eod_price(end_date DESC);

-- Company Reporting Periods
--     [richmosko]: Intermediate table to sync earnings, cash flows, and balance sheets
CREATE TABLE pfin.reporting_period (
    id SERIAL PRIMARY KEY,
    asset_id INTEGER NOT NULL,
    end_date DATE NOT NULL,
    filing_date DATE NOT NULL,
    accepted_date TIMESTAMPTZ NOT NULL,
    fiscal_year INTEGER NOT NULL,
    period VARCHAR(2) NOT NULL,
    CONSTRAINT ck_reporting_period_period
        CHECK (period IN ('FY', 'Q1', 'Q2', 'Q3', 'Q4')),
    CONSTRAINT fk_reporting_period_asset_id
        FOREIGN KEY (asset_id)
        REFERENCES pfin.asset(id) ON DELETE CASCADE,
    CONSTRAINT uq_reporting_period_assetdate
        UNIQUE (asset_id, filing_date)
);
COMMENT ON TABLE pfin.reporting_period IS 'Lists valid reporint periods per asset if available';

CREATE INDEX idx_reporting_period_asset_id ON pfin.reporting_period(asset_id, fiscal_year DESC, period);
CREATE INDEX idx_reporting_period_fiscal_year ON pfin.reporting_period(fiscal_year DESC, period);

-- Company Income Statements
CREATE TABLE pfin.income_statement (
    id SERIAL PRIMARY KEY,
    reporting_period_id INTEGER NOT NULL,
    reported_currency VARCHAR(3),
    cik VARCHAR(20),
    revenue NUMERIC(18, 2),
    cost_of_revenue NUMERIC(18, 2),
    gross_profit NUMERIC(18, 2),
    research_and_development_expenses NUMERIC(18, 2),
    general_and_administrative_expenses NUMERIC(18, 2),
    selling_and_marketing_expenses NUMERIC(18, 2),
    selling_general_and_administrative_expenses NUMERIC(18, 2),
    other_expenses NUMERIC(18, 2),
    operating_expenses NUMERIC(18, 2),
    cost_and_expenses NUMERIC(18, 2),
    net_interest_income NUMERIC(18, 2),
    interest_income NUMERIC(18, 2),
    interest_expense NUMERIC(18, 2),
    depreciation_and_amortization NUMERIC(18, 2),
    ebitda NUMERIC(18, 2),
    ebit NUMERIC(18, 2),
    non_operating_income_excluding_interest NUMERIC(18, 2),
    operating_income NUMERIC(18, 2),
    total_other_income_expenses_net NUMERIC(18, 2),
    income_before_tax NUMERIC(18, 2),
    income_tax_expense NUMERIC(18, 2),
    net_income_from_continuing_operations NUMERIC(18, 2),
    net_income_from_discontinued_operations NUMERIC(18, 2),
    other_adjustments_to_net_income NUMERIC(18, 2),
    net_income NUMERIC(18, 2),
    net_income_deductions NUMERIC(18, 2),
    bottom_line_net_income NUMERIC(18, 2),
    eps NUMERIC(14, 4),
    eps_diluted NUMERIC(14, 4),
    weighted_average_shs_out BIGINT,
    weighted_average_shs_out_dil BIGINT,
    CONSTRAINT fk_income_statement_reporting_period
        FOREIGN KEY (reporting_period_id)
        REFERENCES pfin.reporting_period(id) ON DELETE CASCADE,
    CONSTRAINT uq_income_statement_reporting_period
        UNIQUE (reporting_period_id)
);

-- Company Balance Sheets
CREATE TABLE pfin.balance_sheet (
    id SERIAL PRIMARY KEY,
    reporting_period_id INTEGER NOT NULL,
    reported_currency VARCHAR(3),
    cik VARCHAR(20),
    cash_and_cash_equivalents NUMERIC(18, 2),
    short_term_investments NUMERIC(18, 2),
    cash_and_short_term_investments NUMERIC(18, 2),
    net_receivables NUMERIC(18, 2),
    accounts_receivables NUMERIC(18, 2),
    other_receivables NUMERIC(18, 2),
    inventory NUMERIC(18, 2),
    prepaids NUMERIC(18, 2),
    other_current_assets NUMERIC(18, 2),
    total_current_assets NUMERIC(18, 2),
    property_plant_equipment_net NUMERIC(18, 2),
    goodwill NUMERIC(18, 2),
    intangible_assets NUMERIC(18, 2),
    goodwill_and_intangible_assets NUMERIC(18, 2),
    long_term_investments NUMERIC(18, 2),
    tax_assets NUMERIC(18, 2),
    other_non_current_assets NUMERIC(18, 2),
    total_non_current_assets NUMERIC(18, 2),
    other_assets NUMERIC(18, 2),
    total_assets NUMERIC(18, 2),
    total_payables NUMERIC(18, 2),
    account_payables NUMERIC(18, 2),
    other_payables NUMERIC(18, 2),
    accrued_expenses NUMERIC(18, 2),
    short_term_debt NUMERIC(18, 2),
    capital_lease_obligations_current NUMERIC(18, 2),
    tax_payables NUMERIC(18, 2),
    deferred_revenue NUMERIC(18, 2),
    other_current_liabilities NUMERIC(18, 2),
    total_current_liabilities NUMERIC(18, 2),
    long_term_debt NUMERIC(18, 2),
    capital_lease_obligations_non_current NUMERIC(18, 2),
    deferred_revenue_non_current NUMERIC(18, 2),
    deferred_tax_liabilities_non_current NUMERIC(18, 2),
    other_non_current_liabilities NUMERIC(18, 2),
    total_non_current_liabilities NUMERIC(18, 2),
    other_liabilities NUMERIC(18, 2),
    capital_lease_obligations NUMERIC(18, 2),
    total_liabilities NUMERIC(18, 2),
    treasury_stock NUMERIC(18, 2),
    preferred_stock NUMERIC(18, 2),
    common_stock NUMERIC(18, 2),
    retained_earnings NUMERIC(18, 2),
    additional_paid_in_capital NUMERIC(18, 2),
    accumulated_other_comprehensive_income_loss NUMERIC(18, 2),
    other_total_stockholders_equity NUMERIC(18, 2),
    total_stockholders_equity NUMERIC(18, 2),
    total_equity NUMERIC(18, 2),
    minority_interest NUMERIC(18, 2),
    total_liabilities_and_total_equity NUMERIC(18, 2),
    total_investments NUMERIC(18, 2),
    total_debt NUMERIC(18, 2),
    net_debt NUMERIC(18, 2),
    CONSTRAINT fk_balance_statement_reporting_period
        FOREIGN KEY (reporting_period_id)
        REFERENCES pfin.reporting_period(id) ON DELETE CASCADE,
    CONSTRAINT uq_balance_statement_reporting_period
        UNIQUE (reporting_period_id)
);

-- Company Cash Flows
CREATE TABLE pfin.cash_flow (
    id SERIAL PRIMARY KEY,
    reporting_period_id INTEGER NOT NULL,
    reported_currency VARCHAR(3),
    cik VARCHAR(20),
    net_income NUMERIC(18, 2),
    depreciation_and_amortization NUMERIC(18, 2),
    deferred_income_tax NUMERIC(18, 2),
    stock_based_compensation NUMERIC(18, 2),
    change_in_working_capital NUMERIC(18, 2),
    accounts_receivables NUMERIC(18, 2),
    inventory NUMERIC(18, 2),
    accounts_payables NUMERIC(18, 2),
    other_working_capital NUMERIC(18, 2),
    other_non_cash_items NUMERIC(18, 2),
    net_cash_provided_by_operating_activities NUMERIC(18, 2),
    investments_in_property_plant_and_equipment NUMERIC(18, 2),
    acquisitions_net NUMERIC(18, 2),
    purchases_of_investments NUMERIC(18, 2),
    sales_maturities_of_investments NUMERIC(18, 2),
    other_investing_activities NUMERIC(18, 2),
    net_cash_provided_by_investing_activities NUMERIC(18, 2),
    net_debt_issuance NUMERIC(18, 2),
    long_term_net_debt_issuance NUMERIC(18, 2),
    short_term_net_debt_issuance NUMERIC(18, 2),
    net_stock_issuance NUMERIC(18, 2),
    net_common_stock_issuance NUMERIC(18, 2),
    common_stock_issuance NUMERIC(18, 2),
    common_stock_repurchased NUMERIC(18, 2),
    net_preferred_stock_issuance NUMERIC(18, 2),
    net_dividends_paid NUMERIC(18, 2),
    common_dividends_paid NUMERIC(18, 2),
    preferred_dividends_paid NUMERIC(18, 2),
    other_financing_activities NUMERIC(18, 2),
    net_cash_provided_by_financing_activities NUMERIC(18, 2),
    effect_of_forex_changes_on_cash NUMERIC(18, 2),
    net_change_in_cash NUMERIC(18, 2),
    cash_at_end_of_period NUMERIC(18, 2),
    cash_at_beginning_of_period NUMERIC(18, 2),
    operating_cash_flow NUMERIC(18, 2),
    capital_expenditure NUMERIC(18, 2),
    free_cash_flow NUMERIC(18, 2),
    income_taxes_paid NUMERIC(18, 2),
    interest_paid NUMERIC(18, 2),
    CONSTRAINT fk_cash_flow_reporting_period
        FOREIGN KEY (reporting_period_id)
        REFERENCES pfin.reporting_period(id) ON DELETE CASCADE,
    CONSTRAINT uq_cash_flow_reporting_period
        UNIQUE (reporting_period_id)
);

-- Company Estimates (EPS / Rev)
--     [richmosko]: the FMP "stable/earnings" query has EPS and revenue estimates for future
--     reports as well as historical reports... but doesn't have that for the normal
--     income statements.
CREATE TABLE pfin.estimate (
    id SERIAL PRIMARY KEY,
    reporting_period_id INTEGER NOT NULL,
    eps_actual NUMERIC(14, 4),
    eps_estimated NUMERIC(14, 4),
    revenue_actual NUMERIC(18, 2),
    revenue_estimated NUMERIC(18, 2),
    last_updated DATE,
    CONSTRAINT fk_estimate_reporting_period
        FOREIGN KEY (reporting_period_id)
        REFERENCES pfin.reporting_period(id) ON DELETE CASCADE,
    CONSTRAINT uq_estimate_reporting_period
        UNIQUE (reporting_period_id)
);


-- ==========================================================
-- Simple Tracking of Database Versions and Migration Scripts
--
--     An INSERT INTO statement should be the last command
--     on every *.sql migration script used.
--
-- ==========================================================
CREATE TABLE pfin.schema_version (
    id SERIAL PRIMARY KEY,
    major_release VARCHAR (2) NOT NULL,
    minor_release VARCHAR (2) NOT NULL,
    point_release VARCHAR (4) NOT NULL,
    script_name VARCHAR (50) NOT NULL,
    released_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT uq_pfin_schema_version
        UNIQUE (major_release, minor_release, point_release)
);

INSERT INTO pfin.schema_version (
    id,
    major_release,
    minor_release,
    point_release,
    script_name
) VALUES (
    '01',
    '00',
    '0000',
    'sql/schema/schema.sql'
);
