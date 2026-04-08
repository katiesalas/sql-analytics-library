-- ============================================================
-- MLPX Funnel by Nameplate and Channel
-- ============================================================
-- Measures the sequential MLPX funnel:
--   MLPX Entry → Config Start → Config Complete
--
-- MLPX Entry is the CTA that opens the MLPX experience.
-- Config steps are measured only for those same sessions
-- (LEFT JOIN), so conversion rates reflect onward behaviour
-- from MLPX entry.
--
-- Counting: session-based throughout for funnel consistency.
--   Note: MLPX Entry official dashboard metric is visitor-based.
--   This query uses sessions to keep the funnel comparable across
--   all three steps. To match dashboard numbers exactly,
--   swap session_id → visitor_id in the final COUNTs.
--
-- Channel output: always returns both medium_type (Paid / Not Paid)
--   and the individual channel_grouping so totals can be verified.
--   Sum by medium_type to get Paid/Not Paid; individual channels
--   should sum to match.
--
-- Output: one row per nameplate × channel with session counts
--         and conversion rates at each funnel step.
-- ============================================================
-- To run: update rep_from, rep_to, brand, and interaction IDs.
-- ============================================================

DECLARE rep_from DATE;
DECLARE rep_to   DATE;

SET rep_from = '2026-01-01';
SET rep_to   = '2026-03-31';

-- ============================================================
-- STEP 1: MLPX Entry sessions with channel
-- ============================================================
WITH fm AS (
  SELECT DISTINCT
    e.session_id,
    e.visit_start_date,
    e.nameplate_code,
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
  FROM `your-project.your_dataset.GA4_ecomm_hit_interaction_nameplate` AS e
  JOIN `your-project.your_dataset.GA4_session` AS s
    ON  e.session_id       = s.session_id
    AND e.visit_start_date = s.visit_start_date
  WHERE e.visit_start_date BETWEEN rep_from AND rep_to
    AND e.interaction_id = 227   -- MLPX Entry interaction ID
),

-- ============================================================
-- STEP 2: Config Start
-- ============================================================
cs AS (
  SELECT DISTINCT
    sin.session_id,
    sin.visit_start_date,
    sin.nameplate_code
  FROM `your-project.your_dataset.GA4_session_interaction_nameplate` AS sin
  WHERE sin.visit_start_date BETWEEN rep_from AND rep_to
    AND sin.brand          = 'your-brand'   -- e.g. 'Land Rover'
    AND sin.interaction_id = 5              -- Config Start
),

-- ============================================================
-- STEP 3: Config Complete
-- ============================================================
cc AS (
  SELECT DISTINCT
    sin.session_id,
    sin.visit_start_date,
    sin.nameplate_code
  FROM `your-project.your_dataset.GA4_session_interaction_nameplate` AS sin
  WHERE sin.visit_start_date BETWEEN rep_from AND rep_to
    AND sin.brand          = 'your-brand'
    AND sin.interaction_id = 11             -- Config Complete
)

-- ============================================================
-- FINAL: Funnel counts and conversion rates
--        by nameplate × medium_type × channel_grouping
-- ============================================================
SELECT
  fm.nameplate_code,
  REGEXP_REPLACE(ln.nameplate_desc, r' \(.*\)', '') AS nameplate_desc,
  fm.medium_type,
  fm.channel_grouping,

  -- Funnel step counts
  COUNT(DISTINCT fm.session_id)  AS mlpx_entry_sessions,
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
  AND fm.nameplate_code   = cs.nameplate_code
LEFT JOIN cc
  ON  fm.session_id       = cc.session_id
  AND fm.visit_start_date = cc.visit_start_date
  AND fm.nameplate_code   = cc.nameplate_code
JOIN `your-project.your_dataset.GA4_lookup_nameplate` AS ln
  ON fm.nameplate_code = ln.nameplate_code
GROUP BY 1, 2, 3, 4
ORDER BY nameplate_desc, medium_type, mlpx_entry_sessions DESC
;
