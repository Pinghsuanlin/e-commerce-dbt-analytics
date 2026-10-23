-- Grain: one row per order_id that has at least one review.
-- When an order has several reviews we keep the latest answered one, so every
-- downstream model uses the same single score per order.
with reviews as (

    select * from {{ ref('stg_olist__order_reviews') }}

),

ranked as (

    select
        order_id,
        review_id,
        review_score,
        review_created_at,
        review_answered_at,
        review_comment_message is not null as has_comment,
        count(*) over (partition by order_id) as n_reviews_for_order,
        row_number() over (
            partition by order_id
            order by review_answered_at desc nulls last, review_created_at desc nulls last, review_id
        ) as review_rank
    from reviews

)

select
    order_id,
    review_id,
    review_score,
    review_created_at,
    review_answered_at,
    has_comment,
    n_reviews_for_order
from ranked
where review_rank = 1
