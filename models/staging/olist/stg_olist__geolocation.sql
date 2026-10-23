-- Grain: one row per zip_code_prefix.
-- The raw table has many rows per prefix (one per sampled address). We collapse
-- to the median coordinate, which is robust to the stray points outside Brazil,
-- and the most common city/state spelling.
with source as (

    select * from {{ source('olist', 'geolocation') }}

),

renamed as (

    select
        lpad({{ clean_text('geolocation_zip_code_prefix') }}, 5, '0') as zip_code_prefix,
        cast({{ clean_text('geolocation_lat') }} as double) as latitude,
        cast({{ clean_text('geolocation_lng') }} as double) as longitude,
        lower({{ clean_text('geolocation_city') }}) as city,
        upper({{ clean_text('geolocation_state') }}) as state
    from source

),

collapsed as (

    select
        zip_code_prefix,
        median(latitude) as latitude,
        median(longitude) as longitude,
        mode(city) as city,
        mode(state) as state,
        count(*) as n_source_rows
    from renamed
    where zip_code_prefix is not null
    group by zip_code_prefix

)

select * from collapsed
