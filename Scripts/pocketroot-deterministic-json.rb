#!/usr/bin/env ruby

module PocketRootDeterministicJSON
  class Error < StandardError
  end

  module_function

  def dump(value, error_class: Error)
    "#{render(value, 0, error_class)}\n"
  end

  def render(value, depth, error_class)
    indentation = "  " * depth
    child_indentation = "  " * (depth + 1)

    case value
    when Hash
      return "{}" if value.empty?

      members = value.map do |key, child|
        unless key.is_a?(String)
          raise error_class, "JSON object key must be a string"
        end
        "#{child_indentation}#{json_string(key, error_class)}: " \
          "#{render(child, depth + 1, error_class)}"
      end
      "{\n#{members.join(",\n")}\n#{indentation}}"
    when Array
      return "[]" if value.empty?

      members = value.map do |child|
        "#{child_indentation}#{render(child, depth + 1, error_class)}"
      end
      "[\n#{members.join(",\n")}\n#{indentation}]"
    when String
      json_string(value, error_class)
    when Integer
      value.to_s
    when Float
      unless value.finite?
        raise error_class, "JSON number must be finite"
      end
      value.to_s
    when TrueClass
      "true"
    when FalseClass
      "false"
    when NilClass
      "null"
    else
      raise error_class, "unsupported JSON value: #{value.class}"
    end
  end

  def json_string(value, error_class)
    encoded = value.dup
    if encoded.encoding == Encoding::BINARY
      encoded.force_encoding(Encoding::UTF_8)
    else
      encoded = encoded.encode(Encoding::UTF_8)
    end
    unless encoded.valid_encoding?
      raise error_class, "JSON string must be valid UTF-8"
    end

    escaped = encoded.each_codepoint.map do |codepoint|
      case codepoint
      when 0x08
        "\\b"
      when 0x09
        "\\t"
      when 0x0A
        "\\n"
      when 0x0C
        "\\f"
      when 0x0D
        "\\r"
      when 0x22
        "\\\""
      when 0x5C
        "\\\\"
      when 0x00..0x1F
        format("\\u%04x", codepoint)
      else
        codepoint.chr(Encoding::UTF_8)
      end
    end.join
    "\"#{escaped}\""
  rescue EncodingError
    raise error_class, "JSON string must be valid UTF-8"
  end
end
