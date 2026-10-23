-- Grain: one row per (review_id, order_id).
-- The raw file repeats some review rows; keep the most recently answered copy.
-- An order can still have several distinct reviews; int_order_reviews picks one.
with source as (

    select * from {{ source('olist', 'order_reviews') }}

),

renamed as (

    select
        {{ clean_text('review_id') }} as review_id,
        {{ clean_text('order_id') }} as order_id,
        cast({{ clean_text('review_score') }} as integer) as review_score,
        {{ clean_text('review_comment_title') }} as review_comment_title,
        {{ clean_text('review_comment_message') }} as review_comment_message,
        cast({{ clean_text('review_creation_date') }} as timestamp) as review_created_at,
        cast({{ clean_text('review_answer_timestamp') }} as timestamp) as review_answered_at
    from source

),

deduplicated as (

    select *
    from renamed
    qualify row_number() over (
        partition by review_id, order_id
        order by review_answered_at desc nulls last, review_created_at desc nulls last
    ) = 1

)

select * from deduplicated
