-- ============================================================
-- Onward Enquiry from Page — Rolling 30/90-Day Summary
-- ============================================================
-- Tracks onward enquiry behaviour from specific page visits.
-- Reports both a 30-day count and a 90-day monthly average
-- (90-day total ÷ 3) from a single end_date variable.
--
-- ⚠ The / 3 monthly average only holds if end_date is exactly
--   90 days from start_date. If you change the window, update
--   the divisor accordingly.
--
-- Enquiry sources — two approaches combined:
--   1. GA4_session_interaction_nameplate: Config Start (5),
--      Config Complete (11), STR/RAQ — Send to Retailer (25)
--   2. GA4_hit form submit events: RAQ, STR, FIN2
--      (via event_action REGEXP on form submit hits)
--
-- ⚠ STR appears in both sources — some double-counting is
--   possible if the same session fires both routes.
--
-- Counting: visitor-based throughout.
--
-- Output: one row per page / page type, columns for each
--         enquiry type × date window.
--   Filtered to pages with > 100 avg monthly visitors.
-- ============================================================
-- To run: update end_date, my_market, and page_path list.
-- ============================================================

DECLARE end_date    DATE DEFAULT '2024-08-26';
DECLARE start_date  DATE DEFAULT DATE_SUB(end_date, INTERVAL 90 DAY);   -- 90-day window
DECLARE start_date2 DATE DEFAULT DATE_SUB(end_date, INTERVAL 30 DAY);   -- 30-day window
DECLARE my_market   STRING DEFAULT 'your-market';   -- e.g. 'US'

-- ============================================================
-- CTE 1: Sessions that visited the tracked pages
-- hit_type = 'PAGE' limits to page view hits only
-- ============================================================
WITH filtered_hits AS (
  SELECT
    h.session_id,
    h.visitor_id,
    h.page_path,
    h.visit_start_date
  FROM `your-project.your_dataset.GA4_hit` AS h
  WHERE h.visit_start_date BETWEEN start_date AND end_date
    AND h.brand       = 'your-brand'    -- e.g. 'Land Rover'
    AND h.market_code = my_market
    AND h.hit_type    = 'PAGE'
    AND (
      -- Offers pages: LIKE '%ffers%' catches /Offers/ and /offers/
      h.page_path LIKE '%ffers%'
      OR h.page_path IN (
        -- Update with your market's nameplate overview pages
        'your-domain.com/range-rover/range-rover/index.html',
        'your-domain.com/range-rover/range-rover-sport/index.html',
        'your-domain.com/defender/defender-110/index.html'
        -- add further nameplates as needed
      )
    )
),

-- ============================================================
-- CTE 2: Interaction-based enquiry flags
-- Config Start (5), Config Complete (11), STR (25)
-- ============================================================
filtered_interactions AS (
  SELECT
    sin.session_id,
    sin.visit_start_date,
    CASE
      WHEN sin.interaction_id = 25 THEN 'STR'
      WHEN sin.interaction_id = 5  THEN 'ConfStart'
      WHEN sin.interaction_id = 11 THEN 'ConfCompl'
    END AS EnqType
  FROM `your-project.your_dataset.GA4_session_interaction_nameplate` AS sin
  WHERE sin.visit_start_date BETWEEN start_date AND end_date
    AND sin.brand       = 'your-brand'
    AND sin.market_code = my_market
    AND sin.interaction_id IN (5, 11, 25)
),

-- ============================================================
-- CTE 3: Hit-level form submit enquiry flags
-- RAQ, STR, FIN2 — captured via event_action REGEXP
-- ============================================================
filtered_interactions_hit AS (
  SELECT
    h.session_id,
    h.visit_start_date,
    CASE
      WHEN REGEXP_CONTAINS(h.event_action, r'raq')  THEN 'RAQ'
      WHEN REGEXP_CONTAINS(h.event_action, r'str')  THEN 'STR'
      WHEN REGEXP_CONTAINS(h.event_action, r'fin2') THEN 'FIN2'
    END AS EnqType
  FROM `your-project.your_dataset.GA4_hit` AS h
  WHERE h.visit_start_date BETWEEN start_date AND end_date
    AND REGEXP_CONTAINS(h.event_category, r'form submit')
    AND REGEXP_CONTAINS(h.event_action,   r'raq|str|fin2')
    AND h.brand       = 'your-brand'
    AND h.market_code = my_market
)

-- ============================================================
-- FINAL: Pivot by page, report 30-day counts and 90-day
--        monthly averages (÷ 3) for each enquiry type
-- ============================================================
SELECT
  CASE
    WHEN REGEXP_CONTAINS(fh.page_path, r'/index\.html') THEN 'Nameplate'
    ELSE 'Offers'
  END AS PageType,
  REGEXP_REPLACE(fh.page_path, r'\.html.*', '.html') AS PagePath,

  -- Page visitors
  COUNT(DISTINCT fh.visitor_id) / 3                                                                       AS AvgMonthlyPageVisitorsLast90Days,
  COUNT(DISTINCT CASE WHEN fh.visit_start_date BETWEEN start_date2 AND end_date THEN fh.visitor_id END)  AS PageVisitorsLast30Days,

  -- Config Start
  COUNT(DISTINCT CASE WHEN fi.session_id = fh.session_id AND fi.visit_start_date BETWEEN start_date  AND end_date  AND fi.EnqType = 'ConfStart' THEN fh.visitor_id END) / 3  AS ConfStartAvgMonthlyVisitorsLast90Days,
  COUNT(DISTINCT CASE WHEN fi.session_id = fh.session_id AND fi.visit_start_date BETWEEN start_date2 AND end_date  AND fi.EnqType = 'ConfStart' THEN fh.visitor_id END)       AS ConfStartVisitorsLast30Days,

  -- Config Complete
  COUNT(DISTINCT CASE WHEN fi.session_id = fh.session_id AND fi.visit_start_date BETWEEN start_date  AND end_date  AND fi.EnqType = 'ConfCompl' THEN fh.visitor_id END) / 3  AS ConfComplAvgMonthlyVisitorsLast90Days,
  COUNT(DISTINCT CASE WHEN fi.session_id = fh.session_id AND fi.visit_start_date BETWEEN start_date2 AND end_date  AND fi.EnqType = 'ConfCompl' THEN fh.visitor_id END)       AS ConfComplVisitorsLast30Days,

  -- All interactions (any EnqType from interaction table)
  COUNT(DISTINCT CASE WHEN fi.session_id = fh.session_id AND fi.visit_start_date BETWEEN start_date  AND end_date  THEN fh.visitor_id END) / 3                              AS EnqAvgMonthlyVisitorsLast90Days,
  COUNT(DISTINCT CASE WHEN fi.session_id = fh.session_id AND fi.visit_start_date BETWEEN start_date2 AND end_date  THEN fh.visitor_id END)                                   AS EnqVisitorsLast30Days,

  -- RAQ (form submit, hit-level)
  COUNT(DISTINCT CASE WHEN fih.session_id = fh.session_id AND fih.visit_start_date BETWEEN start_date  AND end_date  AND fih.EnqType = 'RAQ' THEN fh.visitor_id END) / 3    AS RAQAvgMonthlyVisitorsLast90Days,
  COUNT(DISTINCT CASE WHEN fih.session_id = fh.session_id AND fih.visit_start_date BETWEEN start_date2 AND end_date  AND fih.EnqType = 'RAQ' THEN fh.visitor_id END)         AS RAQVisitorsLast30Days,

  -- STR (form submit, hit-level — also in interaction table; possible overlap)
  COUNT(DISTINCT CASE WHEN fih.session_id = fh.session_id AND fih.visit_start_date BETWEEN start_date  AND end_date  AND fih.EnqType = 'STR' THEN fh.visitor_id END) / 3    AS STRAvgMonthlyVisitorsLast90Days,
  COUNT(DISTINCT CASE WHEN fih.session_id = fh.session_id AND fih.visit_start_date BETWEEN start_date2 AND end_date  AND fih.EnqType = 'STR' THEN fh.visitor_id END)         AS STRVisitorsLast30Days,

  -- FIN2 (finance form submit, hit-level)
  COUNT(DISTINCT CASE WHEN fih.session_id = fh.session_id AND fih.visit_start_date BETWEEN start_date  AND end_date  AND fih.EnqType = 'FIN2' THEN fh.visitor_id END) / 3   AS FIN2AvgMonthlyVisitorsLast90Days,
  COUNT(DISTINCT CASE WHEN fih.session_id = fh.session_id AND fih.visit_start_date BETWEEN start_date2 AND end_date  AND fih.EnqType = 'FIN2' THEN fh.visitor_id END)        AS FIN2VisitorsLast30Days

FROM filtered_hits AS fh
LEFT JOIN filtered_interactions     AS fi  ON fi.session_id  = fh.session_id AND fi.visit_start_date  = fh.visit_start_date
LEFT JOIN filtered_interactions_hit AS fih ON fih.session_id = fh.session_id AND fih.visit_start_date = fh.visit_start_date
GROUP BY PageType, PagePath
HAVING AvgMonthlyPageVisitorsLast90Days > 100
ORDER BY 1, 3 DESC
;
