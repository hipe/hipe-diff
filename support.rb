module Hipe
  module Diff
    class Flail < RuntimeError
      def initialize *a, &b
        super(*a)
        @meta = nil
        yield self if block_given?
      end
      attr_accessor :meta
    end
    module Flails
      def flail *a, &b
        raise Flail.new(*a, &b)
      end
    end
    module Colorize
      Codes = {:bright=>'1', :red=>'31', :green=>'32', :yellow=>'33',
        :blue=>'34',:magenta=>'35',:bold=>'1',:blink=>'5'}
      def colorize str, *codes
        return str if codes == [nil] || codes.empty?
        codes = codes.first if codes.size == 1 && codes.first.kind_of?(Array)
        if codes.first == :background
          return str unless codes.size == 2
          nums = ["4#{Codes[codes.last][1..1]}"] # not really excusable in any way
        else
          nums = codes.map{|x| Codes[x]}.compact
        end
        "\e[#{nums * ';'}m#{str}\e[0m"
      end
      module_function :colorize
    end
    module MemoizeParent
      #
      # set parent attribute without it showing up in inspect() dumps ick!
      #
      def parent= mixed
        fail("no clear_parent() available yet.") unless mixed
        @has_parent = !! mixed
        class << self; self end.send(:define_method, :parent){mixed}
        mixed # maybe chain assignmnet of 1 parent to several cx at once
      end
      def parent?
        instance_variable_defined?('@has_parent') && @has_parent # no warnings
      end
      def parent
        nil
      end
    end
  end
end
