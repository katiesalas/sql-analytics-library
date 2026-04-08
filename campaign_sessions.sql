-- ============================================================
-- Campaign Sessions
-- ============================================================
-- Purpose:  Count sessions by market, date, channel, and campaign.
--           Useful for paid channel campaign performance analysis.
-- Grain:    Daily
-- Output:   total_sessions per campaign x channel x date
-- Optional: second date range for period-over-period comparison
--           engagement/enquiry session counts
--           source / medium / keyword breakdown
-- ============================================================
-- To run: update rep_from_1 and rep_to_1.
-- For period comparison: set rep_from_2 / rep_to_2 and UNION.
-- ============================================================

DECLARE rep_from_1 DATE;
DECLARE rep_to_1   DATE;
DECLARE rep_from_2 DATE;  -- optional: period 2 start for comparison
DECLARE rep_to_2   DATE;  -- optional: period 2 end for comparison
DECLARE my_market  STRING;

SET rep_from_1 = '2025-07-01';
SET rep_to_1   = '2025-08-01';
-- SET rep_from_2 = '2025-06-01';
-- SET rep_to_2   = '2025-07-01';

SET my_market = 'your-market';  -- e.g. 'US'

SELECT
  GS.market_code,
  GS.visit_start_date,

  -- Channel normalisation — maps variant names to canonical values
  CASE
    WHEN GS.channel_grouping IN ('Paid Display & Video', 'Display')
      THEN 'Paid Display, Video & Digital Audio'
    WHEN GS.channel_grouping IN ('PMAX', 'Cross Network')
      THEN 'Paid Cross Network'
    WHEN GS.channel_grouping = 'Unclassified'
      THEN 'Paid Unclassified'
    ELSE GS.channel_grouping
  END AS channel_grouping,

  -- Paid / Unpaid classification
  CASE
    WHEN GS.channel_grouping IN (
      'Paid Search', 'Paid Social', 'Other Advertising',
      'Paid Display & Video', 'Display',
      'Paid Display, Video & Digital Audio',
      'PMAX', 'Cross Network', 'Paid Cross Network',
      'Unclassified', 'Paid Unclassified'
    ) THEN 'Paid'
    ELSE 'Unpaid'
  END AS medium_type,

  GS.campaign,
  -- GS.source,    -- uncomment as needed
  -- GS.medium,
  -- GS.keyword,

  COUNT(DISTINCT GS.session_id) AS total_sessions,
  -- COUNT(DISTINCT IF(GL.engagement_flag = 1, GS.session_id, NULL)) AS engagement_sessions,
  -- COUNT(DISTINCT IF(GL.enquiry_flag    = 1, GS.session_id, NULL)) AS enquiry_sessions,

FROM `your-project.your_dataset.GA4_session` AS GS
JOIN `your-project.your_dataset.GA4_session_interaction_nameplate` AS GI
  ON  GS.session_id       = GI.session_id
  AND GS.visit_start_date = GI.visit_start_date
JOIN `your-project.your_dataset.GA4_lookup_interaction` AS GL
  ON  GI.interaction_id = GL.interaction_id
WHERE GS.visit_start_date BETWEEN rep_from_1 AND rep_to_1
  AND GS.market_code = my_market
  AND GS.channel_grouping = 'Paid Social'   -- update channel filter as needed
  -- AND GS.campaign IN ('campaign_name_here')
  -- AND REGEXP_CONTAINS(GS.campaign, r'(?i)keyword_here')
GROUP BY 1, 2, 3, 4, 5
ORDER BY GS.visit_start_date
;
