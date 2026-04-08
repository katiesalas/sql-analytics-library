-- ============================================================
-- Top Paid Pages by Channel
-- ============================================================
-- Ranks pages by session volume within each paid channel grouping
-- over a given date range. Useful for understanding which pages
-- are driving the most paid traffic — e.g. to prioritise landing
-- page optimisation or validate paid campaigns are hitting the
-- right pages.
--
-- Key design notes:
--   - ROW_NUMBER() ranks across the full date range (not per day)
--   - GA4_hit is joined only for page_path (large table — filter
--     dates tightly to keep costs down)
--   - GA4_lookup_interaction join is included but optional:
--     uncomment i.interaction_desc in SELECT and the interaction_id
--     filter in WHERE to narrow to sessions with specific interactions
--
-- Output: top N pages per channel, ordered by sessions DESC
-- ============================================================
-- To run: update rep_from, rep_to, Test_Market, Test_Brand, top_n.
-- ============================================================

DECLARE rep_from     DATE;
DECLARE rep_to       DATE;
DECLARE Test_Market  STRING;
DECLARE Test_Brand   STRING;
DECLARE top_n        INT64;   -- how many pages to return per channel

SET rep_from    = '2024-03-01';
SET rep_to      = '2024-05-30';
SET Test_Market = 'your-market';   -- e.g. 'US'
SET Test_Brand  = 'your-brand';    -- e.g. 'Land Rover'
SET top_n       = 3;

WITH ranked_paths AS (
  SELECT
    s.brand,
    s.market_code,
    s.channel_grouping,
    h.page_path,
    COUNT(DISTINCT s.session_id) AS sessions,
    ROW_NUMBER() OVER (
      PARTITION BY s.channel_grouping
      ORDER BY COUNT(DISTINCT s.session_id) DESC
    ) AS path_rank
  FROM `your-project.your_dataset.GA4_session_interaction_nameplate` AS v
  JOIN `your-project.your_dataset.GA4_session` AS s
    ON  s.session_id       = v.session_id
    AND v.visit_start_date = s.visit_start_date
  JOIN `your-project.your_dataset.GA4_hit` AS h
    ON  s.session_id       = h.session_id
    AND s.visit_start_date = h.visit_start_date
  -- Optional: uncomment interaction_desc in SELECT and filter below
  -- to narrow results to sessions containing specific interactions
  --   34 = Click to Call (a retailer)
  --   35 = Click to Email (a retailer)
  -- Not commonly used for this analysis
  LEFT JOIN `your-project.your_dataset.GA4_lookup_interaction` AS i
    ON v.interaction_id = i.interaction_id
  WHERE s.visit_start_date BETWEEN rep_from AND rep_to
    AND v.market_code     = Test_Market
    AND s.brand           = Test_Brand
    AND s.channel_grouping IN ('Paid Search', 'Paid Social')
    -- AND i.interaction_id IN (34, 35)  -- Click to Call / Click to Email
  GROUP BY 1, 2, 3, 4
)

SELECT
  brand,
  market_code,
  channel_grouping,
  -- i.interaction_desc,  -- uncomment if filtering by interaction above
  page_path,
  sessions
FROM ranked_paths
WHERE path_rank <= top_n
ORDER BY channel_grouping, sessions DESC
;
