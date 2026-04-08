-- ============================================================
-- REGULAR REPORT: Client Education Page Monthly Report
-- ============================================================
-- Engaged vs Not Engaged | By Nameplate + Paid / Not Paid
-- To run: update rep_from and rep_to only.
-- ============================================================
-- Key design notes:
--   - ROW_NUMBER deduplication in session_nameplate ensures each
--     session is attributed to one brand only. Priority: CEP page
--     visit wins; alphabetical tiebreak.
--   - Find Matches: visitor-based (matches dashboard methodology)
--   - Reservations: session-based
-- ============================================================

DECLARE rep_from DATE DEFAULT '2026-03-01';
DECLARE rep_to   DATE DEFAULT '2026-03-31';

WITH

nameplate_lookup AS (
  SELECT
    NP.nameplate_code,
    CASE
      WHEN NP.nameplate_code IN ('L460','L461','L551','L560') THEN 'Range Rover'
      WHEN NP.nameplate_code = 'L663'                        THEN 'Defender'
      WHEN NP.nameplate_code IN ('L462','L550')              THEN 'Discovery'
      -- Add further nameplate codes and labels as needed
    END AS nameplate_label
  FROM `your-project.your_dataset.GA4_lookup_nameplate` NP
),

us_sessions AS (
  SELECT DISTINCT session_id, visit_start_date
  FROM `your-project.your_dataset.GA4_hit`
  WHERE visit_start_date BETWEEN rep_from AND rep_to
    AND market_code = 'your-market'   -- e.g. 'US'
),

cep_visits AS (
  SELECT DISTINCT
    session_id,
    visit_start_date,
    CASE
      -- Update page paths to match your market's CEP URLs
      WHEN page_path = 'your-range-rover-cep-url' THEN 'Range Rover'
      WHEN page_path = 'your-defender-cep-url'    THEN 'Defender'
      WHEN page_path = 'your-discovery-cep-url'   THEN 'Discovery'
    END AS nameplate_label
  FROM `your-project.your_dataset.GA4_hit`
  WHERE visit_start_date BETWEEN rep_from AND rep_to
    AND market_code = 'your-market'
    AND page_path IN (
      'your-range-rover-cep-url',
      'your-defender-cep-url',
      'your-discovery-cep-url'
    )
),

config_interactions AS (
  SELECT
    C.session_id,
    C.visit_start_date,
    NL.nameplate_label,
    MAX(CASE WHEN C.interaction_id = 5  THEN 1 ELSE 0 END) AS had_config_start,
    MAX(CASE WHEN C.interaction_id = 11 THEN 1 ELSE 0 END) AS had_config_complete
  FROM `your-project.your_dataset.GA4_session_interaction_nameplate` C
  LEFT JOIN nameplate_lookup NL ON C.nameplate_code = NL.nameplate_code
  WHERE C.visit_start_date BETWEEN rep_from AND rep_to
    AND C.interaction_id IN (5, 11)
  GROUP BY 1, 2, 3
),

ecomm_interactions AS (
  SELECT
    E.session_id,
    E.visit_start_date,
    NL.nameplate_label,
    MIN(CASE WHEN E.interaction_id = 227 THEN E.visitor_id ELSE NULL END) AS find_matches_visitor,
    MAX(CASE WHEN E.interaction_id = 227 THEN 1 ELSE 0 END)               AS had_find_matches,
    MAX(CASE WHEN E.interaction_id = 221 THEN 1 ELSE 0 END)               AS had_reservation
  FROM `your-project.your_dataset.GA4_ecomm_hit_interaction_nameplate` E
  LEFT JOIN nameplate_lookup NL ON E.nameplate_code = NL.nameplate_code
  WHERE E.visit_start_date BETWEEN rep_from AND rep_to
    AND E.interaction_id IN (221, 227)
  GROUP BY 1, 2, 3
),

session_engagement AS (
  SELECT
    C.session_id,
    C.visit_start_date,
    MAX(CASE WHEN GL.engagement_flag = 1 THEN 1 ELSE 0 END) AS is_engaged
  FROM `your-project.your_dataset.GA4_session_interaction_nameplate` C
  LEFT JOIN `your-project.your_dataset.GA4_lookup_interaction` GL
    ON C.interaction_id = GL.interaction_id
  WHERE C.visit_start_date BETWEEN rep_from AND rep_to
  GROUP BY 1, 2
),

all_nameplate_sessions AS (
  SELECT DISTINCT
    C.session_id,
    C.visit_start_date,
    NL.nameplate_label
  FROM `your-project.your_dataset.GA4_session_interaction_nameplate` C
  LEFT JOIN nameplate_lookup NL ON C.nameplate_code = NL.nameplate_code
  WHERE C.visit_start_date BETWEEN rep_from AND rep_to
    AND NL.nameplate_label IS NOT NULL
),

-- One brand per session: CEP page visit wins; alphabetical tiebreak
session_nameplate AS (
  SELECT session_id, visit_start_date, nameplate_label
  FROM (
    SELECT
      sns.session_id,
      sns.visit_start_date,
      sns.nameplate_label,
      ROW_NUMBER() OVER (
        PARTITION BY sns.session_id
        ORDER BY
          CASE WHEN cv.session_id IS NOT NULL THEN 0 ELSE 1 END,
          sns.nameplate_label ASC
      ) AS rn
    FROM (
      SELECT DISTINCT session_id, visit_start_date, nameplate_label FROM all_nameplate_sessions
      UNION DISTINCT
      SELECT DISTINCT session_id, visit_start_date, nameplate_label FROM cep_visits WHERE nameplate_label IS NOT NULL
    ) sns
    LEFT JOIN cep_visits cv
      ON  sns.session_id      = cv.session_id
      AND sns.nameplate_label = cv.nameplate_label
  )
  WHERE rn = 1
),

session_base AS (
  SELECT
    SN.session_id,
    SN.nameplate_label AS nameplate,
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
    END AS cep_status,
    COALESCE(CI.had_config_start,    0) AS had_config_start,
    COALESCE(CI.had_config_complete, 0) AS had_config_complete,
    COALESCE(EI.had_find_matches,    0) AS had_find_matches,
    COALESCE(EI.had_reservation,     0) AS had_reservation,
    EI.find_matches_visitor               AS find_matches_visitor_id
  FROM session_nameplate SN
  INNER JOIN us_sessions US
    ON  SN.session_id       = US.session_id
    AND SN.visit_start_date = US.visit_start_date
  LEFT JOIN `your-project.your_dataset.GA4_session` B
    ON  SN.session_id       = B.session_id
    AND SN.visit_start_date = B.visit_start_date
  LEFT JOIN cep_visits CV
    ON  SN.session_id      = CV.session_id
    AND SN.nameplate_label = CV.nameplate_label
  LEFT JOIN config_interactions CI
    ON  SN.session_id      = CI.session_id
    AND SN.nameplate_label = CI.nameplate_label
  LEFT JOIN ecomm_interactions EI
    ON  SN.session_id      = EI.session_id
    AND SN.nameplate_label = EI.nameplate_label
  LEFT JOIN session_engagement ENG
    ON  SN.session_id       = ENG.session_id
    AND SN.visit_start_date = ENG.visit_start_date
)

SELECT
  nameplate,
  medium_type,
  cep_status,
  COUNT(DISTINCT session_id)                                                              AS sessions,
  SUM(is_engaged)                                                                         AS engaged_sessions,
  ROUND(SAFE_DIVIDE(SUM(is_engaged), COUNT(DISTINCT session_id)) * 100, 1)               AS engaged_session_rate_pct,
  SUM(had_config_start)                                                                   AS config_starts,
  SUM(had_config_complete)                                                                AS config_completes,
  ROUND(SAFE_DIVIDE(SUM(had_config_complete), SUM(had_config_start)) * 100, 1)           AS config_completion_rate_pct,
  COUNT(DISTINCT CASE WHEN had_find_matches = 1 THEN find_matches_visitor_id END)         AS find_matches,
  ROUND(SAFE_DIVIDE(
    COUNT(DISTINCT CASE WHEN had_find_matches = 1 THEN find_matches_visitor_id END),
    COUNT(DISTINCT session_id)
  ) * 100, 1)                                                                             AS find_matches_rate_pct,
  COUNT(DISTINCT CASE WHEN had_reservation = 1 THEN session_id END)                      AS reservation_requests,
  ROUND(SAFE_DIVIDE(
    COUNT(DISTINCT CASE WHEN had_reservation = 1 THEN session_id END),
    COUNT(DISTINCT session_id)
  ) * 100, 1)                                                                             AS reservation_request_rate_pct
FROM session_base
GROUP BY 1, 2, 3
ORDER BY nameplate, medium_type, cep_status
;
