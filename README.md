# Genie Space Migration Tool

This repository contains tools to migrate Databricks Genie spaces between workspaces. The migration is cloud-agnostic and works across Azure Databricks, AWS Databricks, and GCP Databricks.

## Overview

The tools export a complete Genie space configuration (including code, settings, instructions, joins, table identifiers, and sample questions) from a source workspace and deploy it to a target workspace. As DAB's support for Genie space is currently unavailable, this uses the Genie CRUD APIs linked below and works as a REST API wrapper for Powershell, Shell/BASH and a IPYNB Notebook.

## Features

- **Cloud Agnostic**: Works across Azure, AWS, and GCP Databricks platforms
- **Flexible Authentication**: Supports both Personal Access Tokens (PAT) and Service Principal authentication
- **Complete Migration**: Exports all Genie space components including:
  - Display name and description
  - Instructions and sample questions
  - SQL warehouse configuration
  - Table identifiers and managed tables
  - Data source configuration
- **Multiple Implementations**: Three different implementations for different use cases

## Tools

### 1. Jupyter Notebook (`genie_space_migration.ipynb`)

Interactive notebook for step-by-step migration with detailed output.

**Best for:**
- Interactive exploration and testing
- Learning how the migration works
- One-time migrations with visibility into each step

**Usage:**
```python
# Option 1: Use a config file (recommended)
CONFIG_FILE = "config.json"

# Option 2: Set CONFIG_FILE = None and edit values directly in the notebook
```

1. Open the notebook in Jupyter or Databricks
2. Configure using a config file or edit values directly
3. Run cells sequentially

### 2. PowerShell Script (`migrate-genie-space.ps1`)

Windows-compatible PowerShell script for automated migrations.

**Best for:**
- Windows environments
- Automated CI/CD pipelines on Windows
- Integration with other PowerShell automation

**Usage:**
```powershell
# Use with a config file (recommended)
.\migrate-genie-space.ps1 -ConfigFile config.json

# Or edit the configuration section in the script and run
.\migrate-genie-space.ps1
```

### 3. Shell Script (`migrate-genie-space.sh`)

Unix/Linux/Mac compatible bash script for automated migrations.

**Best for:**
- Unix/Linux/Mac environments
- Automated CI/CD pipelines
- Integration with shell-based automation

**Usage:**
```bash
# Make the script executable
chmod +x migrate-genie-space.sh

# Use with a config file (recommended)
./migrate-genie-space.sh config.json

# Or edit the configuration section in the script and run
./migrate-genie-space.sh
```

## Prerequisites

### For All Tools
- Admin access to both source and target Databricks workspaces
- Valid authentication credentials (PAT or Service Principal)

### Tool-Specific Requirements

**Jupyter Notebook:**
- Python 3.7 or higher
- `requests` library: `pip install requests`

**PowerShell Script:**
- PowerShell 5.1 or higher (Windows) or PowerShell Core 6+ (cross-platform)

**Shell Script:**
- Bash shell
- `curl` command
- `jq` for JSON parsing (config file support and API responses)

## Authentication Methods

### Personal Access Token (PAT)

Simpler setup, good for individual users.

**Configuration:**
```python
SOURCE_AUTH_TYPE = "PAT"
SOURCE_PAT = "dapi1234567890abcdef1234567890ab"
```

**How to generate a PAT:**
1. In Databricks workspace, go to User Settings
2. Go to Access Tokens tab
3. Click "Generate New Token"
4. Copy the token (it will only be shown once)

### Service Principal

Better for automation and production use.

**Configuration:**
```python
SOURCE_AUTH_TYPE = "SERVICE_PRINCIPAL"
SOURCE_SP_CLIENT_ID = "12345678-1234-1234-1234-123456789012"
SOURCE_SP_CLIENT_SECRET = "your-client-secret-here"
```

**How to set up a Service Principal:**

**Azure Databricks:**
1. Create an Azure AD Application
2. Create a client secret for the application
3. Add the service principal to your Databricks workspace
4. Grant appropriate permissions

**AWS Databricks:**
1. Create a service principal in your Databricks account
2. Generate OAuth credentials
3. Add to workspace with appropriate permissions

**GCP Databricks:**
1. Create a service principal in your Databricks account
2. Generate OAuth credentials
3. Add to workspace with appropriate permissions

## Configuration

### Note:
- It is recommended to use Environment variables for the credentials. 
- When using the IPYNB notebook on a Databricks workspace, it is recommended to use [Secret Scope](https://docs.databricks.com/aws/en/security/secrets/).

### Option 1: Using a Config File

Create a `config.json` file with your configuration:

```json
{
  "source_workspace_url": "https://<workspace>.cloud.databricks.com",  
  "source_genie_space_id": "01f0c5aba5e216379ff31843a2b5aef7",
  "target_workspace_url": "https://<workspace>.azuredatabricks.net",
  "target_sql_warehouse_id": "148ccb90800933a1",
  "source_auth_type": "PAT",
  "target_auth_type": "PAT",
  "source_pat": "dapi...",
  "target_pat": "dapi...",
  "action": "CREATE"
}
```

### Option 2: Direct Configuration

Edit the configuration section in each script:

```python
# Source Workspace Configuration
SOURCE_WORKSPACE_URL = ""  # Example: "https://adb-1234567890.7.azuredatabricks.net"
SOURCE_GENIE_SPACE_ID = ""  # Example: "01ef1234567890abcdef1234567890ab"

# Target Workspace Configuration
TARGET_WORKSPACE_URL = ""  # Example: "https://dbc-abcdef12-3456.cloud.databricks.com"

# SQL Warehouse Configuration
# CRITICAL: Warehouse IDs are workspace-specific - always specify for cross-workspace migration
TARGET_SQL_WAREHOUSE_ID = ""  # Example: "abc123def456" - Get this from target workspace

# Authentication Type
SOURCE_AUTH_TYPE = "PAT"  # or "SERVICE_PRINCIPAL"
TARGET_AUTH_TYPE = "PAT"  # or "SERVICE_PRINCIPAL"

# PAT Credentials (if using PAT)
SOURCE_PAT = ""  # Example: "dapi..."
TARGET_PAT = ""  # Example: "dapi..."

# Service Principal Credentials (if using SERVICE_PRINCIPAL)
SOURCE_SP_CLIENT_ID = ""  # Example: "12345678-1234-1234-1234-123456789012"
SOURCE_SP_CLIENT_SECRET = ""
TARGET_SP_CLIENT_ID = ""  # Example: "12345678-1234-1234-1234-123456789012"
TARGET_SP_CLIENT_SECRET = ""

# Optional Overrides
TARGET_TITLE_OVERRIDE = None  # Set to override, or None to keep original
TARGET_DESCRIPTION_OVERRIDE = None  # Set to override, or None to keep original
```

## Migration Workflow

1. **Fetch Source**: Retrieves the complete Genie space configuration from the source workspace using the Genie API with `include_serialized_space=true` parameter
2. **Prepare Configuration**: Extracts title, description, and warehouse ID, applying any overrides specified in the configuration
3. **Deploy**: Creates a new Genie space in the target workspace (or updates an existing one) with the serialized configuration

## Actions

### Create New Space (Default)

Creates a brand new Genie space in the target workspace.

```python
ACTION = "CREATE"
```

### Update Existing Space

Updates an existing Genie space in the target workspace.

```python
ACTION = "UPDATE"
EXISTING_TARGET_SPACE_ID = "01ef1234-5678-90ab-cdef-1234567890ab"
```

## API References

This tool uses the Databricks Genie REST API:

- [Get Space](https://docs.databricks.com/api/azure/workspace/genie/getspace): Retrieve Genie space details
- [Create Space](https://docs.databricks.com/api/azure/workspace/genie/createspace): Create a new Genie space
- [Update Space](https://docs.databricks.com/api/azure/workspace/genie/updatespace): Update an existing Genie space

Note: While the documentation links reference Azure, the API is consistent across all cloud platforms (Azure, AWS, GCP).

## Cross-Cloud Migration

The tools are designed to work across different cloud providers. For example:

- Azure Databricks to AWS Databricks
- AWS Databricks to GCP Databricks
- GCP Databricks to Azure Databricks

**Important considerations for cross-cloud migration:**

1. **SQL Warehouse** (CRITICAL): SQL Warehouse IDs are workspace-specific and MUST be different
   - Find your target warehouse ID: Go to SQL Warehouses in UI, click warehouse, copy ID from URL
   - Always set `TARGET_SQL_WAREHOUSE_ID` explicitly for cross-workspace migrations
2. **Table Identifiers**: Ensure referenced tables exist or are accessible in the target workspace
3. **Permissions**: Service principals and user permissions may need to be reconfigured

## Troubleshooting

### Authentication Errors

- Verify your PAT or Service Principal credentials are correct
- Ensure the credentials have admin permissions in the workspace
- For Service Principals, verify they are added to the workspace

### API Errors

- Check that the source Genie space ID is correct
- Verify the workspace URLs are in the correct format (include `https://`)
- Ensure the API endpoints are accessible (no firewall/network restrictions)

### Missing Dependencies

**Python/Notebook:**
```bash
pip install requests
```

**Shell script:**
```bash
# Install jq (required for config file support)
# Ubuntu/Debian
sudo apt-get install jq

# macOS
brew install jq
```

## Security Best Practices

1. **Never commit credentials** to version control
2. **Use environment variables** or secure vaults for credentials in production
3. **Use Service Principals** instead of PATs for production automation
4. **Rotate credentials** regularly
5. **Grant minimum required permissions** to service principals

## Example: Environment Variables

Instead of hardcoding credentials, use environment variables:

**Python:**
```python
import os

SOURCE_PAT = os.environ.get('DATABRICKS_SOURCE_PAT')
TARGET_PAT = os.environ.get('DATABRICKS_TARGET_PAT')
```

**PowerShell:**
```powershell
$SOURCE_PAT = $env:DATABRICKS_SOURCE_PAT
$TARGET_PAT = $env:DATABRICKS_TARGET_PAT
```

**Bash:**
```bash
SOURCE_PAT="${DATABRICKS_SOURCE_PAT}"
TARGET_PAT="${DATABRICKS_TARGET_PAT}"
```

## Getting Your SQL Warehouse ID

The SQL Warehouse ID is required for migration and is workspace-specific:

1. Go to your target Databricks workspace
2. Navigate to SQL Warehouses in the left sidebar
3. Click on the warehouse you want to use
4. Copy the warehouse ID from the URL or the warehouse details page
5. Add it to your configuration as `TARGET_SQL_WAREHOUSE_ID`

## License

This code is provided as-is for use with Databricks Genie spaces.

## Contributing

Feel free to submit issues or pull requests to improve these tools.

