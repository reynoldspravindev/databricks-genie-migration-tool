#!/bin/bash

# ============================================================================
# Genie Space Migration Tool - Shell Script
# ============================================================================
# This script migrates a Genie space from one Databricks workspace to another.
# Cloud agnostic - works with Azure, AWS, and GCP Databricks.
# Supports both PAT and Service Principal authentication.
# ============================================================================
# Usage:
#   ./migrate-genie-space.sh [config_file.json]
#
# Example:
#   ./migrate-genie-space.sh config.json
# ============================================================================

set -e  # Exit on error

# ==================== CONFIGURATION ====================

# Default configuration (will be overridden by config file if provided)

# Source Workspace Configuration
SOURCE_WORKSPACE_URL=""  # Example: "https://adb-1234567890.7.azuredatabricks.net"
SOURCE_GENIE_SPACE_ID=""  # Example: "01ef1234567890abcdef1234567890ab"
SOURCE_AUTH_TYPE="PAT"  # Options: "PAT" or "SERVICE_PRINCIPAL"
SOURCE_PAT=""  # Example: "dapi1234567890abcdef1234567890ab"
SOURCE_SP_CLIENT_ID=""  # Example: "12345678-1234-1234-1234-123456789012"
SOURCE_SP_CLIENT_SECRET=""

# Target Workspace Configuration
TARGET_WORKSPACE_URL=""  # Example: "https://dbc-abcdef12-3456.cloud.databricks.com"
TARGET_AUTH_TYPE="PAT"  # Options: "PAT" or "SERVICE_PRINCIPAL"
TARGET_PAT=""  # Example: "dapi1234567890abcdef1234567890ab"
TARGET_SP_CLIENT_ID=""  # Example: "12345678-1234-1234-1234-123456789012"
TARGET_SP_CLIENT_SECRET=""

# REQUIRED: Target SQL Warehouse ID (different from source workspace)
TARGET_SQL_WAREHOUSE_ID=""  # Example: "abc123def456"

# Optional: Override title and description
TARGET_TITLE_OVERRIDE=""  # Set to override, or empty to keep original
TARGET_DESCRIPTION_OVERRIDE=""  # Set to override, or empty to keep original

# Action: "CREATE" or "UPDATE"
ACTION="CREATE"
EXISTING_TARGET_SPACE_ID=""  # Required if ACTION is "UPDATE"

# =======================================================

# Load configuration from file if provided
CONFIG_FILE="${1:-}"

if [ -n "$CONFIG_FILE" ] && [ -f "$CONFIG_FILE" ]; then
    echo "Loading configuration from: $CONFIG_FILE"
    
    # Check if jq is available
    if ! command -v jq &> /dev/null; then
        echo "Error: jq is required to load config files but not installed."
        echo "Please install jq or edit the configuration directly in the script."
        exit 1
    fi
    
    # Read and parse config file
    if [ -s "$CONFIG_FILE" ]; then
        SOURCE_WORKSPACE_URL=$(jq -r '.source_workspace_url // ""' "$CONFIG_FILE")
        SOURCE_GENIE_SPACE_ID=$(jq -r '.source_genie_space_id // ""' "$CONFIG_FILE")
        SOURCE_AUTH_TYPE=$(jq -r '.source_auth_type // "PAT"' "$CONFIG_FILE")
        SOURCE_PAT=$(jq -r '.source_pat // ""' "$CONFIG_FILE")
        SOURCE_SP_CLIENT_ID=$(jq -r '.source_sp_client_id // ""' "$CONFIG_FILE")
        SOURCE_SP_CLIENT_SECRET=$(jq -r '.source_sp_client_secret // ""' "$CONFIG_FILE")
        
        TARGET_WORKSPACE_URL=$(jq -r '.target_workspace_url // ""' "$CONFIG_FILE")
        TARGET_AUTH_TYPE=$(jq -r '.target_auth_type // "PAT"' "$CONFIG_FILE")
        TARGET_PAT=$(jq -r '.target_pat // ""' "$CONFIG_FILE")
        TARGET_SP_CLIENT_ID=$(jq -r '.target_sp_client_id // ""' "$CONFIG_FILE")
        TARGET_SP_CLIENT_SECRET=$(jq -r '.target_sp_client_secret // ""' "$CONFIG_FILE")
        
        TARGET_SQL_WAREHOUSE_ID=$(jq -r '.target_sql_warehouse_id // ""' "$CONFIG_FILE")
        TARGET_TITLE_OVERRIDE=$(jq -r '.target_space_display_name // ""' "$CONFIG_FILE")
        TARGET_DESCRIPTION_OVERRIDE=$(jq -r '.target_space_description // ""' "$CONFIG_FILE")
        
        ACTION=$(jq -r '.action // "CREATE"' "$CONFIG_FILE")
        EXISTING_TARGET_SPACE_ID=$(jq -r '.existing_target_space_id // ""' "$CONFIG_FILE")
        
        echo "Configuration loaded successfully from $CONFIG_FILE"
    fi
elif [ -n "$CONFIG_FILE" ]; then
    echo "Warning: Config file '$CONFIG_FILE' not found. Using default configuration."
fi

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
DARK_GRAY='\033[0;90m'
NC='\033[0m' # No Color

# ==================== MAIN EXECUTION ====================

echo -e "${CYAN}"
echo "================================================================================"
echo "GENIE SPACE MIGRATION TOOL"
echo "================================================================================"
echo -e "${NC}"

# Check dependencies
if ! command -v curl &> /dev/null; then
    echo -e "${RED}Error: curl is required but not installed.${NC}"
    exit 1
fi

if ! command -v jq &> /dev/null; then
    echo -e "${RED}Error: jq is required but not installed.${NC}"
    exit 1
fi

# ==================== STEP 1: GET SOURCE GENIE SPACE ====================

echo -e "${GREEN}================================================================================${NC}"
echo -e "${GREEN}STEP 1: FETCHING GENIE SPACE FROM SOURCE WORKSPACE${NC}"
echo -e "${GREEN}================================================================================${NC}"
echo ""

echo -e "${YELLOW}Authenticating to source workspace using $SOURCE_AUTH_TYPE...${NC}"

# Build source authentication header
SOURCE_WORKSPACE_URL=${SOURCE_WORKSPACE_URL%/}  # Remove trailing slash

if [ "$SOURCE_AUTH_TYPE" == "PAT" ]; then
    SOURCE_AUTH_HEADER="Authorization: Bearer ${SOURCE_PAT}"
elif [ "$SOURCE_AUTH_TYPE" == "SERVICE_PRINCIPAL" ]; then
    # Get OAuth token for Service Principal
    TOKEN_URL="${SOURCE_WORKSPACE_URL}/oidc/v1/token"
    TOKEN_RESPONSE=$(curl -s -X POST "$TOKEN_URL" \
        -u "${SOURCE_SP_CLIENT_ID}:${SOURCE_SP_CLIENT_SECRET}" \
        -H "Content-Type: application/x-www-form-urlencoded" \
        -d "grant_type=client_credentials&scope=all-apis")
    
    SOURCE_TOKEN=$(echo "$TOKEN_RESPONSE" | jq -r '.access_token')
    SOURCE_AUTH_HEADER="Authorization: Bearer ${SOURCE_TOKEN}"
else
    echo -e "${RED}Error: Invalid SOURCE_AUTH_TYPE: $SOURCE_AUTH_TYPE${NC}"
    exit 1
fi

echo -e "${GREEN}Authentication successful${NC}"

# Get Genie space with serialized configuration
echo -e "${YELLOW}\nFetching Genie space: $SOURCE_GENIE_SPACE_ID...${NC}"

GET_URL="${SOURCE_WORKSPACE_URL}/api/2.0/genie/spaces/${SOURCE_GENIE_SPACE_ID}?include_serialized_space=true"

SOURCE_SPACE=$(curl -s -X GET "$GET_URL" \
    -H "$SOURCE_AUTH_HEADER" \
    -H "Content-Type: application/json")

echo -e "${GREEN}Genie space retrieved successfully${NC}"

# Display space summary
echo -e "\n${CYAN}================================================================================${NC}"
echo -e "${CYAN}SOURCE GENIE SPACE SUMMARY${NC}"
echo -e "${CYAN}================================================================================${NC}"

SOURCE_TITLE=$(echo "$SOURCE_SPACE" | jq -r '.title // ""')
SOURCE_DESCRIPTION=$(echo "$SOURCE_SPACE" | jq -r '.description // ""')
SOURCE_WAREHOUSE_ID=$(echo "$SOURCE_SPACE" | jq -r '.warehouse_id // ""')
SOURCE_SERIALIZED_SPACE=$(echo "$SOURCE_SPACE" | jq -r '.serialized_space // ""')

echo "Title: $SOURCE_TITLE"
echo "Description: $SOURCE_DESCRIPTION"
echo "Warehouse ID: $SOURCE_WAREHOUSE_ID"

echo -e "\n${DARK_GRAY}DEBUG: Full API response:${NC}"
echo -e "${DARK_GRAY}$(echo "$SOURCE_SPACE" | jq .)${NC}"

# ==================== STEP 2: PREPARE TARGET CONFIGURATION ====================

echo -e "\n${GREEN}================================================================================${NC}"
echo -e "${GREEN}STEP 2: PREPARING CONFIGURATION FOR TARGET WORKSPACE${NC}"
echo -e "${GREEN}================================================================================${NC}"
echo ""

# Use values from source or apply overrides
TARGET_TITLE=${TARGET_TITLE_OVERRIDE:-$SOURCE_TITLE}
TARGET_DESCRIPTION=${TARGET_DESCRIPTION_OVERRIDE:-$SOURCE_DESCRIPTION}

echo "Target Title: $TARGET_TITLE"
echo "Target Description: $TARGET_DESCRIPTION"
echo "Target SQL Warehouse ID: $TARGET_SQL_WAREHOUSE_ID"

# ==================== STEP 3: DEPLOY TO TARGET ====================

echo -e "\n${GREEN}================================================================================${NC}"
echo -e "${GREEN}STEP 3: DEPLOYING GENIE SPACE TO TARGET WORKSPACE${NC}"
echo -e "${GREEN}================================================================================${NC}"
echo ""

echo -e "${YELLOW}Authenticating to target workspace using $TARGET_AUTH_TYPE...${NC}"

# Build target authentication header
TARGET_WORKSPACE_URL=${TARGET_WORKSPACE_URL%/}  # Remove trailing slash

if [ "$TARGET_AUTH_TYPE" == "PAT" ]; then
    TARGET_AUTH_HEADER="Authorization: Bearer ${TARGET_PAT}"
elif [ "$TARGET_AUTH_TYPE" == "SERVICE_PRINCIPAL" ]; then
    # Get OAuth token for Service Principal
    TOKEN_URL="${TARGET_WORKSPACE_URL}/oidc/v1/token"
    TOKEN_RESPONSE=$(curl -s -X POST "$TOKEN_URL" \
        -u "${TARGET_SP_CLIENT_ID}:${TARGET_SP_CLIENT_SECRET}" \
        -H "Content-Type: application/x-www-form-urlencoded" \
        -d "grant_type=client_credentials&scope=all-apis")
    
    TARGET_TOKEN=$(echo "$TOKEN_RESPONSE" | jq -r '.access_token')
    TARGET_AUTH_HEADER="Authorization: Bearer ${TARGET_TOKEN}"
else
    echo -e "${RED}Error: Invalid TARGET_AUTH_TYPE: $TARGET_AUTH_TYPE${NC}"
    exit 1
fi

echo -e "${GREEN}Authentication successful${NC}"

# Prepare payload using API response as-is
if [ "$ACTION" == "CREATE" ]; then
    echo -e "${YELLOW}\nCreating new Genie space in target workspace...${NC}"
    
    # Build request body
    REQUEST_BODY=$(jq -n \
        --arg warehouse_id "$TARGET_SQL_WAREHOUSE_ID" \
        --arg title "$TARGET_TITLE" \
        --arg description "$TARGET_DESCRIPTION" \
        --arg serialized_space "$SOURCE_SERIALIZED_SPACE" \
        '{
            warehouse_id: $warehouse_id,
            title: $title,
            description: $description,
            serialized_space: $serialized_space
        }')
    
    echo -e "\n${DARK_GRAY}DEBUG: Request payload:${NC}"
    echo -e "${DARK_GRAY}$(echo "$REQUEST_BODY" | jq .)${NC}"
    
    CREATE_URL="${TARGET_WORKSPACE_URL}/api/2.0/genie/spaces"
    
    RESULT_SPACE=$(curl -s -X POST "$CREATE_URL" \
        -H "$TARGET_AUTH_HEADER" \
        -H "Content-Type: application/json" \
        -d "$REQUEST_BODY")
    
    echo -e "${GREEN}Genie space created successfully${NC}"
    
elif [ "$ACTION" == "UPDATE" ]; then
    if [ -z "$EXISTING_TARGET_SPACE_ID" ]; then
        echo -e "${RED}Error: EXISTING_TARGET_SPACE_ID is required when ACTION is 'UPDATE'${NC}"
        exit 1
    fi
    
    echo -e "${YELLOW}\nUpdating existing Genie space: $EXISTING_TARGET_SPACE_ID...${NC}"
    
    # Build request body
    REQUEST_BODY=$(jq -n \
        --arg warehouse_id "$TARGET_SQL_WAREHOUSE_ID" \
        --arg title "$TARGET_TITLE" \
        --arg description "$TARGET_DESCRIPTION" \
        --arg serialized_space "$SOURCE_SERIALIZED_SPACE" \
        '{
            warehouse_id: $warehouse_id,
            title: $title,
            description: $description,
            serialized_space: $serialized_space
        }')
    
    echo -e "\n${DARK_GRAY}DEBUG: Request payload:${NC}"
    echo -e "${DARK_GRAY}$(echo "$REQUEST_BODY" | jq .)${NC}"
    
    UPDATE_URL="${TARGET_WORKSPACE_URL}/api/2.0/genie/spaces/${EXISTING_TARGET_SPACE_ID}"
    
    RESULT_SPACE=$(curl -s -X PATCH "$UPDATE_URL" \
        -H "$TARGET_AUTH_HEADER" \
        -H "Content-Type: application/json" \
        -d "$REQUEST_BODY")
    
    echo -e "${GREEN}Genie space updated successfully${NC}"
    
else
    echo -e "${RED}Error: Invalid ACTION: $ACTION. Must be 'CREATE' or 'UPDATE'${NC}"
    exit 1
fi

# ==================== COMPLETION ====================

RESULT_SPACE_ID=$(echo "$RESULT_SPACE" | jq -r '.space_id // ""')

echo -e "\n${CYAN}================================================================================${NC}"
echo -e "${CYAN}MIGRATION COMPLETED SUCCESSFULLY${NC}"
echo -e "${CYAN}================================================================================${NC}"
echo "Source Space ID: $SOURCE_GENIE_SPACE_ID"
echo "Target Space ID: $RESULT_SPACE_ID"
echo "Target Workspace URL: $TARGET_WORKSPACE_URL"
echo ""
echo "New Genie Space URL:"
echo "${TARGET_WORKSPACE_URL}/genie/spaces/${RESULT_SPACE_ID}"
echo ""
