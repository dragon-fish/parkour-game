# Shared by every hook here: run git-lfs's own hook first, exactly as the
# hooks it installed into .git/hooks used to. Pointing core.hooksPath at a
# tracked directory REPLACES those, so anything they did must be done here
# or Git LFS quietly stops smudging and stops uploading objects.
run_lfs() {
	hook=$1
	shift
	if ! command -v git-lfs >/dev/null 2>&1; then
		printf >&2 "\n%s\n\n" "This repository is configured for Git LFS but 'git-lfs' was not found on your path."
		exit 2
	fi
	git lfs "$hook" "$@" || exit $?
}
