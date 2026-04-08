-- ============================================================
-- Enquiry & Engagement Report
-- ============================================================
-- Purpose:  Count sessions with enquiry or engagement flags
--           by date, market, channel, nameplate, and interaction type.
-- Grain:    Daily
-- Filters:  Single market, single brand (configurable below)
-- Output:   enquiry_sessions, engagement_sessions
-- ============================================================
-- To run: update start_date and end_date only.
-- ============================================================

DECLARE start_date DATE DEFAULT '2025-06-01';
DECLARE end_date   DATE DEFAULT '2025-06-30';

-- ============================================================
-- Configuration — update these to match your schema
-- ============================================================
-- Dataset:  your-project.your_dataset
-- Brand:    adjust HIN.brand filter below as needed
-- Market:   adjust SN.market_code filter below as needed
-- ============================================================

WITH

-- Session-level interactions joined to flag lookup
-- engagement_flag and enquiry_flag live in the interaction lookup table
session_interactions AS (
  SELECT
    HIN.session_id,
    HIN.visit_start_date,
    HIN.nameplate_code,
    LI.interaction_id,
    LI.engagement_flag,
    LI.enquiry_flag
  FROM `your-project.your_dataset.GA4_session_interaction_nameplate` HIN
  JOIN `your-project.your_dataset.GA4_lookup_interaction` LI
    ON HIN.interaction_id = LI.interaction_id
  WHERE HIN.brand = 'your-brand'           -- e.g. 'Land Rover'
    AND HIN.visit_start_date BETWEEN start_date AND end_date
)

SELECT
  DT.date,
  DT.week_id_date,
  MT.market_name,

  -- Channel normalisation — maps variant names to canonical values
  -- so Paid/Unpaid classification is consistent across all date ranges
  CASE
    WHEN SN.channel_grouping IN ('Paid Display & Video', 'Display')
      THEN 'Paid Display, Video & Digital Audio'
    WHEN SN.channel_grouping IN ('PMAX', 'Cross Network')
      THEN 'Paid Cross Network'
    WHEN SN.channel_grouping = 'Unclassified'
      THEN 'Paid Unclassified'
    ELSE SN.channel_grouping
  END AS channel_grouping,

  SI.nameplate_code,
  SI.interaction_id,

  -- Session-based counts (use visitor_id instead if visitor-level dedup needed)
  COUNT(DISTINCT CASE WHEN SI.enquiry_flag    = 1 THEN SN.session_id END) AS enquiry_sessions,
  COUNT(DISTINCT CASE WHEN SI.engagement_flag = 1 THEN SN.session_id END) AS engagement_sessions

FROM `your-project.your_dataset.GA4_session` SN
LEFT JOIN session_interactions SI
  ON  SN.session_id       = SI.session_id
  AND SN.visit_start_date = SI.visit_start_date   -- date partition join prevents fan-out
JOIN `your-project.your_dataset.GA4_lookup_date` DT
  ON  SN.visit_start_date = DT.date
JOIN `your-project.your_dataset.GA4_lookup_market` MT
  ON  SN.market_code = MT.market_code
WHERE SN.market_code = 'your-market'              -- e.g. 'US'
  AND SN.visit_start_date BETWEEN start_date AND end_date
GROUP BY 1, 2, 3, 4, 5, 6
ORDER BY 1 DESC
;
