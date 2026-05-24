-- ============================================================
-- REGULAR REPORT: DX_Page — Sessions + Onward Behaviour
-- ============================================================
-- Pivot-ready output. Tracks sessions that entered via a
-- Client Education page and their onward behaviour:
--   Client Education Page Views
--   Engaged Sessions
--   Interaction_1s (KPI_1)
--   Interaction_2s (KPI_2)
--   Find Matches (227)
--   Reservations (221)
--
-- All onward metrics use ab_min_hit_datetime to ensure behaviour
-- occurred AFTER the DX_Page landing.
-- ============================================================
-- To run: update report_week_end and DX_Page page_path list.
-- ============================================================

DECLARE report_week_end   DATE DEFAULT '2026-04-05';
DECLARE report_week_start DATE DEFAULT DATE_SUB(report_week_end, INTERVAL 6 DAY);

DECLARE KPI_1 INT64;
DECLARE KPI_2 INT64;

SET KPI_1 = 5;    -- Interaction_1
SET KPI_2 = 11;   -- Interaction_2

WITH

ab_group_data AS (
  SELECT DISTINCT
    d.week_id_date,
    h.page_path,
    MIN(h.hit_datetime) OVER (PARTITION BY h.session_id) AS ab_min_hit_datetime,
    h.session_id
  FROM `your-project.your_dataset.GA4_hit` h
  JOIN `your-project.your_dataset.GA4_lookup_market` m
    ON  h.market_code = m.market_code
  JOIN `your-project.your_dataset.GA4_session` s
    ON  h.session_id       = s.session_id
    AND h.visit_start_date = s.visit_start_date
  JOIN `your-project.your_dataset.GA4_lookup_date` d
    ON  d.date = h.visit_start_date
  WHERE h.visit_start_date BETWEEN report_week_start AND report_week_end
    AND h.market_code = 'your-market'   -- e.g. 'US'
    AND h.page_path IN (
      -- Update with your market's DX_Page page URLs
      'your-product-1-DX_Page-url',
      'your-product-2-DX_Page-url'
    )
),

session_int AS (
  SELECT
    sn.session_id,
    sn.visit_start_date,
    lki.interaction_id,
    lki.engagement_flag
  FROM `your-project.your_dataset.GA4_session_interaction_product` sn
  JOIN `your-project.your_dataset.GA4_lookup_interaction` lki
    ON sn.interaction_id = lki.interaction_id
  WHERE sn.visit_start_date BETWEEN report_week_start AND report_week_end
),

unioned AS (

  SELECT
    'session_group'     AS rep_group,
    ab.week_id_date,
    ab.page_path,
    CAST(NULL AS INT64) AS interaction_id,
    COUNT(DISTINCT ab.session_id) AS Total_Sessions
  FROM ab_group_data ab
  GROUP BY 1, 2, 3, 4

  UNION ALL

  SELECT
    'enggg_group'       AS rep_group,
    ab.week_id_date,
    ab.page_path,
    CAST(NULL AS INT64) AS interaction_id,
    COUNT(DISTINCT h.session_id) AS Total_Sessions
  FROM `your-project.your_dataset.GA4_hit` h
  JOIN `your-project.your_dataset.GA4_session` s
    ON  h.session_id       = s.session_id
    AND h.visit_start_date = s.visit_start_date
  LEFT JOIN session_int sni
    ON  s.session_id       = sni.session_id
    AND s.visit_start_date = sni.visit_start_date
  JOIN ab_group_data ab ON h.session_id = ab.session_id
  WHERE h.visit_start_date BETWEEN report_week_start AND report_week_end
    AND sni.engagement_flag = 1
    AND h.hit_datetime > ab.ab_min_hit_datetime
  GROUP BY 1, 2, 3, 4

  UNION ALL

  SELECT
    'int_group'         AS rep_group,
    ab.week_id_date,
    ab.page_path,
    hn.interaction_id,
    COUNT(DISTINCT h.session_id) AS Total_Sessions
  FROM `your-project.your_dataset.GA4_hit` h
  LEFT JOIN `your-project.your_dataset.GA4_hit_interaction_product` hn
    ON  h.hit_id           = hn.hit_id
    AND h.visit_start_date = hn.visit_start_date
  JOIN `your-project.your_dataset.GA4_session` s
    ON  h.session_id       = s.session_id
    AND h.visit_start_date = s.visit_start_date
  JOIN ab_group_data ab ON h.session_id = ab.session_id
  WHERE h.visit_start_date BETWEEN report_week_start AND report_week_end
    AND hn.interaction_id IN (KPI_1, KPI_2)
    AND h.hit_datetime > ab.ab_min_hit_datetime
  GROUP BY 1, 2, 3, 4

  UNION ALL

  SELECT
    'mlpx_group'        AS rep_group,
    ab.week_id_date,
    ab.page_path,
    ehit.interaction_id,
    COUNT(DISTINCT ehit.session_id) AS Total_Sessions
  FROM `your-project.your_dataset.GA4_hit` h
  JOIN `your-project.your_dataset.GA4_session` s
    ON  h.session_id       = s.session_id
    AND h.visit_start_date = s.visit_start_date
  JOIN `your-project.your_dataset.GA4_ecomm_hit_interaction_product` ehit
    ON  h.session_id       = ehit.session_id
    AND h.visit_start_date = ehit.visit_start_date
  JOIN ab_group_data ab ON h.session_id = ab.session_id
  WHERE ehit.visit_start_date BETWEEN report_week_start AND report_week_end
    AND ehit.interaction_id IN (221, 227)
    AND h.hit_datetime > ab.ab_min_hit_datetime
  GROUP BY 1, 2, 3, 4
)

SELECT
  week_id_date,
  page_path,
  CASE
    WHEN rep_group = 'session_group'                          THEN 'Client Education Page Views'
    WHEN rep_group = 'enggg_group'                            THEN 'Engaged Sessions'
    WHEN rep_group = 'int_group'  AND interaction_id = KPI_1 THEN 'Interaction_1s'
    WHEN rep_group = 'int_group'  AND interaction_id = KPI_2 THEN 'Interaction_2s'
    WHEN rep_group = 'mlpx_group' AND interaction_id = 227   THEN 'Find Matches'
    WHEN rep_group = 'mlpx_group' AND interaction_id = 221   THEN 'Reservations'
    ELSE 'Other'
  END AS metric_name,
  Total_Sessions
FROM unioned
WHERE
     rep_group = 'session_group'
  OR rep_group = 'enggg_group'
  OR (rep_group = 'int_group'  AND interaction_id IN (KPI_1, KPI_2))
  OR (rep_group = 'mlpx_group' AND interaction_id IN (221, 227))
ORDER BY week_id_date, page_path, metric_name
;
