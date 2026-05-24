-- ============================================================
-- REGULAR REPORT: DX_Page Monthly Report
-- ============================================================
-- Engaged vs Not Engaged | By product + Paid / Not Paid
-- To run: update rep_from and rep_to only.
-- ============================================================
-- Key design notes:
--   - ROW_NUMBER deduplication in session_product ensures each
--     session is attributed to one brand only. Priority: page page
--     visit wins; alphabetical tiebreak.
--   - : visitor-based (matches dashboard methodology)
--   - Interaction_2s: session-based
-- ============================================================

DECLARE rep_from DATE DEFAULT '2026-03-01';
DECLARE rep_to   DATE DEFAULT '2026-03-31';

WITH

product_lookup AS (
  SELECT
    NP.product_code,
    CASE
      WHEN NP.product_code IN ('product_1','product_2') THEN 'Product_A'

      -- Add further product codes and labels as needed
    END AS product_label
  FROM `your-project.your_dataset.GA4_lookup_product` NP
),

us_sessions AS (
  SELECT DISTINCT session_id, visit_start_date
  FROM `your-project.your_dataset.GA4_hit`
  WHERE visit_start_date BETWEEN rep_from AND rep_to
    AND market_code = 'your-market'   -- e.g. 'US'
),

page_visits AS (
  SELECT DISTINCT
    session_id,
    visit_start_date,
    CASE
      -- Update page paths to match your market's page URLs
      WHEN page_path = 'your-product_A_page-url' THEN 'Product_A'
    END AS product_label
  FROM `your-project.your_dataset.GA4_hit`
  WHERE visit_start_date BETWEEN rep_from AND rep_to
    AND market_code = 'your-market'
    AND page_path IN (
      'your-product_A_page-url' 
    )
),

config_interactions AS (
  SELECT
    C.session_id,
    C.visit_start_date,
    NL.product_label,
    MAX(CASE WHEN C.interaction_id = 5  THEN 1 ELSE 0 END) AS had_config_start,
    MAX(CASE WHEN C.interaction_id = 11 THEN 1 ELSE 0 END) AS had_config_complete
  FROM `your-project.your_dataset.GA4_session_interaction_product` C
  LEFT JOIN product_lookup NL ON C.product_code = NL.product_code
  WHERE C.visit_start_date BETWEEN rep_from AND rep_to
    AND C.interaction_id IN (5, 11)
  GROUP BY 1, 2, 3
),

ecomm_interactions AS (
  SELECT
    E.session_id,
    E.visit_start_date,
    NL.product_label,
    MIN(CASE WHEN E.interaction_id = 227 THEN E.visitor_id ELSE NULL END) AS interaction_visitor,
    MAX(CASE WHEN E.interaction_id = 227 THEN 1 ELSE 0 END)               AS had_interaction,
    MAX(CASE WHEN E.interaction_id = 221 THEN 1 ELSE 0 END)               AS had_Interaction_2
  FROM `your-project.your_dataset.GA4_ecomm_hit_interaction_product` E
  LEFT JOIN product_lookup NL ON E.product_code = NL.product_code
  WHERE E.visit_start_date BETWEEN rep_from AND rep_to
    AND E.interaction_id IN (221, 227)
  GROUP BY 1, 2, 3
),

session_engagement AS (
  SELECT
    C.session_id,
    C.visit_start_date,
    MAX(CASE WHEN GL.engagement_flag = 1 THEN 1 ELSE 0 END) AS is_engaged
  FROM `your-project.your_dataset.GA4_session_interaction_product` C
  LEFT JOIN `your-project.your_dataset.GA4_lookup_interaction` GL
    ON C.interaction_id = GL.interaction_id
  WHERE C.visit_start_date BETWEEN rep_from AND rep_to
  GROUP BY 1, 2
),

all_product_sessions AS (
  SELECT DISTINCT
    C.session_id,
    C.visit_start_date,
    NL.product_label
  FROM `your-project.your_dataset.GA4_session_interaction_product` C
  LEFT JOIN product_lookup NL ON C.product_code = NL.product_code
  WHERE C.visit_start_date BETWEEN rep_from AND rep_to
    AND NL.product_label IS NOT NULL
),

-- One brand per session: page page visit wins; alphabetical tiebreak
session_product AS (
  SELECT session_id, visit_start_date, product_label
  FROM (
    SELECT
      sns.session_id,
      sns.visit_start_date,
      sns.product_label,
      ROW_NUMBER() OVER (
        PARTITION BY sns.session_id
        ORDER BY
          CASE WHEN cv.session_id IS NOT NULL THEN 0 ELSE 1 END,
          sns.product_label ASC
      ) AS rn
    FROM (
      SELECT DISTINCT session_id, visit_start_date, product_label FROM all_product_sessions
      UNION DISTINCT
      SELECT DISTINCT session_id, visit_start_date, product_label FROM page_visits WHERE product_label IS NOT NULL
    ) sns
    LEFT JOIN page_visits cv
      ON  sns.session_id      = cv.session_id
      AND sns.product_label = cv.product_label
  )
  WHERE rn = 1
),

session_base AS (
  SELECT
    SN.session_id,
    SN.product_label AS product,
    CASE
      WHEN B.channel_grouping IN (
        'Paid Display & Video', 'Paid Search', 'Paid Social', 'PMAX',
        'Paid Display, Video & Digital Audio', 'Paid Cross Network', 'Paid Unclassified'
      ) THEN 'Paid'
      ELSE 'Not Paid'
    END AS medium_type,
    COALESCE(ENG.is_engaged, 0) AS is_engaged,
    CASE
      WHEN CV.session_id IS NOT NULL THEN 'Engaged with Client Education Page'
      ELSE 'Not Engaged with Client Education Page'
    END AS page_status,
    COALESCE(CI.had_interaction_1,    0) AS had_interaction_1,
    COALESCE(CI.had_interaction_2, 0) AS had_interaction_2,
    COALESCE(EI.had_interaction_3,    0) AS had_interaction_3,
    COALESCE(EI.had_Interaction_4,     0) AS had_interaction_4,
    EI.find_matches_visitor               AS had_interaction_5
  FROM session_product SN
  INNER JOIN us_sessions US
    ON  SN.session_id       = US.session_id
    AND SN.visit_start_date = US.visit_start_date
  LEFT JOIN `your-project.your_dataset.GA4_session` B
    ON  SN.session_id       = B.session_id
    AND SN.visit_start_date = B.visit_start_date
  LEFT JOIN page_visits CV
    ON  SN.session_id      = CV.session_id
    AND SN.product_label = CV.product_label
  LEFT JOIN config_interactions CI
    ON  SN.session_id      = CI.session_id
    AND SN.product_label = CI.product_label
  LEFT JOIN ecomm_interactions EI
    ON  SN.session_id      = EI.session_id
    AND SN.product_label = EI.product_label
  LEFT JOIN session_engagement ENG
    ON  SN.session_id       = ENG.session_id
    AND SN.visit_start_date = ENG.visit_start_date
)

SELECT
  product,
  medium_type,
  page_status,
  COUNT(DISTINCT session_id)                                                              AS sessions,
  SUM(is_engaged)                                                                         AS engaged_sessions,
  ROUND(SAFE_DIVIDE(SUM(is_engaged), COUNT(DISTINCT session_id)) * 100, 1)               AS engaged_session_rate_pct,
  SUM(had_config_start)                                                                   AS interacton_1,
  SUM(had_config_complete)                                                                AS interaction_2,
  ROUND(SAFE_DIVIDE(SUM(had_config_complete), SUM(had_config_start)) * 100, 1)           AS interaction_rate_pct,
  COUNT(DISTINCT CASE WHEN had_find_matches = 1 THEN find_matches_visitor_id END)         AS interaction_3,
  ROUND(SAFE_DIVIDE(
    COUNT(DISTINCT CASE WHEN had_find_matches = 1 THEN find_matches_visitor_id END),
    COUNT(DISTINCT session_id)
  ) * 100, 1)                                                                             AS finteractoin_3_rate_pct,
  COUNT(DISTINCT CASE WHEN had_Interaction_2 = 1 THEN session_id END)                      AS Interaction_2_requests,
  ROUND(SAFE_DIVIDE(
    COUNT(DISTINCT CASE WHEN had_Interaction_2 = 1 THEN session_id END),
    COUNT(DISTINCT session_id)
  ) * 100, 1)                                                                             AS Interaction_2_request_rate_pct
FROM session_base
GROUP BY 1, 2, 3
ORDER BY product, medium_type, page_status
;
