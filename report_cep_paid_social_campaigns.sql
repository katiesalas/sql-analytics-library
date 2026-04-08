-- ============================================================
-- REGULAR REPORT: CEP Paid Social Campaign Performance
-- ============================================================
-- Filters to Paid Social sessions that landed on a Client
-- Education page, then tracks onward behaviour by campaign.
--
-- Campaign enrichment uses full 4-path taxonomy lookup:
--   1. campaign_key match
--   2. SA360 campaign ID
--   3. Engine ID
--   4. Campaign name fallback
--
-- focus_campaigns: leave as empty array [] to return all
-- campaigns, or populate to filter to specific ones.
-- ============================================================
-- To run: update report_week_end and CEP page_path LIKE filter.
-- ============================================================

DECLARE report_week_end   DATE DEFAULT '2026-04-05';
DECLARE report_week_start DATE DEFAULT DATE_SUB(report_week_end, INTERVAL 6 DAY);

DECLARE focus_campaigns ARRAY<STRING> DEFAULT [];

WITH CTE_CHANNEL_CAMPAIGN AS (
  SELECT DISTINCT
    campaign_key,
    campaign_name,
    CASE
      WHEN channel_fy26 IN ('PMAX', 'Cross Network') THEN 'Paid Cross Network'
      WHEN channel_fy26 = 'Unclassified'             THEN 'Paid Unclassified'
      ELSE channel_fy26
    END AS channel_fy26
  FROM `your-project.your_reporting_dataset.GA_agg_db_macroid_campaign_lookup_final`
  WHERE IFNULL(campaign_key, '') != ''
    AND LOWER(campaign_key) NOT IN (
      'unclassified', 'default campaign', 'unknown', '(not set)', 'default ad', 'na'
    )
  QUALIFY ROW_NUMBER() OVER (PARTITION BY campaign_key ORDER BY insert_date DESC) = 1
),

CTE_SA360 AS (
  SELECT DISTINCT
    sa360_campaign_id,
    campaign_name,
    channel_grouping
  FROM `your-project.your_reporting_dataset.GA_agg_db_macroid_sa360id_lookup`
  WHERE IFNULL(sa360_campaign_id, '') != ''
  QUALIFY ROW_NUMBER() OVER (PARTITION BY sa360_campaign_id ORDER BY campaign_name) = 1
),

CTE_ENGINEID AS (
  SELECT DISTINCT
    campaign_id AS engine_id,
    campaign_name,
    channel_grouping
  FROM `your-project.your_reporting_dataset.GA_agg_db_macroid_sa360id_lookup`
  WHERE IFNULL(campaign_id, '') != ''
  QUALIFY ROW_NUMBER() OVER (PARTITION BY campaign_id ORDER BY campaign_name) = 1
),

CTE_CAMPAIGNNAME AS (
  SELECT DISTINCT
    campaign_name,
    channel_fy26
  FROM `your-project.your_reporting_dataset.GA_agg_db_macroid_campaign_lookup_final`
  WHERE IFNULL(campaign_name, '') != ''
  QUALIFY ROW_NUMBER() OVER (PARTITION BY campaign_name ORDER BY insert_date DESC) = 1
),

CHANNEL_ENRICH AS (
  SELECT
    SN.*,
    CASE
      WHEN COALESCE(
        CTC.channel_fy26, SA.channel_grouping, EI.channel_grouping,
        CN.channel_fy26, SN.channel_grouping
      ) IN ('Paid Display & Video', 'Display')
        THEN 'Paid Display, Video & Digital Audio'
      WHEN COALESCE(
        CTC.channel_fy26, SA.channel_grouping, EI.channel_grouping,
        CN.channel_fy26, SN.channel_grouping
      ) IN ('PMAX', 'Cross Network')
        THEN 'Paid Cross Network'
      WHEN COALESCE(
        CTC.channel_fy26, SA.channel_grouping, EI.channel_grouping,
        CN.channel_fy26, SN.channel_grouping
      ) = 'Unclassified'
        THEN 'Paid Unclassified'
      ELSE COALESCE(
        CTC.channel_fy26, SA.channel_grouping,
        EI.channel_grouping, CN.channel_fy26,
        SN.channel_grouping
      )
    END AS channel_grouping_final,
    COALESCE(
      CTC.campaign_name, SA.campaign_name,
      EI.campaign_name, CN.campaign_name,
      JSON_VALUE(SN.campaign, '$.campaign_original'),
      JSON_VALUE(SN.campaign, '$.campaign'),
      SN.campaign
    ) AS campaign_final
  FROM `your-project.your_dataset.GA4_session` SN
  LEFT JOIN CTE_CHANNEL_CAMPAIGN CTC
    ON LOWER(JSON_VALUE(SN.campaign, '$.campaign_original')) = LOWER(CTC.campaign_key)
  LEFT JOIN CTE_SA360 SA
    ON LOWER(JSON_VALUE(SN.campaign, '$.sa360_id'))          = LOWER(SA.sa360_campaign_id)
  LEFT JOIN CTE_ENGINEID EI
    ON LOWER(JSON_VALUE(SN.campaign, '$.engine_id'))         = LOWER(EI.engine_id)
  LEFT JOIN CTE_CAMPAIGNNAME CN
    ON LOWER(JSON_VALUE(SN.campaign, '$.campaign_original')) = LOWER(CN.campaign_name)
  WHERE SN.visit_start_date BETWEEN report_week_start AND report_week_end
),

INTERACTIONS AS (
  SELECT
    HIN.session_id,
    LI.interaction_id,
    LI.engagement_flag
  FROM `your-project.your_dataset.GA4_session_interaction_nameplate` HIN
  JOIN `your-project.your_dataset.GA4_lookup_interaction` LI
    ON HIN.interaction_id = LI.interaction_id
  WHERE HIN.visit_start_date BETWEEN report_week_start AND report_week_end
),

CLIENT_EDU_LANDINGS AS (
  SELECT
    DT.week_id_date,
    CE.campaign_final,
    CE.session_id,
    MIN(H.hit_datetime) AS ce_min_hit_datetime
  FROM CHANNEL_ENRICH CE
  JOIN `your-project.your_dataset.GA4_hit` H
    ON  CE.session_id       = H.session_id
    AND CE.visit_start_date = H.visit_start_date
  JOIN `your-project.your_dataset.GA4_lookup_date` DT
    ON  CE.visit_start_date = DT.date
  JOIN `your-project.your_dataset.GA4_lookup_market` MT
    ON  CE.market_code = MT.market_code
  WHERE CE.visit_start_date BETWEEN report_week_start AND report_week_end
    AND CE.market_code            = 'your-market'   -- e.g. 'US'
    AND CE.channel_grouping_final = 'Paid Social'
    AND H.page_path LIKE '%your-cep-url-pattern%'   -- e.g. '%online-reservations.html%'
    AND (ARRAY_LENGTH(focus_campaigns) = 0
         OR CE.campaign_final IN UNNEST(focus_campaigns))
  GROUP BY 1, 2, 3
)

SELECT
  L.week_id_date,
  L.campaign_final,
  COUNT(DISTINCT L.session_id) AS `Client Education Page Views`,
  COUNT(DISTINCT CASE WHEN I.engagement_flag = 1 THEN L.session_id END)                  AS `Engaged Sessions`,
  COUNT(DISTINCT CASE WHEN H2.hit_datetime > L.ce_min_hit_datetime AND HIN_cfg.interaction_id = 5  THEN L.session_id END) AS `Config Starts`,
  COUNT(DISTINCT CASE WHEN H2.hit_datetime > L.ce_min_hit_datetime AND HIN_cfg.interaction_id = 11 THEN L.session_id END) AS `Config Completes`,
  COUNT(DISTINCT CASE WHEN ECOMM.interaction_id = 227 AND H2.hit_datetime > L.ce_min_hit_datetime THEN L.session_id END)  AS `Find Matches`,
  COUNT(DISTINCT CASE WHEN ECOMM.interaction_id = 221 AND H2.hit_datetime > L.ce_min_hit_datetime THEN L.session_id END)  AS `Reservations`
FROM CLIENT_EDU_LANDINGS L
LEFT JOIN `your-project.your_dataset.GA4_hit` H2
  ON  L.session_id        = H2.session_id
  AND H2.visit_start_date BETWEEN report_week_start AND report_week_end
LEFT JOIN `your-project.your_dataset.GA4_hit_interaction_nameplate` HIN_cfg
  ON  H2.hit_id           = HIN_cfg.hit_id
  AND H2.visit_start_date = HIN_cfg.visit_start_date
LEFT JOIN `your-project.your_dataset.GA4_ecomm_hit_interaction_nameplate` ECOMM
  ON  L.session_id        = ECOMM.session_id
  AND ECOMM.visit_start_date BETWEEN report_week_start AND report_week_end
LEFT JOIN INTERACTIONS I
  ON  L.session_id = I.session_id
GROUP BY L.week_id_date, L.campaign_final
ORDER BY L.week_id_date DESC, L.campaign_final
;
