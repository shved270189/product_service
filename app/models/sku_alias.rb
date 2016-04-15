class SkuAlias < ActiveRecord::Base
  include ::SkuValidator

  belongs_to :sku

  belongs_to :pending_product
end
