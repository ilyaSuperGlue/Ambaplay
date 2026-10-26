#!/bin/sh
# ci-run-passed.sh <owner/repo> <sha>: exit 0 when the app workflow has a run on that commit
# whose build and check jobs both ran and succeeded. A docs-only run is green too, with
# those jobs skipped, so the run's own conclusion proves nothing about the sources.
# The job names are the `name:` of the jobs in .github/workflows/app.yml.
[ $# -eq 2 ] || { echo "usage: ci-run-passed.sh <owner/repo> <sha>" >&2; exit 2; }
build_job=${AMBAPLAY_CI_BUILD_JOB:-full app build}
checks_job=${AMBAPLAY_CI_CHECKS_JOB:-source checks}

command -v gh >/dev/null 2>&1 || exit 1
ids=$(gh run list -R "$1" -w app --commit "$2" --status success --limit 20 \
	--json databaseId -q '.[].databaseId' 2>/dev/null) || exit 1
for id in $ids; do
	gh run view "$id" -R "$1" --json jobs -q '.jobs[] | [.name, .conclusion] | @tsv' 2>/dev/null |
		awk -F '\t' -v b="$build_job" -v c="$checks_job" '
			$1 == b && $2 == "success" { nb++ }
			$1 == c && $2 == "success" { nc++ }
			END { exit !(nb == 1 && nc == 1) }' && exit 0
done
exit 1
