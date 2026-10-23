-- Grain: one row per customer_id (which is one row per order in Olist).
-- customer_unique_id is the person and is the key for retention analysis.
-- Zip prefixes are padded to 5 characters in case leading zeros were dropped.
with source as (

    select * from {{ source('olist', 'customers') }}

),

renamed as (

    select
        {{ clean_text('customer_id') }} as customer_id,
        {{ clean_text('customer_unique_id') }} as customer_unique_id,
        lpad({{ clean_text('customer_zip_code_prefix') }}, 5, '0') as customer_zip_code_prefix,
        lower({{ clean_text('customer_city') }}) as customer_city,
        upper({{ clean_text('customer_state') }}) as customer_state
    from source

),

deduplicated as (

    select *
    from renamed
    qualify row_number() over (partition by customer_id order by customer_unique_id) = 1

)

select * from deduplicated
