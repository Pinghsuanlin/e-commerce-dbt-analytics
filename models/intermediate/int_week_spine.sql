-- Grain: one row per ISO week (week_start is a Monday).
-- Complete weeks only: the week must start on or after analysis_start_date,
-- end on or before analysis_end_date, and end on or before the last purchase
-- date in the data. Partial weeks at either edge would look like demand drops.
with bounds as (

    select
        cast('{{ var("analysis_start_date") }}' as date) as window_start,
        least(
            cast('{{ var("analysis_end_date") }}' as date),
            max(cast(purchased_at as date))
        ) as window_end
    from {{ ref('stg_olist__orders') }}

),

series as (

    select
        unnest(generate_series(
            cast(date_trunc('week', window_start) as timestamp),
            cast(date_trunc('week', window_end) as timestamp),
            interval 7 day
        )) as week_start_ts,
        window_start,
        window_end
    from bounds

),

weeks as (

    select
        cast(week_start_ts as date) as week_start,
        cast(week_start_ts + interval 6 day as date) as week_end,
        window_start,
        window_end
    from series

)

select
    week_start,
    week_end,
    {{ iso_year('week_start') }} as iso_year,
    {{ iso_week('week_start') }} as iso_week,
    cast(row_number() over (order by week_start) as integer) as week_number
from weeks
where week_start >= window_start
    and week_end <= window_end
