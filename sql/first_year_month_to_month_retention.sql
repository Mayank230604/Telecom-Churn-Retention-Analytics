-- Run after telecom_baseline.sql in the telecom_churn database.
-- Active includes Stayed and Joined. Churn rate excludes Joined.
-- Monthly charges are snapshot values, including any negative amounts.
CREATE OR REPLACE VIEW telecom.first_year_month_to_month_retention AS
WITH segment AS (
    SELECT
        COUNT(*) FILTER (WHERE customer_status = 'Stayed') AS stayed_customers,
        COUNT(*) FILTER (WHERE customer_status = 'Joined') AS joined_customers,
        COUNT(*) FILTER (WHERE customer_status = 'Churned') AS churned_customers,
        COALESCE(SUM(monthly_charge) FILTER (
            WHERE customer_status IN ('Stayed', 'Joined')), 0) AS active_monthly_charges,
        COALESCE(SUM(monthly_charge) FILTER (
            WHERE customer_status = 'Churned'), 0) AS churned_monthly_charges
    FROM telecom.customers
    WHERE contract = 'Month-to-Month'
        AND tenure_in_months BETWEEN 1 AND 12
)
SELECT
    stayed_customers,
    joined_customers,
    stayed_customers + joined_customers AS active_customers,
    active_monthly_charges,
    churned_customers,
    churned_monthly_charges,
    ROUND(100.0 * churned_customers
        / NULLIF(stayed_customers + churned_customers, 0), 2) AS existing_customer_churn_pct
FROM segment;

TABLE telecom.first_year_month_to_month_retention;
