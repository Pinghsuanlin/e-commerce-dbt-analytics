-- Grain: one row per Portuguese category name.
with source as (

    select * from {{ source('olist', 'product_category_name_translation') }}

),

renamed as (

    select
        lower({{ clean_text('product_category_name') }}) as product_category_name_pt,
        lower({{ clean_text('product_category_name_english') }}) as product_category_name_en
    from source

),

deduplicated as (

    select *
    from renamed
    where product_category_name_pt is not null
    qualify row_number() over (
        partition by product_category_name_pt
        order by product_category_name_en nulls last
    ) = 1

)

select * from deduplicated
