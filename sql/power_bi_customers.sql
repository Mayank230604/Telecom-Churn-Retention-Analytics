-- One row per customer in the Q2 2022 snapshot. Load telecom_baseline.sql first.
CREATE OR REPLACE VIEW telecom.power_bi_customers AS
WITH customer_segments AS (
    SELECT
        customer_id,
        customer_status,
        contract,
        tenure_in_months,
        CASE
            WHEN tenure_in_months BETWEEN 1 AND 12 THEN 1
            WHEN tenure_in_months BETWEEN 13 AND 24 THEN 2
            WHEN tenure_in_months BETWEEN 25 AND 48 THEN 3
            WHEN tenure_in_months >= 49 THEN 4
            ELSE 5
        END AS tenure_band_order,
        contract = 'Month-to-Month'
            AND COALESCE(tenure_in_months BETWEEN 1 AND 12, false)
            AS is_first_year_month_to_month,
        city,
        zip_code,
        internet_service,
        internet_type,
        payment_method,
        offer,
        CASE WHEN customer_status = 'Churned'
            THEN COALESCE(NULLIF(TRIM(churn_category), ''), 'Unreported')
        END AS churn_category,
        CASE WHEN customer_status = 'Churned'
            THEN COALESCE(NULLIF(TRIM(churn_reason), ''), 'Unreported')
        END AS churn_reason,
        monthly_charge,
        total_revenue AS historical_revenue
    FROM telecom.customers
)
SELECT
    customer_segments.*,
    CASE tenure_band_order
        WHEN 1 THEN '1-12 months'
        WHEN 2 THEN '13-24 months'
        WHEN 3 THEN '25-48 months'
        WHEN 4 THEN '49+ months'
        ELSE 'Unknown or invalid'
    END AS tenure_band,
    CASE WHEN customer_status IN ('Stayed', 'Churned') THEN 1 ELSE 0 END AS existing_customer_count,
    CASE WHEN customer_status IN ('Stayed', 'Joined') THEN 1 ELSE 0 END AS active_customer_count,
    CASE WHEN customer_status = 'Churned' THEN 1 ELSE 0 END AS churned_customer_count,
    CASE WHEN customer_status IN ('Stayed', 'Joined') THEN monthly_charge ELSE 0 END AS active_monthly_charge,
    CASE WHEN customer_status = 'Churned' THEN monthly_charge ELSE 0 END AS churned_monthly_charge
FROM customer_segments;
