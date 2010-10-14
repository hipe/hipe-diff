require 'fileutils'
require 'open3'
require 'shellwords'

module Hipe; end
module Hipe::Diff; end
require File.dirname(__FILE__)+'/stream-colorizer' unless Hipe::Diff.const_defined?('StreamColorizer')

module Hipe::Diff
  module Proxy
    #
    # Sort of like Hipe::Diff.colorize() but use the underlying diff utility
    #
    class << self
      def diff path_a, path_b, opts={}
        diff = ::Hipe::Diff::Proxy::Diff.new(path_a, path_b, opts)
        diff.run
      end
    end

    module DiffClassMethods
      def relativize_validate base, path_a, path_b
        unless [0,0]==[path_a, path_b].map{ |x| x.index(base) }
          Hipe::Diff::Flail.new( "chdir base must be at the beggining of both paths: "<<
            "(#{base.inspect}, #{path_a.inspect}, #{path_b.inspect})") do |fl|
              fl.meta = [base, path_a, path_b]
          end
        end
      end
    end

    class Diff
      include Hipe::Diff::Colorize, Hipe::Diff::Flails
      extend DiffClassMethods
      def initialize path_a, path_b, opts={}
        @path_a = path_a
        @path_b = path_b
        @opts = {}
        opts.keys.each{ |k| @opts[k.to_s.gsub('-','_').to_sym] = opts[k] }
      end
      attr_accessor :filter # sure why not

      # styles and state machines
      def starter_stylesheet
        {
          :header => [:bold, :yellow],
          :add    => [:bold, :green],
          :remove => [:bold, :red],
          :range  => [:bold, :magenta],
          :trailing_whitespace => [:background, :red]
        }
      end
      def stream_colorizer_prototype
        Hipe::Diff::StreamColorizer.new do |sc|
          sc.stylesheet_merge(starter_stylesheet)
          sc.when(:start) do |o|
            o.style nil
            o.when %r(\Adiff ), :state=>:header
            o.when %r(\A\+), :state=>:add
            o.when %r(\A\-), :state=>:remove
          end
          sc.when(:header) do |o|
            o.style :header
            o.when %r(\A@@), :state=>:range
          end
          sc.when(:range) do |o|
            o.style :range
            o.when_not %r(\A@@), :state=>:plain
          end
          sc.when(:plain) do |o|
            o.style nil
            o.trailing_whitespace_style :trailing_whitespace
            o.when %r(\Adiff ), :state=>:header
            o.when %r(\A\+), :state=>:add
            o.when %r(\A\-), :state=>:remove
          end
          sc.when(:add) do |o|
            o.style :add
            o.trailing_whitespace_style :trailing_whitespace
            o.when_not %r(\A\+), :state=>:plain
          end
          sc.when(:remove) do |o|
            o.style :remove
            o.trailing_whitespace_style :trailing_whitespace
            o.when_not %r(\A\-), :state=>:plain
          end
        end
      end

      def run
        status = nil
        begin
          @chdir = @opts.delete(:chdir)
          @out = @opts.delete(:out) || $stdout
          @err = @opts.delete(:err) || $stderr
          @styles = @opts.delete(:styles) || {}
          fail = nil
          [@path_a, @path_b].each do |p|
            unless File.exist? p
              @err.puts colorize("error: ", :red) << "does not exist: #{p}"
              fail = :file_not_found
            end
          end
          fail and return fail_with_message(fail)
          @path_a, @path_b = relativize(@chdir, @path_a, @path_b) if @chdir
          unnorm = { '--unified' => '3', '--recursive' => nil }
          @opts.keys.each{ |k| unnorm["--#{k.to_s.gsub('_','-')}"] = @opts[k] }
          @opts = nil # don't get confused
          @args = ['diff', unnorm.map{|x| x.compact.join('=')}, @path_a, @path_b].flatten
          block = proc do
            Open3.popen3(*@args) do |sin, sout, serr|
              @sout = sout; @serr = serr
              read_streams
            end
          end
          if @chdir
            FileUtils.cd(@chdir, :verbose=>true, &block)
          else
            block.call
          end
        rescue Hipe::Diff::Flail => e
          @err.puts e.message
          status = :flailure
        end
        status
      end
    protected
      def build_stream_colorizer
        stream_colorizer_prototype.spawn do |colorizer|
          colorizer.stylesheet_merge(@styles)
        end
      end
    private
      def fail_with_message symbol
        @err.puts "Hipe::Diff::Proxy -- there were errors: #{symbol.to_s}."
        symbol
      end
      def read_streams
        @filter ||= build_stream_colorizer
        @filter.filter_init @out
        o = ''; e = nil; status = nil
        while o || e do
          if o && o = @sout.gets
            status = @filter.puts(o) and break
          end
          if ! o && e = @serr.gets
            @did or (@did = 1 and @err.puts( colorize("with: ", :yellow) << @args.join(' ')))
            @err.puts colorize("error: ", :red) << e
            status = :diff_error
          end
        end
        status
      end
      def relativize base, path_a, path_b
        fail = self.class.relativize_validate( base, path_a, path_b ) and raise fail
        tail_a, tail_b = [path_a, path_b].map{|x| '.'+x[base.length..-1]}
        [tail_a, tail_b]
      end
    end
  end
end
