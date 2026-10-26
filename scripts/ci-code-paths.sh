#!/bin/sh
# Read changed paths on stdin, one per line, and print those that are not docs.
# What counts as docs comes from .github/docs-only-paths (AMBAPLAY_DOCS_ONLY_FILE
# points at another list). A missing list is an error, so no path is skipped by accident.
patterns=${AMBAPLAY_DOCS_ONLY_FILE:-$(dirname "$0")/../.github/docs-only-paths}
[ -f "$patterns" ] || { echo "ci-code-paths: $patterns not found" >&2; exit 2; }

while IFS= read -r path || [ -n "$path" ]; do
	[ -n "$path" ] || continue
	docs=0
	while IFS= read -r pattern || [ -n "$pattern" ]; do
		case $pattern in '' | '#'*) continue ;; esac
		# shellcheck disable=SC2254 # the pattern is data from the list, not a literal
		case $path in $pattern) docs=1; break ;; esac
	done <"$patterns"
	[ "$docs" -eq 1 ] || printf '%s\n' "$path"
done
