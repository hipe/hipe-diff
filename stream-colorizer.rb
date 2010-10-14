module Hipe; end
module Hipe::Diff; end
require File.dirname(__FILE__)+'/support' unless Hipe::Diff.const_defined?('Colorize')

module Hipe::Diff
  module StreamColorizerSupport
    module RuleList
    public
      def rule_list_init
        @rule_list = []
        @state_set = {}
        class << self
          attr_reader :rule_list
          attr_reader :state_set
        end
      end
      def when(re_or_symbol, opts=nil, &block)
        if re_or_symbol.kind_of?(::Regexp) && Hash===opts && ! block_given?
          add_regex_rule(re_or_symbol, opts)
        elsif re_or_symbol.kind_of?(Symbol) && opts.nil? && block_given?
          define_state(re_or_symbol, &block)
        else
          fail("unrecongized signature: `#{self.class}#when("<<
            "[#{re_or_symbol.class}],[#{opts.class}],[#{block.class}])")
        end
      end
      def when_not re, opts
        add_regex_rule_neg re, opts
      end
    protected
      def add_regex_rule re, opts
        fail("no") unless opts[:state]
        @rule_list.push RegexRule.make(re, opts[:state], {})
      end
      def add_regex_rule_neg re, opts
        fail("no") unless opts[:state]
        @rule_list.push RegexRule.make(re, opts[:state], {:neg=>true})
      end
      def define_state name, &block
        state = State.new(self, name, &block)
        fail("no") if @state_set.key?(state.name)
        @state_set[state.name] = state
      end
    end
    class RegexRule
      # api private
      class << self
        def make regex, state, opts
          if opts[:neg]
            RegexRuleNeg.new(regex, state)
          else
            RegexRule.new(regex, state)
          end
        end
      end
      def initialize regex, state
        @regex = regex
        @state = state or fail('no')
      end
      attr_reader :regex, :state
      def match str
        @regex =~ str
      end
    end
    class RegexRuleNeg < RegexRule
      def match str
        ! super
      end
    end
    class State
      include Hipe::Diff::Colorize, RuleList, Hipe::Diff::MemoizeParent
      def initialize parent, name, &block
        fail('no') unless name.kind_of?(::Symbol)
        @name = name
        self.parent = parent
        rule_list_init
        @style = nil
        @trailing_whitespace_style = nil
        block.call(self)
      end
      attr_accessor :name

      # return next state name or process the token (output it) and return nil
      def process line, out
        # debugger if /five/ =~ line
        other = @rule_list.detect{ |x| x.match(line) }
        other and return other.state
        if @trailing_whitespace_style.nil?
          output_line = colorize(line, *colors)
        else
          /\A(|.*[^[:space:]])([\t ]*)([\r\n]*)\Z/ =~ line or fail('oops')
          head, tail, nl = $1, $2, $3
          output_line = colorize(head, *colors)
          output_line.concat colorize(tail, * get_style(@trailing_whitespace_style)) unless tail.empty?
          output_line.concat nl unless nl.empty?
        end
        out.write output_line
        nil
      end
      def colors
        @colors ||= begin
          if style.nil?
            []
          else
            parent.stylesheet[style] or style_not_found_failure
          end
        end
      end
      def style *a
        case a.size
        when 0; @style
        when 1; @style = a.first
        else fail('no')
        end
      end
      def trailing_whitespace_style *a
        case a.size
        when 0; @trailing_whitespace_style
        when 1; @trailing_whitespace_style = a.first
        else fail('no')
        end
      end
    private
      def get_style style
        return nil if style.nil?
        parent.stylesheet[style] or fail("style not found: #{style.inspect}")
      end
      def style_not_found_failure which = '@style'
        value = instance_variable_get(which)
        fail("#{which} not found: #{value.inspect}")
      end
    end
  end
end

module Hipe::Diff
  class StreamColorizer
    include StreamColorizerSupport  # brings constants in
    include RuleList                # adds instance methods

    def dup
      other = self.class.new
      other.stylesheet = stylesheet.dup
      other.rule_list = @rule_list.dup
      other.state_set = @state_set.dup
      other
    end
    def initialize(*a, &b)
      rule_list_init
      @stylesheet = {}
      if a.any? || block_given?
        merge(*a, &b)
      end
    end
    attr_writer :rule_list
    def filter_init out
      @out = out
      @state = get_state(:start)
    end
    SANITY = 20
    def puts string
      sanity = SANITY
      while next_state_name = @state.process(string, @out)
        (sanity -= 1) < 0 and fail("sanity check failed.  infinite loop in state machine?")
        @state = get_state next_state_name
      end
      nil
    end
    def get_state name
      @state_set[name] or fail("no such state: #{name.inspect}")
    end
    def merge(&block)
      yield(self) if block_given?
      self
    end
    def spawn(*a, &b)
      other = dup
      other.merge(*a, &b)
      other
    end
    attr_writer :state_set
    attr_accessor :stylesheet
    def stylesheet_merge other
      @stylesheet.merge!(other)
    end
  end
end
