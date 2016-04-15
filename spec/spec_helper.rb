require 'pry'
require 'active_record'
require 'pry'
require 'simplecov'

SimpleCov.start

require_relative '../lib/sku_validator.rb'
require_relative '../app/models/sku.rb'
require_relative '../app/models/sku_association.rb'
require_relative '../app/models/sku_alias.rb'
require_relative '../app/models/pending_product.rb'
require_relative '../app/models/product_datum.rb'

ActiveRecord::Base.establish_connection(
  adapter: 'sqlite3',
  database: ':memory:'
)

ActiveRecord::Schema.define do
  create_table :skus, force: true do |t|
    t.string :sku
    t.belongs_to :account, index: true
    t.belongs_to :product_datum, index: true
  end

  create_table :sku_associations, force: true do |t|
    t.belongs_to :sku, index: true
  end

  create_table :sku_aliases, force: true do |t|
    t.string :alias
    t.belongs_to :sku, index: true
    t.belongs_to :pending_product, index: true
  end

  create_table :pending_products, force: true do |t|
    t.string :sku
    t.belongs_to :related_sku, index: true
    t.belongs_to :account, index: true
  end

  create_table :product_datum, force: true do |t|
    t.string :filename
  end
end
