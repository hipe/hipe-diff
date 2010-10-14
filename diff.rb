require 'rubygems' # for 'diff/lcs'
# require 'ruby-debug'; puts "\e[1;5;33mruby-debug\e[0m"
require 'diff/lcs' # '1.1.2'
require 'stringio'

module Hipe; end
module Hipe::Diff; end
require File.dirname(__FILE__) + '/support' unless Hipe::Diff.const_defined?('Colorize')

#
# puts Hipe::Diff.colorize("A\nC\nD", "A\nB\nC")
#


module Hipe::Diff
  class << self
    def string_diff mixed_left, mixed_right, &block
      LcsDiffStyler.new.diff mixed_left, mixed_right, &block
    end
    def colorize mixed_left, mixed_right, &block
      LcsDiffStyler.new{ |l| l.gitlike! }.diff(mixed_left, mixed_right, &block)
    end
  end
  class LcsDiffStyler
    include Colorize
    def initialize
      @context = nil # num lines of context
      @style_loaded = false
      yield self if block_given?
    end
    attr_reader :style_loaded
    alias_method :style_loaded?, :style_loaded
    def plain!
      @add_header    = '%sa%s'
      @add_style = nil
      @change_header = '%sc%s'
      @del_header    = '%sd%s'
      @del_style = nil
      @header_style = nil
      @left  = '<'
      @right = '>'
      @separator_line = '---'
      @trailing_whitespace_style = nil
      @style_loaded = true
    end
    def gitlike!
      common_header = '@@ -%s, +%s @@'
      @add_header =  common_header
      @add_style = [:bold, :green]
      @change_header = common_header
      @del_header = common_header
      @del_style = [:bold, :red]
      @header_style = [:bold, :magenta]
      @left  = '-'
      @right = '+'
      @separator_line = nil
      @trailing_whitespace_style = [:background, :red]
      @style_loaded = true
      self
    end
    # set number of lines of context
    def context= mixed
      fail("no #{mixed.inspect}") unless mixed.kind_of?(Fixnum) && mixed >= 0
      @context = mixed == 0 ? nil : mixed
    end
    def diff mixed1, mixed2, &block
      yield(self) if block_given?
      plain! unless style_loaded?
      case (x=[mixed1.class, mixed2.class])
      when [Array,Array];   diff_arrays  mixed1, mixed2
      when [String,String]; diff_strings mixed1, mixed2
      else
        fail("no diff strategy for #{x.inspect}")
      end
    end
    def diff_arrays arr1, arr2
      @arr1, @arr2 = arr1, arr2
      render Diff::LCS.diff arr1, arr2
    end
    def diff_strings a, b
      diff_arrays a.split("\n", -1), b.split("\n", -1)
    end
    def render diff
      @out = StringIO.new
      @offset_offset = -1
      diff.each do |chunk|
        context_pre(chunk) if @context
        dels = []
        adds = []
        start_add = last_add = start_del = last_del = nil
        chunk.each do |change|
          case change.action
          when '+'
            start_add ||= change.position + 1
            last_add = change.position + 1
            adds.push change.element
          when '-'
            start_del ||= change.position + 1
            last_del = change.position + 1
            dels.push change.element
          else
            fail("no: #{change.action}")
          end
        end
        if adds.any? && dels.any?
          puts_change_header start_del, last_del, start_add, last_add
        elsif adds.any?
          puts_add_header start_add, last_add
        else
          puts_del_header start_del, last_del
        end
        @offset_offset -= ( dels.size - adds.size )
        dels.each do |del|
          puts_del "#{@left} #{del}"
        end
        if adds.any? && dels.any?
          puts_sep
        end
        adds.each do |add|
          puts_add "#{@right} #{add}"
        end
        context_post(chunk) if @context
      end
      @out.rewind
      @out.read
    end
    def context_pre chunk
      pos = chunk.first.position - 1
      puts_range_safe pos - @context, pos
    end
    def context_post chunk
      pos = chunk.last.position + 1
      puts_range_safe pos, pos + @context
    end
    def other_offset start
      start + @offset_offset
    end
    def puts_del str
      puts_change str, @del_style
    end
    def puts_add str
      puts_change str, @add_style
    end
    def puts_add_header start_add, last_add
      str = @add_header % [other_offset(start_add), range(start_add,last_add)]
      @out.puts(colorize(str, @header_style))
    end
    def puts_change str, style
      # separate string into three parts! main string,
      # trailing non-newline whitespace, and trailing newlines
      # we want to highlite the trailing whitespace, but if we are
      # colorizing it we need to exclude the final trailing newlines
      # for puts to work correctly
      if /^(.*[^\s]|)([\t ]*)([\n]*)$/ =~ str
        main_str, ws_str, nl_str = $1, $2, $3
        @out.print(colorize(main_str, style))
        @out.print(colorize(ws_str, @trailing_whitespace_style))
        @out.puts(nl_str)
      else
        # hopefully regex never fails but it might
        @out.puts(colorize(str, style))
      end
    end
    def puts_change_header start_del, last_del, start_add, last_add
      str = @change_header %
        [range(start_del,last_del), range(start_add,last_add)]
      @out.puts(colorize(str, @header_style))
    end
    def puts_del_header start_del, last_del
      str =  @del_header % [range(start_del,last_del), other_offset(start_del)]
      @out.puts(colorize(str, @header_style))
    end
    def puts_range_safe start, final
      start = [start, 0].max
      final = [@arr1.size-1, final].min
      if @last_range
        start = [@last_range[1]+1, start].max
        # assume sequential for now! no need to check about previous
        # ones in front of us
      end
      return if start >= final
      @last_range = [start, final]
      @out.puts @arr1[start..final].map{|x| "  #{x}"}
      # @todo i don't know if i'm reading the chunks right
    end
    def puts_sep
      if @separator_line
        @out.puts(@separator_line)
      end
    end
    def range min, max
      if min == max
        min
      else
        "#{min},#{max}"
      end
    end
  end
end

if __FILE__ == $PROGRAM_NAME
  require 'test/unit'
  require 'test/unit/ui/console/testrunner'
  module Hipe::Diff::Test
    class CaseVisual < Test::Unit::TestCase
      def test_context
        before = <<-B.gsub(/^          /,'')
          alpha
          beta
          gamma
          tau
        B
        after = <<-A.gsub(/^          /,'')
          alpha
          gamma
          zeta
          tau
        A
        $stdout.puts ::Hipe::Diff.colorize(before, after){ |l| l.context = 3 }
      end
    end
  end
  Test::Unit::UI::Console::TestRunner.run(Hipe::Diff::Test::CaseVisual)
end
