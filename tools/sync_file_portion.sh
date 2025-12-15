####
# Synchronise changes on a portion of a text file with portions of a list of other text files and push those files via git. 
# This can be used when changing a portion in the master build script to cascade the changes to build scripts in various app folders.
#
# Usage: ./sync_file_portion.sh -s "/path/to/source_file" -d "/path/to/destination_files_list"
# Arguments:
#   -s : source file
#   -d : destination files list (1 path per line)
####

# Handle arguments
usage() {
        echo "Usage: ./sync_file_portion.sh \"/path/to/source_file\" \"/path/to/destination_files_list\""
        echo " 'destination_files_list' must be a file containing 1 path per line."
}

if [[ -z $1 ]] || [[ -z $2 ]]; then 
    echo -e "Exiting: missing parameter\n"
    usage
    exit;
else
    source_file="$1"
    destination_files_list="$2"
fi

# Define target git branch
target_git_branch="testing"

# Get source git comment
source_folder="${source_file%/*}"
pushd $source_folder
    source_git_comment=$(git show -s --format=%s)
popd

# Loop across lines of the destinations list
while read destination_file; do
    echo "Processing \"$destination_file\"..."
    
    destination_folder="${destination_file%/*}"
    pushd $destination_folder
    
        git checkout "$target_git_branch"
        
        # Skip the current loop if the branch has unmerged modifications
	if [ -n "$(git diff)" ] || [ -n "$(git diff --staged)" ]; then 
            echo "Skipping \"$destination_file\" because $target_git_branch branch contains unmerged commits. Please merge them to remote branch or remove them first."
            continue
        fi
        
	# Skip the current loop if the branch has unmerged untracked files or folders
	if [ -n "$(git ls-files . --exclude-standard --others)" ] || [ -n "$(git ls-files . --exclude-standard --others --directory)" ]; then 
            echo "Skipping \"$destination_file\" because $target_git_branch branch contains unmerged untracked files or folders. Please merge them to remote branch or remove them first."
            continue
        fi

	git fetch #forge authentication may be required at this point
	if [ $? -ne 0 ]; then 
            echo "Exiting... You must authenticate to allow remote git operationss."
	    exit 1
       	fi
	
	if [ -n "$(git log @{u}..HEAD)" ]; then #show commits that are on local branch but not on the remote branch 
            echo "Skipping \"$destination_file\" because $target_git_branch branch already contains local commits not yet pushed to remote branch. Please push them or remove them first."
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
        sed -ie "/$start/,/$end/{
            /$start/{p; r /tmp/source_new_extract.tmp
            }; /$end/p; d }" "$destination_file"

        # Clean temp file
        rm /tmp/source_new_extract.tmp
        
        # Git commit & push
        git add "$destination_file"
        git commit -m "$source_git_comment"
        git push

    popd
    
done <"$destination_files_list"
