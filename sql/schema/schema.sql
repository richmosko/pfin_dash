-- Schema Definition - MODIFIED FOR SUPABASE AUTH INTEGRATION


-- =========================
-- USERS AND ACCESS SECURITY
--   SUPABASE AUTH HYBRID APPROACH
-- * Supabase auth.users handles: authentication, password reset, social logins
-- * owner table handles: business logic, app-specific data
-- * Automatic sync via triggers
-- 
-- CHANGES FROM ORIGINAL:
-- - Added supabase_user_id column (UUID foreign key to auth.users)
-- - Removed password_hash, hash_algorithm (Supabase handles this)
-- - Removed failed_login_attempts, locked_until (Supabase handles this)
-- - Added triggers to auto-sync with auth.users
-- - password_changed_at removed (Supabase tracks this)
-- =========================

-- List of Owners (Users), linked to Supabase auth
CREATE TABLE owner (
    id SERIAL PRIMARY KEY,
    supabase_user_id UUID UNIQUE NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    email VARCHAR(127) UNIQUE NOT NULL,
    -- Supabase auth.users handles all authentication
    token_version INTEGER NOT NULL DEFAULT 0,
    last_token_refresh TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    last_login TIMESTAMPTZ
);

CREATE INDEX idx_owner_email ON owner(email);
CREATE INDEX idx_owner_supabase_user_id ON owner(supabase_user_id);

-- Function to allow trigger updates of 'updated_at' columns
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Add a trigger to update updated_at timestamp
CREATE TRIGGER update_owner_updated_at
    BEFORE UPDATE ON owner
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

-- =========================
-- SUPABASE AUTH INTEGRATION
-- NEW TRIGGERS FOR AUTO-SYNC
-- =========================

-- Auto-create owner record when user signs up via Supabase
CREATE OR REPLACE FUNCTION handle_new_user()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO public.owner (supabase_user_id, email)
    VALUES (NEW.id, NEW.email);
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE TRIGGER on_auth_user_created
    AFTER INSERT ON auth.users
    FOR EACH ROW
    EXECUTE FUNCTION handle_new_user();

-- Sync email changes from Supabase auth to owner table
CREATE OR REPLACE FUNCTION sync_user_email()
RETURNS TRIGGER AS $$
BEGIN
    UPDATE public.owner 
    SET email = NEW.email,
        updated_at = NOW()
    WHERE supabase_user_id = NEW.id;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE TRIGGER on_auth_user_email_updated
    AFTER UPDATE OF email ON auth.users
    FOR EACH ROW
    WHEN (OLD.email IS DISTINCT FROM NEW.email)
    EXECUTE FUNCTION sync_user_email();


-- ==================================================
-- DEFINED CATEGORIES / TYPES (INFREQUENTLY MODIFIED)
-- ==================================================

-- Account Types: Valid account types and associated tax and liability handling
CREATE TABLE account_type (
    id SERIAL PRIMARY KEY,
    name VARCHAR(127) UNIQUE NOT NULL,
    is_taxable BOOLEAN NOT NULL, -- [richmosko]: Will it every be taxed? If so, count unrealized gains
    is_tax_deferred BOOLEAN NOT NULL, -- [richmosko]: Do we count sales this year as realized gains?
    is_liability BOOLEAN NOT NULL
);

-- Asset Categories: Valid assets to track. ie: cash, bonds, equity, alt, etc.
-- and associated sub-categories
CREATE TABLE asset_cat (
    id SERIAL PRIMARY KEY,
    cat VARCHAR(127) NOT NULL,
    sub_cat VARCHAR(127) NOT NULL,
    UNIQUE(cat, sub_cat)
);

-- Transaction Categories: Valid transactions types
CREATE TABLE trans_cat (
    id SERIAL PRIMARY KEY,
    cat VARCHAR(127) NOT NULL,
    sub_cat VARCHAR(127) NOT NULL,
    is_debit BOOLEAN NOT NULL DEFAULT FALSE,
    UNIQUE(cat, sub_cat)
);


-- ================================
-- ACCOUNT AND TRANSACTION TRACKING
-- ================================

-- List of Accounts
CREATE TABLE account (
    id SERIAL PRIMARY KEY,
    account_type_id INTEGER NOT NULL,
    acct_name VARCHAR(127) NOT NULL, -- Account Name (per-creator unique)
    acct_number VARCHAR(127),
    created_by INTEGER NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    FOREIGN KEY(created_by) REFERENCES owner(id) ON DELETE RESTRICT,
    FOREIGN KEY(account_type_id) REFERENCES account_type(id) ON DELETE CASCADE,
    UNIQUE (acct_name, created_by)
);

-- [richmosko]: a trigger to update the updated_at timestamp
CREATE TRIGGER update_account_updated_at
    BEFORE UPDATE ON account
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

CREATE INDEX idx_account_created_by ON account(created_by);

-- Accounts Access: Who can access what
CREATE TABLE account_access (
    account_id INTEGER NOT NULL,
    owner_id INTEGER NOT NULL,
    access_level VARCHAR(20) NOT NULL CHECK (access_level IN ('owner', 'editor', 'viewer')),
    nickname VARCHAR(127) NOT NULL,
    granted_by INTEGER,
    granted_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    notes TEXT,
    FOREIGN KEY(account_id) REFERENCES account(id) ON DELETE CASCADE,
    FOREIGN KEY(owner_id) REFERENCES owner(id) ON DELETE CASCADE,
    FOREIGN KEY(granted_by) REFERENCES owner(id) ON DELETE SET NULL,
    CONSTRAINT account_access_pk PRIMARY KEY (account_id, owner_id),
    CONSTRAINT unique_nickname_per_owner UNIQUE (owner_id, nickname)
);

CREATE INDEX idx_account_access_owner_id ON account_access(owner_id);

-- List of Assets
--     [richmosko]: If "Equity" type, Company Information via the "stock-list" query
CREATE TABLE asset (
    id SERIAL PRIMARY KEY,
    symbol VARCHAR(15) UNIQUE NOT NULL,
    asset_cat_id INTEGER NOT NULL,
    description TEXT,
    exp_date DATE, -- [richmosko]: If NULL, then no expiration date
    FOREIGN KEY(asset_cat_id) REFERENCES asset_cat(id) ON DELETE CASCADE
);

CREATE INDEX idx_asset_cat_id ON asset(asset_cat_id);

-- Account Transactions
--     [richmosko]: Reconciled holdings live here as well. they will show up as 'reconcile' trans_cat_id
CREATE TABLE account_trans (
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
    FOREIGN KEY(account_id) REFERENCES account(id) ON DELETE CASCADE,
    FOREIGN KEY(asset_id) REFERENCES asset(id) ON DELETE CASCADE,
    FOREIGN KEY(trans_cat_id) REFERENCES trans_cat(id) ON DELETE CASCADE,
    UNIQUE(account_id, import_hash)
);

CREATE INDEX idx_account_trans_account_id ON account_trans(account_id);
CREATE INDEX idx_account_trans_asset_id ON account_trans(asset_id);
CREATE INDEX idx_account_trans_date ON account_trans(trans_date);
CREATE INDEX idx_account_trans_import_hash ON account_trans(import_hash);
CREATE INDEX idx_account_trans_account_date ON account_trans(account_id, trans_date DESC);
CREATE INDEX idx_account_trans_date_account ON account_trans(trans_date DESC, account_id);

-- Owner Watchlists
CREATE TABLE owner_watchlist (
    owner_id INTEGER NOT NULL,
    asset_id INTEGER NOT NULL,
    FOREIGN KEY(owner_id) REFERENCES owner(id) ON DELETE CASCADE,
    FOREIGN KEY(asset_id) REFERENCES asset(id) ON DELETE CASCADE,
    CONSTRAINT owner_watchlist_pk PRIMARY KEY (owner_id, asset_id)
);

-- ===============================================
-- ASSET TRACKING FOR ACCOUNTS AND STOCK SCREENING
-- ===============================================

-- List of Company Names: Extended Company Information
--     [richmosko]:  from FMP "profile" JSON query
CREATE TABLE stock_profile (
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
    FOREIGN KEY (asset_id) REFERENCES asset(id) ON DELETE CASCADE
);

-- Company Historical Price Data
--     [richmosko]:  from FMP "historical-price-eod/full" JSON query
CREATE TABLE eod_price (
    id SERIAL PRIMARY KEY,
    asset_id INTEGER NOT NULL,
    date DATE NOT NULL,
    open NUMERIC(14, 2),
    high NUMERIC(14, 2),
    low NUMERIC(14, 2),
    close NUMERIC(14, 2),
    volume BIGINT,
    change NUMERIC(14, 2),
    change_percent NUMERIC(14, 5),
    vwap NUMERIC(14, 4),
    FOREIGN KEY (asset_id) REFERENCES asset(id) ON DELETE CASCADE,
    UNIQUE (asset_id, date)
);

CREATE INDEX idx_eod_price_asset_date ON eod_price(asset_id, date DESC);
CREATE INDEX idx_eod_price_date ON eod_price(date DESC);

-- Company Reporting Periods
--     [richmosko]: Intermediate table to sync earnings, cash flows, and balance sheets
CREATE TABLE reporting_period (
    id SERIAL PRIMARY KEY,
    asset_id INTEGER NOT NULL,
    end_date DATE NOT NULL,
    filing_date DATE NOT NULL,
    fiscal_year INTEGER NOT NULL,
    period VARCHAR(2) NOT NULL CHECK (period IN ('FY', 'Q1', 'Q2', 'Q3', 'Q4')),
    CONSTRAINT fk_stock_period FOREIGN KEY (asset_id) REFERENCES asset(id) ON DELETE CASCADE,
    CONSTRAINT unique_stock_period UNIQUE (asset_id, filing_date)
);

CREATE INDEX idx_reporting_period_asset_id ON reporting_period(asset_id, fiscal_year DESC, period);
CREATE INDEX idx_reporting_period_fiscal_year ON reporting_period(fiscal_year DESC, period);

-- Company Income Statements
CREATE TABLE income_statement (
    id SERIAL PRIMARY KEY,
    reporting_period_id INTEGER NOT NULL,
    reported_currency VARCHAR(3),
    cik VARCHAR(20),
    filing_date DATE,
    accepted_date TIMESTAMPTZ,
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
    FOREIGN KEY (reporting_period_id) REFERENCES reporting_period(id) ON DELETE CASCADE,
    UNIQUE (reporting_period_id)
);

-- Company Balance Sheets
CREATE TABLE balance_sheet (
    id SERIAL PRIMARY KEY,
    reporting_period_id INTEGER NOT NULL,
    reported_currency VARCHAR(3),
    cik VARCHAR(20),
    filing_date DATE,
    accepted_date TIMESTAMPTZ,
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
    FOREIGN KEY (reporting_period_id) REFERENCES reporting_period(id) ON DELETE CASCADE,
    UNIQUE (reporting_period_id)
);

-- Company Cash Flows
CREATE TABLE cash_flow (
    id SERIAL PRIMARY KEY,
    reporting_period_id INTEGER NOT NULL,
    reported_currency VARCHAR(3),
    cik VARCHAR(20),
    filing_date DATE,
    accepted_date TIMESTAMPTZ,
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
    FOREIGN KEY (reporting_period_id) REFERENCES reporting_period(id) ON DELETE CASCADE,
    UNIQUE (reporting_period_id)
);

-- Company Estimates (EPS / Rev)
--     [richmosko]: the FMP "stable/earnings" query has EPS and revenue estimates for future
--     reports as well as historical reports... but doesn't have that for the normal
--     income statements.
CREATE TABLE estimate (
    id SERIAL PRIMARY KEY,
    reporting_period_id INTEGER NOT NULL,
    eps_actual NUMERIC(14, 4),
    eps_estimated NUMERIC(14, 4),
    revenue_actual NUMERIC(18, 2),
    revenue_estimated NUMERIC(18, 2),
    last_updated DATE NOT NULL,
    FOREIGN KEY (reporting_period_id) REFERENCES reporting_period(id) ON DELETE CASCADE,
    UNIQUE (reporting_period_id)
);


-- FUNCTIONS / TRIGGERS
-- --------------------

-- Trigger to automatically grant owner access when account is created
CREATE OR REPLACE FUNCTION grant_creator_access()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO account_access (account_id, owner_id, access_level, granted_by, nickname)
    VALUES (NEW.id, NEW.created_by, 'owner', NEW.created_by, NEW.acct_name);
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- [richmosko]: nickname column defaults to account.acct_name
CREATE TRIGGER account_creator_access
AFTER INSERT ON account
FOR EACH ROW
EXECUTE FUNCTION grant_creator_access();
