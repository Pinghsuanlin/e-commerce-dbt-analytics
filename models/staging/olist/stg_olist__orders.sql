-- Grain: one row per order_id.
with source as (

    select * from {{ source('olist', 'orders') }}

),

renamed as (

    select
        {{ clean_text('order_id') }} as order_id,
        {{ clean_text('customer_id') }} as customer_id,
        lower({{ clean_text('order_status') }}) as order_status,
        cast({{ clean_text('order_purchase_timestamp') }} as timestamp) as purchased_at,
        cast({{ clean_text('order_approved_at') }} as timestamp) as approved_at,
        cast({{ clean_text('order_delivered_carrier_date') }} as timestamp) as delivered_to_carrier_at,
        cast({{ clean_text('order_delivered_customer_date') }} as timestamp) as delivered_to_customer_at,
        cast({{ clean_text('order_estimated_delivery_date') }} as timestamp) as estimated_delivery_at
    from source

),

deduplicated as (

    select *
    from renamed
    qualify row_number() over (
        partition by order_id
        order by approved_at desc nulls last, purchased_at desc
    ) = 1

)

select * from deduplicated
