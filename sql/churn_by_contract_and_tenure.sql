-- Run after telecom_baseline.sql in the same database.
-- Use Stayed + Churned as the existing-customer cohort.
CREATE OR REPLACE VIEW telecom.churn_by_contract_and_tenure AS
WITH customers_by_tenure AS (
    SELECT
        contract,
        customer_status,
        monthly_charge,
        CASE
            WHEN tenure_in_months BETWEEN 1 AND 12 THEN 1
            WHEN tenure_in_months BETWEEN 13 AND 24 THEN 2
            WHEN tenure_in_months BETWEEN 25 AND 48 THEN 3
            WHEN tenure_in_months >= 49 THEN 4
            ELSE 5
        END AS tenure_band_order
    FROM telecom.customers
    WHERE customer_status IN ('Stayed', 'Churned')
)
SELECT
    tenure_band_order,
    CASE tenure_band_order
        WHEN 1 THEN '1-12 months'
        WHEN 2 THEN '13-24 months'
        WHEN 3 THEN '25-48 months'
        WHEN 4 THEN '49+ months'
        ELSE 'Unknown or invalid'
    END AS tenure_band,
    contract,
    COUNT(*) AS existing_customers,
    COUNT(*) FILTER (WHERE customer_status = 'Churned') AS churned_customers,
    ROUND(100.0 * COUNT(*) FILTER (WHERE customer_status = 'Churned')
        / COUNT(*), 2) AS existing_customer_churn_pct,
    COALESCE(SUM(monthly_charge) FILTER (WHERE customer_status = 'Churned'), 0)
        AS churned_monthly_charges
FROM customers_by_tenure
GROUP BY tenure_band_order, contract;

SELECT *
FROM telecom.churn_by_contract_and_tenure
ORDER BY tenure_band_order, existing_customer_churn_pct DESC, contract;
