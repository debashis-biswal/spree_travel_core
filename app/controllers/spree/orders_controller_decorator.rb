module Spree
    OrdersController.class_eval do

      def update
        if @order.contents.update_cart(order_params)
          respond_with(@order) do |format|
            format.html do
              if params.has_key?(:checkout)
                @order.next if @order.cart?
                redirect_to checkout_state_path(@order.checkout_steps.first)
              else
                redirect_to cart_path
              end
            end
          end
        else
          respond_with(@order)
        end
      end


    # Adds a new item to the order (creating a new order if none already exists)
    def populate
      populator = Spree::OrderPopulator.new(current_order(create_order_if_necessary: true), current_currency)
      context = Spree::Context.build_from_params(params, :temporal => false)
      #TODO, este save antes se hacia dentro del 'populator.populate' ahora lo saque para que se puedan productos con contextos diferentes
      context.save

      variant_id = params[:variant_id]
      quantity = params[:quantity]

      #TODO hay que poner algo aqui para asegurar que al carrito solo valla un solo producto, al menos para hoteles

      if populator.populate(variant_id, quantity, context)
        context.line_item = current_order.line_items.last
        # TODO es probable que esto sea "la meerrrr" en frances, hay que discutirlo y revisarlo
        context.save

        line_item = current_order.line_items.last
        line_item.price = params[:price]
        line_item.save

        #TODO cuando se añade un al carrito un producto igual con un contexto diferente se debe añadir como otro line item.....

        current_order.ensure_updated_shipments
        # TODO, esto es un cable extremo, no se si esto deba ser así aqui, tengo dudas con relación al "0"
        # TODO esto es para el caso en que se permita solo un producto en el carrito.
        current_order.contents.update_cart(:line_items_attributes=>{"0"=>{"quantity"=>params[:quantity], "id"=>current_order.line_items.last.id}})

        # fire_event('spree.cart.add')
        # fire_event('spree.order.contents_changed')

        respond_with(@order) do |format|
          format.html { redirect_to cart_path }
        end
      else
        flash[:error] = populator.errors.full_messages.join(" ")
        redirect_to :back
      end
    end


  end
end
