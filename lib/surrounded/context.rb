require 'set'
require 'surrounded/context/role_policy'
module Surrounded
  module Context
    def self.extended(base)
      base.send(:include, InstanceMethods)
    end

    def new_policy(context, assignments)
      policy.new(context, assignments)
    end

    def triggers
      @triggers.dup
    end

    private

    def policies
      @policies ||= {
        'initialize' => Surrounded::Context::InitializePolicy,
        'trigger' => Surrounded::Context::TriggerPolicy
      }
    end

    def apply_roles_on(which)
      @policy = policies.fetch(which.to_s){ const_get(which) }
    end

    def policy
      @policy ||= apply_roles_on(:trigger)
    end

    def setup(*setup_args)
      private_attr_reader(*setup_args)

      # I want this to work so I can set the arity on initialize:
      # class_eval %Q<
      #   def initialize(#{*setup_args})
      #     arguments = parameters.map{|arg| eval(arg[1].to_s) }
      #     variable_names = Array(#{*setup_args})
      #     variable_names.zip(arguments).each do |role, object|
      #       assign_role(role, object)
      #     end
      #     policy.call(__method__, method(:add_role_methods))
      #   end
      # >

      define_method(:initialize){ |*args|
        setup_args.zip(args).each{ |role, object|
          assign_role(role, object)
        }
        policy.call(__method__, method(:add_role_methods))
      }
    end

    def private_attr_reader(*method_names)
      attr_reader(*method_names)
      private(*method_names)
    end

    def trigger(name, *args, &block)
      store_trigger(name)

      define_method(:"trigger_#{name}", *args, &block)

      private :"trigger_#{name}"

      define_method(name, *args){
        begin
          (Thread.current[:context] ||= []).unshift(self)
          policy.call(__method__, method(:add_role_methods))

          self.send("trigger_#{name}", *args)

        ensure
          policy.call(__method__, method(:remove_role_methods))
          (Thread.current[:context] ||= []).shift
        end
      }
    end

    def store_trigger(name)
      @triggers ||= Set.new
      @triggers << name
    end

    module InstanceMethods
      def role?(name, &block)
        accessor = eval('self', block.binding)
        roles.values.include?(accessor) && roles[name.to_s]
      end

      def triggers
        self.class.triggers
      end

      private

      def policy
        @policy ||= self.class.new_policy(self, roles)
      end

      def add_role_methods(obj, mod)
        modifier = modifier_methods.find do |meth|
                     obj.respond_to?(meth)
                   end
        return obj if mod.is_a?(Class) || !modifier

        obj.send(modifier, mod)
        obj
      end

      def remove_role_methods(obj, mod)
        obj.uncast if obj.respond_to?(:uncast)
        obj
      end

      def modifier_methods
        [:cast_as, :extend]
      end

      def assign_role(role, obj)
        roles[role.to_s] = obj
        instance_variable_set("@#{role}", obj)
        self
      end

      def roles
        @roles ||= {}
      end
    end
  end
end