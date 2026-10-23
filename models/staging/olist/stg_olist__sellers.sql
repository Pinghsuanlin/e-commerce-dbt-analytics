-- Grain: one row per seller_id.
with source as (

    select * from {{ source('olist', 'sellers') }}

),

renamed as (

    select
        {{ clean_text('seller_id') }} as seller_id,
        lpad({{ clean_text('seller_zip_code_prefix') }}, 5, '0') as seller_zip_code_prefix,
        lower({{ clean_text('seller_city') }}) as seller_city,
        upper({{ clean_text('seller_state') }}) as seller_state
    from source

),

deduplicated as (

    select *
    from renamed
    qualify row_number() over (partition by seller_id order by seller_zip_code_prefix) = 1

)

select * from deduplicated
