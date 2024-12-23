#!/bin/bash

# Path to the project mapping file
PROJECT_MAP_FILE="projects.mrun"

# Default values
PROJECT_ID=""
COMMAND=""
OS_TYPE=""
ACTION=""

# Function to display usage
usage() {
    echo -e "\nUsage: $0 -p <project_id> -c \"<command>\""
    echo -e "  -p  \tSpecify the unique project ID"
    echo -e "  -c  \tProvide the command to execute inside the selected project folder (enclosed in quotes)"
    echo -e "\nExample: $0 -p project_id -c \"npm install\""
    echo -e "\nUse the -h option for more information on how to use this script."
    exit 1
}

# Function to show help message
help_message() {
    echo -e "\nHelp: This script allows you to run commands inside specific project directories."
    echo -e "You can also list, add, remove, or update projects in your mapping file."
    echo -e "\nCommands:"
    echo -e "  -p <project_id>  \tSpecify the project ID (refer to the mapping file)"
    echo -e "  -c <command>     \tCommand to execute inside the selected project's directory"
    echo -e "\nAdditional Options:"
    echo -e "  -l               \tList all available project IDs from the mapping file."
    echo -e "  -d               \tList all available project IDs with their directories."
    echo -e "  -a               \tAdd a new project to the mapping file."
    echo -e "  -r               \tRemove a project from the mapping file."
    echo -e "  -u               \tUpdate a project's directory in the mapping file."
    echo -e "  -v               \tEnable verbose mode."
    echo -e "  -f               \tForce execution without certain validations."
    echo -e "  -h               \tShow this help message."
    exit 0
}

# Check if input is empty
check_empty_input() {
    if [[ -z "$1" ]]; then
        echo -e "\nError: Input cannot be empty!"
        exit 1
    fi
}

# Function to detect the OS type
detect_os() {
    case "$(uname)" in
        "Darwin")
            OS_TYPE="macOS"
            ;;
        "Linux")
            OS_TYPE="Linux"
            ;;
        "CYGWIN"|"MINGW"*|"MSYS")
            OS_TYPE="Windows"
            ;;
        *)
            OS_TYPE="Unknown"
            ;;
    esac
}

# Check if jq is installed
check_dependencies() {
    if ! command -v jq &> /dev/null; then
        echo -e "\nError: jq is required but not installed. Please install jq first."
        exit 1
    fi

    if [ "$OS_TYPE" == "Windows" ] && ! command -v realpath &> /dev/null; then
        echo -e "\nError: realpath is required on Windows but not found. Please install it first."
        exit 1
    fi
}

# Validate if the project ID exists in the mapping file
validate_project_id() {
    if [[ ! "$PROJECT_ID" =~ ^[a-zA-Z0-9_-]+$ ]]; then
        echo -e "\nError: Invalid project ID '$PROJECT_ID'. Only alphanumeric characters, hyphens, and underscores are allowed."
        exit 1
    fi
}

# Validate if the directory exists and if it's already assigned to another project
validate_directory_unique() {
    if [[ ! -d "$TARGET_DIR" ]]; then
        echo -e "\nError: Directory '$TARGET_DIR' not found!"
        exit 1
    fi

    # Check if the directory is already assigned to a project
    if jq -e "to_entries | .[] | select(.value == \"$TARGET_DIR\")" "$PROJECT_MAP_FILE" > /dev/null; then
        echo -e "\nError: The directory '$TARGET_DIR' is already assigned to another project!"
        exit 1
    fi
}

# Validate the command to ensure it doesn't contain dangerous characters using grep
sanitize_command() {
    if echo "$COMMAND" | grep -q '[;&|<>()\$]'; then
        echo -e "\nError: Command contains potentially dangerous characters (e.g., ; & | < >)."
        exit 1
    fi
    if echo "$COMMAND" | grep -q '[^a-zA-Z0-9\-\_\/\ \=]'; then
        echo -e "\nError: Command contains invalid characters."
        exit 1
    fi
}

# Validate if the mapping file exists and is accessible
validate_mapping_file() {
    if [[ ! -f "$PROJECT_MAP_FILE" ]]; then
        echo -e "\nError: Project mapping file '$PROJECT_MAP_FILE' not found or not accessible!"
        exit 1
    fi

    if ! jq -e . "$PROJECT_MAP_FILE" > /dev/null 2>&1; then
        echo -e "\nError: Invalid JSON format in '$PROJECT_MAP_FILE'."
        exit 1
    fi
}

# Validate if the project directory exists
validate_directory() {
    if [[ ! -d "$TARGET_DIR" ]]; then
        echo -e "\nError: Project directory '$TARGET_DIR' not found!"
        exit 1
    fi
}

# List all projects in the mapping file
list_projects() {
    if [[ ! -f "$PROJECT_MAP_FILE" ]]; then
        echo -e "\nError: Project mapping file '$PROJECT_MAP_FILE' not found or not accessible!"
        exit 1
    fi
    echo -e "\nHere are all the available projects in '$PROJECT_MAP_FILE':\n"
    jq -r 'keys[] | "* \(.)"' "$PROJECT_MAP_FILE"
}

# List all projects with their directories
list_projects_with_dirs() {
    if [[ ! -f "$PROJECT_MAP_FILE" ]]; then
        echo -e "\nError: Project mapping file '$PROJECT_MAP_FILE' not found or not accessible!"
        exit 1
    fi
    echo -e "\nHere are all the available projects with their directories in '$PROJECT_MAP_FILE':\n"
    jq -r 'to_entries | .[] | "* \(.key) -> \(.value)"' "$PROJECT_MAP_FILE"
}

# Helper function to normalize the directory path
normalize_directory_path() {
    # Ensure the path is relative to the current working directory
    if [[ "$1" == /* ]]; then
        # If the path starts with '/', make it relative to the root of the project
        echo "$1" | sed "s|^/||"
    else
        # Otherwise, it's already relative, so we just return it as-is
        echo "$1"
    fi
}

# Add a new project to the mapping file
add_project() {
    echo
    read -p "Enter the new project ID: " NEW_PROJECT_ID
    check_empty_input "$NEW_PROJECT_ID"
    read -p "Enter the directory for the new project: " NEW_PROJECT_DIR
    check_empty_input "$NEW_PROJECT_DIR"

    # Normalize the directory to be relative
    NEW_PROJECT_DIR=$(normalize_directory_path "$NEW_PROJECT_DIR")

    # Check if the directory exists
    if [[ ! -d "$NEW_PROJECT_DIR" ]]; then
        echo -e "\nError: Directory '$NEW_PROJECT_DIR' not found!"
        exit 1
    fi

    # Check if project ID already exists
    if jq -e ".\"$NEW_PROJECT_ID\"" "$PROJECT_MAP_FILE" > /dev/null; then
        echo -e "\nError: Project ID '$NEW_PROJECT_ID' already exists!"
        exit 1
    fi

    # Validate if the directory is already assigned
    if jq -e "to_entries | .[] | select(.value == \"$NEW_PROJECT_DIR\")" "$PROJECT_MAP_FILE" > /dev/null; then
        echo -e "\nError: Directory '$NEW_PROJECT_DIR' is already assigned to another project!"
        exit 1
    fi

    # Update the JSON file with the new project
    jq --arg id "$NEW_PROJECT_ID" --arg dir "$NEW_PROJECT_DIR" \
        '. + {($id): $dir}' "$PROJECT_MAP_FILE" > temp.json && mv temp.json "$PROJECT_MAP_FILE"
    echo -e "\nProject '$NEW_PROJECT_ID' added successfully."
}

# Remove a project from the mapping file
remove_project() {
    echo
    read -p "Enter the project ID to remove: " REMOVE_PROJECT_ID
    check_empty_input "$REMOVE_PROJECT_ID"

    # Check if the project exists
    if ! jq -e ".\"$REMOVE_PROJECT_ID\"" "$PROJECT_MAP_FILE" > /dev/null; then
        echo -e "\nError: Project ID '$REMOVE_PROJECT_ID' not found!"
        exit 1
    fi

    # Remove the project from the JSON file
    jq "del(.\"$REMOVE_PROJECT_ID\")" "$PROJECT_MAP_FILE" > temp.json && mv temp.json "$PROJECT_MAP_FILE"
    echo -e "\nProject '$REMOVE_PROJECT_ID' removed successfully."
}

# Update the directory of a project in the mapping file
update_project() {
    echo
    read -p "Enter the project ID to update: " UPDATE_PROJECT_ID
    check_empty_input "$UPDATE_PROJECT_ID"

    # Check if the project exists
    if ! jq -e ".\"$UPDATE_PROJECT_ID\"" "$PROJECT_MAP_FILE" > /dev/null; then
        echo -e "\nError: Project ID '$UPDATE_PROJECT_ID' not found!"
        exit 1
    fi

    # Prompt for new project ID (optional)
    read -p "Update project ID (leave blank if unchanged): " NEW_PROJECT_ID
    if [[ -n "$NEW_PROJECT_ID" ]]; then
        # Validate the new project ID
        if jq -e ".\"$NEW_PROJECT_ID\"" "$PROJECT_MAP_FILE" > /dev/null; then
            echo -e "\nError: Project ID '$NEW_PROJECT_ID' already exists!"
            exit 1
        fi

        # Update the project ID in the mapping file
        jq --arg old_id "$UPDATE_PROJECT_ID" --arg new_id "$NEW_PROJECT_ID" \
            'del(.[$old_id]) | .[$new_id] = .[$old_id]' "$PROJECT_MAP_FILE" > temp.json && mv temp.json "$PROJECT_MAP_FILE"
        echo -e "\nProject ID updated to '$NEW_PROJECT_ID'."
        UPDATE_PROJECT_ID="$NEW_PROJECT_ID"  # Set the new project ID
    fi

    # Prompt for new directory (optional)
    read -p "Update directory (leave blank if unchanged): " UPDATE_PROJECT_DIR
    if [[ -n "$UPDATE_PROJECT_DIR" ]]; then
        # Normalize the directory to be relative
        UPDATE_PROJECT_DIR=$(normalize_directory_path "$UPDATE_PROJECT_DIR")

        # Check if the new directory exists
        if [[ ! -d "$UPDATE_PROJECT_DIR" ]]; then
            echo -e "\nError: Directory '$UPDATE_PROJECT_DIR' not found!"
            exit 1
        fi

        # Check if the new directory is already assigned to another project
        if jq -e "to_entries | .[] | select(.value == \"$UPDATE_PROJECT_DIR\")" "$PROJECT_MAP_FILE" > /dev/null; then
            echo -e "\nError: Directory '$UPDATE_PROJECT_DIR' is already assigned to another project!"
            exit 1
        fi

        # Update the project's directory in the JSON file
        jq --arg id "$UPDATE_PROJECT_ID" --arg dir "$UPDATE_PROJECT_DIR" \
            '.[$id] = $dir' "$PROJECT_MAP_FILE" > temp.json && mv temp.json "$PROJECT_MAP_FILE"
        echo -e "\nDirectory updated to '$UPDATE_PROJECT_DIR'."
    fi

    if [[ -z "$NEW_PROJECT_ID" && -z "$UPDATE_PROJECT_DIR" ]]; then
        echo -e "\nNo changes were made. Nothing to update."
    else
        echo -e "\nProject '$UPDATE_PROJECT_ID' updated successfully."
    fi
}

check_no_projects_configured() {
    if [[ ! -s "$PROJECT_MAP_FILE" || "$(jq 'length' "$PROJECT_MAP_FILE")" -eq 0 ]]; then
        return 0
    else
        return 1
    fi
}

# Initialize $PROJECT_MAP_FILE file if not present
initialize_mapping_file() {
    if [[ -f "$PROJECT_MAP_FILE" ]]; then
        echo
        read -p "Looks like '$PROJECT_MAP_FILE' already exists. Do you want to reinitialize it and remove all project entries? [y/n]: " reinit_choice
        check_empty_input "$reinit_choice"
        if [[ "$reinit_choice" == "y" || "$reinit_choice" == "Y" ]]; then
            echo -e "{}" > "$PROJECT_MAP_FILE"
            echo -e "\n'$PROJECT_MAP_FILE' has been reinitialized."
            add_project
        else
            echo -e "\nSkipping reinitialization of '$PROJECT_MAP_FILE'."
        fi
    else
        echo -e "\n'$PROJECT_MAP_FILE' not found. Initializing it now..."
        echo -e "{}" > "$PROJECT_MAP_FILE"
        echo -e "\nNew '$PROJECT_MAP_FILE' file created."
        add_project
    fi
}

# Main script logic
if [[ "$1" == "init" ]]; then
    initialize_mapping_file
    exit 0
fi

if [[ ! -f "$PROJECT_MAP_FILE" ]]; then
    echo -e "\nLooks like you don't have any '$PROJECT_MAP_FILE' configured. Please run './mrun.sh init' first."
    exit 1
fi

if check_no_projects_configured; then
    echo -e "\nYou need to add at least one project in '$PROJECT_MAP_FILE'. Let's do that now.\n"
    add_project
fi

# Parse arguments
while getopts ":p:c:lhdaru:vf" opt; do
    case ${opt} in
        p)
            PROJECT_ID=$OPTARG
            ;;
        c)
            COMMAND=$OPTARG
            ;;
        l)
            list_projects
            exit 0
            ;;
        d)
            list_projects_with_dirs
            exit 0
            ;;
        a)
            ACTION="add"
            ;;
        r)
            ACTION="remove"
            ;;
        u)
            ACTION="update"
            ;;
        v)
            VERBOSE="true"
            ;;
        f)
            FORCE="true"
            ;;
        h)
            help_message
            ;;
        \?)
            usage
            ;;
    esac
done

# Check if both parameters are provided for running the command
if [[ -z "$PROJECT_ID" || -z "$COMMAND" ]] && [[ -z "$ACTION" ]]; then
    usage
fi

# Check if jq is installed
check_dependencies

# Validate the project ID format
if [[ -n "$PROJECT_ID" ]]; then
    validate_project_id
fi

# Check if the mapping file exists and is valid
validate_mapping_file

# Handle actions
if [[ "$ACTION" == "add" ]]; then
    add_project
    exit 0
elif [[ "$ACTION" == "remove" ]]; then
    remove_project
    exit 0
elif [[ "$ACTION" == "update" ]]; then
    update_project
    exit 0
fi

# Get the project directory from the mapping file using jq
if [[ -n "$PROJECT_ID" ]]; then
    PROJECT_DIR=$(jq -r ".\"$PROJECT_ID\"" "$PROJECT_MAP_FILE")

    # Check if the project ID exists in the mapping
    if [[ "$PROJECT_DIR" == "null" || -z "$PROJECT_DIR" ]]; then
        echo -e "\nError: Project ID '$PROJECT_ID' not found in the mapping!\n"
        exit 1
    fi
fi

# Resolve the absolute path to the project directory
TARGET_DIR=""
if [[ "$OS_TYPE" == "Windows" ]]; then
    TARGET_DIR=$(cygpath -w "$PROJECT_DIR")
else
    TARGET_DIR=$(realpath "$PROJECT_DIR")
fi

# Validate if the resolved directory exists
validate_directory

# Function to ensure safe execution of commands in the target directory
run_command() {
    echo -e "\nRunning command '$COMMAND' in $PROJECT_ID -> $TARGET_DIR\n"
    cd "$TARGET_DIR" && eval "$COMMAND"

    # Handle verbosity
    if [[ "$VERBOSE" == "true" ]]; then
        echo -e "\nCommand '$COMMAND' executed successfully!"
    fi

    # Capture the exit status of the command
    EXIT_STATUS=$?

    if [[ $EXIT_STATUS -ne 0 ]]; then
        echo -e "\nError: Command '$COMMAND' failed with status code $EXIT_STATUS."
        exit $EXIT_STATUS
    fi
}

# Sanitize and validate the command
sanitize_command

# Run the command in the target directory
run_command
