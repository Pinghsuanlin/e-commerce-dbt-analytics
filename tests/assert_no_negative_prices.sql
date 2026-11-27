-- No item line may carry a negative price or freight charge.
select order_id, order_item_id, item_price, freight_value
from {{ ref('int_order_items_enriched') }}
where item_price < 0 or freight_value < 0
