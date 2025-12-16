####
# Synchronise changes on a portion of a text file with portions of a list of other text files and push those files via git.
# This can be used when changing a portion in the master build script to cascade the changes to build scripts in various app folders.
#
# Usage: ./sync_file_portion.sh -s "/path/to/source_file" -d "/path/to/destination_files_list" "Git comment text" "target_git_branch"
#
#   - 'destination_file_list' must be a file containing 1 path per line.
#   - 'Git comment text' is optional (text from the last commit of the source file's repo is the fallback option).
#   - 'target_git_branch' fallback to 'testing'
#   - You can use full paths or paths relative to the current folder of the terminal.
####

usage() {
    echo "Usage: ./sync_file_portion.sh \"/path/to/source_file\" \"/path/to/destination_files_list\" \"Git comment text\" \"target_git_branch\""
    echo ""
    echo "  - 'destination_files_list' must be a file containing 1 path per line."
    echo "  - 'Git comment text' is optional (text from the last commit of the source file's repo is the fallback option)."
    echo "  - 'target_git_branch' fallback to 'testing'"
    echo "  - You can use full paths or paths relative to the current folder of the terminal."

}

# Hide pushd/popd output in standard output
pushd () {
    command pushd "$@" > /dev/null
}
popd () {
    command popd "$@" > /dev/null
}

# Handle mandatory arguments
if [[ -z $1 ]] || [[ -z $2 ]]; then
    echo -e "Exiting: missing parameter\n"
    usage
    exit;
else
    source_file="$(echo "$(cd -- "$(dirname -- "$1")"; pwd)/$(basename -- "$1")")" #supports full or relative path, cf. https://stackoverflow.com/questions/4175264/how-to-retrieve-absolute-path-given-relative#answer-31605674
    destination_files_list="$(echo "$(cd -- "$(dirname -- "$2")"; pwd)/$(basename -- "$2")")"
fi

# Get source git comment
source_folder="${source_file%/*}"
if [[ -n $3 ]]; then
    source_git_comment="$3"
else
    pushd $source_folder
        source_git_comment=$(git show -s --format=%s)
    popd
fi

# Define target git branch
if [[ -z $4 ]]; then
    target_git_branch=testing
else
    target_git_branch="$4"
fi

# Loop across lines of the destinations list (skips line starting with #)
grep -v '^#' "$destination_files_list" | while read destination_file; do
    echo -e "\n-----------------------------"
    echo "Processing \"$destination_file\"..."

    destination_folder="${destination_file%/*}"
    pushd $destination_folder

        # Skip the current loop is the branch does not exist
        if ! git show-ref --quiet "refs/heads/$target_git_branch"; then
            echo "Skipping \"$destination_file\" because $target_git_branch does not exist locally. Please pull this branch or select another one."
            echo "$(git branch)"
            continue
        fi

        git checkout "$target_git_branch"

        # Skip the current loop if the branch has unmerged modifications
        if [ -n "$(git diff)" ] || [ -n "$(git diff --staged)" ]; then
            echo "Skipping \"$destination_file\" because $target_git_branch branch contains unmerged commits. Please merge them to remote branch or remove them first."
            echo "$(git diff --name-only)"
            echo -e "$(git diff --staged --name-only)\n"
            continue
        fi

        # Skip the current loop if the branch has unmerged untracked files or folders
        if [ -n "$(git ls-files . --exclude-standard --others)" ] || [ -n "$(git ls-files . --exclude-standard --others --directory)" ]; then
            echo "Skipping \"$destination_file\" because $target_git_branch branch contains unmerged untracked files or folders. Please merge them to remote branch or remove them first."
            echo "$(git ls-files . --exclude-standard --others)"
            echo -e "$(git ls-files . --exclude-standard --others --directory)\n"
            continue
        fi

        git fetch #forge authentication may be required at this point
        if [ $? -ne 0 ]; then
            echo "Exiting... You must authenticate to allow remote git operationss."
            exit 1
        fi

        if [ -n "$(git log @{u}..HEAD)" ]; then #show commits that are on local branch but not on the remote branch
            echo "Skipping \"$destination_file\" because $target_git_branch branch already contains local commits not yet pushed to remote branch. Please push them or remove them first."
            echo -e "$(git log @{u}..HEAD)\n"
            continue
        fi

        git pull
        git rebase

        # Markers of the portion
        start='^# YOU SHOULD NOT NEED TO EDIT WHAT FOLLOWS$'
        end='\%$' #(end of file)

        # Extract section from source file to temp file
        sed -n "/$start/,/$end/p" "$source_file" > /tmp/source_new_extract.tmp

        # Replace section in destination file with the one in the temp file
        sed -i -e "/$start/,/$end/{
            /$start/{r /tmp/source_new_extract.tmp
            }; /$end/p; d }" "$destination_file"

        # Clean temp file
        rm /tmp/source_new_extract.tmp

        # Git commit & push
        git add "$destination_file"
        git commit -m "$source_git_comment"
        git push

        echo "File processed!"
    popd

done
