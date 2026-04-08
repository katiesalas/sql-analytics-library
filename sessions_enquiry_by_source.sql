-- ============================================================
-- Sessions & Enquiry Sessions by Source
-- ============================================================
-- Breaks down sessions and enquiry sessions by raw source
-- attribution fields: date, week, month, market, channel,
-- source, medium, keyword, ad_content, and nameplate.
--
-- Contrast with campaign_sessions.sql:
--   That query enriches via campaign taxonomy CTEs (JSON_VALUE parsing).
--   This query uses source/medium/keyword directly from the session
--   table — simpler and useful for raw media reconciliation.
--
-- Output: one row per unique combination of the above dimensions,
--         with total sessions and sessions where enquiry_flag = 1.
-- ============================================================
-- To run: update rep_from and rep_to. Update market/brand filters.
-- ============================================================

DECLARE rep_from DATE;
DECLARE rep_to   DATE;

SET rep_from = '2023-08-01';
SET rep_to   = '2023-08-31';

SELECT
  dt.date,
  dt.week_id_date,
  dt.month_long_name,
  mt.market_name,
  sn.channel_grouping,
  sn.source,
  sn.medium,
  sn.keyword,
  sn.ad_content,
  hint.nameplate_code,
  hint.interaction_desc,
  COUNT(DISTINCT CASE WHEN hint.enquiry_flag = 1 THEN sn.session_id END) AS enquiry_sessions,
  COUNT(DISTINCT sn.session_id)                                          AS total_sessions
FROM `your-project.your_dataset.GA4_session` AS sn
LEFT JOIN (
  SELECT
    hin.*,
    lki.* EXCEPT (interaction_id),
    lki.interaction_id AS Int_id
  FROM `your-project.your_dataset.GA4_session_interaction_nameplate` AS hin
  INNER JOIN `your-project.your_dataset.GA4_lookup_interaction` AS lki
    ON hin.interaction_id = lki.interaction_id
  WHERE hin.brand             = 'your-brand'   -- e.g. 'Land Rover'
    AND hin.visit_start_date BETWEEN rep_from AND rep_to
) AS hint
  ON  sn.session_id       = hint.session_id
  AND sn.visit_start_date = hint.visit_start_date
JOIN `your-project.your_dataset.GA4_lookup_date` AS dt
  ON sn.visit_start_date = dt.date
JOIN `your-project.your_dataset.GA4_lookup_market` AS mt
  ON sn.market_code = mt.market_code
WHERE sn.market_code       = 'your-market'   -- e.g. 'US'
  AND sn.brand             = 'your-brand'    -- e.g. 'Land Rover'
  AND sn.visit_start_date BETWEEN rep_from AND rep_to
GROUP BY 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11
ORDER BY 1 DESC
;
