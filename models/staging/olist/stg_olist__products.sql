-- Grain: one row per product_id.
-- The source spells "length" as "lenght"; fixed here so nothing downstream
-- inherits the typo.
with source as (

    select * from {{ source('olist', 'products') }}

),

renamed as (

    select
        {{ clean_text('product_id') }} as product_id,
        lower({{ clean_text('product_category_name') }}) as product_category_name_pt,
        cast({{ clean_text('product_name_lenght') }} as integer) as product_name_length,
        cast({{ clean_text('product_description_lenght') }} as integer) as product_description_length,
        cast({{ clean_text('product_photos_qty') }} as integer) as product_photos_qty,
        cast({{ clean_text('product_weight_g') }} as double) as product_weight_g,
        cast({{ clean_text('product_length_cm') }} as double) as product_length_cm,
        cast({{ clean_text('product_height_cm') }} as double) as product_height_cm,
        cast({{ clean_text('product_width_cm') }} as double) as product_width_cm
    from source

),

deduplicated as (

    select *
    from renamed
    qualify row_number() over (partition by product_id order by product_category_name_pt nulls last) = 1

)

select * from deduplicated
