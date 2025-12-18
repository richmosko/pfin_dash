-- Schema Definition?


-- =========================
-- USERS AND ACCESS SECURITY
--   BEST PRACTICES SUMMARY
-- * Use VARCHAR(255) instead of CHAR(64) for password_hash
-- * Use bcrypt, argon2, or scrypt (NOT plain SHA-256)
-- * Never store passwords in plaintext
-- * Don't need separate salt column with modern algorithms
-- * Use at least 12 rounds for bcrypt (balance security/performance)
-- * Implement account lockout after failed login attempts
-- * TODO... Add email verification and 2FA for enhanced security
-- =========================

-- List of Owners (Users), with credentials for authentication
CREATE TABLE owner (
    id SERIAL PRIMARY KEY,
    email VARCHAR(127) UNIQUE NOT NULL,
    password_hash VARCHAR(255) NOT NULL,
    hash_algorithm VARCHAR(20) NOT NULL DEFAULT 'bcrypt',
    token_version INTEGER NOT NULL DEFAULT 0,
    last_token_refresh TIMESTAMPTZ,
    password_changed_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    failed_login_attempts INTEGER NOT NULL  NOT NULL DEFAULT 0 CHECK (failed_login_attempts >= 0),
    locked_until TIMESTAMPTZ,  -- Account lockout after failed attempts
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    last_login TIMESTAMPTZ -- is this really needed?
);

CREATE INDEX idx_owner_email ON owner(email);

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


-- ==================================================
-- DEFINED CATEGORIES / TYPES (INFREQUENTLY MODIFIED)
-- ==================================================

-- Account Types: Valid account types and associated tax and liability handling
CREATE TABLE account_type (
    id SERIAL PRIMARY KEY,
    name VARCHAR(127) UNIQUE NOT NULL,
    is_taxable BOOLEAN NOT NULL, -- Will it every be taxed? If so, count unrealized gains
    is_tax_deferred BOOLEAN NOT NULL, -- Do we count sales this year as realized gains?
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

-- Transaction Categories: Valid transactions types... FIXME: CONSTRAINTS TBD
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

-- List of Accounts: This is equivalent to a single google sheets file
CREATE TABLE account (
    id SERIAL PRIMARY KEY,
    account_type_id INTEGER NOT NULL,
    acct_name VARCHAR(127) NOT NULL, -- Canonical/system name (per-creator unique)
    acct_number VARCHAR(127),
    created_by INTEGER NOT NULL, -- Who created this account (for audit/history)
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
     FOREIGN KEY(created_by) REFERENCES owner(id) ON DELETE RESTRICT, -- Don't allow deleting creator
    FOREIGN KEY(account_type_id) REFERENCES account_type(id) ON DELETE CASCADE,
    UNIQUE (acct_name, created_by)
);

-- Add a trigger to update updated_at timestamp
CREATE TRIGGER update_account_updated_at
    BEFORE UPDATE ON account
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

CREATE INDEX idx_account_created_by ON account(created_by);

-- Accounts Access: The specification for who can access what
CREATE TABLE account_access (
    account_id INTEGER NOT NULL,
    owner_id INTEGER NOT NULL,
    access_level VARCHAR(20) NOT NULL CHECK (access_level IN ('owner', 'editor', 'viewer')),
    nickname VARCHAR(127) NOT NULL, -- Personal display name for this account (defaults to acct.acct_name)
    granted_by INTEGER,
    granted_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    notes TEXT,
    FOREIGN KEY(account_id) REFERENCES account(id) ON DELETE CASCADE,
    FOREIGN KEY(owner_id) REFERENCES owner(id) ON DELETE CASCADE,
    FOREIGN KEY(granted_by) REFERENCES owner(id) ON DELETE SET NULL,
    CONSTRAINT account_access_pk PRIMARY KEY (account_id, owner_id),
    CONSTRAINT unique_nickname_per_owner UNIQUE (owner_id, nickname) -- Each owner has unique nicknames
);

CREATE INDEX idx_account_access_owner_id ON account_access(owner_id);

-- List of Assets: If "Equity" type, Company Information via the "stock-list" query
CREATE TABLE asset (
    id SERIAL PRIMARY KEY,
    symbol VARCHAR(15) UNIQUE NOT NULL,
    asset_cat_id INTEGER NOT NULL,
    description TEXT,
    exp_date DATE, -- If NULL, then no expiration date
    FOREIGN KEY(asset_cat_id) REFERENCES asset_cat(id) ON DELETE CASCADE
);

CREATE INDEX idx_asset_cat_id ON asset(asset_cat_id);

-- Account Transactions: Self explanatory...
--   Note: Reconciled holdings live here as well. they will show up as 'reconcile' trans_cat_id
CREATE TABLE account_trans (
    id SERIAL PRIMARY KEY, -- This is also used for Lot grouping and sorting
    account_id INTEGER NOT NULL,
    asset_id INTEGER NOT NULL,
    trans_cat_id INTEGER NOT NULL,
    trans_date DATE NOT NULL,
    price NUMERIC(14, 4),
    qty NUMERIC(14, 4),
    amount NUMERIC(14, 2),
    cost NUMERIC(14, 2),
    balance NUMERIC(14, 2), -- imported running CASH balance to use for reconcilliation
    description TEXT,
    import_text TEXT,
    import_hash VARCHAR(32) NOT NULL, -- MD5 checksum of imported CSV... this is for deduplication
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

-- List of Company Names: Extended Company Information via the "profile" query
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

-- Company Historical Price Data via the "historical-price-eod/full" query
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

-- Company Reporting Periods (Intermediate table to sync
-- earnings and balance sheets)
CREATE TABLE reporting_period (
    id SERIAL PRIMARY KEY,
    asset_id INTEGER NOT NULL,
    period_end_date DATE NOT NULL,
    fiscal_year INTEGER NOT NULL,
    period VARCHAR(2) NOT NULL CHECK (period IN ('FY', 'Q1', 'Q2', 'Q3', 'Q4')),
    CONSTRAINT fk_stock_period FOREIGN KEY (asset_id) REFERENCES asset(id) ON DELETE CASCADE,
    CONSTRAINT unique_stock_period UNIQUE (asset_id, period_end_date)
);

CREATE INDEX idx_reporting_period_asset_id ON reporting_period(asset_id, fiscal_year DESC, period);
CREATE INDEX idx_reporting_period_fiscal_year ON reporting_period(fiscal_year DESC, period);

-- Company Income Statements (references reporting_periods)
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

-- Company Balance Sheets (references reporting_periods)
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

-- Company Cash Flows (references reporting_periods)
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
--   Note: the "stable/earnings" query has EPS and revenue estimates for future reports
--         as well as historical reports... but doesn't have that for the normal income
--         statements.
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

-- Technical Indicators and Current Price?


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

CREATE TRIGGER account_creator_access
AFTER INSERT ON account
FOR EACH ROW
EXECUTE FUNCTION grant_creator_access();

