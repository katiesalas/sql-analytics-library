-- ============================================================
-- Ecommerce Interactions
-- ============================================================
-- Purpose:  Count sessions with ecommerce interactions
--           (e.g. Find Matches, Reservations) by month and nameplate.
-- Grain:    Monthly
-- Output:   sessions per interaction type per nameplate
-- ============================================================
-- To run: update start_date and end_date only.
-- ============================================================

DECLARE start_date DATE DEFAULT '2026-03-01';
DECLARE end_date   DATE DEFAULT '2026-03-31';

-- ============================================================
-- Configuration — update interaction IDs to match your schema
-- ============================================================

SELECT
  EXTRACT(MONTH FROM E.visit_start_date)  AS month,
  E.nameplate_code,
  NP.nameplate_desc,

  -- Human-readable interaction label — update IDs to match your schema
  CASE
    WHEN E.interaction_id = 227 THEN 'Find Matches'
    WHEN E.interaction_id = 221 THEN 'Reservation'
  END                                     AS interaction_name,

  E.interaction_id,
  COUNT(DISTINCT E.session_id)            AS sessions

FROM `your-project.your_dataset.GA4_ecomm_hit_interaction_nameplate` E
LEFT JOIN `your-project.your_dataset.GA4_lookup_nameplate` NP
  ON E.nameplate_code = NP.nameplate_code
WHERE E.visit_start_date BETWEEN start_date AND end_date
  AND E.interaction_id IN (221, 227)     -- update IDs as needed
  -- Note: if your ecomm table is market-specific, no market filter is needed
GROUP BY 1, 2, 3, 4, 5
ORDER BY 1, 2
;
