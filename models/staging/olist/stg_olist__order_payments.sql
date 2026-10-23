-- Grain: one row per (order_id, payment_sequential).
with source as (

    select * from {{ source('olist', 'order_payments') }}

),

renamed as (

    select
        {{ clean_text('order_id') }} as order_id,
        cast({{ clean_text('payment_sequential') }} as integer) as payment_sequential,
        lower({{ clean_text('payment_type') }}) as payment_type,
        cast({{ clean_text('payment_installments') }} as integer) as payment_installments,
        cast({{ clean_text('payment_value') }} as decimal(12, 2)) as payment_value
    from source

),

deduplicated as (

    select *
    from renamed
    qualify row_number() over (
        partition by order_id, payment_sequential
        order by payment_value desc
    ) = 1

)

select * from deduplicated
