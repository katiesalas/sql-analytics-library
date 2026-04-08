-- ============================================================
-- Pre / Post Analysis
-- ============================================================
-- Purpose:  Measures the impact of a page change by comparing
--           sessions, CTA clicks, and onward behaviour before
--           and after a change was made.
--
-- Segments (comment out as needed):
--   page_sessions  — baseline: all sessions on the tracked page
--   click_group    — sessions that clicked the changed CTA
--   int_group      — onward config starts / completes
--   enq_group      — onward enquiry sessions
--   fm_group       — onward find matches (optional)
--
-- Typical workflow:
--   1. Run click_group first to verify CTA tracking is correct
--   2. Run page_sessions to confirm baseline session volume
--   3. Run int_group + enq_group (+ fm_group if needed) for onward behaviour
--
-- Note: pre/post analyses assume no other significant page changes
-- occurred in the date range. Always verify click_group first.
-- ============================================================

DECLARE rep_from DATE;
DECLARE rep_to   DATE;
DECLARE KPI_1    NUMERIC;  -- e.g. Config Start interaction ID
DECLARE KPI_2    NUMERIC;  -- e.g. Config Complete interaction ID
DECLARE KPI_3    NUMERIC;  -- optional additional KPI

SET rep_from = '2026-01-15';
SET rep_to   = '2026-03-02';
SET KPI_1 = 1;   -- update to your interaction IDs
SET KPI_2 = 2;
-- SET KPI_3 = ...;

-- ============================================================
-- UPDATE THESE FOR EACH ANALYSIS:
--   page_path IN (...)      = pages where the change was made
--   event_label LIKE '...'  = CTA being tracked
--   event_category          = event category for the CTA
-- ============================================================

WITH ab_group_data AS (
  -- Cohort: sessions that clicked the tracked CTA
  SELECT DISTINCT
    h.visit_start_date,
    h.brand,
    h.page_path,
    h.event_label,
    h.event_action,
    MIN(h.hit_datetime) OVER (PARTITION BY h.session_id) AS ab_min_hit_datetime,
    h.session_id
  FROM `your-project.your_dataset.GA4_hit` AS h
  JOIN `your-project.your_dataset.GA4_lookup_market` AS m
    ON h.market_code = m.market_code
  WHERE h.visit_start_date BETWEEN rep_from AND rep_to
    AND h.market_code = 'your-market'
    AND h.page_path IN (
      'your-page-path-1',
      'your-page-path-2'
    )
    AND h.event_category = 'your-event-category'
    AND h.event_label LIKE '%your-cta-label%'
),

-- ============================================================
-- SEGMENT 1: Page Sessions (baseline)
-- ============================================================
page_sessions AS (
  SELECT
    'page_sessions'          AS rep_group,
    GH.visit_start_date,
    GH.page_path,
    CAST(NULL AS STRING)     AS event_label,
    CAST(NULL AS STRING)     AS event_action,
    CAST(NULL AS NUMERIC)    AS interaction_id,
    COUNT(DISTINCT GH.session_id) AS total_sessions
  FROM `your-project.your_dataset.GA4_hit` GH
  JOIN `your-project.your_dataset.GA4_session` SN
    ON  GH.session_id       = SN.session_id
    AND GH.visit_start_date = SN.visit_start_date
  WHERE GH.visit_start_date BETWEEN rep_from AND rep_to
    AND GH.market_code = 'your-market'
    AND GH.brand = 'your-brand'
    AND GH.page_path IN (
      'your-page-path-1',
      'your-page-path-2'
    )
  GROUP BY 1, 2, 3, 4, 5, 6
),

-- ============================================================
-- SEGMENT 2: CTA Clicks
-- Run first to verify tracking before drawing conclusions
-- ============================================================
click_group AS (
  SELECT
    'click_group'            AS rep_group,
    GH.visit_start_date,
    GH.page_path,
    GH.event_label,
    GH.event_action,
    CAST(NULL AS NUMERIC)    AS interaction_id,
    COUNT(DISTINCT GH.session_id) AS total_sessions
  FROM `your-project.your_dataset.GA4_hit` GH
  JOIN `your-project.your_dataset.GA4_session` SN
    ON  GH.session_id       = SN.session_id
    AND GH.visit_start_date = SN.visit_start_date
  WHERE GH.visit_start_date BETWEEN rep_from AND rep_to
    AND GH.market_code = 'your-market'
    AND GH.brand = 'your-brand'
    AND GH.event_category = 'your-event-category'
    AND GH.event_label LIKE '%your-cta-label%'
    AND GH.page_path IN (
      'your-page-path-1',
      'your-page-path-2'
    )
  GROUP BY 1, 2, 3, 4, 5, 6
),

-- ============================================================
-- SEGMENT 3: Config Starts & Completes (onward behaviour)
-- ============================================================
int_group AS (
  SELECT
    'int_group'              AS rep_group,
    h.visit_start_date,
    ab.page_path,
    ab.event_label,
    ab.event_action,
    hn.interaction_id,
    COUNT(DISTINCT h.session_id) AS total_sessions
  FROM `your-project.your_dataset.GA4_hit` AS h
  LEFT JOIN `your-project.your_dataset.GA4_hit_interaction_nameplate` AS hn
    ON  h.hit_id            = hn.hit_id
    AND h.visit_start_date  = hn.visit_start_date
  INNER JOIN ab_group_data AS ab
    ON h.session_id = ab.session_id
  WHERE h.visit_start_date BETWEEN rep_from AND rep_to
    AND hn.interaction_id IN (KPI_1, KPI_2)
    AND h.hit_datetime > ab.ab_min_hit_datetime
  GROUP BY 1, 2, 3, 4, 5, 6
),

-- ============================================================
-- SEGMENT 4: Enquiry Sessions (onward behaviour)
-- ============================================================
enq_group AS (
  SELECT
    'enq_group'              AS rep_group,
    h.visit_start_date,
    ab.page_path,
    ab.event_label,
    ab.event_action,
    CAST(NULL AS NUMERIC)    AS interaction_id,
    COUNT(DISTINCT h.session_id) AS total_sessions
  FROM `your-project.your_dataset.GA4_hit` AS h
  INNER JOIN `your-project.your_dataset.GA4_session` AS s
    ON  h.session_id        = s.session_id
    AND h.visit_start_date  = s.visit_start_date
  LEFT JOIN (
    SELECT
      sn.session_id,
      sn.visit_start_date,
      lki.enquiry_flag
    FROM `your-project.your_dataset.GA4_session_interaction_nameplate` AS sn
    INNER JOIN `your-project.your_dataset.GA4_lookup_interaction` AS lki
      ON sn.interaction_id = lki.interaction_id
    WHERE sn.visit_start_date BETWEEN rep_from AND rep_to
  ) AS sni
    ON  s.session_id        = sni.session_id
    AND s.visit_start_date  = sni.visit_start_date
  INNER JOIN ab_group_data AS ab
    ON h.session_id = ab.session_id
  WHERE h.visit_start_date BETWEEN rep_from AND rep_to
    AND sni.enquiry_flag = 1
    AND h.hit_datetime > ab.ab_min_hit_datetime
  GROUP BY 1, 2, 3, 4, 5, 6
),

-- ============================================================
-- SEGMENT 5: Find Matches (onward behaviour — optional)
-- ============================================================
fm_group AS (
  SELECT
    'fm_group'               AS rep_group,
    ab.visit_start_date,
    ab.page_path,
    ab.event_label,
    ab.event_action,
    CAST(EHIT.interaction_id AS NUMERIC) AS interaction_id,
    COUNT(DISTINCT h.session_id) AS total_sessions
  FROM `your-project.your_dataset.GA4_hit` AS h
  INNER JOIN `your-project.your_dataset.GA4_session` AS s
    ON  h.session_id        = s.session_id
    AND h.visit_start_date  = s.visit_start_date
  JOIN `your-project.your_dataset.GA4_ecomm_hit_interaction_nameplate` AS EHIT
    ON  h.session_id        = EHIT.session_id
    AND h.visit_start_date  = EHIT.visit_start_date
  INNER JOIN ab_group_data AS ab
    ON h.session_id = ab.session_id
  WHERE h.visit_start_date BETWEEN rep_from AND rep_to
    AND EHIT.interaction_id = 227   -- Find Matches; update if different
    AND h.hit_datetime > ab.ab_min_hit_datetime
  GROUP BY 1, 2, 3, 4, 5, 6
)

-- ============================================================
-- FINAL OUTPUT — comment out segments not needed
-- ============================================================
SELECT * FROM page_sessions
UNION ALL
SELECT * FROM click_group
UNION ALL
SELECT * FROM int_group
UNION ALL
SELECT * FROM enq_group
-- UNION ALL
-- SELECT * FROM fm_group   -- uncomment when looking at find matches

ORDER BY 1, 2, 3, 4
;
