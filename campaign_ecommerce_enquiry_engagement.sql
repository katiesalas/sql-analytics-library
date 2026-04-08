-- ============================================================
-- Campaign Ecommerce Enquiry & Engagement Analysis
-- ============================================================
-- Purpose:  Count ecommerce interaction sessions (e.g. Find Matches,
--           Reservations) by month, nameplate, channel, and campaign.
--           Uses taxonomy lookup tables to enrich channel and campaign
--           from session-level campaign JSON.
-- Grain:    Monthly
-- Output:   sessions per interaction x channel x campaign x nameplate
-- ============================================================
-- To run: update start_date and end_date only.
-- ============================================================

DECLARE start_date DATE DEFAULT '2026-03-01';
DECLARE end_date   DATE DEFAULT '2026-03-31';

-- ============================================================
-- Configuration — update to match your schema
-- ============================================================
-- Dataset:        your-project.your_dataset
-- Reporting DS:   your-project.your_reporting_dataset
-- Interaction IDs: update 221/227 to match your ecomm interactions
-- ============================================================

WITH

-- ============================================================
-- 1. Campaign Lookup Layers
--    Three join paths to resolve campaign + channel:
--    (a) campaign_key match, (b) SA360 ID, (c) engine ID, (d) campaign name
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
--    Resolves channel and campaign name via taxonomy lookups.
--    Falls back through four join paths before using raw session value.
-- ============================================================
channel_enrich AS (
  SELECT
    SN.session_id,
    SN.visit_start_date,
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
      EI.campaign_name,  CN.campaign_name,
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
  WHERE SN.visit_start_date BETWEEN start_date AND end_date
)

-- ============================================================
-- 3. Final Output
-- ============================================================
SELECT
  EXTRACT(MONTH FROM E.visit_start_date)  AS month,
  E.nameplate_code,
  NP.nameplate_desc,

  CASE
    WHEN E.interaction_id = 227 THEN 'Find Matches'
    WHEN E.interaction_id = 221 THEN 'Reservation'
  END                                     AS interaction_name,

  E.interaction_id,
  CE.channel_grouping_final               AS channel_grouping,

  CASE
    WHEN CE.channel_grouping_final IN (
      'Paid Search', 'Paid Social', 'Other Advertising',
      'Paid Display & Video', 'Display',
      'Paid Display, Video & Digital Audio',
      'Paid Cross Network', 'Paid Unclassified'
    ) THEN 'Paid'
    ELSE 'Unpaid'
  END                                     AS medium_type,

  CE.campaign_final                       AS campaign,
  COUNT(DISTINCT E.session_id)            AS sessions

FROM `your-project.your_dataset.GA4_ecomm_hit_interaction_nameplate` E
JOIN channel_enrich CE
  ON  E.session_id       = CE.session_id
  AND E.visit_start_date = CE.visit_start_date
LEFT JOIN `your-project.your_dataset.GA4_lookup_nameplate` NP
  ON E.nameplate_code = NP.nameplate_code
WHERE E.visit_start_date BETWEEN start_date AND end_date
  AND E.interaction_id IN (221, 227)      -- update IDs as needed
GROUP BY 1, 2, 3, 4, 5, 6, 7, 8
ORDER BY 1, 2
;
