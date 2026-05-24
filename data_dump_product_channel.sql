-- ============================================================
-- Data Dump — All Metrics by Product, Channel, Source
-- ============================================================
-- Purpose:  High-level session and engagement metrics across all
--           Products and channels. Useful for media agency
--           reconciliation and channel performance deep dives.
-- Grain:    Monthly (month_id_date)
-- Output:   sessions, engaged_sessions, enquiry_sessions
--           by Product x channel x source
-- ============================================================data_dump_product_channel.sql
-- To run: update start_date and end_date only.
-- ⚠ Always use the same date range for both session and
--   interaction filters to avoid NULL interaction data.
-- ============================================================

DECLARE start_date DATE DEFAULT '2025-04-01';
DECLARE end_date   DATE DEFAULT '2025-05-31';

SELECT
  d.month_id_date,
  sin.Product_code,
  NP.Product_desc,

  -- Channel normalisation — maps variant names to canonical values
  CASE
    WHEN s.channel_grouping IN ('Paid Display & Video', 'Display')
      THEN 'Paid Display, Video & Digital Audio'
    WHEN s.channel_grouping IN ('PMAX', 'Cross Network')
      THEN 'Paid Cross Network'
    WHEN s.channel_grouping = 'Unclassified'
      THEN 'Paid Unclassified'
    ELSE s.channel_grouping
  END AS channel_grouping,

  -- Paid / Unpaid classification
  CASE
    WHEN s.channel_grouping IN (
      'Paid Search', 'Paid Social', 'Other Advertising',
      'Paid Display & Video', 'Display',
      'Paid Display, Video & Digital Audio',
      'PMAX', 'Cross Network', 'Paid Cross Network',
      'Unclassified', 'Paid Unclassified'
    ) THEN 'Paid'
    ELSE 'Unpaid'
  END AS medium_type,

  s.source,

  COUNT(DISTINCT s.session_id)                                                    AS sessions,
  COUNT(DISTINCT CASE WHEN i.engagement_flag = 1 THEN s.session_id END)          AS engaged_sessions,
  COUNT(DISTINCT CASE WHEN i.enquiry_flag    = 1 THEN s.session_id END)          AS enquiry_sessions

FROM `your-project.your_dataset.GA4_session` s
LEFT JOIN `your-project.your_dataset.GA4_session_interaction_Product` sin
  ON  s.session_id       = sin.session_id
  AND s.visit_start_date = sin.visit_start_date  -- date join prevents fan-out
LEFT JOIN `your-project.your_dataset.GA4_lookup_interaction` i
  ON  sin.interaction_id = i.interaction_id
JOIN `your-project.your_dataset.GA4_lookup_date` d
  ON  s.visit_start_date = d.date
LEFT JOIN `your-project.your_dataset.GA4_lookup_Product` NP
  ON  sin.Product_code = NP.Product_code
WHERE s.market_code = 'your-market'
  AND s.visit_start_date   BETWEEN start_date AND end_date
  AND sin.visit_start_date BETWEEN start_date AND end_date  -- ⚠ keep in sync with above
GROUP BY 1, 2, 3, 4, 5, 6
ORDER BY 1, 2, 3, 4
;
