#!/bin/bash

# Create the work file next to its destination so the final rename cannot cross
# filesystems. If a live config already exists, retain its ownership and mode;
# otherwise inherit them from the image template.
create_hawkbit_config_work_file() {
  local destination="$1"
  local template="$2"
  local destination_dir
  local destination_name
  local work_file

  destination_dir=$(dirname "$destination")
  destination_name=$(basename "$destination")
  work_file=$(mktemp "${destination_dir}/.${destination_name}.XXXXXX") || return 1

  if [ -e "$destination" ]; then
    if ! cp -p "$destination" "$work_file" || ! cp "$template" "$work_file"; then
      rm -f "$work_file"
      return 1
    fi
  elif ! cp -p "$template" "$work_file"; then
    rm -f "$work_file"
    return 1
  fi

  printf '%s\n' "$work_file"
}

publish_hawkbit_config() {
  local work_file="$1"
  local destination="$2"

  if grep -Eq '__[A-Z0-9_]+__' "$work_file"; then
    echo "ERROR: refusing to publish Hawkbit config with unresolved placeholders" >&2
    return 1
  fi

  # create_hawkbit_config_work_file guarantees both paths share a directory and
  # therefore a filesystem. mv consequently publishes one complete inode.
  mv -f "$work_file" "$destination"
}
