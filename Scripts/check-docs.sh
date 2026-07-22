#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

ruby <<'RUBY'
require "pathname"
require "set"

errors = []

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
  "CONTRIBUTING.md" => "CONTRIBUTING.en.md"
}

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
