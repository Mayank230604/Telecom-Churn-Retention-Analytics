-- Run after telecom_baseline.sql in the same database.
-- Shares use all churned customers within each cohort, including unreported reasons.
CREATE OR REPLACE VIEW telecom.churn_reasons_by_cohort AS
WITH churned AS (
    SELECT
        CASE
            WHEN contract = 'Month-to-Month' AND tenure_in_months BETWEEN 1 AND 12
                THEN 'First-year month-to-month'
            ELSE 'Other churned customers'
        END AS cohort,
        COALESCE(NULLIF(TRIM(churn_category), ''), 'Unreported') AS churn_category,
        COALESCE(NULLIF(TRIM(churn_reason), ''), 'Unreported') AS churn_reason,
        monthly_charge
    FROM telecom.customers
    WHERE customer_status = 'Churned'
),
reason_totals AS (
    SELECT cohort, churn_category, churn_reason,
        COUNT(*) AS churned_customers,
        SUM(monthly_charge) AS churned_monthly_charges
    FROM churned
    GROUP BY cohort, churn_category, churn_reason
)
SELECT cohort, churn_category, churn_reason, churned_customers,
    SUM(churned_customers) OVER (PARTITION BY cohort) AS cohort_churned_customers,
    ROUND(100.0 * churned_customers
        / SUM(churned_customers) OVER (PARTITION BY cohort), 2) AS cohort_churn_share_pct,
    churned_monthly_charges,
    DENSE_RANK() OVER (PARTITION BY cohort ORDER BY churned_customers DESC) AS count_rank,
    DENSE_RANK() OVER (PARTITION BY cohort ORDER BY churned_monthly_charges DESC) AS monthly_charge_rank
FROM reason_totals;

-- Compare the same reason across cohorts. A missing reason has zero share
-- when the cohort exists. An empty cohort has an undefined share.
WITH reason_comparison AS (
    SELECT churn_category, churn_reason,
        COALESCE(SUM(churned_customers) FILTER (
            WHERE cohort = 'First-year month-to-month'), 0) AS first_year_count,
        COALESCE(SUM(churned_customers) FILTER (
            WHERE cohort = 'Other churned customers'), 0) AS other_count,
        COALESCE(SUM(churned_monthly_charges) FILTER (
            WHERE cohort = 'First-year month-to-month'), 0) AS first_year_monthly_charges
    FROM telecom.churn_reasons_by_cohort
    GROUP BY churn_category, churn_reason
),
shares AS (
    SELECT *,
        100.0 * first_year_count / NULLIF(SUM(first_year_count) OVER (), 0) AS first_year_share,
        100.0 * other_count / NULLIF(SUM(other_count) OVER (), 0) AS other_share
    FROM reason_comparison
)
SELECT churn_category, churn_reason, first_year_count,
    ROUND(first_year_share, 2) AS first_year_share_pct,
    other_count, ROUND(other_share, 2) AS other_share_pct,
    ROUND(first_year_share - other_share, 2) AS share_gap_pp,
    first_year_monthly_charges
FROM shares
ORDER BY first_year_count DESC, churn_category, churn_reason;
