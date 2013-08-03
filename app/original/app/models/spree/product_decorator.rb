module Spree
  Product.class_eval do
    translates :name, :description, :meta_description, :meta_keywords, :fallbacks_for_empty_translations => true
    acts_as_mappable :default_units => :kms,
                     :default_formula => :sphere,
                     #:default_formula => :simple,
                     :distance_field_name => :distance,
                     :lat_column_name => :latitude,
                     :lng_column_name => :longitude
    attr_accessible :name, :sku, :price, :description, :meta_description, :meta_keywords, :latitude,:longitude
    attr_accessible :product_properties_attributes, :available_on, :permalink, :stars, :option_types, :small_description, :recomended
    #attr_accessible :discount_amount, :related_to_id, :relation_type_id, :related_to_type

    include Jaf::Product::Stuff
    include Jaf::Product::Transfer
    include Jaf::Product::Car
    include Jaf::Product::Destination
    include Jaf::Product::Hotel
    include Jaf::Product::Point
    include Jaf::Product::Package
    include Jaf::Product::Route
    include Jaf::Product::Relation
    include Jaf::Product::Taxonomy
    include Jaf::Product::Facet

    function_fields = [
        :adults_combinations,
        :child_combinations,
        :infant_combinations,
        :meal_plan_combinations,
        :pax_combinations,
        :transmission_combinations,
        :duration_combinations,
        :taxi_confort_combinations,
        :season_ids,
        :properties_feature,
        :properties_include,
        :variant_names,
        :origin_taxon,
        :destination_taxon
    ]
    acts_as_solr :fields => Constant::SOLR_FIELDS + function_fields, :facets => Constant::SOLR_FACETS #rescue nil

    def self.with_default_inclusions
      to_include = []
      to_include << :images
      to_include << :master
      to_include << {:variants => {:option_values => :option_type}}
      to_include << :translations
      to_include << {:relations => [:relation_type]}
      to_include << :taxons
      to_include << {:product_properties => {:property => :translations}}
      to_include << {:properties => :translations}
      includes(to_include)
    end

    def self.in_taxons_at_same_time(taxons)
      first = taxons[0]
      rest = taxons[1..-1]
      list = Spree::Product.in_taxon(first).map(&:id)
      for taxon in rest
        list = list & Spree::Product.in_taxon(taxon).map(&:id)
      end
      where(:id => list)
    end

    def program?
      type_is?('program')
    end

    def accommodation?
      type_is?('accommodation')
    end

    def tour?
      type_is?('tour')
    end

    def flight?
      type_is?('flight')
    end

    def transfer?
      type_is?('transfers')
    end

    def car?
      type_is?('rent-cars')
    end

    def rent?
      type_is?('rent-cars')
    end

    def destination?
      type_is?(Constant::DESTINATIONS, :max_taxons => 1)
    end

    def get_product_to_map_from_destination
      destination = self.taxons.first
      permalinks = ['categories/accommodation', 'categories/programs', 'categories/tours', 'things-to-do']
      permalinks.each do |p|
        categ = Spree::Taxon.find_by_permalink(p)
        taxons = [categ, destination]
        reference_product = Spree::Product.in_taxons_at_same_time(taxons).limit(1).first
        return reference_product if reference_product && reference_product.lng && reference_product.lat
      end
      return false
    end

    ###############################################################################

    def variant_for_room(context)
      current_variant = nil
      adults       = (context[:adults_accommodation]    || Constant::DEFAULT_ADULTS_ACCOMMODATION).to_i
      children     = (context[:children_accommodation]  || Constant::DEFAULT_CHILDREN_ACCOMMODATION).to_i
      infants      = (context[:infants_accommodation]   || Constant::DEFAULT_INFANTS_ACCOMMODATION).to_i
      check_in     = (context[:check_in_accommodation]  || Constant.DEFAULT_CHECK_IN_ACCOMMODATION).to_date
      check_out    = (context[:check_out_accommodation] || Constant.DEFAULT_CHECK_OUT_ACCOMMODATION).to_date
      meal_plan_id = context[:meal_plan_accommodation]

      cant_ov = 3
      cant_ov += 1 if children > 0
      cant_ov += 1 if infants > 0
      din = check_in.strftime('%Y/%m/%d')
      dout = check_out.strftime('%Y/%m/%d')

      sql = "SELECT sv.id AS id, sv.sku AS sku, sv.price AS price"
      sql += ", sov1.name AS adults " if adults > 0
      sql += ", sov2.name AS children " if children > 0
      sql += ", sov3.name AS infants " if infants > 0
      sql += ", sov4.name AS season "
      sql += ", sov5.name AS meal_plan " if meal_plan_id.present?
      sql += "FROM spree_variants AS sv "
      sql += "INNER JOIN spree_option_values_variants AS sovv1 ON sovv1.variant_id = sv.id INNER JOIN spree_option_values AS sov1 ON sov1.id = sovv1.option_value_id " if adults > 0
      sql += "INNER JOIN spree_option_values_variants AS sovv2 ON sovv2.variant_id = sv.id INNER JOIN spree_option_values AS sov2 ON sov2.id = sovv2.option_value_id " if children > 0
      sql += "INNER JOIN spree_option_values_variants AS sovv3 ON sovv3.variant_id = sv.id INNER JOIN spree_option_values AS sov3 ON sov3.id = sovv3.option_value_id " if infants > 0
      sql += "INNER JOIN spree_option_values_variants AS sovv4 ON sovv4.variant_id = sv.id INNER JOIN spree_option_values AS sov4 ON sov4.id = sovv4.option_value_id "
      sql += "INNER JOIN spree_option_values_variants AS sovv5 ON sovv5.variant_id = sv.id INNER JOIN spree_option_values AS sov5 ON sov5.id = sovv5.option_value_id " if meal_plan_id.present?
      sql += "WHERE sv.product_id = #{self.id} "
      sql += "AND sov1.name = 'adult-#{adults}' " if adults > 0
      sql += "AND sov2.name = 'child-#{children}' " if children > 0
      sql += "AND sov3.name = 'infant-#{infants}' " if infants > 0
      sql += "AND date(substring_index(substring_index(sov4.name, '-', 2), '-', -1)) <= date('#{din}') AND date(substring_index(sov4.name, '-', -1)) >= date('#{dout}') "
      sql += "AND sov5.id = #{meal_plan_id} " if meal_plan_id.present?

      records = Spree::Variant.find_by_sql(sql)
      records.each do |r|
        if r.option_values.count == cant_ov
          current_variant = Spree::Variant.find_by_sku(r.sku)
          return current_variant
        end
      end
      current_variant

    end

    def price_for_room_variant(variant, context)
      check_in  = (context[:check_in_accommodation]  || Constant.DEFAULT_CHECK_IN_ACCOMMODATION).to_date
      check_out = (context[:check_out_accommodation] || Constant.DEFAULT_CHECK_OUT_ACCOMMODATION).to_date
      if variant then variant.price * (check_out - check_in) else 0 end
    end

    def price_for_room(context)
      variant = variant_for_room(context)
      price_for_room_variant(variant, context)
    end

    def variant_and_price_for_room(context)
      variant = variant_for_room(context)
      price = price_for_room_variant(variant, context)
      {
        'variant' => variant,
        'price' => price,
        'customization' => {}
      }
    end

    ###############################################################################

    def variant_for_hotel(context)
      main_room ? main_room.variant_for_room(context) : nil
    end

    def price_for_hotel_variant(variant, context)
      main_room ? main_room.price_for_room_variant(variant, context) : 0
    end

    def price_for_hotel(context)
      main_room ? main_room.price_for_room(context) : 0
    end

    def variant_and_price_for_hotel(context)
      if main_room
        main_room.variant_and_price_for_room(context)
      else
        variant = variant_for_room(context)
        price = price_for_room_variant(variant, context)
        {
          'variant' => variant,
          'price' => price,
          'customization' => {}
        }
      end
    end

    ###############################################################################

    def variant_for_program(context)
      date     = (context[:date_program]     || Constant.DEFAULT_DATE_PROGRAM).to_date
      #adults   = (context[:adults_program]   || Constant::DEFAULT_ADULTS_PROGRAM).to_i
      children = (context[:children_program] || Constant::DEFAULT_CHILDREN_PROGRAM).to_i
      infants  = (context[:infants_program]  || Constant::DEFAULT_INFANTS_PROGRAM).to_i
      current_variant = nil

      adults = 1
      if context[:adults_program].nil?
        list_adults = "('adult-1','adult-2','adult-3','adult-4','adult-5','adult-6','adult-7','adult-8')"
      else
        list_adults = "('adult-#{context[:adults_program]}')"
      end

      cant_ov = 2
      cant_ov += 1 if children > 0
      cant_ov += 1 if infants > 0
      d = date.strftime('%Y/%m/%d')

      sql = "SELECT sv.id AS id, sv.sku AS sku, sv.price AS price"
      sql += ", sov1.name AS adults " if adults > 0
      sql += ", sov2.name AS children " if children > 0
      sql += ", sov3.name AS infants " if infants > 0
      sql += ", sov4.name AS season "
      sql += "FROM spree_variants AS sv "
      sql += "INNER JOIN spree_option_values_variants AS sovv1 ON sovv1.variant_id = sv.id INNER JOIN spree_option_values AS sov1 ON sov1.id = sovv1.option_value_id " if adults > 0
      sql += "INNER JOIN spree_option_values_variants AS sovv2 ON sovv2.variant_id = sv.id INNER JOIN spree_option_values AS sov2 ON sov2.id = sovv2.option_value_id " if children > 0
      sql += "INNER JOIN spree_option_values_variants AS sovv3 ON sovv3.variant_id = sv.id INNER JOIN spree_option_values AS sov3 ON sov3.id = sovv3.option_value_id " if infants > 0
      sql += "INNER JOIN spree_option_values_variants AS sovv4 ON sovv4.variant_id = sv.id INNER JOIN spree_option_values AS sov4 ON sov4.id = sovv4.option_value_id "
      sql += "WHERE sv.product_id = #{self.id} "
      #sql += "AND sov1.name = 'adult-#{adults}' " if adults > 0
      sql += "AND sov1.name in #{list_adults} " if adults > 0
      sql += "AND sov2.name = 'child-#{children}' " if children > 0
      sql += "AND sov3.name = 'infant-#{infants}' " if infants > 0
      sql += "AND date(substring_index(substring_index(sov4.name, '-', 2), '-', -1)) <= date('#{d}') AND date(substring_index(sov4.name, '-', -1)) >= date('#{d}') "

      records = Spree::Variant.find_by_sql(sql)
      records.each do |r|
        if r.option_values.count == cant_ov
          current_variant = r
          return current_variant
        end
      end
      current_variant

    end

    def testing
      list = Spree::Variant.joins(:option_values => :option_type).where("spree_option_type.name = ? and spree_option_value.name = ?", 'adults', 2)
      list
    end

    def price_for_program_variant(variant, context)
      if variant then variant.price else 0 end
    end

    def price_for_program(context)
      variant = variant_for_program(context)
      price_for_program_variant(variant, context)
    end

    def variant_and_price_for_program(context)
      variant = variant_for_program(context)
      price = price_for_program_variant(variant, context)
      {
        'variant' => variant,
        'price' => price,
        'customization' => {}
      }
    end

    ###############################################################################

    def variant_for_tour(context)
      self.master if price_for_tour(context) > 0
    end

    def price_for_tour_variant(variant, context)
      price_for_tour(context)
    end

    def price_for_tour(context)
      customizations = values_for_customization(context)
      a = customizations[:adults]
      ap = customizations[:adults_price]
      c = customizations[:children]
      cp = customizations[:children_price]
      a * ap + c * cp
    end

    def values_for_tour_customization(context)
      date     = (context[:date_program]     || Constant.DEFAULT_DATE_PROGRAM).to_date
      adults   = (context[:adults_program]   || Constant::DEFAULT_ADULTS_PROGRAM).to_i
      children = (context[:children_program] || Constant::DEFAULT_CHILDREN_PROGRAM).to_i
      current_adult_variant = nil
      current_children_variant = nil

      cant_ov = 3
      d = date.strftime('%Y/%m/%d')

      sql = "SELECT sv.id AS id, sv.sku AS sku, sv.price AS price"
      sql += ", sov1.name AS adults "
      sql += ", sov2.name AS children "
      sql += ", sov3.name AS season "
      sql += "FROM spree_variants AS sv "
      sql += "INNER JOIN spree_option_values_variants AS sovv1 ON sovv1.variant_id = sv.id INNER JOIN spree_option_values AS sov1 ON sov1.id = sovv1.option_value_id "
      sql += "INNER JOIN spree_option_values_variants AS sovv2 ON sovv2.variant_id = sv.id INNER JOIN spree_option_values AS sov2 ON sov2.id = sovv2.option_value_id "
      sql += "INNER JOIN spree_option_values_variants AS sovv3 ON sovv3.variant_id = sv.id INNER JOIN spree_option_values AS sov3 ON sov3.id = sovv3.option_value_id "
      sql += "WHERE sv.product_id = #{self.id} "
      sql += "AND (sov1.name = 'adult-1' OR sov1.name = 'adult-0') "
      sql += "AND (sov2.name = 'child-1' OR sov2.name = 'child-0') "
      sql += "AND date(substring_index(substring_index(sov3.name, '-', 2), '-', -1)) <= date('#{d}') AND date(substring_index(sov3.name, '-', -1)) >= date('#{d}') "

      records = Spree::Variant.find_by_sql(sql)
      records.each do |r|
        if r.option_values.count == cant_ov && r.attributes['adults'] == 'adult-1'
          current_adult_variant = r
        elsif r.option_values.count == cant_ov && r.attributes['children'] == 'child-1'
          current_children_variant = r
        end
      end
      {
          :children => children,
          :children_price => !current_children_variant.nil? ? current_children_variant.price : 0,
          :adults => adults,
          :adults_price => !current_adult_variant.nil? ? current_adult_variant.price : 0
      }
    end

    def variant_and_price_for_tour(context)
      customizations = values_for_customization(context)
      a = customizations[:adults]
      ap = customizations[:adults_price]
      c = customizations[:children]
      cp = customizations[:children_price]
      price = a * ap + c * cp
      variant = price > 0 ? self.master : nil
      {
        'variant' => variant,
        'price' => price,
        'customization' => customizations
      }
    end

    ###############################################################################

    def variant_for_transfer(context)
      adults     = (context[:adults_transfer]   || Constant::DEFAULT_ADULTS_TRANSFER).to_i
      children   = (context[:children_transfer] || Constant::DEFAULT_CHILDREN_TRANSFER).to_i
      date       = (context[:date_transfer]     || Constant.DEFAULT_INIT_DATE_TRANSFER).to_date
      packs      = adults + children
      confort_id = (context[:confort_transfer]  || Constant.DEFAULT_CONFORT_TRANSFER).to_i
      current_variant = nil

      cant_ov = 2
      cant_ov += 1 if packs < 3
      d = date.strftime('%Y/%m/%d')

      sql = "SELECT sv.id AS id, sv.sku AS sku, sv.price AS price"
      sql += ", sov1.name AS packs "
      sql += ", sov2.name AS season "
      sql += ", sov3.name AS confort " if packs < 3
      sql += "FROM spree_variants AS sv "
      sql += "INNER JOIN spree_option_values_variants AS sovv1 ON sovv1.variant_id = sv.id INNER JOIN spree_option_values AS sov1 ON sov1.id = sovv1.option_value_id "
      sql += "INNER JOIN spree_option_values_variants AS sovv2 ON sovv2.variant_id = sv.id INNER JOIN spree_option_values AS sov2 ON sov2.id = sovv2.option_value_id "
      sql += "INNER JOIN spree_option_values_variants AS sovv3 ON sovv3.variant_id = sv.id INNER JOIN spree_option_values AS sov3 ON sov3.id = sovv3.option_value_id " if packs < 3
      sql += "WHERE sv.product_id = #{self.id} "
      sql += "AND substring_index(substring_index(sov1.name, '..', 1), '-', -1) <= '#{packs}' AND substring_index(sov1.name, '..', -1) >= '#{packs}' "
      sql += "AND date(substring_index(substring_index(sov2.name, '-', 2), '-', -1)) <= date('#{d}') AND date(substring_index(sov2.name, '-', -1)) >= date('#{d}') "
      sql += "AND sov3.id = #{confort_id} " if packs < 3

      records = Spree::Variant.find_by_sql(sql)
      records.each do |r|
        if r.option_values.count == cant_ov
          current_variant = r
          return current_variant
        end
      end
      current_variant

    end

    def price_for_transfer_variant(variant, context)
      if variant then variant.price else 0 end
    end

    def price_for_transfer(context)
      variant = variant_for_transfer(context)
      price_for_transfer_variant(variant, context)
    end

    def variant_and_price_for_transfer(context)
      variant = variant_for_transfer(context)
      price = price_for_transfer_variant(variant, context)
      {
        'variant' => variant,
        'price' => price,
        'customization' => {}
      }
    end

    def origin_taxon
      self.taxons.where("permalink like 'destination%'").first.id
    end

    def destination_taxon
      self.taxons.where("permalink like 'destination%'").last.id
    end

    ###############################################################################

    def variant_for_flight(context)
      self.master if price_for_flight(context) > 0
    end

    def price_for_flight_variant(variant, context)
      price_for_flight(context)
    end

    def price_for_flight(context)
      customizations = values_for_customization(context)
      a  = customizations[:adults]
      ap = customizations[:adults_price]
      c  = customizations[:children]
      cp = customizations[:children_price]
      a * ap + c * cp
    end

    def values_for_flight_customization(context)
      # TODO: preguntarle a pqr si falta chequear por ida y vuelta o se chequea en otro lado
      # Ahora mismo funciona porque lo unico que hay en la base de datos es ida y vuelta
      date     = (context[:date_flight]     || Constant.DEFAULT_INIT_DATE_FLIGHT).to_date
      adults   = (context[:adults_flight]   || Constant::DEFAULT_ADULTS_FLIGHT).to_i
      children = (context[:children_flight] || Constant::DEFAULT_CHILDREN_FLIGHT).to_i
      current_adult_variant = nil
      current_children_variant = nil

      cant_ov = 4 # TODO: revisar por que los vuelos tiene un option value mas, ummmmmm ...
      d = date.strftime('%Y/%m/%d')

      sql = "SELECT sv.id AS id, sv.sku AS sku, sv.price AS price"
      sql += ", sov1.name AS adults "
      sql += ", sov2.name AS children "
      sql += ", sov3.name AS season "
      sql += "FROM spree_variants AS sv "
      sql += "INNER JOIN spree_option_values_variants AS sovv1 ON sovv1.variant_id = sv.id INNER JOIN spree_option_values AS sov1 ON sov1.id = sovv1.option_value_id "
      sql += "INNER JOIN spree_option_values_variants AS sovv2 ON sovv2.variant_id = sv.id INNER JOIN spree_option_values AS sov2 ON sov2.id = sovv2.option_value_id "
      sql += "INNER JOIN spree_option_values_variants AS sovv3 ON sovv3.variant_id = sv.id INNER JOIN spree_option_values AS sov3 ON sov3.id = sovv3.option_value_id "
      sql += "WHERE sv.product_id = #{self.id} "
      sql += "AND (sov1.name = 'adult-1' OR sov1.name = 'adult-0') "
      sql += "AND (sov2.name = 'child-1' OR sov2.name = 'child-0') "
      sql += "AND date(substring_index(substring_index(sov3.name, '-', 2), '-', -1)) <= date('#{d}') AND date(substring_index(sov3.name, '-', -1)) >= date('#{d}') "

      records = Spree::Variant.find_by_sql(sql)
      records.each do |r|
        if r.option_values.count == cant_ov && r.attributes['adults'] == 'adult-1'
          current_adult_variant = r
        elsif r.option_values.count == cant_ov && r.attributes['children'] == 'child-1'
          current_children_variant = r
        end
      end
      {
          :children => children,
          :children_price => !current_children_variant.nil? ? current_children_variant.price : 0,
          :adults => adults,
          :adults_price => !current_adult_variant.nil? ? current_adult_variant.price : 0
      }

    end

    def variant_and_price_for_flight(context)
      customizations = values_for_customization(context)
      a = customizations[:adults]
      ap = customizations[:adults_price]
      c = customizations[:children]
      cp = customizations[:children_price]
      price = a * ap + c * cp
      variant = price > 0 ? self.master : nil
      {
        'variant' => variant,
        'price' => price,
        'customization' => customizations
      }
    end

    ###############################################################################

    def variant_for_rent(context)
      check_in        = (context[:date_rent] || Constant.DEFAULT_INIT_DATE_RENT).to_date
      check_out       = (context[:date_devolution_rent] || Constant.DEFAULT_END_DATE_RENT).to_date
      transmission_id = context[:transmission_rent]
      duration = (check_out - check_in).to_i
      current_variant = nil

      cant_ov = 4 # TODO: revisar por que las rentas tienen option value de adultos, ummmmmm ...
      din = check_in.strftime('%Y/%m/%d')
      dout = check_out.strftime('%Y/%m/%d')

      sql = "SELECT sv.id AS id, sv.sku AS sku, sv.price AS price"
      sql += ", sov1.name AS duration "
      sql += ", sov2.name AS season "
      sql += ", sov3.name AS transmission " if transmission_id.present?
      sql += "FROM spree_variants AS sv "
      sql += "INNER JOIN spree_option_values_variants AS sovv1 ON sovv1.variant_id = sv.id INNER JOIN spree_option_values AS sov1 ON sov1.id = sovv1.option_value_id "
      sql += "INNER JOIN spree_option_values_variants AS sovv2 ON sovv2.variant_id = sv.id INNER JOIN spree_option_values AS sov2 ON sov2.id = sovv2.option_value_id "
      sql += "INNER JOIN spree_option_values_variants AS sovv3 ON sovv3.variant_id = sv.id INNER JOIN spree_option_values AS sov3 ON sov3.id = sovv3.option_value_id " if transmission_id.present?
      sql += "WHERE sv.product_id = #{self.id} "
      sql += "AND substring_index(substring_index(sov1.name, '..', 1), '-', -1) <= #{duration} AND substring_index(sov1.name, '..', -1) >= #{duration} "
      sql += "AND date(substring_index(substring_index(sov2.name, '-', 2), '-', -1)) <= date('#{din}') AND date(substring_index(sov2.name, '-', -1)) >= date('#{dout}') "
      sql += "AND sov3.id = #{transmission_id} " if transmission_id.present?

      records = Spree::Variant.find_by_sql(sql)
      records.each do |r|
        if r.option_values.count == cant_ov
          current_variant = r
          return current_variant
        end
      end
      current_variant

    end

    def price_for_rent_variant(variant, context)
      check_in        = (context[:date_rent] || Constant.DEFAULT_INIT_DATE_RENT).to_date
      check_out       = (context[:date_devolution_rent] || Constant.DEFAULT_END_DATE_RENT).to_date
      duration = check_out - check_in
      if variant then variant.price * duration else 0 end
    end

    def price_for_rent(context)
      variant = variant_for_rent(context)
      price_for_rent_variant(variant, context)
    end

    def variant_and_price_for_rent(context)
      variant = variant_for_rent(context)
      price = price_for_rent_variant(variant, context)
      {
        'variant' => variant,
        'price' => price,
        'customization' => {}
      }
    end

    ###############################################################################

    def values_for_customization(context)
      if self.tour?
        values_for_tour_customization(context)
      elsif self.flight?
        values_for_flight_customization(context)
      end
    end

    def price_with_context(context)
      if self.room?
        price_for_room(context)
      elsif self.hotel?
        price_for_hotel(context)
      elsif self.program?
        price_for_program(context)
      elsif self.tour?
        price_for_tour(context)
      elsif self.transfer?
        price_for_transfer(context)
      elsif self.flight?
        price_for_flight(context)
      elsif self.rent?
        price_for_rent(context)
      else
        self.price
      end
    end

    def variant_with_context(context)
      if self.room?
        variant_for_room(context)
      elsif self.hotel?
        variant_for_hotel(context)
      elsif self.program?
        variant_for_program(context)
      elsif self.tour?
        variant_for_tour(context)
      elsif self.transfer?
        variant_for_transfer(context)
      elsif self.flight?
        variant_for_flight(context)
      elsif self.rent?
        variant_for_rent(context)
      else
        self.master
      end
    end

    def variant_and_price_with_context(context)
      if self.room?
        variant_and_price_for_room(context)
      elsif self.hotel?
        variant_and_price_for_hotel(context)
      elsif self.program?
        variant_and_price_for_program(context)
      elsif self.tour?
        variant_and_price_for_tour(context)
      elsif self.transfer?
        variant_and_price_for_transfer(context)
      elsif self.flight?
        variant_and_price_for_flight(context)
      elsif self.rent?
        variant_and_price_for_rent(context)
      else
        {
          'variant' => self.master,
          'price' => self.price,
          'customization' => {}
        }
      end
    end

    ###############################################################################

    #def self.list_of(string)
    #  list = []
    #  Spree::Product.all.each do |p|
    #    list << p if p.type_is?(string)
    #  end
    #  list
    #end

    ###############################################################################

    def season_ids
      get_option_values('season', 'id')
    end

    def adults_combinations
      get_option_values('adult')
    end

    def child_combinations
      get_option_values('child')
    end

    def infant_combinations
      get_option_values('infant')
    end

    def meal_plan_combinations
      get_option_values('meal-plan', 'id')
    end

    def pax_combinations
      get_option_values('pax')
    end

    def transmission_combinations
      get_option_values('transmission', 'id')
    end

    def duration_combinations
      get_option_values('duration')
    end

    def taxi_confort_combinations
      get_option_values('taxi-confort', 'id')
    end

    def get_option_values(option_name, type='presentation')
      list = Spree::OptionValue.joins(:option_type, :variants => :product)
      list = list.where('spree_option_types.name = ?', option_name)
      product_ids = [self.id]
      if self.accommodation?
        product_ids += self.children_rooms.map(&:id)
      end
      list = list.where('spree_products.id IN (?)', product_ids)
      if type == 'presentation'
        list = list.uniq.map(&:presentation)
      elsif type  == 'id'
        list = list.uniq.map(&:id)
      end
      list
    end

    def properties_feature
      list = []
      properties = self.product_properties
      properties.each do |p|
        list << "#{p.property.name}-#{p.value}" if !p.value.nil?
      end
      list
    end

    def properties_include
      list = []
      properties = self.product_properties
      properties.each do |p|
        list << p.property.name if p.value.nil?
      end
      list
    end

    def variant_names
      if self.accommodation?
        variants = []
        self.children_rooms.each do |r|
          variants += r.variants_including_master.map {|v| v.order_values}
        end
        variants = variants.uniq
      else
        variants = self.variants_including_master.map {|v| v.order_values}
      end
      variants
    end

    #####################################################################################

  end
end
