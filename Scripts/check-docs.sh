#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

ruby <<'RUBY'
require "pathname"
require "set"
require "yaml"

errors = []

def nonempty_string?(value)
  value.is_a?(String) && !value.strip.empty?
end

def boolean_or_nil?(value)
  value.nil? || value.instance_of?(TrueClass) || value.instance_of?(FalseClass)
end

def github_heading_anchors(text)
  anchors = Set.new
  occurrences = Hash.new(0)
  in_fence = false

  text.each_line do |line|
    if line.match?(/\A\s*(```|~~~)/)
      in_fence = !in_fence
      next
    end
    next if in_fence

    match = line.match(/\A {0,3}\#{1,6}\s+(.+?)\s*#*\s*\z/)
    next unless match

    heading = match[1]
      .gsub(/!\[([^\]]*)\]\([^)]+\)/, "\\1")
      .gsub(/\[([^\]]+)\]\([^)]+\)/, "\\1")
      .gsub(/<[^>]+>/, "")
      .gsub(/[`*_~]/, "")
      .downcase
    slug = heading
      .gsub(/[^\p{L}\p{N}\s_-]/u, "")
      .gsub(/\s/u, "-")
    next if slug.empty?

    occurrence = occurrences[slug]
    anchors << (occurrence.zero? ? slug : "#{slug}-#{occurrence}")
    occurrences[slug] += 1
  end

  anchors
end

root_pairs = {
  "README.md" => "README.en.md",
  "CHANGELOG.md" => "CHANGELOG.en.md",
  "CONTRIBUTING.md" => "CONTRIBUTING.en.md",
  "SECURITY.md" => "SECURITY.en.md",
  "CODE_OF_CONDUCT.md" => "CODE_OF_CONDUCT.en.md"
}

community_files = %w[
  .github/ISSUE_TEMPLATE/bug_report.yml
  .github/ISSUE_TEMPLATE/feature_request.yml
  .github/ISSUE_TEMPLATE/integration_help.yml
  .github/ISSUE_TEMPLATE/config.yml
  .github/PULL_REQUEST_TEMPLATE.md
  .github/SUPPORT.md
]

community_files.each do |path|
  errors << "Missing community health file: #{path}" unless Pathname(path).file?
end

issue_form_paths = %w[
  .github/ISSUE_TEMPLATE/bug_report.yml
  .github/ISSUE_TEMPLATE/feature_request.yml
  .github/ISSUE_TEMPLATE/integration_help.yml
]
issue_form_paths.each do |path|
  next unless Pathname(path).file?

  begin
    form = YAML.safe_load(Pathname(path).read, permitted_classes: [], aliases: false)
    unless form.is_a?(Hash) && nonempty_string?(form["name"]) &&
      nonempty_string?(form["description"]) &&
      (form["title"].nil? || form["title"].is_a?(String)) &&
      form["body"].is_a?(Array) && !form["body"].empty?
      errors << "Invalid GitHub Issue form structure: #{path}"
      next
    end

    ids = Set.new
    form["body"].each_with_index do |item, index|
      unless item.is_a?(Hash) &&
        %w[markdown input textarea dropdown checkboxes].include?(item["type"]) &&
        item["attributes"].is_a?(Hash)
        errors << "Invalid GitHub Issue form item: #{path}:#{index + 1}"
        next
      end
      type = item["type"]
      attributes = item["attributes"]
      if type == "markdown"
        unless nonempty_string?(attributes["value"])
          errors << "Invalid GitHub Issue form markdown value: #{path}:#{index + 1}"
        end
        next
      end

      id = item["id"]
      label = attributes["label"]
      if !id.is_a?(String) || !id.match?(/\A[a-zA-Z0-9_-]+\z/) ||
        ids.include?(id) || !nonempty_string?(label)
        errors << "Invalid or duplicate GitHub Issue form id/label: #{path}:#{index + 1}"
      end
      ids << id if id.is_a?(String)

      validations = item["validations"]
      if !validations.nil? &&
        (!validations.is_a?(Hash) ||
          !boolean_or_nil?(validations["required"]))
        errors << "Invalid GitHub Issue form validations: #{path}:#{index + 1}"
      end

      if %w[input textarea].include?(type)
        %w[description placeholder].each do |key|
          value = attributes[key]
          unless value.nil? || nonempty_string?(value)
            errors << "Invalid GitHub Issue form #{key}: #{path}:#{index + 1}"
          end
        end
        render = attributes["render"]
        unless type == "textarea" || render.nil?
          errors << "Invalid GitHub Issue form render: #{path}:#{index + 1}"
        end
        unless render.nil? || nonempty_string?(render)
          errors << "Invalid GitHub Issue form render: #{path}:#{index + 1}"
        end
      elsif type == "dropdown"
        options = attributes["options"]
        unless options.is_a?(Array) && !options.empty? &&
          options.all? { |option| nonempty_string?(option) } &&
          options.uniq.length == options.length &&
          boolean_or_nil?(attributes["multiple"])
          errors << "Invalid GitHub Issue form dropdown options: #{path}:#{index + 1}"
        end
      elsif type == "checkboxes"
        options = attributes["options"]
        unless options.is_a?(Array) && !options.empty? && options.all? do |option|
          option.is_a?(Hash) && nonempty_string?(option["label"]) &&
            boolean_or_nil?(option["required"])
        end
          errors << "Invalid GitHub Issue form checkbox options: #{path}:#{index + 1}"
        end
      end
    end
  rescue Psych::Exception => error
    errors << "Invalid GitHub Issue form YAML: #{path}: #{error.message}"
  end
end

config_path = Pathname(".github/ISSUE_TEMPLATE/config.yml")
if config_path.file?
  begin
    config = YAML.safe_load(config_path.read, permitted_classes: [], aliases: false)
    links = config.is_a?(Hash) ? config["contact_links"] : nil
    unless [true, false].include?(config&.fetch("blank_issues_enabled", nil)) &&
      links.is_a?(Array) && !links.empty? && links.all? do |link|
        link.is_a?(Hash) && link["name"].is_a?(String) &&
          link["url"].to_s.start_with?("https://") &&
          link["about"].is_a?(String)
      end
      errors << "Invalid GitHub Issue template config: #{config_path}"
    end
  rescue Psych::Exception => error
    errors << "Invalid GitHub Issue template config YAML: #{error.message}"
  end
end

chinese_paths = root_pairs.keys.map { |path| Pathname(path) }
chinese_paths.concat(
  Pathname.glob("Docs/**/*.md").reject do |path|
    path.each_filename.to_a.include?("en")
  end
)

english_paths = root_pairs.values.map { |path| Pathname(path) }
english_paths.concat(Pathname.glob("Docs/en/**/*.md"))

root_pairs.each do |chinese, english|
  errors << "Missing Chinese document: #{chinese}" unless Pathname(chinese).file?
  errors << "Missing English mirror: #{english}" unless Pathname(english).file?
end

chinese_paths.each do |path|
  next unless path.file?

  components = path.each_filename.to_a
  english =
    if components.first == "Docs"
      Pathname("Docs/en").join(*components.drop(1))
    else
      Pathname(root_pairs.fetch(path.to_s))
    end
  errors << "Missing English mirror for #{path}: #{english}" unless english.file?
end

english_paths.each do |path|
  next unless path.file?

  components = path.each_filename.to_a
  chinese =
    if components.first == "Docs" && components[1] == "en"
      Pathname("Docs").join(*components.drop(2))
    else
      Pathname(root_pairs.invert.fetch(path.to_s))
    end
  errors << "Missing Chinese primary for #{path}: #{chinese}" unless chinese.file?
end

all_paths = (chinese_paths + english_paths).uniq.select(&:file?)

chinese_paths.select(&:file?).each do |path|
  text = path.read
  unless text.match?(/[\u3400-\u4dbf\u4e00-\u9fff]/)
    errors << "Chinese primary contains no CJK text: #{path}"
  end
end

heading_anchor_cache = {}

all_paths.each do |path|
  text = path.read

  unless text.include?("[简体中文]") && text.include?("[English]")
    errors << "Missing language switch in #{path}"
  end

  fence_count = text.lines.count { |line| line.start_with?("```") }
  errors << "Unbalanced fenced code blocks in #{path}" if fence_count.odd?

  text.lines.each_with_index do |line, index|
    if line.match?(/[\t ]+\n\z/)
      errors << "Trailing whitespace in #{path}:#{index + 1}"
    end
  end

  text.scan(/!?\[[^\]]*\]\(([^)]+)\)/).flatten.each do |raw_target|
    target = raw_target.strip
    target = target[1...-1] if target.start_with?("<") && target.end_with?(">")
    next if target.empty?
    next if target.match?(/\A[a-z][a-z0-9+.-]*:/i)

    relative, fragment = target.split("#", 2)
    relative = relative.to_s.split("?", 2).first.to_s
    fragment = fragment.to_s.split("?", 2).first.to_s

    resolved = if relative.empty?
      path
    else
      path.dirname.join(relative).cleanpath
    end
    unless resolved.exist?
      errors << "Broken relative link in #{path}: #{target}"
      next
    end

    next if fragment.empty? || resolved.extname.downcase != ".md"

    anchors = heading_anchor_cache[resolved.to_s] ||= github_heading_anchors(
      resolved.read
    )
    unless anchors.include?(fragment.downcase)
      errors << "Broken Markdown anchor in #{path}: #{target}"
    end
  end
end

if errors.empty?
  puts "Documentation check passed: #{chinese_paths.count(&:file?)} Chinese primaries, " \
       "#{english_paths.count(&:file?)} English mirrors, and all relative links and " \
       "Markdown anchors resolved."
else
  warn errors.map { |message| "- #{message}" }.join("\n")
  exit 1
end
RUBY
