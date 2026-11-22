\set ON_ERROR_STOP on
-- Run with psql from the project root against a project database.
-- Input is the Q2 2022 customer snapshot and ZIP population lookup.
BEGIN;

CREATE SCHEMA IF NOT EXISTS telecom;

CREATE TEMP TABLE raw_customers (
    customer_id text,
    gender text,
    age text,
    married text,
    number_of_dependents text,
    city text,
    zip_code text,
    latitude text,
    longitude text,
    number_of_referrals text,
    tenure_in_months text,
    offer text,
    phone_service text,
    avg_monthly_long_distance_charges text,
    multiple_lines text,
    internet_service text,
    internet_type text,
    avg_monthly_gb_download text,
    online_security text,
    online_backup text,
    device_protection_plan text,
    premium_tech_support text,
    streaming_tv text,
    streaming_movies text,
    streaming_music text,
    unlimited_data text,
    contract text,
    paperless_billing text,
    payment_method text,
    monthly_charge text,
    total_charges text,
    total_refunds text,
    total_extra_data_charges text,
    total_long_distance_charges text,
    total_revenue text,
    customer_status text,
    churn_category text,
    churn_reason text
) ON COMMIT DROP;

CREATE TEMP TABLE raw_zip_population (
    zip_code text,
    population text
) ON COMMIT DROP;

\copy raw_customers FROM 'data/raw/telecom_customer_churn.csv' WITH (FORMAT csv, HEADER true)
\copy raw_zip_population FROM 'data/raw/telecom_zipcode_population.csv' WITH (FORMAT csv, HEADER true)

CREATE TABLE IF NOT EXISTS telecom.zip_population (
    zip_code text PRIMARY KEY CHECK (zip_code ~ '^[0-9]{5}$'),
    population integer NOT NULL CHECK (population >= 0)
);

CREATE TABLE IF NOT EXISTS telecom.customers (
    customer_id text PRIMARY KEY CHECK (customer_id <> ''),
    gender text,
    age integer,
    married text,
    number_of_dependents integer,
    city text,
    zip_code text NOT NULL REFERENCES telecom.zip_population (zip_code),
    latitude numeric,
    longitude numeric,
    number_of_referrals integer,
    tenure_in_months integer,
    offer text,
    phone_service text,
    avg_monthly_long_distance_charges numeric,
    multiple_lines text,
    internet_service text,
    internet_type text,
    avg_monthly_gb_download integer,
    online_security text,
    online_backup text,
    device_protection_plan text,
    premium_tech_support text,
    streaming_tv text,
    streaming_movies text,
    streaming_music text,
    unlimited_data text,
    contract text NOT NULL,
    paperless_billing text,
    payment_method text,
    monthly_charge numeric NOT NULL,
    total_charges numeric,
    total_refunds numeric,
    total_extra_data_charges numeric,
    total_long_distance_charges numeric,
    total_revenue numeric NOT NULL,
    customer_status text NOT NULL CHECK (customer_status IN ('Stayed', 'Joined', 'Churned')),
    churn_category text,
    churn_reason text,
    CHECK (
        total_charges IS NOT NULL AND total_refunds IS NOT NULL
        AND total_extra_data_charges IS NOT NULL AND total_long_distance_charges IS NOT NULL
        AND total_revenue = total_charges - total_refunds
            + total_extra_data_charges + total_long_distance_charges
    )
);

DO $$
BEGIN
    IF NOT EXISTS (SELECT FROM raw_customers)
        OR NOT EXISTS (SELECT FROM raw_zip_population) THEN
        RAISE EXCEPTION 'Both source files must contain data rows';
    END IF;
END $$;

-- Reload both snapshot tables atomically. ZIP identifiers retain leading zeros.
TRUNCATE telecom.customers, telecom.zip_population;

INSERT INTO telecom.zip_population (zip_code, population)
SELECT zip_code, population::integer
FROM raw_zip_population;

INSERT INTO telecom.customers (
    customer_id,
    gender,
    age,
    married,
    number_of_dependents,
    city,
    zip_code,
    latitude,
    longitude,
    number_of_referrals,
    tenure_in_months,
    offer,
    phone_service,
    avg_monthly_long_distance_charges,
    multiple_lines,
    internet_service,
    internet_type,
    avg_monthly_gb_download,
    online_security,
    online_backup,
    device_protection_plan,
    premium_tech_support,
    streaming_tv,
    streaming_movies,
    streaming_music,
    unlimited_data,
    contract,
    paperless_billing,
    payment_method,
    monthly_charge,
    total_charges,
    total_refunds,
    total_extra_data_charges,
    total_long_distance_charges,
    total_revenue,
    customer_status,
    churn_category,
    churn_reason
)
SELECT
    customer_id,
    gender,
    NULLIF(age, '')::integer,
    married,
    NULLIF(number_of_dependents, '')::integer,
    city,
    zip_code,
    NULLIF(latitude, '')::numeric,
    NULLIF(longitude, '')::numeric,
    NULLIF(number_of_referrals, '')::integer,
    NULLIF(tenure_in_months, '')::integer,
    offer,
    phone_service,
    NULLIF(avg_monthly_long_distance_charges, '')::numeric,
    multiple_lines,
    internet_service,
    internet_type,
    NULLIF(avg_monthly_gb_download, '')::integer,
    online_security,
    online_backup,
    device_protection_plan,
    premium_tech_support,
    streaming_tv,
    streaming_movies,
    streaming_music,
    unlimited_data,
    contract,
    paperless_billing,
    payment_method,
    NULLIF(monthly_charge, '')::numeric,
    NULLIF(total_charges, '')::numeric,
    NULLIF(total_refunds, '')::numeric,
    NULLIF(total_extra_data_charges, '')::numeric,
    NULLIF(total_long_distance_charges, '')::numeric,
    NULLIF(total_revenue, '')::numeric,
    customer_status,
    churn_category,
    churn_reason
FROM raw_customers;

-- Existing-customer churn uses Stayed + Churned as a proxy for the starting cohort.
-- Monthly charge sums preserve source adjustments, including negative values.
CREATE OR REPLACE VIEW telecom.churn_kpis AS
SELECT
    COUNT(*) AS total_customers,
    COUNT(*) FILTER (WHERE customer_status = 'Stayed') AS stayed_customers,
    COUNT(*) FILTER (WHERE customer_status = 'Joined') AS joined_customers,
    COUNT(*) FILTER (WHERE customer_status = 'Churned') AS churned_customers,
    ROUND(100.0 * COUNT(*) FILTER (WHERE customer_status = 'Churned')
        / NULLIF(COUNT(*), 0), 2) AS snapshot_churn_share_pct,
    ROUND(100.0 * COUNT(*) FILTER (WHERE customer_status = 'Churned')
        / NULLIF(COUNT(*) FILTER (WHERE customer_status IN ('Stayed', 'Churned')), 0), 2)
        AS existing_customer_churn_pct,
    SUM(monthly_charge) FILTER (WHERE customer_status = 'Churned') AS churned_monthly_charges,
    SUM(monthly_charge) FILTER (WHERE customer_status IN ('Stayed', 'Joined')) AS active_monthly_charges,
    SUM(total_revenue) FILTER (WHERE customer_status = 'Churned') AS churned_customer_historical_revenue
FROM telecom.customers;

CREATE OR REPLACE VIEW telecom.churn_by_contract AS
SELECT
    contract,
    COUNT(*) FILTER (WHERE customer_status IN ('Stayed', 'Churned')) AS existing_customers,
    COUNT(*) FILTER (WHERE customer_status = 'Churned') AS churned_customers,
    ROUND(100.0 * COUNT(*) FILTER (WHERE customer_status = 'Churned')
        / NULLIF(COUNT(*) FILTER (WHERE customer_status IN ('Stayed', 'Churned')), 0), 2)
        AS existing_customer_churn_pct
FROM telecom.customers
GROUP BY contract;

COMMIT;

TABLE telecom.churn_kpis;
SELECT * FROM telecom.churn_by_contract ORDER BY existing_customer_churn_pct DESC NULLS LAST;
