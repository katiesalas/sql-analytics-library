-- ============================================================
-- Enquiry Form Source Analysis
-- ============================================================
-- Purpose:  Identifies which page or CTA a user came from before
--           opening, changing, or submitting an enquiry form.
--           Uses LAG window function to look back one hit in the
--           session and capture the previous page path.
--
-- Key technique: LAG(page_path, 1) OVER (PARTITION BY session_id
--   ORDER BY hit_number) captures the previous page in session order.
--   row_flag = 1 marks the first hit on each new page.
--
-- Segments:
--   Form Open   — page_view hit on a form URL
--   Form Change — form change event on a form URL
--   Form Submit — form submit event on a form URL
--
-- Potential adaptation — MLPX Find Matches source:
--   Replace the EXISTS subquery with MLPX interaction filter
--   (e.g. interaction_id = 227) and swap the form REGEXP patterns
--   for MLPX page/event patterns. The LAG previous_page logic
--   transfers directly and shows where users came from before
--   clicking Find Matches.
-- ============================================================
-- To run: update rep_from and rep_to only.
-- ============================================================

DECLARE rep_from     DATE;
DECLARE rep_to       DATE;
DECLARE Test_Market  STRING;
DECLARE Test_Brand   STRING;
DECLARE KPI_1        NUMERIC;  -- Form Submit interaction ID
DECLARE KPI_2        NUMERIC;  -- Form Arrival interaction ID
DECLARE KPI_3        NUMERIC;  -- reserved for future use
DECLARE KPI_4        NUMERIC;  -- reserved for future use

SET rep_from    = '2025-07-01';
SET rep_to      = '2025-07-31';
SET Test_Market = 'your-market';   -- e.g. 'US'
SET Test_Brand  = 'your-brand';    -- e.g. 'Land Rover'
SET KPI_1 = 15;   -- update to your form submit interaction ID
SET KPI_2 = 67;   -- update to your form arrival interaction ID

WITH

-- ============================================================
-- BASE CTEs
-- Captures hit-level data with previous page via LAG.
-- row_flag = 1 = first hit on a new page within the session.
-- Three variants with slightly different event filters:
--   po = form opens (page_view only)
--   pc = form changes (excludes page_view + noise events)
--   ps = form submits (excludes page_view + noise + form change events)
-- ============================================================

po AS (
  SELECT
    h.market_code,
    s.visit_start_date,
    hn.nameplate_code,
    s.channel_grouping,
    s.returning_visitor,
    h.session_id,
    h.visitor_id,
    h.hit_number,
    h.event_name,
    h.event_category,
    h.event_action,
    h.page_path AS page,
    CASE
      WHEN h.page_path != LAG(h.page_path, 1) OVER (PARTITION BY h.session_id ORDER BY h.hit_number)
      THEN LAG(h.page_path, 1) OVER (PARTITION BY h.session_id ORDER BY h.hit_number)
    END AS previous_page,
    CASE
      WHEN h.page_path != LAG(h.page_path, 1) OVER (PARTITION BY h.session_id ORDER BY h.hit_number)
      THEN 1
    END AS row_flag
  FROM `your-project.your_dataset.GA4_hit` AS h
  INNER JOIN `your-project.your_dataset.GA4_session` AS s
    ON  h.session_id       = s.session_id
    AND h.visit_start_date = s.visit_start_date
  LEFT JOIN `your-project.your_dataset.GA4_hit_interaction_nameplate` hn
    ON  h.hit_id           = hn.hit_id
    AND h.visit_start_date = hn.visit_start_date
  LEFT JOIN `your-project.your_dataset.GA4_lookup_interaction` lki
    ON  hn.interaction_id  = lki.interaction_id
  INNER JOIN `your-project.your_dataset.GA4_lookup_market` lkm
    ON  h.market_code      = lkm.market_code
  WHERE h.visit_start_date BETWEEN rep_from AND rep_to
    AND lkm.market_type = 'NSC'         -- update market_type filter as needed
    AND h.market_code   = Test_Market
    AND h.brand         = Test_Brand
    AND EXISTS (
      SELECT sn.session_id
      FROM `your-project.your_dataset.GA4_session_interaction_nameplate` AS sn
      INNER JOIN `your-project.your_dataset.GA4_lookup_interaction` AS lki
        ON sn.interaction_id = lki.interaction_id
      WHERE sn.visit_start_date BETWEEN rep_from AND rep_to
        AND lkm.market_type    = 'NSC'
        AND sn.market_code     = Test_Market
        AND sn.brand           = Test_Brand
        AND lki.interaction_id = KPI_2  -- arrival/trigger interaction
    )
),

pc AS (
  SELECT
    h.market_code,
    s.visit_start_date,
    hn.nameplate_code,
    s.channel_grouping,
    s.returning_visitor,
    h.session_id,
    h.visitor_id,
    h.hit_number,
    h.event_name,
    h.event_category,
    h.event_action,
    h.page_path AS page,
    CASE
      WHEN h.page_path != LAG(h.page_path, 1) OVER (PARTITION BY h.session_id ORDER BY h.hit_number)
      THEN LAG(h.page_path, 1) OVER (PARTITION BY h.session_id ORDER BY h.hit_number)
    END AS previous_page,
    CASE
      WHEN h.page_path != LAG(h.page_path, 1) OVER (PARTITION BY h.session_id ORDER BY h.hit_number)
      THEN 1
    END AS row_flag
  FROM `your-project.your_dataset.GA4_hit` AS h
  INNER JOIN `your-project.your_dataset.GA4_session` AS s
    ON  h.session_id       = s.session_id
    AND h.visit_start_date = s.visit_start_date
  LEFT JOIN `your-project.your_dataset.GA4_hit_interaction_nameplate` hn
    ON  h.hit_id           = hn.hit_id
    AND h.visit_start_date = hn.visit_start_date
  LEFT JOIN `your-project.your_dataset.GA4_lookup_interaction` lki
    ON  hn.interaction_id  = lki.interaction_id
  INNER JOIN `your-project.your_dataset.GA4_lookup_market` lkm
    ON  h.market_code      = lkm.market_code
  WHERE h.visit_start_date BETWEEN rep_from AND rep_to
    AND NOT REGEXP_CONTAINS(LOWER(h.event_name),     r'page_view')
    AND NOT REGEXP_CONTAINS(LOWER(h.event_category), r'intent|intscore|target')
    AND lkm.market_type = 'NSC'
    AND h.market_code   = Test_Market
    AND h.brand         = Test_Brand
    AND EXISTS (
      SELECT sn.session_id
      FROM `your-project.your_dataset.GA4_session_interaction_nameplate` AS sn
      INNER JOIN `your-project.your_dataset.GA4_lookup_interaction` AS lki
        ON sn.interaction_id = lki.interaction_id
      WHERE sn.visit_start_date BETWEEN rep_from AND rep_to
        AND lkm.market_type    = 'NSC'
        AND sn.market_code     = Test_Market
        AND sn.brand           = Test_Brand
        AND lki.interaction_id = KPI_2
    )
),

ps AS (
  SELECT
    h.market_code,
    s.visit_start_date,
    hn.nameplate_code,
    s.channel_grouping,
    s.returning_visitor,
    h.session_id,
    h.visitor_id,
    h.hit_number,
    h.event_name,
    h.event_category,
    h.event_action,
    h.page_path AS page,
    CASE
      WHEN h.page_path != LAG(h.page_path, 1) OVER (PARTITION BY h.session_id ORDER BY h.hit_number)
      THEN LAG(h.page_path, 1) OVER (PARTITION BY h.session_id ORDER BY h.hit_number)
    END AS previous_page,
    CASE
      WHEN h.page_path != LAG(h.page_path, 1) OVER (PARTITION BY h.session_id ORDER BY h.hit_number)
      THEN 1
    END AS row_flag
  FROM `your-project.your_dataset.GA4_hit` AS h
  INNER JOIN `your-project.your_dataset.GA4_session` AS s
    ON  h.session_id       = s.session_id
    AND h.visit_start_date = s.visit_start_date
  LEFT JOIN `your-project.your_dataset.GA4_hit_interaction_nameplate` hn
    ON  h.hit_id           = hn.hit_id
    AND h.visit_start_date = hn.visit_start_date
  LEFT JOIN `your-project.your_dataset.GA4_lookup_interaction` lki
    ON  hn.interaction_id  = lki.interaction_id
    AND lki.enquiry_flag   = 1
  INNER JOIN `your-project.your_dataset.GA4_lookup_market` lkm
    ON  h.market_code      = lkm.market_code
  WHERE h.visit_start_date BETWEEN rep_from AND rep_to
    AND NOT REGEXP_CONTAINS(LOWER(h.event_name),     r'page_view')
    AND NOT REGEXP_CONTAINS(LOWER(h.event_category), r'intent|intscore|target|omg_enquiry_hit|omg_engagement_hit|form change')
    AND lkm.market_type = 'NSC'
    AND h.market_code   = Test_Market
    AND h.brand         = Test_Brand
    AND EXISTS (
      SELECT sn.session_id
      FROM `your-project.your_dataset.GA4_session_interaction_nameplate` AS sn
      INNER JOIN `your-project.your_dataset.GA4_lookup_interaction` AS lki
        ON sn.interaction_id = lki.interaction_id
      WHERE sn.visit_start_date BETWEEN rep_from AND rep_to
        AND lkm.market_type    = 'NSC'
        AND sn.market_code     = Test_Market
        AND sn.brand           = Test_Brand
        AND lki.enquiry_flag   = 1
        AND lki.interaction_id = KPI_1
    )
),

-- ============================================================
-- FILTER CTEs
-- ============================================================

fo AS (
  SELECT
    po.market_code, po.visit_start_date, po.nameplate_code,
    CASE
      WHEN po.channel_grouping IN ('Paid Display & Video', 'Display') THEN 'Paid Display, Video & Digital Audio'
      WHEN po.channel_grouping IN ('PMAX', 'Cross Network')           THEN 'Paid Cross Network'
      WHEN po.channel_grouping = 'Unclassified'                       THEN 'Paid Unclassified'
      ELSE po.channel_grouping
    END AS channel_grouping,
    CASE WHEN po.returning_visitor = 1 THEN 'Returning' ELSE 'New' END AS new_ret_vis,
    po.page,
    CASE
      WHEN po.previous_page LIKE '%buildyour%' THEN 'Config'
      WHEN po.previous_page LIKE '%forms%'     THEN 'Form'
      ELSE po.previous_page
    END AS previous_page,
    po.session_id, po.visitor_id
  FROM po
  WHERE po.row_flag = 1
    -- Update REGEXP to match your form URL patterns
    AND REGEXP_CONTAINS(LOWER(po.page), r'(?i)((formcode=.*|dlform\/.*)(raq|qq|rq|str|co([0-9]|-|$)|fin2)|jlrforms.*(raq|qq|quote|rmi))')
    AND po.event_name LIKE '%page_view%'
),

fc AS (
  SELECT
    pc.market_code, pc.visit_start_date, pc.nameplate_code,
    CASE
      WHEN pc.channel_grouping IN ('Paid Display & Video', 'Display') THEN 'Paid Display, Video & Digital Audio'
      WHEN pc.channel_grouping IN ('PMAX', 'Cross Network')           THEN 'Paid Cross Network'
      WHEN pc.channel_grouping = 'Unclassified'                       THEN 'Paid Unclassified'
      ELSE pc.channel_grouping
    END AS channel_grouping,
    CASE WHEN pc.returning_visitor = 1 THEN 'Returning' ELSE 'New' END AS new_ret_vis,
    pc.page,
    CASE
      WHEN pc.previous_page LIKE '%buildyour%' THEN 'Config'
      WHEN pc.previous_page LIKE '%forms%'     THEN 'Form'
      ELSE pc.previous_page
    END AS previous_page,
    pc.session_id, pc.visitor_id
  FROM pc
  WHERE pc.row_flag = 1
    AND REGEXP_CONTAINS(LOWER(pc.event_action), r'(?i)((formcode=.*|dlform\/.*)(raq|qq|rq|str|co([0-9]|-|$)|fin2)|jlrforms.*(raq|qq|quote|rmi))')
    AND pc.event_category LIKE '%form change%'
),

fs AS (
  SELECT
    ps.market_code, ps.visit_start_date, ps.nameplate_code,
    CASE
      WHEN ps.channel_grouping IN ('Paid Display & Video', 'Display') THEN 'Paid Display, Video & Digital Audio'
      WHEN ps.channel_grouping IN ('PMAX', 'Cross Network')           THEN 'Paid Cross Network'
      WHEN ps.channel_grouping = 'Unclassified'                       THEN 'Paid Unclassified'
      ELSE ps.channel_grouping
    END AS channel_grouping,
    CASE WHEN ps.returning_visitor = 1 THEN 'Returning' ELSE 'New' END AS new_ret_vis,
    ps.page,
    CASE
      WHEN ps.previous_page LIKE '%buildyour%' THEN 'Config'
      WHEN ps.previous_page LIKE '%forms%'     THEN 'Form'
      ELSE ps.previous_page
    END AS previous_page,
    ps.session_id, ps.visitor_id
  FROM ps
  WHERE ps.row_flag = 1
    AND REGEXP_CONTAINS(LOWER(ps.event_action), r'(?i)((formcode=[^&]*|dlform\/.*)(raq|qq|rq|str|co([0-9]|-|$)|fin2)|jlrforms.*(raq|qq|quote|rmi))')
    AND ps.event_category LIKE '%form submit%'
)

-- ============================================================
-- FINAL OUTPUT
-- ============================================================
SELECT 'Form Open'   AS rep_group, fo.market_code, fo.visit_start_date, fo.nameplate_code,
  fo.channel_grouping, fo.new_ret_vis, fo.previous_page,
  COUNT(DISTINCT fo.session_id) AS sessions, COUNT(DISTINCT fo.visitor_id) AS visitors
FROM fo GROUP BY 1,2,3,4,5,6,7

UNION ALL

SELECT 'Form Change' AS rep_group, fc.market_code, fc.visit_start_date, fc.nameplate_code,
  fc.channel_grouping, fc.new_ret_vis, fc.previous_page,
  COUNT(DISTINCT fc.session_id) AS sessions, COUNT(DISTINCT fc.visitor_id) AS visitors
FROM fc GROUP BY 1,2,3,4,5,6,7

UNION ALL

SELECT 'Form Submit' AS rep_group, fs.market_code, fs.visit_start_date, fs.nameplate_code,
  fs.channel_grouping, fs.new_ret_vis, fs.previous_page,
  COUNT(DISTINCT fs.session_id) AS sessions, COUNT(DISTINCT fs.visitor_id) AS visitors
FROM fs GROUP BY 1,2,3,4,5,6,7

ORDER BY 1, 2, 3, 4, 5, 6, 7
;
