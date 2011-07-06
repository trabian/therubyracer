require 'stringio'

module V8
  class Context
    attr_reader :native, :scope, :access, :portal

    def initialize(opts = {})
      @access = Access.new
      @to = @portal = Portal.new(self, @access)
      @portal.lock do
        with = opts[:with]
        constructor = nil
        template = if with
          constructor = @portal.templates.to_constructor(with.class)
          constructor.disable()
          constructor.template.InstanceTemplate()
        else
          C::ObjectTemplate::New()
        end
        @native = opts[:with] ? C::Context::New(template) : C::Context::New()
        @native.enter do
          @global = @native.Global()
          @portal.proxies.register_javascript_proxy @global, :for => with if with
          constructor.enable() if constructor
          @scope = @portal.rb(@global)
          @global.SetHiddenValue(C::String::NewSymbol("TheRubyRacer::RubyContext"), C::External::New(self))
        end
        yield(self) if block_given?
      end
    end

    ##
    # Destroy this context and all the objects that it contains. You noramlly
    # will not need this.
    #
    # WARNING: This is an interim measure until a more complete solution can
    # be found for the challenges of managing garbage collection between Ruby
    # and V8
    def destroy
      @portal.destroy
    end

    def eval(javascript, filename = "<eval>", line = 1)
      if IO === javascript || StringIO === javascript
        javascript = javascript.read()
      end
      err = nil
      value = nil
      @to.lock do
        C::TryCatch.try do |try|
          @native.enter do
            script = C::Script::Compile(@to.v8(javascript.to_s), @to.v8(filename.to_s))
            if try.HasCaught()
              err = JSError.new(try, @to)
            else
              result = script.Run()
              if try.HasCaught()
                err = JSError.new(try, @to)
              else
                value = @to.rb(result)
              end
            end
          end
        end
      end
      raise err if err
      return value
    end

    def load(filename)
      File.open(filename) do |file|
        self.eval file, filename, 1
      end
    end

    def [](key)
      @to.open do
        @to.rb @global.Get(@to.v8(key))
      end
    end

    def []=(key, value)
      @to.open do
        @global.Set(@to.v8(key), @to.v8(value))
      end
      return value
    end

    def self.stack(limit = 99)
      if native = C::Context::GetEntered()
        global = native.Global()
        cxt = global.GetHiddenValue(C::String::NewSymbol("TheRubyRacer::RubyContext")).Value()
        cxt.instance_eval {@to.rb(C::StackTrace::CurrentStackTrace(limit))}
      else
        []
      end
    end
  end

  module C
    class Context
      def enter
        if block_given?
          if IsEntered()
            yield(self)
          else
            Enter()
            begin
              yield(self)
            ensure
              Exit()
            end
          end
        end
      end
    end
  end
end