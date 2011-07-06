
require "#{File.dirname(__FILE__)}/../spec_helper.rb"

include V8

describe C::Context do

  before {@lock = C::Locker.new}
  after {@lock.delete}

  it "should not have a current context if no context is open" do
    C::Context::GetEntered().should be_nil
  end

  it "can javascript properties on the global scope via ruby when the default scope is a ruby object" do
    V8::Context.new(:with => Object.new) do |cxt|
      cxt['foo'] = 'bar'
      cxt.eval('foo').should eql('bar')
    end
  end

  it "can get the current javascript execution stack" do
    V8::Context.new do |cxt|
      trace = nil
      cxt['getTrace'] = lambda do
        trace = V8::Context.stack
      end
      cxt.eval(<<-JS, 'trace.js')
      function one() {
        return two();
      }

      function two() {
        return three();
      }

      function three() {
        return getTrace()
      }
      one();
JS
      trace.length.should be(4)
      trace.to_a[0].tap do |frame|
        frame.line_number.should == 10
        frame.column.should == 16
        frame.script_name.should == 'trace.js'
        frame.function_name.should == 'three'
        frame.should_not be_eval
        frame.should_not be_constructor
      end
    end
  end

  it "has an empty stack if there is no enterned context" do
    V8::Context.stack.should be_empty
  end

  describe "a destroyed context" do
    before do
      @cxt = V8::Context.new
      @cxt['foo'] = Object.new
      @bar = @cxt.eval('(function() {})')
      @cxt.destroy
    end
    it "should release all proxies" do
      @cxt.portal.proxies.should be_empty
    end
    it "shouldn't be useable for evaluation'" do
      expect {@cxt.eval('1')}.should raise_error(V8::Portal::ClosedError)
    end
    it "shouldn't be useable for variable retrieval or setting" do
      expect {@cxt['foo']}.should raise_error(V8::Portal::ClosedError)
    end
    it "invalidates JS objects that came from it" do
      expect {@bar.to_s}.should raise_error(V8::Portal::ClosedError)
      expect {@bar.call()}.should raise_error(V8::Portal::ClosedError)
    end
  end
end