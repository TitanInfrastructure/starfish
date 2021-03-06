begin
  require 'active_record'
rescue LoadError
  require 'rubygems'
  gem 'activerecord'
  require 'active_record'
end

class MapReduce
  module ActiveRecord
    module Base
      attr_accessor :order, :group, :joins, :include, :select, :readonly
      attr_accessor :queue_size, :locked_queue_wait, :empty_queue_wait, :rescan_when_complete, :vigilant
      
      class Client
        include DRbUndumped
        
        include Enumerable

        def initialize(server_object)
          @server_object = server_object
          @type = eval(server_object.type_to_s)
        end
        
        def each
          @server_object.limit.times do
            yield get_value_from(@server_object.get_id)
          end
        end
        
        def logger(*args)
          @server_object.logger(*args)
        end
        
      private
      
        def get_value_from(object_id)
          case object_id
          when :locked_queue_wait
            sleep @server_object.locked_queue_wait || 1
            get_value_from(@server_object.get_id)
          when :empty_queue_wait
            sleep @server_object.empty_queue_wait || 30
            get_value_from(@server_object.get_id)
          else
            @type.find(object_id,
               :include => @server_object.include,
              :readonly => @server_object.readonly
            )
          end
        end
      end

      def get_id
        t = Time.now

        if @lock
          return :locked_queue_wait
        else
          unless object_id = queue.shift
            return :empty_queue_wait
          end
        end

        @time_spent_grabbing_objects += (Time.now - t)
        @num_objects_grabbed += 1

        return object_id
      end

private
      
      def set_total
        @total = type.count(:all, :conditions => input)
        if @rescan_when_complete
          @offset = 0
        else
          @queue_size ||= @total
        end
      end
      
      def queue
        if @queue.empty?
          if @offset == 0
            set_total
          elsif @offset >= @total
            if @rescan_when_complete || @vigilant
              set_total
            else
              begin
                self.finished
              rescue NameError
              ensure
                exit
              end
            end
          end
          
          GC.start

          @time_began = Time.now if @time_began == 0
          @lock = true
          t = Time.now

          @queue = type.find(:all,
            :conditions => input,
                 :limit => @queue_size,
                :offset => @offset,
                 :order => @order,
                 :group => @group,
                 :joins => @joins,
               :include => @include,
                :select => @select,
              :readonly => @readonly
          ).map{|object|object.id}

          @time_spent_grabbing_queues += (Time.now - t)
          @num_queues_grabbed += 1

          @offset += @queue.size unless @queue.empty?
          @lock = false
        end

        @queue
      end
    end
  end
end