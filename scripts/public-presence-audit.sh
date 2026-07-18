#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

ruby <<'RUBY'
require "pathname"

markdown_files = ["README.md"] + Dir.glob("docs/**/*.md") + Dir.glob(".github/**/*.md")
missing_links = []

markdown_files.each do |file|
  File.read(file).scan(/\[[^\]]*\]\(([^)]+)\)/).flatten.each do |target|
    target = target.split(/\s+['\"]/).first
    next if target.start_with?("http://", "https://", "mailto:", "#")

    relative_path = target.split("#", 2).first
    next if relative_path.empty?

    resolved_path = (Pathname(file).dirname + relative_path).cleanpath
    missing_links << "#{file}: #{target}" unless resolved_path.exist?
  end
end

unless missing_links.empty?
  warn "public presence audit failed: relative Markdown links do not resolve"
  missing_links.each { |link| warn "  #{link}" }
  exit 1
end

metadata_path = "docs/APP_STORE_METADATA_DRAFT.md"
metadata = File.read(metadata_path)

{"App Name" => 30, "Subtitle" => 30, "Promotional Text" => 170, "Keywords" => 100}.each do |heading, field_limit|
  value = metadata[/^## #{Regexp.escape(heading)}\n\n([^\n]+)/, 1]
  count_match = metadata.match(
    /^## #{Regexp.escape(heading)}\n\n[^\n]+\n\nCharacter count: (\d+) of (\d+)\./
  )

  unless value && count_match
    warn "public presence audit failed: #{heading} or its character count is missing"
    exit 1
  end

  declared_count, declared_limit = count_match.captures.map(&:to_i)
  if value.length != declared_count || declared_limit != field_limit || value.length > field_limit
    warn "public presence audit failed: #{heading} is #{value.length} characters, " \
         "but the draft declares #{declared_count} of #{declared_limit} (limit #{field_limit})"
    exit 1
  end
end

{"Description" => 4_000, "What To Test" => 4_000}.each do |heading, field_limit|
  value = metadata[/^## #{Regexp.escape(heading)}\n\n(.*?)(?=\n## |\z)/m, 1]&.strip

  unless value
    warn "public presence audit failed: #{heading} is missing"
    exit 1
  end

  if value.length > field_limit
    warn "public presence audit failed: #{heading} is #{value.length} characters (limit #{field_limit})"
    exit 1
  end
end

puts "public presence audit passed"
RUBY
