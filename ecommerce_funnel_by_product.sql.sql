-- ============================================================
-- Ecommerce Funnel by Product and Channel
-- ============================================================
-- Measures the sequential Ecommerce funnel:
--   Ecommerce Entry → Interacton → Config Complete
--
-- Ecommerce Entry is the CTA that opens the Ecommerce experience.
-- Config steps are measured only for those same sessions
-- (LEFT JOIN), so conversion rates reflect onward behaviour
-- from Ecommerce entry.
--
-- Counting: session-based throughout for funnel consistency.
--   Note: Ecommerce Entry official dashboard metric is visitor-based.
--   This query uses sessions to keep the funnel comparable across
--   all three steps. To match dashboard numbers exactly,
--   swap session_id → visitor_id in the final COUNTs.
--
-- Channel output: always returns both medium_type (Paid / Not Paid)
--   and the individual channel_grouping so totals can be verified.
--   Sum by medium_type to get Paid/Not Paid; individual channels
--   should sum to match.
--
-- Output: one row per product × channel with session counts
--         and conversion rates at each funnel step.
-- ============================================================
-- To run: update rep_from, rep_to, brand, and interaction IDs.
-- ============================================================

DECLARE rep_from DATE;
DECLARE rep_to   DATE;

SET rep_from = '2026-01-01';
SET rep_to   = '2026-03-31';

-- ============================================================
-- STEP 1: Ecommerce Entry sessions with channel
-- ============================================================
WITH fm AS (
  SELECT DISTINCT
    e.session_id,
    e.visit_start_date,
    e.product_code,
    CASE
      WHEN s.channel_grouping IN ('Paid Display & Video', 'Display')
        THEN 'Paid Display, Video & Digital Audio'
      WHEN s.channel_grouping IN ('PMAX', 'Cross Network')
        THEN 'Paid Cross Network'
      WHEN s.channel_grouping = 'Unclassified'
        THEN 'Paid Unclassified'
      ELSE s.channel_grouping
    END AS channel_grouping,
    CASE
      WHEN s.channel_grouping IN (
        'Paid Search', 'Paid Social', 'Other Advertising',
        'Paid Display & Video', 'Display',
        'Paid Display, Video & Digital Audio',
        'PMAX', 'Cross Network', 'Paid Cross Network',
        'Unclassified', 'Paid Unclassified'
      ) THEN 'Paid'
      ELSE 'Not Paid'
    END AS medium_type
  FROM `your-project.your_dataset.GA4_ecomm_hit_interaction_product` AS e
  JOIN `your-project.your_dataset.GA4_session` AS s
    ON  e.session_id       = s.session_id
    AND e.visit_start_date = s.visit_start_date
  WHERE e.visit_start_date BETWEEN rep_from AND rep_to
    AND e.interaction_id = 227   -- Ecommerce Entry interaction ID
),

-- ============================================================
-- STEP 2: Interacton
-- ============================================================
cs AS (
  SELECT DISTINCT
    sin.session_id,
    sin.visit_start_date,
    sin.product_code
  FROM `your-project.your_dataset.GA4_session_interaction_product` AS sin
  WHERE sin.visit_start_date BETWEEN rep_from AND rep_to
    AND sin.brand          = 'your-brand'   -- e.g. 'Product'
    AND sin.interaction_id = 5              -- Interacton
),

-- ============================================================
-- STEP 3: Config Complete
-- ============================================================
cc AS (
  SELECT DISTINCT
    sin.session_id,
    sin.visit_start_date,
    sin.product_code
  FROM `your-project.your_dataset.GA4_session_interaction_product` AS sin
  WHERE sin.visit_start_date BETWEEN rep_from AND rep_to
    AND sin.brand          = 'your-brand'
    AND sin.interaction_id = 11             -- Config Complete
)

-- ============================================================
-- FINAL: Funnel counts and conversion rates
--        by product × medium_type × channel_grouping
-- ============================================================
SELECT
  fm.product_code,
  REGEXP_REPLACE(ln.product_desc, r' \(.*\)', '') AS product_desc,
  fm.medium_type,
  fm.channel_grouping,

  -- Funnel step counts
  COUNT(DISTINCT fm.session_id)  AS Ecommerce_entry_sessions,
  COUNT(DISTINCT cs.session_id)  AS config_start_sessions,
  COUNT(DISTINCT cc.session_id)  AS config_complete_sessions,

  -- Conversion rates
  ROUND(SAFE_DIVIDE(COUNT(DISTINCT cs.session_id), COUNT(DISTINCT fm.session_id)) * 100, 1) AS entry_to_config_start_pct,
  ROUND(SAFE_DIVIDE(COUNT(DISTINCT cc.session_id), COUNT(DISTINCT cs.session_id)) * 100, 1) AS config_start_to_complete_pct,
  ROUND(SAFE_DIVIDE(COUNT(DISTINCT cc.session_id), COUNT(DISTINCT fm.session_id)) * 100, 1) AS entry_to_config_complete_pct

FROM fm
LEFT JOIN cs
  ON  fm.session_id       = cs.session_id
  AND fm.visit_start_date = cs.visit_start_date
  AND fm.product_code   = cs.product_code
LEFT JOIN cc
  ON  fm.session_id       = cc.session_id
  AND fm.visit_start_date = cc.visit_start_date
  AND fm.product_code   = cc.product_code
JOIN `your-project.your_dataset.GA4_lookup_product` AS ln
  ON fm.product_code = ln.product_code
GROUP BY 1, 2, 3, 4
ORDER BY product_desc, medium_type, Ecommerce_entry_sessions DESC
;
