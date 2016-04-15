class PendingProduct < ActiveRecord::Base
  belongs_to :related_sku, :class_name => 'Sku'
  has_many :sku_aliases
end
