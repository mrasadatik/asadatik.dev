#!/bin/bash

PROJECT_MAP_FILE="projects.mrun"

PROJECT_ID=""
COMMAND=""
OS_TYPE=""
ACTION=""

usage() {
    echo -e "\nUsage: $0 -p <project_id> -c \"<command>\""
    echo -e "  -p  \tSpecify the unique project ID"
    echo -e "  -c  \tProvide the command to execute inside the selected project folder (enclosed in quotes)"
    echo -e "\nExample: $0 -p project_id -c \"npm install\""
    echo -e "\nUse the -h option for more information on how to use this script."
    exit 1
}

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
    echo -e "  -h               \tShow this help message."
    exit 0
}

log_message() {
    MESSAGE="$1"
    LOG_TO_FILE=$2
    LOG_TO_CLI=$3
    NEWLINE=$4

    LOGGING_FILE="mrun.log"

    if [[ $NEWLINE == true ]]; then
        echo ""
    fi

    FORMATTED_MESSAGE="[$(date)] - $MESSAGE"

    if [[ "$LOG_TO_CLI" == true ]]; then
        echo -e "$FORMATTED_MESSAGE"
    fi

    if [[ "$LOG_TO_FILE" == true ]]; then
        echo -e "$FORMATTED_MESSAGE" >> "$LOGGING_FILE"
    fi
}

check_empty_input() {
    USER_INPUT_TO_CHECK="$1"

    if [[ -z "$USER_INPUT_TO_CHECK" ]]; then
        log_message "Error: Input cannot be empty!" true true false
        exit 1
    fi
}

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

check_dependencies() {
    DETECTED_OS_TYPE="$1"

    if ! command -v jq &> /dev/null; then
        log_message "Error: jq is required but not installed. Please install jq first." true true false
        exit 1
    fi

    if [ "$DETECTED_OS_TYPE" == "Windows" ] && ! command -v realpath &> /dev/null; then
        log_message "Error: realpath is required but not installed. Please install realpath first." true true false
        exit 1
    fi
}

validate_project_id() {
    PROJECT_ID_TO_VALIDATE="$1"

    if [[ ! "$PROJECT_ID_TO_VALIDATE" =~ ^[a-zA-Z0-9_-]+$ ]]; then
        log_message "Error: Invalid project ID '$1'. Only alphanumeric characters, hyphens, and underscores are allowed." true true false
        exit 1
    fi
}

validate_directory() {
    PROJECT_DIR_TO_VALIDATE="$1"

    if [[ ! -d "$PROJECT_DIR_TO_VALIDATE" ]]; then
        log_message "Error: Project directory '$1' not found!" true true false
        exit 1
    fi
}

validate_directory_unique() {
    PROJECT_MAPPING_FILE="$1"
    PROJECT_DIR_TO_VALIDATE="$2"

    validate_directory "$PROJECT_DIR_TO_VALIDATE"

    if jq -e "to_entries | .[] | select(.value == \"$PROJECT_DIR_TO_VALIDATE\")" "$PROJECT_MAPPING_FILE" > /dev/null; then
        log_message "Error: The directory '$PROJECT_DIR_TO_VALIDATE' is already assigned to another project!" true true false
        exit 1
    fi
}

validate_project_id_unique() {
    PROJECT_MAPPING_FILE="$1"
    PROJECT_ID_TO_VALIDATE="$2"

    validate_project_id "$PROJECT_ID_TO_VALIDATE"

    if jq -e ".\"$PROJECT_ID_TO_VALIDATE\"" "$PROJECT_MAPPING_FILE" > /dev/null; then
        log_message "Error: Project ID '$PROJECT_ID_TO_VALIDATE' already exists!" true true false
        exit 1
    fi
}

sanitize_command() {
    COMMAND_TO_SANITIZE="$1"

    if echo "$COMMAND_TO_SANITIZE" | grep -q '[;&|<>()\$]'; then
        log_message "Error: Command contains potentially dangerous characters (e.g., ; & | < >)." true true false
        exit 1
    fi
    if echo "$COMMAND_TO_SANITIZE" | grep -q '[^a-zA-Z0-9\-\_\/\ \=]'; then
        log_message "Error: Command contains invalid characters." true true false
        exit 1
    fi
}

validate_mapping_file() {
    PROJECT_MAPPING_FILE="$1"

    if [[ ! -f "$PROJECT_MAPPING_FILE" ]]; then
        log_message "Info: Looks like you don't have any '$PROJECT_MAPPING_FILE' configured. Please run './mrun.sh init' first." true true false
        exit 1
    fi

    if ! jq -e . "$PROJECT_MAPPING_FILE" > /dev/null 2>&1; then
        log_message "Error: Invalid JSON format in '$PROJECT_MAPPING_FILE'. Please re-configure '$PROJECT_MAPPING_FILE' first." true true false
        exit 1
    fi
}

normalize_directory_path() {
    PATH_TO_CHECK="$1"

    if [[ "$PATH_TO_CHECK" == /* ]]; then
        echo "$PATH_TO_CHECK" | sed "s|^/||"
    else
        echo "$PATH_TO_CHECK"
    fi
}

project_file_entries_action() {
    PROJECT_MAPPING_FILE="$1"
    FILE_ACTION="$2"

    if [[ $FILE_ACTION == "create" ]]; then
        # $3 -> NEW_PROJECT_ID
        # $4 -> NEW_PROJECT_DIR
        jq --arg id "$3" --arg dir "$4" \
        '. + {($id): $dir}' "$PROJECT_MAPPING_FILE" > temp.mrun.json && mv temp.mrun.json "$PROJECT_MAPPING_FILE"
    elif [[ $FILE_ACTION == "read" ]]; then
        # $3 -> WITH_DIR_ACTION
        if [[ $3 == "all" ]]; then
            jq -r 'to_entries | .[] | "* \(.key) -> \(.value)"' "$PROJECT_MAPPING_FILE"
        else
            jq -r 'keys[] | "* \(.)"' "$PROJECT_MAPPING_FILE"
        fi
    elif [[ $FILE_ACTION == "update" ]]; then
        # $3 -> UPDATE_FIELD_TYPE
        if [[ $3 == "id" ]]; then
            # $4 -> OLD_PROJECT_ID
            # $5 -> NEW_PROJECT_ID
            jq --arg old_id "$4" --arg new_id "$5" \
                'if .[$old_id] then .[$new_id] = .[$old_id] | del(.[$old_id]) else . end' "$PROJECT_MAPPING_FILE" > temp.json && mv temp.json "$PROJECT_MAPPING_FILE"
        elif [[ $3 == "dir" ]]; then
            # $4 -> PROJECT_ID
            # $5 -> NEW_PROJECT_DIR
            jq --arg id "$4" --arg dir "$5" \
                '.[$id] = $dir' "$PROJECT_MAPPING_FILE" > temp.mrun.json && mv temp.mrun.json "$PROJECT_MAPPING_FILE"
        fi
    elif [[ $FILE_ACTION == "delete" ]]; then
        # $3 -> PROJECT_ID_TO_DELETE
        jq "del(.\"$3\")" "$PROJECT_MAPPING_FILE" > temp.mrun.json && mv temp.mrun.json "$PROJECT_MAPPING_FILE"
    fi
}

create_project() {
    PROJECT_MAPPING_FILE="$1"

    read -p "Enter the new project ID: " NEW_PROJECT_ID
    check_empty_input "$NEW_PROJECT_ID"

    validate_project_id_unique "$PROJECT_MAPPING_FILE" "$NEW_PROJECT_ID"

    read -p "Enter the directory for the new project: " NEW_PROJECT_DIR
    check_empty_input "$NEW_PROJECT_DIR"

    NEW_PROJECT_DIR=$(normalize_directory_path "$NEW_PROJECT_DIR")

    validate_directory_unique "$PROJECT_MAPPING_FILE" "$NEW_PROJECT_DIR"

    project_file_entries_action "$PROJECT_MAPPING_FILE" "create" "$NEW_PROJECT_ID" "$NEW_PROJECT_DIR"
    log_message "Info: Project '$NEW_PROJECT_ID' added successfully." true true false
}

read_projects() {
    PROJECT_MAPPING_FILE="$1"

    echo -e "Here are all the available projects in '$PROJECT_MAPPING_FILE':"
    project_file_entries_action $PROJECT_MAPPING_FILE "read"
}

read_projects_with_dirs() {
    PROJECT_MAPPING_FILE="$1"

    echo -e "Here are all the available projects with their directories in '$PROJECT_MAPPING_FILE':"
    project_file_entries_action "$PROJECT_MAPPING_FILE" "read" "all"
}

update_project() {
    PROJECT_MAPPING_FILE="$1"

    read -p "Enter the project ID to update: " UPDATE_PROJECT_ID
    check_empty_input "$UPDATE_PROJECT_ID"

    if ! jq -e ".\"$UPDATE_PROJECT_ID\"" "$PROJECT_MAPPING_FILE" > /dev/null; then
        log_message "Error: Project ID '$UPDATE_PROJECT_ID' not found!" true true false
        exit 1
    fi

    read -p "Update project ID (leave blank if unchanged): " NEW_PROJECT_ID
    if [[ -n "$NEW_PROJECT_ID" ]]; then
        validate_project_id_unique "$PROJECT_MAPPING_FILE" "$NEW_PROJECT_ID"

        project_file_entries_action "$PROJECT_MAPPING_FILE" "update" "id" "$UPDATE_PROJECT_ID" "$NEW_PROJECT_ID"
        log_message "Info: Project ID '$UPDATE_PROJECT_ID' updated to '$NEW_PROJECT_ID'." true false false
        UPDATE_PROJECT_ID="$NEW_PROJECT_ID"
    fi

    read -p "Update directory (leave blank if unchanged): " UPDATE_PROJECT_DIR
    if [[ -n "$UPDATE_PROJECT_DIR" ]]; then
        UPDATE_PROJECT_DIR=$(normalize_directory_path "$UPDATE_PROJECT_DIR")

        validate_directory_unique "$PROJECT_MAPPING_FILE" "$UPDATE_PROJECT_DIR"

        project_file_entries_action "$PROJECT_MAPPING_FILE" "update" "dir" "$UPDATE_PROJECT_ID" "$UPDATE_PROJECT_DIR"

        log_message "Info: Directory of project ID '$UPDATE_PROJECT_ID' updated to '$UPDATE_PROJECT_DIR'." true false false
    fi

    if [[ -z "$NEW_PROJECT_ID" && -z "$UPDATE_PROJECT_DIR" ]]; then
        log_message "Info: No changes were made. Nothing to update." false true false
    else
        log_message "Info: Updated successfully." false true false
    fi
}

delete_project() {
    PROJECT_MAPPING_FILE="$1"

    read -p "Enter the project ID to delete: " DELETE_PROJECT_ID
    check_empty_input "$DELETE_PROJECT_ID"

    if ! jq -e ".\"$DELETE_PROJECT_ID\"" "$PROJECT_MAPPING_FILE" > /dev/null; then
        log_message "Error: Project ID '$DELETE_PROJECT_ID' not found!" true true false
        exit 1
    fi

    project_file_entries_action $PROJECT_MAPPING_FILE "delete" "$DELETE_PROJECT_ID"
    log_message "Info: Project ID '$DELETE_PROJECT_ID' deleted successfully." true true false
}

check_no_projects_configured() {
    PROJECT_MAPPING_FILE="$1"

    if [[ ! -s "$PROJECT_MAPPING_FILE" || "$(jq 'length' "$PROJECT_MAPPING_FILE")" -eq 0 ]]; then
        log_message "Info: You need to add at least one project in '$PROJECT_MAPPING_FILE'. Let's do that now." false true false
        if [[ ! -s "$PROJECT_MAPPING_FILE" || ! $(jq empty "$PROJECT_MAPPING_FILE" 2>/dev/null) ]]; then
            echo "{}" > "$PROJECT_MAPPING_FILE"
        fi
        create_project "$PROJECT_MAPPING_FILE"
    fi
}

run_command() {
    PROJECT_MAPPING_FILE="$1"
    TYPE_OS="$2"
    COMMAND_TO_RUN="$3"
    TARGETED_PROJECT_ID="$4"
    ITS_DIR="$5"

    if [[ -n "$TARGETED_PROJECT_ID" ]]; then
        ITS_DIR=$(jq -r ".\"$TARGETED_PROJECT_ID\"" "$PROJECT_MAPPING_FILE")

        if [[ "$ITS_DIR" == "null" || -z "$ITS_DIR" ]]; then
            log_message "Error: Project ID '$TARGETED_PROJECT_ID' not found in the mapping!" true true false
            exit 1
        fi
    fi

    ITS_DIR_PATH=""
    if [[ "$TYPE_OS" == "Windows" ]]; then
        ITS_DIR_PATH=$(cygpath -w "$ITS_DIR")
    else
        ITS_DIR_PATH=$(realpath "$ITS_DIR")
    fi

    validate_directory "$ITS_DIR_PATH"

    log_message "Info: Running command '$COMMAND_TO_RUN' in $TARGETED_PROJECT_ID -> $ITS_DIR" true true false
    cd "$ITS_DIR" && eval "$COMMAND_TO_RUN"

    EXIT_STATUS=$?

    if [[ $EXIT_STATUS -ne 0 ]]; then
        log_message "Error: Command '$COMMAND_TO_RUN' failed with status code $EXIT_STATUS." true true false
        exit $EXIT_STATUS
    fi
}

initialize_mapping_file() {
    PROJECT_MAPPING_FILE="$1"

    if [[ -f "$PROJECT_MAPPING_FILE" ]]; then
        read -p "Looks like '$PROJECT_MAPPING_FILE' already exists. Do you want to reinitialize it and remove all project entries? [y/n]: " reinit_choice
        check_empty_input "$reinit_choice"
        if [[ "$reinit_choice" == "y" || "$reinit_choice" == "Y" ]]; then
            echo -e "{}" > "$PROJECT_MAPPING_FILE"
            log_message "Info: '$PROJECT_MAPPING_FILE' has been reinitialized." true true false
            create_project "$PROJECT_MAPPING_FILE"
        else
            log_message "Info: Skipping reinitialization of '$PROJECT_MAPPING_FILE'." false true false
        fi
    else
        log_message "Info: '$PROJECT_MAPPING_FILE' not found. Initializing it now..." false true false
        echo -e "{}" > "$PROJECT_MAPPING_FILE"
        log_message "Info: New '$PROJECT_MAPPING_FILE' file created." true true false
        create_project "$PROJECT_MAPPING_FILE"
    fi
}

detect_os

check_dependencies "$OS_TYPE"

if [[ "$1" == "init" ]]; then
    initialize_mapping_file "$PROJECT_MAP_FILE"
    exit 0
fi

validate_mapping_file "$PROJECT_MAP_FILE"

check_no_projects_configured "$PROJECT_MAP_FILE"

while getopts ":p:c:lhdaru" opt; do
    case ${opt} in
        p)
            validate_project_id "$OPTARG"
            PROJECT_ID=$OPTARG
            ;;
        c)
            sanitize_command "$OPTARG"
            COMMAND=$OPTARG
            ;;
        a)
            ACTION="create"
            ;;
        l)
            read_projects "$PROJECT_MAP_FILE"
            exit 0
            ;;
        d)
            read_projects_with_dirs "$PROJECT_MAP_FILE"
            exit 0
            ;;
        u)
            ACTION="update"
            ;;
        r)
            ACTION="delete"
            ;;
        h)
            help_message
            ;;
        \?)
            usage
            ;;
    esac
done

if [[ -z "$PROJECT_ID" || -z "$COMMAND" ]] && [[ -z "$ACTION" ]]; then
    usage
fi

if [[ "$ACTION" == "create" ]]; then
    create_project $PROJECT_MAP_FILE
    exit 0
elif [[ "$ACTION" == "delete" ]]; then
    delete_project $PROJECT_MAP_FILE
    exit 0
elif [[ "$ACTION" == "update" ]]; then
    update_project $PROJECT_MAP_FILE
    exit 0
fi

run_command $PROJECT_MAP_FILE $OS_TYPE $COMMAND $PROJECT_ID $TARGET_DIR
