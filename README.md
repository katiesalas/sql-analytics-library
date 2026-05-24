# SQL Analytics Library

Production-ready BigQuery SQL for GA4 web analytics — built from real enterprise implementations and anonymized for reuse.

This library covers the patterns that come up constantly in digital analytics work and are the hardest to get right: multi-source campaign attribution, funnel analysis, session-level lead tracking, and recurring reporting. Each query is self-contained, documented, and parameterized so you can drop it into your own environment with minimal configuration.

---

## Who this is for

Digital analysts, marketing analysts, and data engineers working with GA4 data in BigQuery. Particularly useful if you're building campaign attribution reporting, tracking on-site conversion flows, or producing recurring monthly reports for stakeholders.

---

## How queries are structured

Every file follows the same conventions:

- **Header block** — purpose, grain, output description, and configuration notes
- **`DECLARE` statements** — date range parameters at the top, so the only thing you need to change to run a query is the start and end date
- **Placeholder references** — all project and dataset IDs use `your-project.your_dataset` so nothing accidentally points anywhere real
- **Inline comments** — CTEs and key logic blocks are explained as you read

---

## Query index

### Campaign & channel attribution

| File | What it does |
|---|---|
| `campaign_sessions.sql` | Session counts by channel and campaign with taxonomy enrichment — resolves channel through multiple fallback join paths |
| `campaign_ecommerce_enquiry_engagement.sql` | Ecommerce interaction sessions by month, product, channel, and campaign — cross-references campaign lookup tables to standardize channel groupings |
| `paid_social_campaigns_report.sql` | Paid social campaign performance report with channel and medium breakdowns |

### Ecommerce & conversion

| File | What it does |
|---|---|
| `ecommerce_interactions.sql` | Ecommerce interaction events with session and product context |
| `ecommerce_funnel_by_product.sql` | Funnel step analysis by product with volume at each stage |
| `ecommerce_funnel_entry_daily.sql` | Daily funnel entry counts by product — useful for trend monitoring and anomaly detection |

### Enquiry & lead tracking

| File | What it does |
|---|---|
| `enquiry_engagement_report.sql` | Enquiry event counts with channel and campaign attribution |
| `enquiry_form_source_analysis.sql` | Form submission analysis broken down by traffic source and medium |
| `onward_enquiry_from_page.sql` | Sessions where a user visited a specific page and subsequently submitted an enquiry |
| `sessions_enquiry_by_source.sql` | Sessions containing an enquiry event, grouped by source and medium |
| `user_journey_to_enquiry.sql` | Reconstructs the page path users take before submitting an enquiry |

### Page & content performance

| File | What it does |
|---|---|
| `hero_carousel_clicks.sql` | Click interactions on hero and carousel components, broken down by page |
| `top_paid_pages.sql` | Top landing pages from paid traffic by session volume |
| `digital_experience_pages_report.sql` | Page performance report across key digital experience pages |

### Reporting & data exports

| File | What it does |
|---|---|
| `data_dump_product_channel.sql` | Flat session export by product and channel for downstream reporting or visualization |
| `monthly_report.sql` | Monthly aggregate report across core metrics — designed for recurring stakeholder delivery |
| `pre_post_analysis.sql` | Compares metrics across two configurable date periods — useful for campaign evaluation or site change measurement |

---

## Setup

1. Replace all instances of `your-project.your_dataset` and `your-project.your_reporting_dataset` with your actual BigQuery project and dataset IDs
2. Update the `DECLARE` date variables at the top of each query
3. Review any lookup table references (campaign taxonomy, product metadata) and update to match your schema — or remove those joins if you don't have equivalent tables

---

## Notes

- Written for GA4 BigQuery exports using the standard flat event table schema
- Assumes session-level and hit-level derived tables built from raw GA4 exports
- Campaign attribution uses a multi-path resolution strategy: campaign key → SA360 ID → engine ID → campaign name, with COALESCE fallback to raw session values
- All queries use CTEs for readability — no nested subqueries

---

*Built from production analytics work across enterprise digital implementations. All client-specific data and references have been removed.*
