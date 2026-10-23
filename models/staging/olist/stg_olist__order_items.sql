-- Grain: one row per (order_id, order_item_id). Each row is one unit:
-- Olist repeats the line with an incrementing order_item_id for quantity > 1.
with source as (

    select * from {{ source('olist', 'order_items') }}

),

renamed as (

    select
        {{ clean_text('order_id') }} as order_id,
        cast({{ clean_text('order_item_id') }} as integer) as order_item_id,
        {{ clean_text('product_id') }} as product_id,
        {{ clean_text('seller_id') }} as seller_id,
        cast({{ clean_text('shipping_limit_date') }} as timestamp) as shipping_limit_at,
        cast({{ clean_text('price') }} as decimal(12, 2)) as item_price,
        cast({{ clean_text('freight_value') }} as decimal(12, 2)) as freight_value
    from source

),

deduplicated as (

    select *
    from renamed
    qualify row_number() over (
        partition by order_id, order_item_id
        order by shipping_limit_at desc nulls last
    ) = 1

)

select * from deduplicated
