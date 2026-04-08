-- ============================================================
-- REGULAR REPORT: MLPX Entry Daily Query
-- ============================================================
-- Tracks CTA clicks and onward reservations for MLPX entry CTAs.
-- Reports daily history from history_start through report_week_end.
--
-- CTAs tracked by event_label pattern (update LIKE filters for
-- your market's CTA label naming convention):
--   Find Matches        — cta--primary (Summary Page)
--   Find Matches        — cta--secondary (Sticky)
--   View Inventory Matches — cta--primary
--   View Inventory Matches — cta--secondary
--
-- Reservations are visitor-based: did the visitor who clicked
-- go on to reserve in any subsequent session?
-- Config (5/11) is session-based across all sessions.
-- ============================================================
-- To run: update report_week_end only.
--         history_start stays fixed at start of reporting period.
-- ============================================================

DECLARE report_week_end DATE DEFAULT '2026-04-05';
DECLARE history_start   DATE DEFAULT '2026-01-01';

WITH

fm_clicks AS (
  SELECT
    h.session_id,
    SN.visitor_id,
    h.visit_start_date,
    CASE
      WHEN h.event_label LIKE 'FIND MATCHES%'           THEN 'Find Matches'
      WHEN h.event_label LIKE 'VIEW INVENTORY MATCHES%' THEN 'View Inventory Matches'
      -- Update LIKE patterns to match your market's CTA event labels
    END AS cta_type,
    CASE
      WHEN h.event_label LIKE '%_cta--primary%'   THEN 'Primary'
      WHEN h.event_label LIKE '%_cta--secondary%' THEN 'Secondary'
    END AS cta_position,
    MIN(h.hit_datetime) OVER (PARTITION BY h.session_id) AS first_fm_click_time
  FROM `your-project.your_dataset.GA4_hit` h
  JOIN `your-project.your_dataset.GA4_session` SN
    ON  h.session_id       = SN.session_id
    AND h.visit_start_date = SN.visit_start_date
  WHERE h.visit_start_date BETWEEN history_start AND report_week_end
    AND h.market_code    = 'your-market'   -- e.g. 'US'
    AND h.brand          = 'your-brand'    -- e.g. 'Land Rover'
    AND h.event_category = 'nav: cta linkClicks by class'
    AND h.event_label LIKE '%MATCHES%'
),

onward_res AS (
  SELECT DISTINCT
    fm.visitor_id,
    fm.cta_type,
    fm.cta_position
  FROM fm_clicks fm
  JOIN `your-project.your_dataset.GA4_session` s
    ON  fm.visitor_id      = s.visitor_id
    AND s.visit_start_date BETWEEN history_start AND report_week_end
    AND s.visit_start_date >= fm.visit_start_date
  JOIN `your-project.your_dataset.GA4_ecomm_hit_interaction_nameplate` ehit
    ON  s.session_id       = ehit.session_id
    AND s.visit_start_date = ehit.visit_start_date
  WHERE ehit.interaction_id = 221   -- Reservation
),

config_int AS (
  SELECT session_id, nameplate_code, interaction_id
  FROM `your-project.your_dataset.GA4_session_interaction_nameplate`
  WHERE brand            = 'your-brand'
    AND visit_start_date BETWEEN history_start AND report_week_end
    AND interaction_id   IN (5, 11)
)

SELECT
  SN.visit_start_date                                                            AS date,
  DT.week_id_date,
  CASE
    WHEN SN.channel_grouping IN (
      'Paid Search', 'Paid Social', 'Paid Display & Video', 'PMAX',
      'Paid Display, Video & Digital Audio', 'Paid Cross Network', 'Paid Unclassified'
    ) THEN 'Paid'
    ELSE 'Unpaid'
  END                                                                            AS traffic_type,
  SN.channel_grouping,
  CI.nameplate_code,
  NP.nameplate_desc                                                              AS nameplate,

  COUNT(DISTINCT CASE WHEN CI.interaction_id = 5  THEN SN.session_id END)       AS config_starts,
  COUNT(DISTINCT CASE WHEN CI.interaction_id = 11 THEN SN.session_id END)       AS config_completes,

  COUNT(DISTINCT CASE WHEN FM.cta_type = 'Find Matches'
    AND FM.cta_position = 'Primary' THEN FM.session_id END)                     AS fm_primary_clicks,
  COUNT(DISTINCT CASE WHEN FM.cta_type = 'Find Matches'
    AND FM.cta_position = 'Primary'
    AND RES.visitor_id IS NOT NULL THEN FM.visitor_id END)                      AS fm_primary_reservations,

  COUNT(DISTINCT CASE WHEN FM.cta_type = 'Find Matches'
    AND FM.cta_position = 'Secondary' THEN FM.session_id END)                   AS fm_secondary_clicks,
  COUNT(DISTINCT CASE WHEN FM.cta_type = 'Find Matches'
    AND FM.cta_position = 'Secondary'
    AND RES.visitor_id IS NOT NULL THEN FM.visitor_id END)                      AS fm_secondary_reservations,

  COUNT(DISTINCT CASE WHEN FM.cta_type = 'View Inventory Matches'
    AND FM.cta_position = 'Primary' THEN FM.session_id END)                     AS vim_primary_clicks,
  COUNT(DISTINCT CASE WHEN FM.cta_type = 'View Inventory Matches'
    AND FM.cta_position = 'Primary'
    AND RES.visitor_id IS NOT NULL THEN FM.visitor_id END)                      AS vim_primary_reservations,

  COUNT(DISTINCT CASE WHEN FM.cta_type = 'View Inventory Matches'
    AND FM.cta_position = 'Secondary' THEN FM.session_id END)                   AS vim_secondary_clicks,
  COUNT(DISTINCT CASE WHEN FM.cta_type = 'View Inventory Matches'
    AND FM.cta_position = 'Secondary'
    AND RES.visitor_id IS NOT NULL THEN FM.visitor_id END)                      AS vim_secondary_reservations

FROM `your-project.your_dataset.GA4_session` SN
JOIN  `your-project.your_dataset.GA4_lookup_date` DT
  ON  SN.visit_start_date = DT.date
LEFT JOIN config_int CI
  ON  SN.session_id = CI.session_id
LEFT JOIN `your-project.your_dataset.GA4_lookup_nameplate` NP
  ON  CI.nameplate_code = NP.nameplate_code
LEFT JOIN fm_clicks FM
  ON  SN.session_id = FM.session_id
LEFT JOIN onward_res RES
  ON  FM.visitor_id   = RES.visitor_id
  AND FM.cta_type     = RES.cta_type
  AND FM.cta_position = RES.cta_position
WHERE SN.market_code = 'your-market'
  AND SN.visit_start_date BETWEEN history_start AND report_week_end
  AND (CI.session_id IS NOT NULL OR FM.session_id IS NOT NULL)
GROUP BY 1, 2, 3, 4, 5, 6
ORDER BY 1 DESC
;
