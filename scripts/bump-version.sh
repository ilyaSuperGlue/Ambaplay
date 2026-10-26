#!/bin/sh
# Bump Ambaplay's version in dylib/version.h before a release.
#
#   scripts/bump-version.sh patch|minor|major|set X.Y.Z [--upstream "NotProton X.Y.Z"] [--highest-build N] [--named X.Y.Z]
#
# Almost always patch (fixes, features, upstream merges); minor and major are rare, see
# docs/RELEASING.md. set picks any X.Y.Z above the committed one (0.7.3 -> 0.7.31). AMBAPLAY_BUILD goes up by one every time, since Sparkle orders updates by it.
# --upstream records the NotProton release this build is based on (NOTPROTON_VERSION);
# a clean upstream merge already brings upstream's value, so it is rarely needed.
# --highest-build N (or AMBAPLAY_HIGHEST_BUILD) is the highest build ever published, stable or
# beta. The new build is one above the larger of N and the committed build, so the stable that
# ships a beta outranks every beta. --named X.Y.Z is the release that beta was named after: the
# bump fails unless it lands exactly there.
# The committed version is always a plain X.Y.Z; a beta label is stamped at build time
# (scripts/stamp-beta.sh) and never committed.
# Edits the file only; commit it yourself. See docs/RELEASING.md.

set -eu

repo=$(cd "$(dirname "$0")/.." && pwd)
header=$repo/dylib/version.h
# shellcheck source=/dev/null
. "$repo/scripts/version-lib.sh"

usage() {
	sed -n '4p' "$0" | sed 's/^# \{0,1\}//' >&2
	exit 1
}

part=${1:-}
target=""
case "$part" in
	patch|minor|major) shift ;;
	set)
		[ $# -ge 2 ] || usage
		is_semver "$2" || { echo "==> set wants X.Y.Z, got '$2'" >&2; exit 1; }
		target=$2
		shift 2
		;;
	*) usage ;;
esac

upstream=""
highest=${AMBAPLAY_HIGHEST_BUILD:-}
named=""
while [ $# -gt 0 ]; do
	case "$1" in
		--upstream)
			[ $# -ge 2 ] || usage
			upstream=${2#NotProton }
			shift 2
			;;
		--highest-build)
			[ $# -ge 2 ] || usage
			is_posint "$2" || { echo "==> --highest-build wants a positive integer, got '$2'" >&2; exit 1; }
			highest=$2
			shift 2
			;;
		--named)
			[ $# -ge 2 ] || usage
			is_semver "$2" || { echo "==> --named wants X.Y.Z, got '$2'" >&2; exit 1; }
			named=$2
			shift 2
			;;
		*) usage ;;
	esac
done

die() { echo "==> $*" >&2; exit 1; }

version=$(header_string "$header" AMBAPLAY_VERSION)
build=$(header_number "$header" AMBAPLAY_BUILD)
based=$(header_string "$header" NOTPROTON_VERSION)
is_semver "$version" || die "AMBAPLAY_VERSION '$version' in $header is not X.Y.Z; a beta label is stamped at build time, never committed"
[ -n "$build" ] || die "no numeric AMBAPLAY_BUILD in $header"
[ -n "$based" ] || die "no NOTPROTON_VERSION in $header"
if [ -n "$upstream" ]; then
	echo "$upstream" | grep -Eq '^[0-9]+(\.[0-9]+)*$' || die "--upstream wants 'NotProton X.Y.Z', got '$upstream'"
fi
if [ -n "$highest" ]; then
	is_posint "$highest" || die "--highest-build wants a positive integer, got '$highest'"
fi

if [ -n "$target" ]; then
	semver_gt "$target" "$version" || die "set $target is not above the committed $version"
	next=$target
else
	next=$(semver_next "$part" "$version")
fi
[ -z "$named" ] || [ "$named" = "$next" ] \
	|| die "a $part bump of $version gives $next, not $named, the release the beta was named after; pick the matching part"
base_build=$build
if [ -n "$highest" ] && [ "$highest" -gt "$base_build" ]; then
	base_build=$highest
fi
next_build=$((base_build + 1))
next_based=${upstream:-$based}

# Written through a temporary file so the same edit works with BSD and GNU sed.
tmp=$header.tmp.$$
trap 'rm -f "$tmp"' EXIT
sed \
	-e "s/^#define AMBAPLAY_VERSION \".*\"$/#define AMBAPLAY_VERSION \"$next\"/" \
	-e "s/^#define AMBAPLAY_BUILD [0-9][0-9]*$/#define AMBAPLAY_BUILD $next_build/" \
	-e "s/^#define NOTPROTON_VERSION \".*\"$/#define NOTPROTON_VERSION \"$next_based\"/" \
	"$header" >"$tmp"
cat "$tmp" >"$header"

echo "==> Ambaplay $version ($build) -> $next ($next_build), based on NotProton $next_based"
