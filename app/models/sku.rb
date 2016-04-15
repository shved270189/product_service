class Sku < ActiveRecord::Base
  include ::SkuValidator

  belongs_to :product_datum
  has_many :sku_associations
  has_many :sku_aliases
  has_many :pending_products, :foreign_key => :related_sku_id

  attr_accessor :the_contract

  validates_presence_of :sku
end
