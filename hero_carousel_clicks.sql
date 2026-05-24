-- ============================================================
--   Hero & Hero Carousel CTA Click Analysis
-- ============================================================
-- Purpose:  Tracks clicks on specific CTAs in the   hero
--           and hero carousel components, with onward behaviour
--           (enquiries,  interaction_1s/interaction_2s,  interaction_3)
--           per CTA type.
--
-- Note:     This query uses the full campaign taxonomy enrichment
--           pattern to resolve channel grouping from session-level
--           campaign data via multiple lookup paths.
--
-- CTAs tracked (update event_label IN list as needed):
--   CTA_1, CTA_2, etc
--
-- Components tracked (update event_category IN list as needed):
--     hero, nav: carousel, cta_click_standardized
-- ============================================================
-- To run: update start_date and end_date only.
-- ============================================================

DECLARE start_date DATE DEFAULT '2025-07-01';
DECLARE end_date   DATE DEFAULT '2025-09-30';

WITH

-- ============================================================
-- 1. Campaign Taxonomy Lookup
-- ============================================================
CTE_CHANNEL_CAMPAIGN AS (
  SELECT DISTINCT
    campaign_key,
    campaign_name,
    CASE
      WHEN channel_fy26 IN ('PMAX', 'Cross Network') THEN 'Paid Cross Network'
      WHEN channel_fy26 = 'Unclassified'             THEN 'Paid Unclassified'
      ELSE channel_fy26
    END AS channel_fy26
  FROM `your-project.your_reporting_dataset.campaign_lookup`
  WHERE IFNULL(campaign_key, '') != ''
    AND LOWER(campaign_key) NOT IN (
      'unclassified', 'default campaign', 'unknown', '(not set)', 'default ad', 'na'
    )
  QUALIFY ROW_NUMBER() OVER (
    PARTITION BY campaign_key ORDER BY insert_date DESC
  ) = 1
),

CTE_SA360 AS (
  SELECT DISTINCT
    sa360_campaign_id,
    campaign_name,
    channel_grouping
  FROM `your-project.your_reporting_dataset.sa360_lookup`
  WHERE IFNULL(sa360_campaign_id, '') != ''
  QUALIFY ROW_NUMBER() OVER (
    PARTITION BY sa360_campaign_id ORDER BY campaign_name
  ) = 1
),

CTE_ENGINEID AS (
  SELECT DISTINCT
    campaign_id AS engine_id,
    campaign_name,
    channel_grouping
  FROM `your-project.your_reporting_dataset.sa360_lookup`
  WHERE IFNULL(campaign_id, '') != ''
  QUALIFY ROW_NUMBER() OVER (
    PARTITION BY campaign_id ORDER BY campaign_name
  ) = 1
),

CTE_CAMPAIGNNAME AS (
  SELECT DISTINCT
    campaign_name,
    channel_fy26
  FROM `your-project.your_reporting_dataset.campaign_lookup`
  WHERE IFNULL(campaign_name, '') != ''
  QUALIFY ROW_NUMBER() OVER (
    PARTITION BY campaign_name ORDER BY insert_date DESC
  ) = 1
),

-- ============================================================
-- 2. Channel-Enriched Sessions
-- ============================================================
channel_enrich AS (
  SELECT
    B.session_id,
    B.visit_start_date,
    CASE
      WHEN COALESCE(
        CTC.channel_fy26, SA.channel_grouping, EI.channel_grouping,
        CN.channel_fy26, B.channel_grouping
      ) IN ('Paid Display & Video', 'Display')
        THEN 'Paid Display, Video & Digital Audio'
      WHEN COALESCE(
        CTC.channel_fy26, SA.channel_grouping, EI.channel_grouping,
        CN.channel_fy26, B.channel_grouping
      ) IN ('PMAX', 'Cross Network')
        THEN 'Paid Cross Network'
      WHEN COALESCE(
        CTC.channel_fy26, SA.channel_grouping, EI.channel_grouping,
        CN.channel_fy26, B.channel_grouping
      ) = 'Unclassified'
        THEN 'Paid Unclassified'
      ELSE COALESCE(
        CTC.channel_fy26, SA.channel_grouping,
        EI.channel_grouping, CN.channel_fy26,
        B.channel_grouping
      )
    END AS channel_grouping_final
  FROM `your-project.your_dataset.GA4_session` B
  LEFT JOIN CTE_CHANNEL_CAMPAIGN CTC
    ON LOWER(JSON_VALUE(B.campaign, '$.campaign_original')) = LOWER(CTC.campaign_key)
  LEFT JOIN CTE_SA360 SA
    ON LOWER(JSON_VALUE(B.campaign, '$.sa360_id'))          = LOWER(SA.sa360_campaign_id)
  LEFT JOIN CTE_ENGINEID EI
    ON LOWER(JSON_VALUE(B.campaign, '$.engine_id'))         = LOWER(EI.engine_id)
  LEFT JOIN CTE_CAMPAIGNNAME CN
    ON LOWER(JSON_VALUE(B.campaign, '$.campaign_original')) = LOWER(CN.campaign_name)
  WHERE B.visit_start_date BETWEEN start_date AND end_date
)

-- ============================================================
-- 3. Final Output
-- ============================================================
SELECT
  D.week_id_date,

  -- Sub-model mapping via page_path (update LIKE patterns as needed)
  -- Useful when one nameplate_code covers multiple sub-models

  CE.channel_grouping_final AS channel_grouping,

  CASE
    WHEN CE.channel_grouping_final IN (
      'Paid Search', 'Paid Social', 'Other Advertising',
      'Paid Display & Video', 'Display',
      'Paid Display, Video & Digital Audio',
      'PMAX', 'Cross Network', 'Paid Cross Network',
      'Unclassified', 'Paid Unclassified'
    ) THEN 'Paid'
    ELSE 'Unpaid'
  END AS medium_type,

  -- ── CTA Click Sessions ───────────────────────────────────
  COUNT(DISTINCT CASE WHEN A.event_label = 'CTA_1'
    AND LOWER(A.event_category) IN ('  hero', 'nav: carousel')
    THEN A.session_id END)                                                        AS CTA_1_sessions,

  COUNT(DISTINCT CASE WHEN A.event_label = 'CTA_2'
    AND LOWER(A.event_category) IN ('  hero', 'nav: carousel')
    THEN A.session_id END)                                                        AS CTA_2_sessions,

  COUNT(DISTINCT CASE WHEN A.event_label = 'CTA_3'
    AND LOWER(A.event_category) = 'nav: carousel'
    THEN A.session_id END)                                                        AS CTA_3_sessions,


  -- ── CTA_1 — Onward Behaviour ────────────────
  COUNT(DISTINCT CASE WHEN A.event_label = 'CTA_1'
    AND LOWER(A.event_category) IN ('  hero', 'nav: carousel')
    AND E.enquiry_flag = 1 THEN A.session_id END)                                AS CTA_1_enquiries,

  COUNT(DISTINCT CASE WHEN A.event_label = 'CTA_1'
    AND LOWER(A.event_category) IN ('  hero', 'nav: carousel')
    AND C.interaction_id = 5 THEN A.session_id END)                              AS CTA_1config_starts,

  COUNT(DISTINCT CASE WHEN A.event_label = 'CTA_1'
    AND LOWER(A.event_category) IN ('  hero', 'nav: carousel')
    AND C.interaction_id = 11 THEN A.session_id END)                             AS CTA_1config_completes,

  COUNT(DISTINCT CASE WHEN A.event_label = 'CTA_1'
    AND LOWER(A.event_category) IN ('  hero', 'nav: carousel')
    AND ecomm.interaction_id = 227 THEN ecomm.session_id END)                    AS CTA_1find_matches,

  -- ── CTA_2 — Onward Behaviour ───────────────────
  COUNT(DISTINCT CASE WHEN A.event_label = 'CTA_2'
    AND LOWER(A.event_category) = 'nav: carousel'
    AND E.enquiry_flag = 1 THEN A.session_id END)                                AS CTA_2_enquiries,

  COUNT(DISTINCT CASE WHEN A.event_label = 'CTA_2'
    AND LOWER(A.event_category) = 'nav: carousel'
    AND C.interaction_id = 5 THEN A.session_id END)                              AS CTA_2_config_starts,

  COUNT(DISTINCT CASE WHEN A.event_label = 'CTA_2'
    AND LOWER(A.event_category) = 'nav: carousel'
    AND C.interaction_id = 11 THEN A.session_id END)                             AS CTA_2_config_completes,

  COUNT(DISTINCT CASE WHEN A.event_label = 'CTA_2'
    AND LOWER(A.event_category) = 'nav: carousel'
    AND ecomm.interaction_id = 227 THEN ecomm.session_id END)                    AS CTA_2_find_matches,

  -- ── EXPLORE INNOVATION — Onward Behaviour ───────────────
  COUNT(DISTINCT CASE WHEN A.event_label = 'CTA_3
    AND LOWER(A.event_category) = 'nav: carousel'
    AND E.enquiry_flag = 1 THEN A.session_id END)                                AS CTA_3_enquiries,

  COUNT(DISTINCT CASE WHEN A.event_label = 'CTA_3
    AND LOWER(A.event_category) = 'nav: carousel'
    AND C.interaction_id = 5 THEN A.session_id END)                              AS CTA_3_config_starts,

  COUNT(DISTINCT CASE WHEN A.event_label = 'CTA_3
    AND LOWER(A.event_category) = 'nav: carousel'
    AND C.interaction_id = 11 THEN A.session_id END)                             AS CTA_3_config_completes,

  COUNT(DISTINCT CASE WHEN A.event_label = 'CTA_3
    AND LOWER(A.event_category) = 'nav: carousel'
    AND ecomm.interaction_id = 227 THEN ecomm.session_id END)                    AS CTA_3_find_matches,



  -- ── Overall ──────────────────────────────────────────────
  COUNT(DISTINCT A.session_id)                                                    AS overall_sessions

FROM `your-project.your_dataset.GA4_hit` A
LEFT JOIN `your-project.your_dataset.GA4_session` B
  ON  A.session_id       = B.session_id
  AND A.visit_start_date = B.visit_start_date
LEFT JOIN `your-project.your_dataset.GA4_session_interaction_nameplate` C
  ON  A.session_id       = C.session_id
  AND A.visit_start_date = C.visit_start_date
LEFT JOIN `your-project.your_dataset.GA4_lookup_date` D
  ON  A.visit_start_date = D.date
LEFT JOIN `your-project.your_dataset.GA4_lookup_interaction` E
  ON  C.interaction_id   = E.interaction_id
LEFT JOIN `your-project.your_dataset.GA4_ecomm_hit_interaction_nameplate` ecomm
  ON  A.session_id       = ecomm.session_id
  AND A.visit_start_date = ecomm.visit_start_date
  AND ecomm.interaction_id = 227
LEFT JOIN channel_enrich CE
  ON  A.session_id       = CE.session_id
  AND A.visit_start_date = CE.visit_start_date
WHERE A.visit_start_date BETWEEN start_date AND end_date
  AND B.visit_start_date BETWEEN start_date AND end_date
  AND C.visit_start_date BETWEEN start_date AND end_date
  AND A.market_code = 'your-market'
  AND C.nameplate_code IN ('your-nameplate-codes')  -- e.g. 'L460','L461','L663'
  AND LOWER(A.event_category) IN (
    '  hero',
    'nav: cta linkclicks by class',
    'nav: carousel',
    'cta_click_standardized'
  )
  AND A.event_label IN (

    'CTA_2',
    'CTA_3',
    'CTA_1'
  )
GROUP BY
  D.week_id_date,
  C.nameplate_code,
  A.page_path,
  CE.channel_grouping_final
ORDER BY 1, 2, 3
;
