# ============================================================================
# Genie Space Migration Tool - PowerShell Script
# ============================================================================
# This script migrates a Genie space from one Databricks workspace to another.
# Cloud agnostic - works with Azure, AWS, and GCP Databricks.
# Supports both PAT and Service Principal authentication.
# ============================================================================

param(
    [Parameter(Mandatory=$false)]
    [string]$ConfigFile = ""
)

# ==================== CONFIGURATION ====================

# Source Workspace Configuration
$SOURCE_WORKSPACE_URL = ""  # Example: "https://adb-1234567890.7.azuredatabricks.net"
$SOURCE_GENIE_SPACE_ID = ""  # Example: "01ef1234567890abcdef1234567890ab"
$SOURCE_AUTH_TYPE = "PAT"  # Options: "PAT" or "SERVICE_PRINCIPAL"
$SOURCE_PAT = ""  # Example: "dapi1234567890abcdef1234567890ab"
$SOURCE_SP_CLIENT_ID = ""  # Example: "12345678-1234-1234-1234-123456789012"
$SOURCE_SP_CLIENT_SECRET = ""

# Target Workspace Configuration
$TARGET_WORKSPACE_URL = ""  # Example: "https://dbc-abcdef12-3456.cloud.databricks.com"
$TARGET_AUTH_TYPE = "PAT"  # Options: "PAT" or "SERVICE_PRINCIPAL"
$TARGET_PAT = ""  # Example: "dapi1234567890abcdef1234567890ab"
$TARGET_SP_CLIENT_ID = ""  # Example: "12345678-1234-1234-1234-123456789012"
$TARGET_SP_CLIENT_SECRET = ""

# REQUIRED: Target SQL Warehouse ID (different from source workspace)
$TARGET_SQL_WAREHOUSE_ID = ""  # Example: "abc123def456"

# Optional: Override title and description
$TARGET_TITLE_OVERRIDE = $null  # Set to override, or $null to keep original
$TARGET_DESCRIPTION_OVERRIDE = $null  # Set to override, or $null to keep original

# Action: "CREATE" or "UPDATE"
$ACTION = "CREATE"
$EXISTING_TARGET_SPACE_ID = ""  # Required if ACTION is "UPDATE"

# =======================================================

# Load configuration from file if provided
if ($ConfigFile -and (Test-Path $ConfigFile)) {
    Write-Host "Loading configuration from: $ConfigFile" -ForegroundColor Cyan
    $config = Get-Content $ConfigFile | ConvertFrom-Json
    
    if ($config.source_workspace_url) { $SOURCE_WORKSPACE_URL = $config.source_workspace_url }
    if ($config.source_genie_space_id) { $SOURCE_GENIE_SPACE_ID = $config.source_genie_space_id }
    if ($config.target_workspace_url) { $TARGET_WORKSPACE_URL = $config.target_workspace_url }
    if ($config.source_auth_type) { $SOURCE_AUTH_TYPE = $config.source_auth_type }
    if ($config.target_auth_type) { $TARGET_AUTH_TYPE = $config.target_auth_type }
    if ($config.source_pat) { $SOURCE_PAT = $config.source_pat }
    if ($config.target_pat) { $TARGET_PAT = $config.target_pat }
    if ($config.source_sp_client_id) { $SOURCE_SP_CLIENT_ID = $config.source_sp_client_id }
    if ($config.source_sp_client_secret) { $SOURCE_SP_CLIENT_SECRET = $config.source_sp_client_secret }
    if ($config.target_sp_client_id) { $TARGET_SP_CLIENT_ID = $config.target_sp_client_id }
    if ($config.target_sp_client_secret) { $TARGET_SP_CLIENT_SECRET = $config.target_sp_client_secret }
    if ($config.target_sql_warehouse_id) { $TARGET_SQL_WAREHOUSE_ID = $config.target_sql_warehouse_id }
    if ($config.action) { $ACTION = $config.action }
    if ($config.existing_target_space_id) { $EXISTING_TARGET_SPACE_ID = $config.existing_target_space_id }
}

# ==================== MAIN EXECUTION ====================

Write-Host ""
Write-Host "================================================================================" -ForegroundColor Cyan
Write-Host "GENIE SPACE MIGRATION TOOL" -ForegroundColor Cyan
Write-Host "================================================================================" -ForegroundColor Cyan
Write-Host ""

# ==================== STEP 1: GET SOURCE GENIE SPACE ====================

Write-Host "================================================================================" -ForegroundColor Green
Write-Host "STEP 1: FETCHING GENIE SPACE FROM SOURCE WORKSPACE" -ForegroundColor Green
Write-Host "================================================================================" -ForegroundColor Green
Write-Host ""

Write-Host "Authenticating to source workspace using $SOURCE_AUTH_TYPE..." -ForegroundColor Yellow

# Build source authentication headers
$sourceHeaders = @{
    'Content-Type' = 'application/json'
}

if ($SOURCE_AUTH_TYPE -eq "PAT") {
    $sourceHeaders['Authorization'] = "Bearer $SOURCE_PAT"
}
elseif ($SOURCE_AUTH_TYPE -eq "SERVICE_PRINCIPAL") {
    # Get OAuth token for Service Principal
    $sourceWorkspaceUrl = $SOURCE_WORKSPACE_URL.TrimEnd('/')
    $tokenUrl = "$sourceWorkspaceUrl/oidc/v1/token"
    $base64Auth = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("${SOURCE_SP_CLIENT_ID}:${SOURCE_SP_CLIENT_SECRET}"))
    
    $tokenHeaders = @{
        'Authorization' = "Basic $base64Auth"
        'Content-Type' = 'application/x-www-form-urlencoded'
    }
    
    $tokenBody = @{
        'grant_type' = 'client_credentials'
        'scope' = 'all-apis'
    }
    
    $tokenResponse = Invoke-RestMethod -Uri $tokenUrl -Method Post -Headers $tokenHeaders -Body $tokenBody
    $sourceHeaders['Authorization'] = "Bearer $($tokenResponse.access_token)"
}

Write-Host "Authentication successful" -ForegroundColor Green

# Get Genie space with serialized configuration
Write-Host "`nFetching Genie space: $SOURCE_GENIE_SPACE_ID..." -ForegroundColor Yellow

$sourceWorkspaceUrl = $SOURCE_WORKSPACE_URL.TrimEnd('/')
$getUrl = "$sourceWorkspaceUrl/api/2.0/genie/spaces/$SOURCE_GENIE_SPACE_ID" + "?include_serialized_space=true"

$sourceSpace = Invoke-RestMethod -Uri $getUrl -Method Get -Headers $sourceHeaders

Write-Host "Genie space retrieved successfully" -ForegroundColor Green

# Display space summary
Write-Host "`n================================================================================" -ForegroundColor Cyan
Write-Host "SOURCE GENIE SPACE SUMMARY" -ForegroundColor Cyan
Write-Host "================================================================================" -ForegroundColor Cyan
Write-Host "Title: $($sourceSpace.title)"
Write-Host "Description: $($sourceSpace.description)"
Write-Host "Warehouse ID: $($sourceSpace.warehouse_id)"

Write-Host "`nDEBUG: Full API response:" -ForegroundColor DarkGray
Write-Host ($sourceSpace | ConvertTo-Json -Depth 20) -ForegroundColor DarkGray

# ==================== STEP 2: PREPARE TARGET CONFIGURATION ====================

Write-Host "`n================================================================================" -ForegroundColor Green
Write-Host "STEP 2: PREPARING CONFIGURATION FOR TARGET WORKSPACE" -ForegroundColor Green
Write-Host "================================================================================" -ForegroundColor Green
Write-Host ""

# Use values from source or apply overrides
$targetTitle = if ($TARGET_TITLE_OVERRIDE) { $TARGET_TITLE_OVERRIDE } else { $sourceSpace.title }
$targetDescription = if ($TARGET_DESCRIPTION_OVERRIDE) { $TARGET_DESCRIPTION_OVERRIDE } else { $sourceSpace.description }

Write-Host "Target Title: $targetTitle"
Write-Host "Target Description: $targetDescription"
Write-Host "Target SQL Warehouse ID: $TARGET_SQL_WAREHOUSE_ID"

# ==================== STEP 3: DEPLOY TO TARGET ====================

Write-Host "`n================================================================================" -ForegroundColor Green
Write-Host "STEP 3: DEPLOYING GENIE SPACE TO TARGET WORKSPACE" -ForegroundColor Green
Write-Host "================================================================================" -ForegroundColor Green
Write-Host ""

Write-Host "Authenticating to target workspace using $TARGET_AUTH_TYPE..." -ForegroundColor Yellow

# Build target authentication headers
$targetHeaders = @{
    'Content-Type' = 'application/json'
}

if ($TARGET_AUTH_TYPE -eq "PAT") {
    $targetHeaders['Authorization'] = "Bearer $TARGET_PAT"
}
elseif ($TARGET_AUTH_TYPE -eq "SERVICE_PRINCIPAL") {
    # Get OAuth token for Service Principal
    $targetWorkspaceUrl = $TARGET_WORKSPACE_URL.TrimEnd('/')
    $tokenUrl = "$targetWorkspaceUrl/oidc/v1/token"
    $base64Auth = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("${TARGET_SP_CLIENT_ID}:${TARGET_SP_CLIENT_SECRET}"))
    
    $tokenHeaders = @{
        'Authorization' = "Basic $base64Auth"
        'Content-Type' = 'application/x-www-form-urlencoded'
    }
    
    $tokenBody = @{
        'grant_type' = 'client_credentials'
        'scope' = 'all-apis'
    }
    
    $tokenResponse = Invoke-RestMethod -Uri $tokenUrl -Method Post -Headers $tokenHeaders -Body $tokenBody
    $targetHeaders['Authorization'] = "Bearer $($tokenResponse.access_token)"
}

Write-Host "Authentication successful" -ForegroundColor Green

# Prepare payload using API response as-is
$targetWorkspaceUrl = $TARGET_WORKSPACE_URL.TrimEnd('/')

if ($ACTION -eq "CREATE") {
    Write-Host "`nCreating new Genie space in target workspace..." -ForegroundColor Yellow
    
    # Build request body
    $requestBody = @{
        warehouse_id = $TARGET_SQL_WAREHOUSE_ID
        title = $targetTitle
        description = $targetDescription
        serialized_space = $sourceSpace.serialized_space
    }
    
    $body = $requestBody | ConvertTo-Json -Depth 10
    
    Write-Host "`nDEBUG: Request payload:" -ForegroundColor DarkGray
    Write-Host $body -ForegroundColor DarkGray
    
    $createUrl = "$targetWorkspaceUrl/api/2.0/genie/spaces"
    $resultSpace = Invoke-RestMethod -Uri $createUrl -Method Post -Headers $targetHeaders -Body $body
    
    Write-Host "Genie space created successfully" -ForegroundColor Green
}
elseif ($ACTION -eq "UPDATE") {
    if (-not $EXISTING_TARGET_SPACE_ID) {
        throw "EXISTING_TARGET_SPACE_ID is required when ACTION is 'UPDATE'"
    }
    
    Write-Host "`nUpdating existing Genie space: $EXISTING_TARGET_SPACE_ID..." -ForegroundColor Yellow
    
    # Build request body
    $requestBody = @{
        warehouse_id = $TARGET_SQL_WAREHOUSE_ID
        title = $targetTitle
        description = $targetDescription
        serialized_space = $sourceSpace.serialized_space
    }
    
    $body = $requestBody | ConvertTo-Json -Depth 10
    
    Write-Host "`nDEBUG: Request payload:" -ForegroundColor DarkGray
    Write-Host $body -ForegroundColor DarkGray
    
    $updateUrl = "$targetWorkspaceUrl/api/2.0/genie/spaces/$EXISTING_TARGET_SPACE_ID"
    $resultSpace = Invoke-RestMethod -Uri $updateUrl -Method Patch -Headers $targetHeaders -Body $body
    
    Write-Host "Genie space updated successfully" -ForegroundColor Green
}
else {
    throw "Invalid ACTION: $ACTION. Must be 'CREATE' or 'UPDATE'"
}

# ==================== COMPLETION ====================

Write-Host "`n================================================================================" -ForegroundColor Cyan
Write-Host "MIGRATION COMPLETED SUCCESSFULLY" -ForegroundColor Cyan
Write-Host "================================================================================" -ForegroundColor Cyan
Write-Host "Source Space ID: $SOURCE_GENIE_SPACE_ID"
Write-Host "Target Space ID: $($resultSpace.space_id)"
Write-Host "Target Workspace URL: $TARGET_WORKSPACE_URL"
Write-Host "`nNew Genie Space URL:"
Write-Host "$TARGET_WORKSPACE_URL/genie/spaces/$($resultSpace.space_id)"
Write-Host ""
