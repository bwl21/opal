# frozen_string_literal: true

require 'pathname'
require 'opal/version'
require 'opal/nodes/scope'

module Opal
  module Nodes
    # Generates code for an entire file, i.e. the base sexp
    class TopNode < ScopeNode
      handle :top

      children :body

      def compile
        push version_comment

        opening
        in_scope do
          body_code = stmt(stmts)
          body_code = [body_code] unless body_code.is_a?(Array)

          if compiler.eval?
            add_temp '$nesting = self.$$is_a_module ? [self] : [self.$$class]'
          else
            add_temp 'self = Opal.top'
            add_temp '$nesting = []'
          end
          add_temp 'nil = Opal.nil'
          add_temp '$$$ = Opal.const_get_qualified'
          add_temp '$$ = Opal.const_get_relative'

          add_used_helpers
          add_used_operators
          line scope.to_vars

          compile_method_stubs
          compile_irb_vars
          compile_end_construct

          line body_code
        end

        closing
      end

      def opening
        if compiler.requirable?
          path = Pathname(compiler.file).cleanpath.to_s
          line "Opal.modules[#{path.inspect}] = function(Opal) {"
        elsif compiler.eval?
          line '(function(Opal, self) {'
        else
          line '(function(Opal) {'
        end
      end

      def closing
        if compiler.requirable?
          line "};\n"
        elsif compiler.eval?
          line '})(Opal, self)'
        else
          line "})(Opal);\n"
        end
      end

      def stmts
        compiler.returns(body)
      end

      def compile_irb_vars
        if compiler.irb?
          line 'if (!Opal.irb_vars) { Opal.irb_vars = {}; }'
        end
      end

      def add_used_helpers
        helpers = compiler.helpers.to_a
        helpers.to_a.each { |h| add_temp "$#{h} = Opal.#{h}" }
      end

      def add_used_operators
        operators = compiler.operator_helpers.to_a
        operators.each do |op|
          name = Nodes::CallNode::OPERATORS[op]
          line "function $rb_#{name}(lhs, rhs) {"
          line "  return (typeof(lhs) === 'number' && typeof(rhs) === 'number') ? lhs #{op} rhs : lhs['$#{op}'](rhs);"
          line '}'
        end
      end

      def compile_method_stubs
        if compiler.method_missing?
          calls = compiler.method_calls
          stubs = calls.to_a.map { |k| "'$#{k}'" }.join(', ')
          line "Opal.add_stubs([#{stubs}]);" unless stubs.empty?
        end
      end

      # Any special __END__ content in code
      def compile_end_construct
        if content = compiler.eof_content
          line 'var $__END__ = Opal.Object.$new();'
          line "$__END__.$read = function() { return #{content.inspect}; };"
        end
      end

      def version_comment
        "/* Generated by Opal #{Opal::VERSION} */"
      end
    end
  end
end
