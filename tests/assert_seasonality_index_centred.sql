-- The seasonality index is rescaled to average 1.0 and must be positive
-- everywhere; anything else means the trend fit or the rescaling broke.
select avg(seasonality_index) as mean_index, min(seasonality_index) as min_index
from {{ ref('int_seasonality_index') }}
having abs(avg(seasonality_index) - 1.0) > 0.001 or min(seasonality_index) <= 0
