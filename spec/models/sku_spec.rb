require 'spec_helper'

describe Sku do
  let(:sku) { Sku.create(:sku => ' SkuSkuSKu ') }
  it 'should be creatable' do
    sku.sku.should == 'SkuSkuSKu'
  end

  it 'is strippable' do
    sku.strip_sku
    sku.sku.should == 'SkuSkuSKu'
  end
end
