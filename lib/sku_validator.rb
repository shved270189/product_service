module SkuValidator
  def self.included(base)
    base.send :include, InstanceMethods

    if base.class_name != 'ProductDatumLineItem'
      base.send :validate, :validate_sku_uniqueness
      base.send :before_validation, :strip_sku
    end
  end

  module InstanceMethods
    def strip_sku
      self.sku = (sku || '').strip if respond_to?(:sku) && sku.is_a?(String)
      self.alias = (self.alias || '').strip if respond_to?(:alias)
    end

    def exists_for_licensees?(licensee_ids)
      return false if licensee_ids.blank?

      _, licensees = get_licensors_licensees

      (licensees.flatten.uniq.reject(&:blank?) & licensee_ids) == licensee_ids
    end

    def exists_for_licensors?(licensor_ids)
      return false if licensor_ids.blank?

      licensors, _ = get_licensors_licensees

      (licensors.flatten.uniq.reject(&:blank?) & licensor_ids) == licensor_ids
    end

    def get_licensors_licensees
      licensees = []
      licensors = []

      case self
      when SkuAlias
        # alias for submission
        if pending_product.present? && pending_product.contract.present?
          licensees << pending_product.contract.licensee_id
          licensors << pending_product.contract.licensor_id
        # alias for product
        elsif sku.present? && sku.sku_associations.present?
          licensees << sku.sku_associations.map{|sa| sa.contract.licensee_id }
          licensors << sku.sku_associations.map{|sa| sa.contract.licensor_id }
        elsif product_datum.present? && product_datum.contract.present?
          licensees << product_datum.contract.licensee_id
          licensors << product_datum.contract.licensor_id
        end
      when Sku
        # product with the_contract set
        if the_contract.present?
          licensees << the_contract.licensee_id
          if the_contract.account.paid_licensee?
            licensors << the_contract.account.contracts.map{|c| c.licensor_id}.uniq
          else
            licensors << the_contract.licensor_id
          end
        # product with the_contract not set
        elsif sku_associations.present?
          licensees << sku_associations.map{|sa| sa.contract.licensee_id }
          licensors << sku_associations.map{|sa| sa.contract.licensor_id }
        elsif pending_products.present?
          licensees << pending_products.map{|pp| pp.contract.licensee_id }
          licensors << pending_products.map{|pp| pp.contract.licensor_id }
        elsif product_datum.present? && product_datum.contract.present?
          licensees << product_datum.contract.licensee_id
          if product_datum.contract.account.paid_licensee?
            licensors << product_datum.contract.account.contracts.map{|c| c.licensor_id}.uniq
          else
            licensors << product_datum.contract.licensor_id
          end
        end
      when PendingProduct
        if contract.present?
          licensees << contract.licensee_id
          if contract.account.paid_licensee?
            licensors << contract.account.contracts.map{|c| c.licensor_id}.uniq
          else
            licensors << contract.licensor_id
          end
        end
      when ProductDatumLineItem
        # contract already populated
        if contract.present?
          licensees << contract.licensee_id
          if contract.account.paid_licensee?
            licensors << contract.account.contracts.map{|c| c.licensor_id}.uniq
          else
            licensors << contract.licensor_id
          end
        # otherwise let's try to grab it from product_datum
        elsif product_datum.present? && product_datum.contract.present?
          if product_datum.contract.account.paid_licensee?
            licensors << product_datum.contract.account.contracts.map{|c| c.licensor_id}.uniq
          else
            licensors << product_datum.contract.licensor_id
          end
        end
      end

      return licensors.flatten.uniq.reject(&:blank?), licensees.flatten.uniq.reject(&:blank?)
    end

    def validate_sku_uniqueness
      licensor_ids, licensee_ids = get_licensors_licensees

      case self
      when SkuAlias
        the_account = if sku.present?
          sku.account_id
        elsif pending_product.present? && pending_product.contract
          pending_product.contract.licensee_id
        elsif product_datum.present? && product_datum.contract
          product_datum.contract.licensee_id
        else
          fail 'SkuValidator unable to find appropriate account'
        end
        conflicting_aliases = SkuAlias.all(
          :conditions => { 'sku_aliases.alias' => self.alias },
          :include => :sku,
          :include => :pending_product
        ).select { |s| s.is_duplicate_for?(the_account, id) }
        errors.add_to_base("SKU #{self.alias} is already in use. You must use a different SKU number.") && return if conflicting_aliases.present?

        conflicting_skus = Sku.all(:conditions => { :sku => self.alias, :account_id => the_account})
        errors.add_to_base("SKU #{self.alias} is already in use. You must use a different SKU number.") && return if conflicting_skus.present?

        conflicting_pps = PendingProduct.all(:conditions => { :sku => self.alias }).select{|pp| pp.exists_for_licensees?(licensee_ids) && pp.exists_for_licensors?(licensor_ids) }.select(&:alive_product_submission?)
        errors.add_to_base("SKU #{self.alias} is already in use. You must use a different SKU number.") && return if conflicting_pps.present?
      when Sku
        conflicting_skus = Sku.all(:conditions => { :sku => sku, :account_id => self.account_id }).select{|s| s.id != id }
        errors.add_to_base("SKU #{sku} is already in use. You must use a different SKU number.") && return if conflicting_skus.present?

        conflicting_aliases = SkuAlias.all(:conditions => { 'sku_aliases.alias' => sku, 'skus.account_id' => account_id }, :include => :sku)
        errors.add_to_base("SKU #{sku} is already in use. You must use a different SKU number.") && return if conflicting_aliases.present?

        conflicting_pps = PendingProduct.all(:conditions => { :sku => sku }).select{|pp| pp.exists_for_licensees?(licensee_ids) && pp.exists_for_licensors?(licensor_ids) && pp.alive_product_submission? }
        conflicting_pps = conflicting_pps.reject{|pp| pp.related_sku_id.present? && pp.related_sku_id == id }
        errors.add_to_base("SKU #{sku} is already in use. You must use a different SKU number.") && return if conflicting_pps.present?

        conflicting_pp_aliases = SkuAlias.all(:conditions => { :alias => sku, :pending_products => {:account_id => (licensor_ids | licensee_ids) }}, :include => :pending_product)
        errors.add_to_base("SKU #{sku} is already in use. You must use a different SKU number.") && return if conflicting_pp_aliases.present?
      when PendingProduct
        errors.add(manufacturer? ? :company : :sku, :blank) && return if sku.blank?
        if manufacturer?
          conflicting_pps = PendingProduct.all(:conditions => { :sku => sku }).select{|pp| pp.exists_for_licensees?(licensee_ids) && pp.exists_for_licensors?(licensor_ids) && pp.alive_manufacturer_submission? && pp.id != id }

          errors.add :company, 'must be unique' if Manufacturer.for_licensor(licensor_id).exists?(:company => sku) || conflicting_pps.present?
        elsif product?
          conflicting_pps = PendingProduct.all(:conditions => { 'pending_products.sku' => sku, 'contracts.licensee_id' => self.contract.licensee_id }, :include => :contract).select{|pp| pp.alive_product_submission? && pp.id != id }
          conflicting_skus = Sku.all(:conditions => { :sku => sku, :account_id => self.contract.licensee_id })
          conflicting_aliases = SkuAlias.all(
            :conditions => {
              'sku_aliases.alias' => sku,
              :skus => {
                :account_id => (licensor_ids | licensee_ids)
              }
            },
            :include => :sku
          )

          errors.add_to_base "SKU #{sku} is already in use. You must use a different SKU number." if conflicting_pps.present? || conflicting_skus.present? || conflicting_aliases.present?
        end
      when ProductDatumLineItem
        conflicting_aliases = if (licensor_ids | licensee_ids).blank?
          SkuAlias.all(:conditions => { 'sku_aliases.alias' => sku_name}, :include => :sku)
        else
          SkuAlias.all(:conditions => { :alias => sku_name, :skus => {:account_id => (licensor_ids | licensee_ids)} }, :include => :sku)
        end.select{|s| s.product_datum_line_item_id != id }
        errors.add_to_base("SKU #{sku_name} is already in use. You must use a different SKU number.") && return if conflicting_aliases.present?

        conflicting_pps = if licensee_ids.blank?
          PendingProduct.all(:conditions => { 'pending_products.sku' => sku_name }, :include => :contract)
        else
          PendingProduct.all(:conditions => { :sku => sku_name, :contracts => {:licensee_id => licensee_ids }}, :include => :contract)
        end.select{|pp| pp.alive_product_submission? }
        errors.add_to_base("SKU #{sku_name} is already in use. You must use a different SKU number.") && return if conflicting_pps.present?

        self.aliases.each do |a|
          conflicting_aliases = if (licensor_ids | licensee_ids).blank?
            SkuAlias.all(:conditions => { 'sku_aliases.alias' => a }, :include => :sku)
          else
            SkuAlias.all(:conditions => { :alias => a, :skus => {:account_id => (licensor_ids | licensee_ids)} }, :include => :sku)
          end.select{|s| s.product_datum_line_item_id != id }

          errors.add_to_base("SKU #{a} is already in use. You must use a different SKU number.") && return if conflicting_aliases.present?

          conflicting_skus = if licensee_ids.blank?
            Sku.all(:conditions => { :sku => a })
          else
            Sku.all(:conditions => { :sku => a, :account_id => licensee_ids })
          end.select{|s| s.product_datum_line_item_id != id }
          errors.add_to_base("SKU #{a} is already in use. You must use a different SKU number.") && return if conflicting_skus.present?

          conflicting_pps = if licensee_ids.blank?
            PendingProduct.all(:conditions => { 'pending_products.sku' => a }, :include => :contract)
          else
            PendingProduct.all(:conditions => { :sku => a, :contracts => {:licensee_id => licensee_ids }}, :include => :contract)
          end.select(&:alive_product_submission?)
          errors.add_to_base("SKU #{a} is already in use. You must use a different SKU number.") && return if conflicting_pps.present?

          errors.add_to_base(%Q[alias "#{a}" on line #{line_number} will be created as a SKU]) if product_datum.product_datum_line_items.map{|p| p.sku_name}.select{|s| a == s}.present?

          current_aliases = ProductDatumLineItem.find_all_by_product_datum_id(product_datum_id, :conditions => ["sku_name != ?", sku_name]).map{|p| p.aliases}.flatten.uniq.compact.delete_if(&:empty?)
          errors.add_to_base(%Q[alias "#{ a }" on line #{ line_number } is already assigned to a SKU within this upload set]) if current_aliases.include?(a)
        end
      else
        raise "NYI for class: #{self.class.to_s}"
      end
    end
  end
end
