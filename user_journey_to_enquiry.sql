-- ============================================================
-- User Journey to Enquiry
-- ============================================================
-- Reconstructs the full page-by-page journey for sessions that
-- contained an enquiry form submit. Uses LEAD (not LAG) to look
-- forward in the session and build a journey string.
--
-- Contrast with enquiry_form_source_analysis.sql:
--   That query uses LAG to show the single previous page before
--   the form. This query shows the entire session path for
--   enquiry sessions — up to 21 steps.
--
-- Key technique:
--   LEAD(page_path, 1) captures the next page in hit order.
--   STRING_AGG builds a pipe-delimited journey string per session.
--   SPLIT then pivots the string into page1–page21 columns.
--   Final filter keeps only sessions where FORM SUBMIT appears
--   somewhere in the journey.
--
-- Known limitation:
--   STRING_AGG() OVER (PARTITION BY session_id) does not include
--   ORDER BY in the window, so journey step order is not guaranteed.
--   If exact ordering is critical, convert to a GROUP BY aggregate:
--   STRING_AGG(next_page, '|' ORDER BY hit_number, hit_datetime)
--
-- Output: one row per unique journey path x session, with
--         visitor and session counts.
-- ============================================================
-- To run: update rep_from, rep_to, Test_Market, Test_Brand.
--         Update brand/NP page REGEXP patterns for your market.
-- ============================================================

DECLARE rep_from    DATE;
DECLARE rep_to      DATE;
DECLARE Test_Market STRING;
DECLARE Test_Brand  STRING;

SET rep_from    = '2024-08-01';
SET rep_to      = '2024-08-31';
SET Test_Market = 'your-market';   -- e.g. 'US'
SET Test_Brand  = 'your-brand';    -- e.g. 'Land Rover'

-- ============================================================
-- STEP 1 + 2: Hit-level data for enquiry sessions
-- Subquery identifies sessions with enquiry_flag = 1.
-- LEAD captures the next page within each session.
-- ============================================================
WITH uj AS (
  SELECT
    h.market_code,
    h.hit_datetime,
    h.session_id,
    h.visitor_id,
    h.hit_number,
    h.event_name,
    h.event_category,
    h.event_action,
    h.page_path AS page_path,
    CASE
      WHEN h.page_path != LEAD(h.page_path, 1) OVER (PARTITION BY h.session_id ORDER BY h.hit_number)
        THEN LEAD(h.page_path, 1) OVER (PARTITION BY h.session_id ORDER BY h.hit_number)
      WHEN h.event_name LIKE '%nav%'
        THEN CONCAT('Navigation-', h.page_path)
    END AS next_page
  FROM `your-project.your_dataset.GA4_hit` AS h
  INNER JOIN `your-project.your_dataset.GA4_session` AS s
    ON  h.session_id       = s.session_id
    AND h.visit_start_date = s.visit_start_date
  INNER JOIN `your-project.your_dataset.GA4_lookup_market` AS lkm
    ON  h.market_code = lkm.market_code
  WHERE h.visit_start_date BETWEEN rep_from AND rep_to
    AND lkm.market_type = 'NSC'
    AND h.market_code   = Test_Market
    AND h.brand         = Test_Brand
    -- Subquery: sessions that had at least one enquiry interaction
    AND h.session_id IN (
      SELECT h2.session_id
      FROM `your-project.your_dataset.GA4_hit` AS h2
      INNER JOIN `your-project.your_dataset.GA4_session` AS s2
        ON  h2.session_id       = s2.session_id
        AND h2.visit_start_date = s2.visit_start_date
      INNER JOIN `your-project.your_dataset.GA4_lookup_market` AS m
        ON  h2.market_code = m.market_code
      LEFT JOIN (
        SELECT
          sn.*,
          lki.* EXCEPT (interaction_id),
          lki.interaction_id AS Int_id
        FROM `your-project.your_dataset.GA4_session_interaction_nameplate` AS sn
        INNER JOIN `your-project.your_dataset.GA4_lookup_interaction` AS lki
          ON sn.interaction_id = lki.interaction_id
        WHERE sn.visit_start_date BETWEEN rep_from AND rep_to
      ) AS sni
        ON s2.session_id = sni.session_id
      WHERE h2.visit_start_date BETWEEN rep_from AND rep_to
        AND h2.market_code = Test_Market
        AND h2.brand       = Test_Brand
        AND sni.enquiry_flag = 1
    )
  GROUP BY 1, 2, 3, 4, 5, 6, 7, 8, 9
),

-- ============================================================
-- STEP 3: Categorise next_page into readable labels.
-- Update REGEXP patterns to match your market's URL structure.
-- ============================================================
uj0 AS (
  SELECT
    market_code,
    session_id,
    visitor_id,
    hit_datetime,
    hit_number,
    event_name,
    event_category,
    event_action,
    page_path,
    CASE
      WHEN next_page LIKE '%Navigation%'
        THEN next_page
      WHEN REGEXP_CONTAINS(next_page, r'your-brand-page-url-pattern')
        THEN 'Brand Page'
      WHEN REGEXP_CONTAINS(next_page, r'your-nameplate-overview-page-url-pattern')
        THEN 'NP Overview Page'
      WHEN next_page LIKE '%/configure%'
        OR next_page LIKE '%buildyour%'
        THEN 'Config'
      ELSE next_page
    END AS next_page
  FROM uj
),

-- ============================================================
-- STEP 4: Add row_flag (deduplicate repeated next_page values)
--         and enq_flag (mark form submit hits)
-- ============================================================
uj1 AS (
  SELECT
    uj0.*,
    CASE
      WHEN next_page != LEAD(next_page, 1) OVER (PARTITION BY session_id ORDER BY hit_number, hit_datetime)
      THEN 1
    END AS row_flag,
    CASE
      WHEN event_category LIKE '%dataLayer form submits%' THEN 1
    END AS enq_flag
  FROM uj0
  WHERE next_page IS NOT NULL
),

-- ============================================================
-- STEP 6: Keep first occurrence of each next_page per session.
--         Mark form submit steps with FORM SUBMIT prefix.
-- ============================================================
page_seq AS (
  SELECT
    visitor_id,
    session_id,
    CASE
      WHEN enq_flag = 1 THEN CONCAT('FORM SUBMIT-', next_page)
      ELSE next_page
    END AS next_page
  FROM uj1
  WHERE row_flag = 1
)

-- ============================================================
-- STEPS 7–9: Build journey string, split into columns,
--            filter to sessions containing FORM SUBMIT.
-- ============================================================
SELECT
  page1, page2, page3, page4, page5, page6, page7,
  page8, page9, page10, page11, page12, page13, page14,
  page15, page16, page17, page18, page19, page20, page21,
  COUNT(DISTINCT visitor_id) AS visitors,
  COUNT(DISTINCT session_id) AS sessions,
  NULL                       AS forms   -- placeholder; not yet populated
FROM (
  -- Step 8: split journey string into positional page columns
  SELECT
    visitor_id,
    session_id,
    SPLIT(journey, '|')[SAFE_OFFSET(0)]  AS page1,
    SPLIT(journey, '|')[SAFE_OFFSET(1)]  AS page2,
    SPLIT(journey, '|')[SAFE_OFFSET(2)]  AS page3,
    SPLIT(journey, '|')[SAFE_OFFSET(3)]  AS page4,
    SPLIT(journey, '|')[SAFE_OFFSET(4)]  AS page5,
    SPLIT(journey, '|')[SAFE_OFFSET(5)]  AS page6,
    SPLIT(journey, '|')[SAFE_OFFSET(6)]  AS page7,
    SPLIT(journey, '|')[SAFE_OFFSET(7)]  AS page8,
    SPLIT(journey, '|')[SAFE_OFFSET(8)]  AS page9,
    SPLIT(journey, '|')[SAFE_OFFSET(9)]  AS page10,
    SPLIT(journey, '|')[SAFE_OFFSET(10)] AS page11,
    SPLIT(journey, '|')[SAFE_OFFSET(11)] AS page12,
    SPLIT(journey, '|')[SAFE_OFFSET(12)] AS page13,
    SPLIT(journey, '|')[SAFE_OFFSET(13)] AS page14,
    SPLIT(journey, '|')[SAFE_OFFSET(14)] AS page15,
    SPLIT(journey, '|')[SAFE_OFFSET(15)] AS page16,
    SPLIT(journey, '|')[SAFE_OFFSET(16)] AS page17,
    SPLIT(journey, '|')[SAFE_OFFSET(17)] AS page18,
    SPLIT(journey, '|')[SAFE_OFFSET(18)] AS page19,
    SPLIT(journey, '|')[SAFE_OFFSET(19)] AS page20,
    SPLIT(journey, '|')[SAFE_OFFSET(20)] AS page21
  FROM (
    -- Step 7: aggregate page steps into a pipe-delimited journey string
    -- Note: window STRING_AGG has no ORDER BY — step order not guaranteed
    SELECT DISTINCT
      visitor_id,
      session_id,
      STRING_AGG(next_page, '|') OVER (PARTITION BY visitor_id, session_id) AS journey
    FROM page_seq
  )
)
WHERE (
     page1  LIKE '%FORM SUBMIT%' OR page2  LIKE '%FORM SUBMIT%'
  OR page3  LIKE '%FORM SUBMIT%' OR page4  LIKE '%FORM SUBMIT%'
  OR page5  LIKE '%FORM SUBMIT%' OR page6  LIKE '%FORM SUBMIT%'
  OR page7  LIKE '%FORM SUBMIT%' OR page8  LIKE '%FORM SUBMIT%'
  OR page9  LIKE '%FORM SUBMIT%' OR page10 LIKE '%FORM SUBMIT%'
  OR page11 LIKE '%FORM SUBMIT%' OR page12 LIKE '%FORM SUBMIT%'
  OR page13 LIKE '%FORM SUBMIT%' OR page14 LIKE '%FORM SUBMIT%'
  OR page15 LIKE '%FORM SUBMIT%' OR page16 LIKE '%FORM SUBMIT%'
  OR page17 LIKE '%FORM SUBMIT%' OR page18 LIKE '%FORM SUBMIT%'
  OR page19 LIKE '%FORM SUBMIT%' OR page20 LIKE '%FORM SUBMIT%'
)
GROUP BY 1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21
ORDER BY 1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21
;
