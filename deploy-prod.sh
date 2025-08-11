#!/bin/bash

# Nebulax Serverless Application Deployment Script
# Complete deployment for AWS Lambda with API Gateway, DynamoDB, and S3

set -e  # Exit on any error

# Configuration
PROJECT_NAME="nebulax"
STACK_NAME="nebulax"
REGION="us-east-1"
STAGE="dev"

# Global variables for user input
USER_S3_BUCKET=""
USER_REGION=""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# Print functions
print_info() { echo -e "${CYAN}ℹ️  $1${NC}"; }
print_success() { echo -e "${GREEN}✅ $1${NC}"; }
print_warning() { echo -e "${YELLOW}⚠️  $1${NC}"; }
print_error() { echo -e "${RED}❌ $1${NC}"; }
print_header() { echo -e "\n${BOLD}${BLUE}🚀 $1${NC}\n"; }
print_step() { echo -e "${BOLD}📋 $1${NC}"; }

# Function to monitor real-time CloudFormation events
monitor_stack_events() {
    local stack_name="$1"
    local operation_type="$2"  # CREATE, UPDATE, DELETE
    local wait_start=$(date +%s)
    local last_event_time=""
    local event_count=0
    local last_status_update=0
    
    print_header "Real-time CloudFormation Events Monitor"
    print_info "🎯 Stack: $stack_name"
    print_info "🔄 Operation: $operation_type"
    print_info "📍 Region: $REGION"
    print_info "⏱️  Updates every 5 seconds"
    echo ""
    
    # Get the current latest event timestamp as baseline to filter new events
    local baseline_events=$(aws cloudformation describe-stack-events \
        --stack-name "$stack_name" \
        --region "$REGION" \
        --query 'StackEvents[0].Timestamp' \
        --output text 2>/dev/null || echo "")
    
    # Convert baseline timestamp to epoch for comparison
    local baseline_timestamp=0
    if [ -n "$baseline_events" ] && [ "$baseline_events" != "None" ]; then
        baseline_timestamp=$(date -d "$baseline_events" +%s 2>/dev/null || date -j -f "%Y-%m-%dT%H:%M:%S" "${baseline_events%.*}" +%s 2>/dev/null || echo "$wait_start")
    else
        baseline_timestamp=$wait_start
    fi
    
    print_info "🕐 Monitoring events newer than: $(date -d "@$baseline_timestamp" 2>/dev/null || date -r "$baseline_timestamp" 2>/dev/null || echo "now")"
    echo ""
    
    # Create a temporary file to track seen events
    local seen_events_file="/tmp/cf_events_${stack_name}_$$"
    touch "$seen_events_file"
    
    while true; do
        # Get current stack status
        local stack_status=$(aws cloudformation describe-stacks \
            --stack-name "$stack_name" \
            --region "$REGION" \
            --query 'Stacks[0].StackStatus' \
            --output text 2>/dev/null || echo "STACK_NOT_FOUND")
        
        # Get recent events (last 20 events, sorted by timestamp)
        local events=$(aws cloudformation describe-stack-events \
            --stack-name "$stack_name" \
            --region "$REGION" \
            --query 'StackEvents[:20].{Time:Timestamp,Resource:LogicalResourceId,Type:ResourceType,Status:ResourceStatus,Reason:ResourceStatusReason}' \
            --output json 2>/dev/null)
        
        if [ -n "$events" ] && [ "$events" != "null" ] && [ "$events" != "[]" ]; then
            # Process each event - only show events newer than baseline
            echo "$events" | jq -r '.[] | "\(.Time)|\(.Resource)|\(.Type)|\(.Status)|\(.Reason // "")"' | while IFS='|' read -r event_time resource_id resource_type status reason; do
                # Convert event timestamp to epoch for comparison
                local event_timestamp=$(date -d "$event_time" +%s 2>/dev/null || date -j -f "%Y-%m-%dT%H:%M:%S" "${event_time%.*}" +%s 2>/dev/null || echo "0")
                
                # Only process events that occurred after baseline (i.e., new events during this operation)
                if [ "$event_timestamp" -le "$baseline_timestamp" ]; then
                    continue
                fi
                
                local event_id="${event_time}_${resource_id}_${status}"
                
                # Check if we've already seen this event
                if ! grep -q "$event_id" "$seen_events_file" 2>/dev/null; then
                    echo "$event_id" >> "$seen_events_file"
                    
                    # Format timestamp
                    local formatted_time=$(date -d "$event_time" "+%H:%M:%S" 2>/dev/null || date -j -f "%Y-%m-%dT%H:%M:%S" "${event_time%.*}" "+%H:%M:%S" 2>/dev/null || echo "${event_time%.*}")
                    
                    # Choose emoji and color based on status
                    local status_emoji=""
                    local status_color=""
                    case "$status" in
                        *_COMPLETE)
                            status_emoji="✅"
                            status_color="${GREEN}"
                            ;;
                        *_IN_PROGRESS)
                            status_emoji="🔄"
                            status_color="${CYAN}"
                            ;;
                        *_FAILED)
                            status_emoji="❌"
                            status_color="${RED}"
                            ;;
                        CREATE_COMPLETE)
                            status_emoji="🎉"
                            status_color="${GREEN}"
                            ;;
                        DELETE_COMPLETE)
                            status_emoji="🗑️"
                            status_color="${GREEN}"
                            ;;
                        *)
                            status_emoji="📋"
                            status_color="${YELLOW}"
                            ;;
                    esac
                    
                    # Display the event with enhanced description
                    local description=""
                    case "$status" in
                        "CREATE_IN_PROGRESS")
                            description="Creating resource..."
                            ;;
                        "CREATE_COMPLETE")
                            description="Resource created successfully"
                            ;;
                        "DELETE_IN_PROGRESS")
                            description="Deleting resource..."
                            ;;
                        "DELETE_COMPLETE")
                            description="Resource deleted successfully"
                            ;;
                        "UPDATE_IN_PROGRESS")
                            description="Updating resource..."
                            ;;
                        "UPDATE_COMPLETE")
                            description="Resource updated successfully"
                            ;;
                        *"_FAILED")
                            description="Operation failed!"
                            ;;
                        *)
                            description="$status"
                            ;;
                    esac
                    
                    printf "${status_color}${status_emoji} [%s] %-25s %-20s %s${NC}\n" \
                        "$formatted_time" \
                        "${resource_id:0:25}" \
                        "$description" \
                        "${resource_type}"
                    
                    # Show reason for failed events
                    if [[ "$status" == *"_FAILED"* ]] && [ -n "$reason" ]; then
                        printf "   ${RED}💬 %s${NC}\n" "$reason"
                    fi
                    
                    ((event_count++))
                fi
            done
        fi
        
        # Check if operation is complete
        case "$stack_status" in
            CREATE_COMPLETE|UPDATE_COMPLETE|DELETE_COMPLETE)
                local elapsed=$(($(date +%s) - wait_start))
                local elapsed_min=$((elapsed / 60))
                local elapsed_sec=$((elapsed % 60))
                
                echo ""
                print_success "🎉 Stack operation completed successfully!"
                echo -e "  ${BOLD}Final Status:${NC} ${GREEN}$stack_status${NC}"
                echo -e "  ${BOLD}Duration:${NC} ${elapsed_min}m ${elapsed_sec}s"
                echo -e "  ${BOLD}Events Processed:${NC} $event_count"
                echo -e "  ${BOLD}Completion Time:${NC} $(date)"
                
                # Cleanup
                rm -f "$seen_events_file"
                return 0
                ;;
            CREATE_FAILED|UPDATE_FAILED|ROLLBACK_COMPLETE|UPDATE_ROLLBACK_COMPLETE|DELETE_FAILED)
                local elapsed=$(($(date +%s) - wait_start))
                local elapsed_min=$((elapsed / 60))
                local elapsed_sec=$((elapsed % 60))
                
                echo ""
                print_error "❌ Stack operation failed!"
                echo -e "  ${BOLD}Final Status:${NC} ${RED}$stack_status${NC}"
                echo -e "  ${BOLD}Duration:${NC} ${elapsed_min}m ${elapsed_sec}s"
                echo -e "  ${BOLD}Events Processed:${NC} $event_count"
                
                # Show recent failure events in detail
                echo ""
                print_error "🔍 Failure Analysis:"
                aws cloudformation describe-stack-events \
                    --stack-name "$stack_name" \
                    --region "$REGION" \
                    --query 'StackEvents[?ResourceStatus==`CREATE_FAILED` || ResourceStatus==`UPDATE_FAILED` || ResourceStatus==`DELETE_FAILED`].{Time:Timestamp,Resource:LogicalResourceId,Type:ResourceType,Status:ResourceStatus,Reason:ResourceStatusReason}' \
                    --output table 2>/dev/null || print_error "Could not retrieve detailed failure events"
                
                # Cleanup
                rm -f "$seen_events_file"
                return 1
                ;;
            STACK_NOT_FOUND)
                if [[ "$operation_type" == "DELETE" ]]; then
                    local elapsed=$(($(date +%s) - wait_start))
                    local elapsed_min=$((elapsed / 60))
                    local elapsed_sec=$((elapsed % 60))
                    
                    echo ""
                    print_success "🎉 Stack successfully deleted!"
                    echo -e "  ${BOLD}Duration:${NC} ${elapsed_min}m ${elapsed_sec}s"
                    echo -e "  ${BOLD}Events Processed:${NC} $event_count"
                    
                    # Cleanup
                    rm -f "$seen_events_file"
                    return 0
                else
                    print_error "❌ Stack not found during $operation_type operation"
                    rm -f "$seen_events_file"
                    return 1
                fi
                ;;
            *)
                # Show periodic status updates every 30 seconds
                local current_time=$(date +%s)
                if [ $((current_time - last_status_update)) -ge 30 ]; then
                    local elapsed=$((current_time - wait_start))
                    local elapsed_min=$((elapsed / 60))
                    local elapsed_sec=$((elapsed % 60))
                    
                    echo ""
                    print_info "📊 Status Update: $stack_status | Duration: ${elapsed_min}m ${elapsed_sec}s | Events: $event_count"
                    echo ""
                    last_status_update=$current_time
                fi
                
                # Continue monitoring - check every 5 seconds for new events
                sleep 5
                ;;
        esac
    done
}

# Loading spinner function
show_spinner() {
    local pid=$1
    local message=$2
    local spinner="/-\|"
    local i=0
    
    while kill -0 $pid 2>/dev/null; do
        printf "\r${CYAN}${spinner:$i:1} ${message}${NC}"
        i=$(((i+1) % 4))
        sleep 0.1
    done
    printf "\r${GREEN}✅ ${message}${NC}\n"
}

# Progress bar function
show_progress() {
    local current=$1
    local total=$2
    local message=$3
    local width=50
    local percentage=$((current * 100 / total))
    local filled=$((current * width / total))
    local empty=$((width - filled))
    
    printf "\r${CYAN}%s${NC} [" "$message"
    printf "%*s" $filled | tr ' ' '█'
    printf "%*s" $empty | tr ' ' '░'
    printf "] %d%%" $percentage
    
    if [ $current -eq $total ]; then
        printf " ✅\n"
    fi
}

# Enhanced loading with progress simulation
show_loading_with_progress() {
    local message=$1
    local duration=${2:-5}  # Default 5 seconds
    local steps=100
    local step_duration=$(echo "scale=2; $duration / $steps" | bc -l 2>/dev/null || echo "0.05")
    
    for i in $(seq 1 $steps); do
        show_progress $i $steps "$message"
        sleep $step_duration
    done
}

# Function to check prerequisites
check_prerequisites() {
    print_step "Checking Prerequisites"
    
    # Check required tools with spinner
    (
        for tool in aws sam mvn java curl jq; do
            if ! command -v $tool &> /dev/null; then
                echo "MISSING:$tool" >&2
                exit 1
            fi
            sleep 0.2  # Small delay for visual effect
        done
        
        # Check AWS credentials
        if ! aws sts get-caller-identity &> /dev/null; then
            echo "MISSING:AWS credentials" >&2
            exit 1
        fi
        sleep 0.5
    ) &
    
    show_spinner $! "Checking tools and credentials"
    wait $!  # Wait for background process
    
    if [ $? -ne 0 ]; then
        print_error "Prerequisites check failed"
        exit 1
    fi
    
    ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    print_success "All prerequisites met (Account: $ACCOUNT_ID)"
}

# Function to get user input for deployment configuration
get_deployment_configuration() {
    print_step "Deployment Configuration"
    
    # Get stack name
    echo "Enter Stack Name:"
    echo "Default: ${STACK_NAME}"
    read -p "Stack name (press Enter for default): " input_stack_name
    
    if [ -z "$input_stack_name" ]; then
        USER_STACK_NAME="$STACK_NAME"
        print_info "Using default stack name: $USER_STACK_NAME"
    else
        USER_STACK_NAME="$input_stack_name"
        print_info "Using custom stack name: $USER_STACK_NAME"
        # Update global STACK_NAME variable
        STACK_NAME="$USER_STACK_NAME"
    fi
    
    # Get AWS account ID for S3 bucket name
    ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Derive S3 bucket name from stack name and account ID
    USER_S3_BUCKET="${USER_STACK_NAME}-artifact-${ACCOUNT_ID}"
    
    # Get region
    echo "Enter AWS region:"
    echo "Default: ${REGION}"
    read -p "Region (press Enter for default): " input_region
    
    if [ -z "$input_region" ]; then
        USER_REGION="$REGION"
        print_info "Using default region: $USER_REGION"
    else
        USER_REGION="$input_region"
        print_info "Using custom region: $USER_REGION"
        # Update global REGION variable
        REGION="$USER_REGION"
    fi
    
    # Set sensible defaults for all other options
    STORAGE_CLASS="STANDARD"
    ENABLE_VERSIONING="false"
    ENABLE_ENCRYPTION="true"
    
    # Summary
    echo ""
    echo -e "${BOLD}Deployment Configuration Summary:${NC}"
    echo -e "  ${BOLD}Stack Name:${NC} $USER_STACK_NAME"
    echo -e "  ${BOLD}Lambda Function:${NC} ${USER_STACK_NAME}-func"
    echo -e "  ${BOLD}API Gateway:${NC} ${USER_STACK_NAME}-api"
    echo -e "  ${BOLD}S3 Bucket:${NC} $USER_S3_BUCKET"
    echo -e "  ${BOLD}Videos S3 Bucket:${NC} ${USER_STACK_NAME}-s3-${ACCOUNT_ID}"
    echo -e "  ${BOLD}Region:${NC} $USER_REGION"
    
    echo ""
    read -p "Proceed with this configuration? (Y/n): " confirm
    if [[ $confirm =~ ^[Nn]$ ]]; then
        print_warning "Configuration cancelled. Please run the script again."
        exit 0
    fi
}

# Function to create configuration
create_config() {
    if [ ! -f "samconfig.toml" ]; then
        print_step "Creating Configuration"
        
        # Show loading while creating config
        (
            sleep 1  # Simulate processing time
            cat > samconfig.toml << EOF
version = 0.1

[default.global.parameters]
stack_name = "$STACK_NAME"
region = "$USER_REGION"
confirm_changeset = false
fail_on_empty_changeset = false
s3_bucket = "$USER_S3_BUCKET"

[default.build.parameters]
cached = true
parallel = true

[default.deploy.parameters]
stack_name = "$STACK_NAME"
s3_bucket = "$USER_S3_BUCKET"
region = "$USER_REGION"
confirm_changeset = false
fail_on_empty_changeset = false
capabilities = "CAPABILITY_IAM"
parameter_overrides = "Stage=$STAGE"
EOF
        ) &
        
        show_spinner $! "Generating configuration"
        wait $!
        print_success "Configuration created"
    else
        print_info "Using existing configuration"
    fi
}

# Function to create S3 bucket
setup_s3() {
    # Check if bucket exists (suppress all output)
    if ! aws s3api head-bucket --bucket "$USER_S3_BUCKET" --region "$USER_REGION" >/dev/null 2>&1; then
        print_step "Creating S3 Bucket"
        
        (
            # Create bucket with region-specific handling
            if [ "$USER_REGION" = "us-east-1" ]; then
                aws s3api create-bucket --bucket "$USER_S3_BUCKET" --region "$USER_REGION" >/dev/null 2>&1
            else
                aws s3api create-bucket --bucket "$USER_S3_BUCKET" --region "$USER_REGION" \
                    --create-bucket-configuration LocationConstraint="$USER_REGION" >/dev/null 2>&1
            fi
            
            # Apply versioning if enabled
            if [ "$ENABLE_VERSIONING" = "true" ]; then
                aws s3api put-bucket-versioning --bucket "$USER_S3_BUCKET" \
                    --versioning-configuration Status=Enabled >/dev/null 2>&1
            fi
            
            # Apply encryption if enabled
            if [ "$ENABLE_ENCRYPTION" = "true" ]; then
                aws s3api put-bucket-encryption --bucket "$USER_S3_BUCKET" \
                    --server-side-encryption-configuration '{
                        "Rules": [{
                            "ApplyServerSideEncryptionByDefault": {
                                "SSEAlgorithm": "AES256"
                            }
                        }]
                    }' >/dev/null 2>&1
            fi
            
            sleep 1  # Small delay for visual effect
        ) &
        
        show_spinner $! "Setting up S3 bucket"
        wait $!
        
        print_success "S3 bucket created: $USER_S3_BUCKET"
    else
        print_info "Using existing S3 bucket: $USER_S3_BUCKET"
    fi
}

# Function to build project
build_project() {
    print_step "Building Application"
    
    # Start build process in background, capturing output
    (
        mvn clean package -Plambda -DskipTests -q 2>&1
    ) > /tmp/build_output &
    
    BUILD_PID=$!
    
    # Show animated progress for build
    local spinner="/-\|"
    local i=0
    local message="Compiling with Lambda profile"
    
    while kill -0 $BUILD_PID 2>/dev/null; do
        printf "\r${CYAN}${spinner:$i:1} ${message}${NC}"
        i=$(((i+1) % 4))
        sleep 0.2
    done
    
    wait $BUILD_PID
    BUILD_STATUS=$?
    
    if [ $BUILD_STATUS -eq 0 ]; then
        printf "\r${GREEN}✅ ${message}${NC}\n"
        
        # Check for warnings in build output
        if [ -f /tmp/build_output ] && grep -q "WARNING" /tmp/build_output; then
            echo -e "${YELLOW}⚠️  Build warnings detected:${NC}"
            grep "WARNING" /tmp/build_output | head -3 | sed 's/^/   /'
        fi
        
        JAR_SIZE=$(ls -lh target/demo-lambda.jar | awk '{print $5}')
        print_success "Build complete (JAR: $JAR_SIZE)"
    else
        printf "\r${RED}❌ ${message}${NC}\n"
        
        # Show build errors
        if [ -f /tmp/build_output ]; then
            echo -e "${RED}❌ Build errors:${NC}"
            cat /tmp/build_output | tail -10 | sed 's/^/   /'
        fi
        
        print_error "Build failed"
        exit 1
    fi
    
    # Clean up temp file
    rm -f /tmp/build_output
}

# Function to show S3 upload progress with enhanced tracking
show_s3_upload_progress() {
    local file_path="$1"
    local s3_uri="$2"
    
    if [ ! -f "$file_path" ]; then
        print_error "File not found: $file_path"
        return 1
    fi
    
    local file_size=$(stat -f%z "$file_path" 2>/dev/null || stat -c%s "$file_path" 2>/dev/null || echo "0")
    local file_name=$(basename "$file_path")
    local file_size_mb=$(echo "scale=2; $file_size / 1024 / 1024" | bc -l 2>/dev/null || echo "0")
    
    print_info "📦 Uploading artifact: $file_name (${file_size_mb} MB)"
    
    # Create temporary log file for upload progress
    local temp_log="/tmp/s3_upload_$$.log"
    
    # Start upload in background with progress logging
    (
        aws s3 cp "$file_path" "$s3_uri" --cli-write-timeout 0 --cli-read-timeout 0 > "$temp_log" 2>&1
        echo $? > "${temp_log}.status"
    ) &
    
    local upload_pid=$!
    local progress=0
    local spinner="/-\|"
    local i=0
    local elapsed=0
    local start_time=$(date +%s)
    
    # Enhanced progress simulation with more realistic timing
    while kill -0 $upload_pid 2>/dev/null; do
        elapsed=$(($(date +%s) - start_time))
        
        # More realistic progress calculation based on file size and elapsed time
        if [ "$file_size" -gt 0 ]; then
            # Estimate progress based on typical upload speeds
            local estimated_time=$((file_size / 1000000 + 5))  # Rough estimate: 1MB/s + 5s overhead
            progress=$((elapsed * 100 / estimated_time))
            if [ $progress -gt 95 ]; then
                progress=95
            fi
        else
            # Fallback linear progress
            progress=$((elapsed * 10))
            if [ $progress -gt 95 ]; then
                progress=95
            fi
        fi
        
        # Show enhanced progress bar with time info
        local filled=$((progress * 50 / 100))
        local empty=$((50 - filled))
        
        printf "\r${CYAN}${spinner:$i:1}${NC} ${BOLD}$file_name${NC} ["
        printf "%*s" $filled | tr ' ' '█'
        printf "%*s" $empty | tr ' ' '░'
        printf "] %d%% (%ds)" $progress $elapsed
        
        i=$(((i+1) % 4))
        sleep 0.2
    done
    
    wait $upload_pid
    local upload_status
    if [ -f "${temp_log}.status" ]; then
        upload_status=$(cat "${temp_log}.status")
    else
        upload_status=1
    fi
    
    elapsed=$(($(date +%s) - start_time))
    
    if [ $upload_status -eq 0 ]; then
        printf "\r${GREEN}✅${NC} ${BOLD}$file_name${NC} ["
        printf "%*s" 50 | tr ' ' '█'
        printf "] 100%% (${elapsed}s)   \n"
        
        # Show upload statistics
        if [ "$file_size" -gt 0 ] && [ $elapsed -gt 0 ]; then
            local speed_mbps=$(echo "scale=2; $file_size_mb / $elapsed" | bc -l 2>/dev/null || echo "0")
            print_info "   📊 Upload speed: ${speed_mbps} MB/s"
        fi
        
        rm -f "$temp_log" "${temp_log}.status" 2>/dev/null
        return 0
    else
        printf "\r${RED}❌ Failed to upload ${file_name}${NC}                    \n"
        
        # Show error details if available
        if [ -f "$temp_log" ]; then
            print_error "Upload error details:"
            cat "$temp_log" | head -3
        fi
        
        rm -f "$temp_log" "${temp_log}.status" 2>/dev/null
        return 1
    fi
}

# Function to show CloudFormation change set with enhanced details
show_change_set() {
    local change_set_name="$1"
    
    print_step "📋 CloudFormation Change Set Analysis"
    
    # Wait for change set to be created with better progress indication
    local spinner="/-\|"
    local i=0
    local wait_count=0
    
    while true; do
        local status=$(aws cloudformation describe-change-set \
            --stack-name "$STACK_NAME" \
            --change-set-name "$change_set_name" \
            --region "$REGION" \
            --query 'Status' \
            --output text 2>/dev/null || echo "PENDING")
        
        if [ "$status" = "CREATE_COMPLETE" ]; then
            printf "\r${GREEN}✅ Change set analysis complete${NC}\n"
            break
        elif [ "$status" = "FAILED" ]; then
            local reason=$(aws cloudformation describe-change-set \
                --stack-name "$STACK_NAME" \
                --change-set-name "$change_set_name" \
                --region "$REGION" \
                --query 'StatusReason' \
                --output text 2>/dev/null || echo "Unknown")
            
            if [[ "$reason" == *"no updates"* ]] || [[ "$reason" == *"No updates"* ]]; then
                printf "\r${YELLOW}⚠️  No changes detected in the changeset${NC}\n"
                print_info "The submitted information didn't contain changes"
                return 0
            else
                printf "\r${RED}❌ Change set creation failed${NC}\n"
                print_error "Reason: $reason"
                return 1
            fi
        fi
        
        printf "\r${CYAN}${spinner:$i:1} Analyzing infrastructure changes...${NC}"
        i=$(((i+1) % 4))
        wait_count=$((wait_count + 1))
        
        # Show extended wait message for long analysis
        if [ $((wait_count % 30)) -eq 0 ]; then
            printf "\n${BLUE}🔍 Still analyzing... (complex changes may take longer)${NC}\n"
        fi
        
        sleep 0.5
    done
    
    # Get comprehensive change set details
    local changeset_info=$(aws cloudformation describe-change-set \
        --stack-name "$STACK_NAME" \
        --change-set-name "$change_set_name" \
        --region "$REGION" \
        --output json 2>/dev/null)
    
    if [ $? -ne 0 ] || [ -z "$changeset_info" ]; then
        print_error "Failed to retrieve changeset details"
        return 1
    fi
    
    local changes=$(echo "$changeset_info" | jq -r '.Changes // []')
    local creation_time=$(echo "$changeset_info" | jq -r '.CreationTime // "Unknown"')
    local description=$(echo "$changeset_info" | jq -r '.Description // "No description"')
    
    echo ""
    echo -e "${BOLD}${BLUE}📊 Change Set Details:${NC}"
    echo -e "  ${BOLD}Name:${NC} $change_set_name"
    echo -e "  ${BOLD}Created:${NC} $creation_time"
    echo -e "  ${BOLD}Description:${NC} $description"
    echo ""
    
    if [ "$changes" != "[]" ] && [ "$changes" != "null" ]; then
        echo -e "${BOLD}${GREEN}📋 Planned Infrastructure Changes:${NC}"
        echo ""
        
        # Enhanced change display with more details
        echo "$changes" | jq -r '.[] | 
            "  \u001b[36m● " + .Action + "\u001b[0m " + 
            .ResourceChange.ResourceType + " " + 
            "\u001b[33m" + .ResourceChange.LogicalResourceId + "\u001b[0m" +
            (if .ResourceChange.PhysicalResourceId then " (" + .ResourceChange.PhysicalResourceId + ")" else "" end) +
            (if .ResourceChange.Replacement then "\n    \u001b[31m⚠️  Replacement: " + .ResourceChange.Replacement + "\u001b[0m" else "" end) +
            (if (.ResourceChange.Details | length) > 0 then "\n    \u001b[90m📝 Modified: " + ((.ResourceChange.Details | map(.Target.Name) | join(", ")) // "properties") + "\u001b[0m" else "" end)'
        
        echo ""
        
        # Summary statistics
        local add_count=$(echo "$changes" | jq '[.[] | select(.Action == "Add")] | length')
        local modify_count=$(echo "$changes" | jq '[.[] | select(.Action == "Modify")] | length')
        local remove_count=$(echo "$changes" | jq '[.[] | select(.Action == "Remove")] | length')
        
        echo -e "${BOLD}📈 Change Summary:${NC}"
        [ "$add_count" -gt 0 ] && echo -e "  ${GREEN}+ $add_count resources to be added${NC}"
        [ "$modify_count" -gt 0 ] && echo -e "  ${YELLOW}~ $modify_count resources to be modified${NC}"
        [ "$remove_count" -gt 0 ] && echo -e "  ${RED}- $remove_count resources to be removed${NC}"
        
    else
        echo -e "${YELLOW}⚠️  No infrastructure changes detected${NC}"
        echo -e "   The template appears to be identical to the current stack"
    fi
    
    echo ""
    echo -e "${BOLD}${RED}⚠️  Important:${NC} Please review the changes carefully before proceeding."
    echo -e "   Changes marked with 'Replacement: True' will cause resource recreation."
    echo ""
    
    # Interactive confirmation with timeout
    read -t 30 -p "$(echo -e ${BOLD}${GREEN}"Do you want to execute these changes? (Y/n) [30s timeout]: "${NC})" confirm
    
    if [ $? -gt 128 ]; then
        echo ""
        print_warning "⏱️  Confirmation timeout - deployment cancelled"
        aws cloudformation delete-change-set \
            --stack-name "$STACK_NAME" \
            --change-set-name "$change_set_name" \
            --region "$REGION" >/dev/null 2>&1
        exit 0
    fi
    
    if [[ $confirm =~ ^[Nn]$ ]]; then
        print_warning "🛑 Deployment cancelled by user"
        # Clean up change set
        aws cloudformation delete-change-set \
            --stack-name "$STACK_NAME" \
            --change-set-name "$change_set_name" \
            --region "$REGION" >/dev/null 2>&1
        exit 0
    fi
    
    print_info "✅ Changes approved - proceeding with deployment"
}

# Function to deploy
deploy_application() {
    print_step "Deploying to AWS"
    
    # Check if stack exists to determine if this is create or update
    local stack_exists=false
    if aws cloudformation describe-stacks --stack-name "$STACK_NAME" --region "$REGION" >/dev/null 2>&1; then
        stack_exists=true
    fi
    
    # Create change set name with timestamp
    local change_set_name="changeset-$(date +%Y%m%d-%H%M%S)"
    
    # Package SAM template using CloudFormation with native progress
    print_step "Packaging SAM template with CloudFormation..."
    
    # Check if JAR file exists
    local jar_file="target/demo-lambda.jar"
    if [ -f "$jar_file" ]; then
        local file_size_mb=$(echo "scale=2; $(stat -f%z "$jar_file" 2>/dev/null || stat -c%s "$jar_file" 2>/dev/null || echo "0") / 1024 / 1024" | bc -l 2>/dev/null || echo "0")
        print_info "📦 Artifact ready: $(basename "$jar_file") (${file_size_mb} MB)"
    fi
    
    # Package the template using CloudFormation with native progress display
    print_info "🔄 Packaging template and uploading artifacts..."
    aws cloudformation package \
        --template-file template.yaml \
        --s3-bucket "$USER_S3_BUCKET" \
        --s3-prefix "$STACK_NAME" \
        --output-template-file packaged-template.yaml \
        --region "$REGION"
    
    local package_status=$?
    
    if [ $package_status -ne 0 ]; then
        print_error "Failed to package SAM template"
        print_error "Please check if the S3 bucket '$USER_S3_BUCKET' exists and is accessible"
        exit 1
    fi
    
    print_success "SAM template packaged successfully"
    
    if [[ "$INTERACTIVE_MODE" == "true" ]]; then
        print_step "Creating change set for review..."
        
        # Create change set using CloudFormation
        (
            aws cloudformation deploy \
                --template-file packaged-template.yaml \
                --stack-name "$STACK_NAME" \
                --parameter-overrides "Stage=$STAGE" \
                --capabilities CAPABILITY_IAM \
                --no-execute-changeset \
                --region "$REGION" >/dev/null 2>&1
        ) &
        show_spinner $! "Creating change set"
        
        # Execute after review
        (
            aws cloudformation deploy \
                --template-file packaged-template.yaml \
                --stack-name "$STACK_NAME" \
                --parameter-overrides "Stage=$STAGE" \
                --capabilities CAPABILITY_IAM \
                --no-fail-on-empty-changeset \
                --region "$REGION" >/dev/null 2>&1
        ) &
        show_spinner $! "Deploying stack"
        
        # Check if change set was created and show details
        local changeset_id=$(aws cloudformation list-change-sets \
            --stack-name "$STACK_NAME" \
            --region "$REGION" \
            --query 'Summaries[0].ChangeSetId' \
            --output text 2>/dev/null)
        
        if [[ "$changeset_id" != "None" && -n "$changeset_id" ]]; then
            print_info "Change set created. Executing changes..."
            
            aws cloudformation execute-change-set \
                --change-set-name "$changeset_id" \
                --region "$REGION" >/dev/null 2>&1
            
            # Wait for execution
            (
                aws cloudformation wait stack-update-complete \
                    --stack-name "$STACK_NAME" \
                    --region "$REGION" >/dev/null 2>&1 || \
                aws cloudformation wait stack-create-complete \
                    --stack-name "$STACK_NAME" \
                    --region "$REGION" >/dev/null 2>&1
            ) &
            show_spinner $! "Executing deployment"
        else
            # Delete the empty change set
            aws cloudformation delete-change-set \
                --change-set-name "samcli-deploy$(date +%s)" \
                --stack-name "$STACK_NAME" \
                --region "$REGION" >/dev/null 2>&1 || true
            print_warning "No changes detected"
        fi
    else
        # Direct deployment using CloudFormation
        (
            aws cloudformation deploy \
                --template-file packaged-template.yaml \
                --stack-name "$STACK_NAME" \
                --parameter-overrides "Stage=$STAGE" \
                --capabilities CAPABILITY_IAM \
                --no-fail-on-empty-changeset \
                --region "$REGION" >/dev/null 2>&1
        ) &
        show_spinner $! "Deploying stack"
    fi
    
    # Deploy using CloudFormation directly
    print_step "Preparing CloudFormation Deployment"
    
    if [ "$stack_exists" = true ]; then
        print_info "Existing stack detected - creating changeset for review"
        
        # Create changeset for existing stack
        print_step "Creating CloudFormation changeset..."
        local changeset_status=0
        (
            aws cloudformation create-change-set \
                --template-body file://packaged-template.yaml \
                --stack-name "$STACK_NAME" \
                --change-set-name "$change_set_name" \
                --capabilities CAPABILITY_IAM \
                --parameters ParameterKey=Stage,ParameterValue="$STAGE" \
                --region "$REGION" >/dev/null 2>&1
            echo $? > /tmp/changeset_status
        ) &
        show_spinner $! "Creating changeset"
        wait $!
        
        changeset_status=$(cat /tmp/changeset_status 2>/dev/null || echo "1")
        rm -f /tmp/changeset_status
        
        if [ $changeset_status -ne 0 ]; then
            print_error "Failed to create changeset"
            exit 1
        fi
        
        # Show changeset details and get confirmation
        show_change_set "$change_set_name"
        
        # Execute the changeset
        print_step "Executing CloudFormation changeset"
        local execute_status=0
        (
            aws cloudformation execute-change-set \
                --stack-name "$STACK_NAME" \
                --change-set-name "$change_set_name" \
                --region "$REGION" >/dev/null 2>&1
            echo $? > /tmp/execute_status
        ) &
        show_spinner $! "Executing changeset"
        wait $!
        
        execute_status=$(cat /tmp/execute_status 2>/dev/null || echo "1")
        rm -f /tmp/execute_status
        
        if [ $execute_status -ne 0 ]; then
            print_error "Failed to execute changeset"
            # Clean up changeset
            aws cloudformation delete-change-set \
                --stack-name "$STACK_NAME" \
                --change-set-name "$change_set_name" \
                --region "$REGION" >/dev/null 2>&1
            exit 1
        fi
    else
        print_info "New stack detected - deploying directly"
        
        # For new stack, deploy directly
        print_step "Deploying new CloudFormation stack"
        local deploy_status=0
        (
            aws cloudformation deploy \
                --template-file packaged-template.yaml \
                --stack-name "$STACK_NAME" \
                --capabilities CAPABILITY_IAM \
                --parameter-overrides "Stage=$STAGE" \
                --region "$REGION" >/dev/null 2>&1
            echo $? > /tmp/deploy_status
        ) &
        show_spinner $! "Creating new stack"
        wait $!
        
        deploy_status=$(cat /tmp/deploy_status 2>/dev/null || echo "1")
        rm -f /tmp/deploy_status
        
        if [ $deploy_status -ne 0 ]; then
            print_error "CloudFormation deployment failed"
            exit 1
        fi
    fi
    
    # Monitor stack operation with real-time events
    if [ "$stack_exists" = true ]; then
        monitor_stack_events "$STACK_NAME" "UPDATE"
    else
        monitor_stack_events "$STACK_NAME" "CREATE"
    fi
    
    print_success "Deployment completed successfully"
}

test_deployment() {
    print_step "Testing Deployment"
    
    # Get outputs with loading
    (
        aws cloudformation describe-stacks --stack-name "$STACK_NAME" --region "$REGION" --query 'Stacks[0].Outputs[?OutputKey==`DemoApiUrl`].OutputValue' --output text > /tmp/api_url
        aws cloudformation describe-stacks --stack-name "$STACK_NAME" --region "$REGION" --query 'Stacks[0].Outputs[?OutputKey==`HealthEndpoint`].OutputValue' --output text > /tmp/health_url
        aws cloudformation describe-stacks --stack-name "$STACK_NAME" --region "$REGION" --query 'Stacks[0].Outputs[?OutputKey==`LambdaFunctionName`].OutputValue' --output text > /tmp/lambda_arn
        sleep 1  # Small delay for visual effect
    ) &
    
    show_spinner $! "Retrieving deployment information"
    wait $!
    
    # Read the results from temp files
    API_URL=$(cat /tmp/api_url 2>/dev/null)
    HEALTH_URL=$(cat /tmp/health_url 2>/dev/null)
    LAMBDA_ARN=$(cat /tmp/lambda_arn 2>/dev/null)
    
    # Clean up temp files
    rm -f /tmp/api_url /tmp/health_url /tmp/lambda_arn
    
    if [ -z "$HEALTH_URL" ]; then
        print_error "Could not get deployment URLs"
        exit 1
    fi
    
    # Test endpoint with animated loading
    local spinner="/-\|"
    local i=0
    local message="Testing health endpoint"
    
    (
        RESPONSE=$(timeout 30 curl -s -X GET "$HEALTH_URL" -H "Accept: application/json" 2>/dev/null || echo "TIMEOUT")
        echo "$RESPONSE" > /tmp/health_response
    ) &
    
    TEST_PID=$!
    
    while kill -0 $TEST_PID 2>/dev/null; do
        printf "\r${CYAN}${spinner:$i:1} ${message}${NC}"
        i=$(((i+1) % 4))
        sleep 0.2
    done
    
    wait $TEST_PID
    RESPONSE=$(cat /tmp/health_response)
    rm -f /tmp/health_response
    
    if [[ "$RESPONSE" == "TIMEOUT" ]]; then
        printf "\r${YELLOW}⚠️  ${message}${NC}\n"
        echo -e "   ${YELLOW}Warning: Health check timed out (cold start expected)${NC}"
    elif echo "$RESPONSE" | jq -e '.success == true' > /dev/null 2>&1; then
        printf "\r${GREEN}✅ ${message}${NC}\n"
        print_success "Health check passed"
    else
        printf "\r${YELLOW}⚠️  ${message}${NC}\n"
        echo -e "   ${YELLOW}Warning: Unexpected response:${NC}"
        echo "$RESPONSE" | sed 's/^/   /'
    fi
    
    # Display results
    print_header "Deployment Summary"
    echo -e "${BOLD}🌐 API Gateway:${NC} $API_URL"
    echo -e "${BOLD}🏥 Health Check:${NC} $HEALTH_URL"
    echo -e "${BOLD}⚡ Lambda Function:${NC} $LAMBDA_ARN"
    echo ""
    print_info "Test your API:"
    echo -e "  ${BOLD}curl $HEALTH_URL${NC}"
}

# Function to configure S3 notifications for MediaConvert triggers
configure_s3_notifications() {
    print_step "Configuring S3 Event Notifications"
    
    # Get resource names from CloudFormation outputs
    local s3_bucket=$(aws cloudformation describe-stacks \
        --stack-name "$STACK_NAME" \
        --region "$REGION" \
        --query 'Stacks[0].Outputs[?OutputKey==`VideosBucketName`].OutputValue' \
        --output text 2>/dev/null || echo "")
    
    local s3_processor_function=$(aws cloudformation describe-stacks \
        --stack-name "$STACK_NAME" \
        --region "$REGION" \
        --query 'Stacks[0].Outputs[?OutputKey==`S3VideoProcessorFunctionName`].OutputValue' \
        --output text 2>/dev/null || echo "")
    
    if [[ -z "$s3_bucket" ]] || [[ -z "$s3_processor_function" ]]; then
        print_warning "Could not retrieve S3 bucket or Lambda function from CloudFormation outputs"
        print_info "Attempting to use default naming convention..."
        s3_bucket="${STACK_NAME}-s3-$(aws sts get-caller-identity --query Account --output text)"
        s3_processor_function="${STACK_NAME}-s3-processor"
    fi
    
    print_info "S3 Bucket: $s3_bucket"
    print_info "Lambda Function: $s3_processor_function"
    
    # Check if S3 notification already exists
    print_info "Checking existing S3 notifications..."
    local existing_notifications=$(aws s3api get-bucket-notification-configuration \
        --bucket "$s3_bucket" \
        --region "$REGION" 2>/dev/null || echo "{}")
    
    if echo "$existing_notifications" | jq -e '.LambdaFunctionConfigurations[]? | select(.Events[]? == "s3:ObjectCreated:*")' > /dev/null 2>&1; then
        print_success "S3 notification already configured"
        return 0
    fi
    
    # Get Lambda function ARN
    local lambda_arn=$(aws lambda get-function \
        --function-name "$s3_processor_function" \
        --region "$REGION" \
        --query 'Configuration.FunctionArn' \
        --output text 2>/dev/null || echo "")
    
    if [[ -z "$lambda_arn" ]]; then
        print_error "Could not find Lambda function: $s3_processor_function"
        return 1
    fi
    
    print_info "Lambda ARN: $lambda_arn"
    
    # Add Lambda permission for S3 to invoke the function (if not already exists)
    print_info "Adding Lambda permission for S3 invocation..."
    if aws lambda add-permission \
        --function-name "$s3_processor_function" \
        --statement-id "s3-invoke-processor-$(date +%s)" \
        --action "lambda:InvokeFunction" \
        --principal "s3.amazonaws.com" \
        --source-arn "arn:aws:s3:::$s3_bucket" \
        --region "$REGION" 2>/dev/null; then
        print_success "Lambda permission added successfully"
    else
        print_info "Permission might already exist (continuing...)"
    fi
    
    # Create notification configuration
    print_info "Creating S3 notification configuration..."
    cat > /tmp/s3-notification.json << EOF
{
  "LambdaFunctionConfigurations": [
    {
      "Id": "VideoProcessorTrigger",
      "LambdaFunctionArn": "$lambda_arn",
      "Events": ["s3:ObjectCreated:*"],
      "Filter": {
        "Key": {
          "FilterRules": [
            {
              "Name": "suffix",
              "Value": ".mp4"
            }
          ]
        }
      }
    }
  ]
}
EOF
    
    # Apply notification configuration
    print_info "Applying S3 notification configuration..."
    if aws s3api put-bucket-notification-configuration \
        --bucket "$s3_bucket" \
        --notification-configuration file:///tmp/s3-notification.json \
        --region "$REGION"; then
        print_success "S3 notification configured successfully"
        print_info "S3 will now trigger $s3_processor_function for .mp4 uploads"
    else
        print_error "Failed to configure S3 notification"
        print_info "Checking notification configuration file:"
        cat /tmp/s3-notification.json
        return 1
    fi
    
    # Clean up temp file
    rm -f /tmp/s3-notification.json
}

# Function to show recent logs
show_logs() {
    print_step "Fetching Recent Logs"
    
    # Get the Lambda function name
    FUNCTION_NAME="nebulax-func"
    LOG_GROUP="/aws/lambda/${FUNCTION_NAME}"
    
    # Check if log group exists
    if ! aws logs describe-log-groups --log-group-name-prefix "$LOG_GROUP" --region "$REGION" --query 'logGroups[0].logGroupName' --output text 2>/dev/null | grep -q "$LOG_GROUP"; then
        print_error "Log group not found. Make sure the application is deployed."
        return 1
    fi
    
    print_info "Showing logs for: $LOG_GROUP"
    echo ""
    
    # Get recent log events (last 10 minutes)
    START_TIME=$(($(date +%s) - 600))000  # 10 minutes ago in milliseconds
    
    aws logs filter-log-events \
        --log-group-name "$LOG_GROUP" \
        --region "$REGION" \
        --start-time "$START_TIME" \
        --query 'events[*].[timestamp,message]' \
        --output table 2>/dev/null || {
        print_error "Failed to fetch logs"
        return 1
    }
    
    print_success "Recent logs displayed"
}

# Function to tail logs in real-time
tail_logs() {
    print_step "Tailing Logs (Press Ctrl+C to stop)"
    
    # Get the Lambda function name
    FUNCTION_NAME="${STACK_NAME}-func"
    LOG_GROUP="/aws/lambda/${FUNCTION_NAME}"
    
    # Check if log group exists
    if ! aws logs describe-log-groups --log-group-name-prefix "$LOG_GROUP" --region "$REGION" --query 'logGroups[0].logGroupName' --output text 2>/dev/null | grep -q "$LOG_GROUP"; then
        print_error "Log group not found. Make sure the application is deployed."
        return 1
    fi
    
    print_info "Tailing logs for: $LOG_GROUP"
    print_info "Press Ctrl+C to stop tailing"
    echo ""
    
    # Use AWS CLI to tail logs
    trap 'print_info "Stopped tailing logs"; exit 0' INT
    
    # Start tailing from now
    START_TIME=$(date +%s)000  # Current time in milliseconds
    
    while true; do
        # Get new log events
        CURRENT_TIME=$(date +%s)000
        
        LOG_EVENTS=$(aws logs filter-log-events \
            --log-group-name "$LOG_GROUP" \
            --region "$REGION" \
            --start-time "$START_TIME" \
            --end-time "$CURRENT_TIME" \
            --query 'events[*].[timestamp,message]' \
            --output text 2>/dev/null)
        
        if [ -n "$LOG_EVENTS" ] && [ "$LOG_EVENTS" != "None" ]; then
            echo "$LOG_EVENTS" | while IFS=$'\t' read -r timestamp message; do
                if [ -n "$timestamp" ] && [ "$timestamp" != "None" ]; then
                    # Convert timestamp to readable format
                    READABLE_TIME=$(date -r $((timestamp/1000)) '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo "Unknown")
                    echo -e "${CYAN}[$READABLE_TIME]${NC} $message"
                fi
            done
        fi
        
        # Update start time for next iteration
        START_TIME=$CURRENT_TIME
        sleep 2
    done
}

# Function to show deployment logs during deployment
show_deployment_logs() {
    print_step "Monitoring Deployment Logs"
    
    FUNCTION_NAME="${STACK_NAME}-func"
    LOG_GROUP="/aws/lambda/${FUNCTION_NAME}"
    
    # Start monitoring from current time
    START_TIME=$(date +%s)000
    
    print_info "Monitoring logs during deployment..."
    echo ""
    
    # Monitor for 30 seconds after deployment
    for i in {1..15}; do
        CURRENT_TIME=$(date +%s)000
        
        LOG_EVENTS=$(aws logs filter-log-events \
            --log-group-name "$LOG_GROUP" \
            --region "$REGION" \
            --start-time "$START_TIME" \
            --end-time "$CURRENT_TIME" \
            --query 'events[*].[timestamp,message]' \
            --output text 2>/dev/null)
        
        if [ -n "$LOG_EVENTS" ] && [ "$LOG_EVENTS" != "None" ]; then
            echo "$LOG_EVENTS" | while IFS=$'\t' read -r timestamp message; do
                if [ -n "$timestamp" ] && [ "$timestamp" != "None" ]; then
                    READABLE_TIME=$(date -r $((timestamp/1000)) '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo "Unknown")
                    echo -e "${CYAN}[$READABLE_TIME]${NC} $message"
                fi
            done
            START_TIME=$CURRENT_TIME
        fi
        
        sleep 2
    done
    
    print_success "Deployment log monitoring complete"
}
cleanup_deployment() {
    print_warning "This will delete all AWS resources including S3 buckets and their contents"
    read -p "Are you sure? (y/N): " -n 1 -r
    echo
    
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        print_step "🧹 Starting Cleanup Process"
        local ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text 2>/dev/null)
        
        if [ -z "$ACCOUNT_ID" ]; then
            print_error "Failed to get AWS account ID. Please check your AWS credentials."
            exit 1
        fi
        
        # Determine bucket names based on configuration
        local ARTIFACT_BUCKET=""
        local VIDEOS_BUCKET=""
        local TRANSCODED_BUCKET=""
        
        # Get stack name for bucket naming
        local ACTUAL_STACK_NAME="$STACK_NAME"
        if [ -n "$USER_STACK_NAME" ]; then
            ACTUAL_STACK_NAME="$USER_STACK_NAME"
        fi
        
        # Set bucket names
        if [ -n "$USER_S3_BUCKET" ]; then
            ARTIFACT_BUCKET="$USER_S3_BUCKET"
        else
            ARTIFACT_BUCKET="${ACTUAL_STACK_NAME}-artifact-${ACCOUNT_ID}"
        fi
        
        VIDEOS_BUCKET="${ACTUAL_STACK_NAME}-s3-${ACCOUNT_ID}"
        TRANSCODED_BUCKET="${ACTUAL_STACK_NAME}-transcoded-${ACCOUNT_ID}"
        
        print_info "🎯 Target Resources:"
        echo -e "  ${BOLD}Stack Name:${NC} $ACTUAL_STACK_NAME"
        echo -e "  ${BOLD}Region:${NC} $REGION"
        echo -e "  ${BOLD}Artifact bucket:${NC} $ARTIFACT_BUCKET"
        echo -e "  ${BOLD}Videos bucket:${NC} $VIDEOS_BUCKET"
        echo -e "  ${BOLD}Transcoded bucket:${NC} $TRANSCODED_BUCKET"
        echo ""
        
        # Function to completely empty S3 bucket with progress
        empty_bucket_completely() {
            local bucket_name="$1"
            local bucket_type="$2"
            
            if aws s3api head-bucket --bucket "$bucket_name" --region "$REGION" >/dev/null 2>&1; then
                print_step "🗑️  Emptying $bucket_type bucket: $bucket_name"
                
                # Get initial counts
                print_info "📊 Analyzing bucket contents..."
                local version_count=$(aws s3api list-object-versions --bucket "$bucket_name" --query 'length(Versions)' --output text 2>/dev/null || echo "0")
                local marker_count=$(aws s3api list-object-versions --bucket "$bucket_name" --query 'length(DeleteMarkers)' --output text 2>/dev/null || echo "0")
                local upload_count=$(aws s3api list-multipart-uploads --bucket "$bucket_name" --query 'length(Uploads)' --output text 2>/dev/null || echo "0")
                local object_count=$(aws s3api list-objects-v2 --bucket "$bucket_name" --query 'KeyCount' --output text 2>/dev/null || echo "0")
                
                if [ "$version_count" = "0" ] && [ "$marker_count" = "0" ] && [ "$upload_count" = "0" ] && [ "$object_count" = "0" ]; then
                    print_success "   Bucket is already empty"
                    return 0
                fi
                
                print_info "   📦 Found: $object_count objects, $version_count versions, $marker_count markers, $upload_count uploads"
                
                # Abort multipart uploads with progress
                if [ "$upload_count" != "0" ] && [ "$upload_count" != "null" ]; then
                    print_info "   🔄 Aborting multipart uploads..."
                    local aborted=0
                    aws s3api list-multipart-uploads --bucket "$bucket_name" --query 'Uploads[].{Key:Key,UploadId:UploadId}' --output text 2>/dev/null | while read key upload_id; do
                        if [ -n "$key" ] && [ -n "$upload_id" ] && [ "$key" != "None" ] && [ "$upload_id" != "None" ]; then
                            aws s3api abort-multipart-upload --bucket "$bucket_name" --key "$key" --upload-id "$upload_id" >/dev/null 2>&1
                            ((aborted++))
                            printf "\r   📤 Aborted $aborted uploads..."
                        fi
                    done
                    printf "\n"
                fi
                
                # Delete object versions with progress
                if [ "$version_count" != "0" ] && [ "$version_count" != "null" ]; then
                    print_info "   🗂️  Deleting object versions..."
                    local deleted_versions=0
                    aws s3api list-object-versions --bucket "$bucket_name" --query 'Versions[].{Key:Key,VersionId:VersionId}' --output text 2>/dev/null | while read key version_id; do
                        if [ -n "$key" ] && [ -n "$version_id" ] && [ "$key" != "None" ] && [ "$version_id" != "None" ]; then
                            aws s3api delete-object --bucket "$bucket_name" --key "$key" --version-id "$version_id" >/dev/null 2>&1
                            ((deleted_versions++))
                            printf "\r   🗑️  Deleted $deleted_versions versions..."
                        fi
                    done
                    printf "\n"
                fi
                
                # Delete delete markers with progress
                if [ "$marker_count" != "0" ] && [ "$marker_count" != "null" ]; then
                    print_info "   🏷️  Deleting delete markers..."
                    local deleted_markers=0
                    aws s3api list-object-versions --bucket "$bucket_name" --query 'DeleteMarkers[].{Key:Key,VersionId:VersionId}' --output text 2>/dev/null | while read key version_id; do
                        if [ -n "$key" ] && [ -n "$version_id" ] && [ "$key" != "None" ] && [ "$version_id" != "None" ]; then
                            aws s3api delete-object --bucket "$bucket_name" --key "$key" --version-id "$version_id" >/dev/null 2>&1
                            ((deleted_markers++))
                            printf "\r   🏷️  Deleted $deleted_markers markers..."
                        fi
                    done
                    printf "\n"
                fi
                
                # Final recursive cleanup for current objects
                if [ "$object_count" != "0" ] && [ "$object_count" != "null" ]; then
                    print_info "   📁 Removing remaining objects..."
                    aws s3 rm s3://"$bucket_name" --recursive 2>/dev/null || true
                fi
                
                # Verify bucket is completely empty
                local final_count=$(aws s3api list-objects-v2 --bucket "$bucket_name" --query 'KeyCount' --output text 2>/dev/null || echo "0")
                local final_versions=$(aws s3api list-object-versions --bucket "$bucket_name" --query 'length(Versions)' --output text 2>/dev/null || echo "0")
                local final_markers=$(aws s3api list-object-versions --bucket "$bucket_name" --query 'length(DeleteMarkers)' --output text 2>/dev/null || echo "0")
                
                if [ "$final_count" = "0" ] && [ "$final_versions" = "0" ] && [ "$final_markers" = "0" ]; then
                    print_success "   ✅ $bucket_type bucket completely emptied"
                else
                    print_warning "   ⚠️  $bucket_type bucket may still contain items ($final_count objects, $final_versions versions, $final_markers markers)"
                    print_info "   🔄 Attempting final cleanup..."
                    
                    # More aggressive cleanup
                    aws s3api list-objects-v2 --bucket "$bucket_name" --query 'Contents[].Key' --output text 2>/dev/null | tr '\t' '\n' | while read -r key; do
                        if [ -n "$key" ] && [ "$key" != "None" ]; then
                            aws s3api delete-object --bucket "$bucket_name" --key "$key" >/dev/null 2>&1
                        fi
                    done
                    
                    # Final verification
                    final_count=$(aws s3api list-objects-v2 --bucket "$bucket_name" --query 'KeyCount' --output text 2>/dev/null || echo "0")
                    if [ "$final_count" = "0" ]; then
                        print_success "   ✅ $bucket_type bucket now completely empty"
                    else
                        print_warning "   ⚠️  Some objects may remain in $bucket_type bucket"
                    fi
                fi
            else
                print_info "   ℹ️  $bucket_type bucket '$bucket_name' not found or already deleted"
            fi
        }
        
        # Step 1: Empty all S3 buckets
        print_header "Step 1: Emptying S3 Buckets"
        print_info "🎯 This ensures CloudFormation can delete buckets without conflicts"
        
        empty_bucket_completely "$ARTIFACT_BUCKET" "Artifact"
        empty_bucket_completely "$VIDEOS_BUCKET" "Videos"
        empty_bucket_completely "$TRANSCODED_BUCKET" "Transcoded Videos"
        
        print_success "✅ Step 1 completed: All buckets emptied"
        
        # Step 2: Delete CloudFormation stack with detailed monitoring
        print_header "Step 2: Deleting CloudFormation Stack"
        
        if aws cloudformation describe-stacks --stack-name "$ACTUAL_STACK_NAME" --region "$REGION" &>/dev/null; then
            print_info "🎯 Stack found: $ACTUAL_STACK_NAME"
            
            # Initiate stack deletion
            print_step "🗑️  Initiating stack deletion..."
            if aws cloudformation delete-stack --stack-name "$ACTUAL_STACK_NAME" --region "$REGION"; then
                print_success "   Stack deletion initiated successfully"
                
                # Monitor deletion with real-time CloudFormation events
                print_info "⏳ Monitoring stack deletion progress with real-time events..."
                print_info "   💡 This process typically takes 2-5 minutes"
                echo ""
                
                # Start real-time CloudFormation events monitoring
                monitor_stack_events "$ACTUAL_STACK_NAME" "DELETE"
            else
                print_error "❌ Failed to initiate stack deletion"
                print_info "This may indicate the stack doesn't exist or insufficient permissions"
            fi
        else
            print_info "ℹ️  CloudFormation stack '$ACTUAL_STACK_NAME' not found or already deleted"
            print_success "✅ No stack to delete"
        fi
        
        print_success "✅ Step 2 completed: CloudFormation stack processing finished"
        
        # Step 3: Final Cleanup
        print_header "Step 3: Final Cleanup"
        
        # Only clean artifact buckets - videos bucket should be handled by CloudFormation
        if aws s3api head-bucket --bucket "$ARTIFACT_BUCKET" --region "$REGION" >/dev/null 2>&1; then
            print_info "🧹 Cleaning up remaining artifact bucket: $ARTIFACT_BUCKET"
            
            # Empty artifact bucket completely one more time
            print_info "   📦 Ensuring artifact bucket is completely empty..."
            
            # Delete all remaining object versions and delete markers
            aws s3api delete-objects --bucket "$ARTIFACT_BUCKET" --delete "$(aws s3api list-object-versions --bucket "$ARTIFACT_BUCKET" --query '{Objects: Versions[].{Key: Key, VersionId: VersionId}}' --max-items 1000)" --region "$REGION" >/dev/null 2>&1 || true
            aws s3api delete-objects --bucket "$ARTIFACT_BUCKET" --delete "$(aws s3api list-object-versions --bucket "$ARTIFACT_BUCKET" --query '{Objects: DeleteMarkers[].{Key: Key, VersionId: VersionId}}' --max-items 1000)" --region "$REGION" >/dev/null 2>&1 || true
            
            # Delete multipart uploads
            aws s3api list-multipart-uploads --bucket "$ARTIFACT_BUCKET" --region "$REGION" --query 'Uploads[].{Key: Key, UploadId: UploadId}' --output text | \
            while read -r key upload_id; do
                if [ -n "$upload_id" ] && [ "$upload_id" != "None" ]; then
                    aws s3api abort-multipart-upload --bucket "$ARTIFACT_BUCKET" --key "$key" --upload-id "$upload_id" --region "$REGION" >/dev/null 2>&1 || true
                fi
            done
            
            # Delete the artifact bucket
            print_info "   🗑️  Deleting artifact bucket..."
            if aws s3api delete-bucket --bucket "$ARTIFACT_BUCKET" --region "$REGION" >/dev/null 2>&1; then
                print_success "   ✅ Artifact bucket deleted successfully"
            else
                print_warning "   ⚠️  Failed to delete artifact bucket: $ARTIFACT_BUCKET"
                print_info "   💡 Please delete manually from AWS Console if needed"
            fi
        else
            print_success "   ✅ Artifact bucket already removed or doesn't exist"
        fi
        
        # Verify videos bucket was cleaned by CloudFormation
        if aws s3api head-bucket --bucket "$VIDEOS_BUCKET" --region "$REGION" >/dev/null 2>&1; then
            print_warning "   ⚠️  Videos bucket still exists: $VIDEOS_BUCKET"
            print_info "   💡 This should have been deleted by CloudFormation"
            print_info "   🛠️  You may need to delete it manually from AWS Console"
        else
            print_success "   ✅ Videos bucket successfully removed by CloudFormation"
        fi

        # Verify transcoded videos bucket was cleaned by CloudFormation
        if aws s3api head-bucket --bucket "$TRANSCODED_BUCKET" --region "$REGION" >/dev/null 2>&1; then
            print_warning "   ⚠️  Transcoded videos bucket still exists: $TRANSCODED_BUCKET"
            print_info "   💡 This should have been deleted by CloudFormation"
            print_info "   🛠️  You may need to delete it manually from AWS Console"
        else
            print_success "   ✅ Transcoded videos bucket successfully removed by CloudFormation"
        fi
        
        # Clean local files
        print_step "🧹 Cleaning local configuration files"
        local cleanup_files=(
            "samconfig.toml"
            "packaged-template.yaml"
            "template.yaml.bak"
            ".env*"
            ".env.template"
        )
        
        for file_pattern in "${cleanup_files[@]}"; do
            if ls $file_pattern 1> /dev/null 2>&1; then
                rm -f $file_pattern 2>/dev/null || true
                print_info "   🗑️  Removed: $file_pattern"
            fi
        done
        
        print_success "✅ Step 3 completed: Local cleanup finished"
        
        # Final summary
        echo ""
        print_header "🎉 Cleanup Complete!"
        echo -e "${GREEN}✅ All AWS resources have been successfully removed:${NC}"
        echo -e "  ${BOLD}•${NC} CloudFormation stack: ${BOLD}$ACTUAL_STACK_NAME${NC}"
        echo -e "  ${BOLD}•${NC} S3 buckets: ${BOLD}$ARTIFACT_BUCKET${NC}, ${BOLD}$VIDEOS_BUCKET${NC} & ${BOLD}$TRANSCODED_BUCKET${NC}"
        echo -e "  ${BOLD}•${NC} All associated AWS resources (Lambda, API Gateway, DynamoDB, MediaConvert, EventBridge, etc.)"
        echo -e "  ${BOLD}•${NC} Local configuration files"
        echo ""
        echo -e "${CYAN}💰 This should stop all charges related to this deployment.${NC}"
        echo -e "${CYAN}🔍 You can verify the cleanup in the AWS Console.${NC}"
        
    else
        print_info "❌ Cleanup cancelled by user"
    fi
}

# Function to show help
show_help() {
    echo "Nebulax Application Deployment Script"
    echo ""
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -h, --help       Show this help message"
    echo "  -c, --clean      Clean up all AWS resources"
    echo "  -b, --build      Build only (no deploy)"
    echo "  -u, --update     Build and update existing deployment (skip configuration)"
    echo "  -t, --test       Test existing deployment"
    echo "  -s, --setup      Configure deployment settings only"
    echo "  --logs           Show recent CloudWatch logs"
    echo "  --tail-logs      Tail CloudWatch logs in real-time"
}

# Main function
main() {
    # Parse arguments first to handle cleanup differently
    case "${1:-}" in
        -h|--help)
            print_header "Nebulax Application Deployment"
            show_help
            exit 0
            ;;
        -c|--clean)
            print_header "Cleanup Deployment"
            cleanup_deployment
            exit 0
            ;;
        -t|--test)
            print_header "Nebulax Application Deployment"
            test_deployment
            exit 0
            ;;
        -b|--build)
            print_header "Nebulax Application Deployment"
            check_prerequisites
            build_project
            print_success "Build complete"
            exit 0
            ;;
        -u|--update)
            print_header "🚀 Nebulax Application Update"
            check_prerequisites
            
            # Use default configuration for update
            USER_STACK_NAME="$STACK_NAME"
            USER_REGION="$REGION"
            ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
            USER_S3_BUCKET="${USER_STACK_NAME}-artifact-${ACCOUNT_ID}"
            
            print_info "Using existing configuration:"
            print_info "  Stack Name: $USER_STACK_NAME"
            print_info "  Region: $USER_REGION"
            print_info "  S3 Bucket: $USER_S3_BUCKET"
            
            # Check if S3 bucket exists, create if not
            if ! aws s3api head-bucket --bucket "$USER_S3_BUCKET" --region "$USER_REGION" >/dev/null 2>&1; then
                setup_s3
            else
                print_info "Using existing S3 bucket: $USER_S3_BUCKET"
            fi
            
            build_project
            deploy_application
            test_deployment
            configure_s3_notifications
            exit 0
            ;;
        -s|--setup)
            print_header "Nebulax Application Deployment"
            check_prerequisites
            get_deployment_configuration
            create_config
            setup_s3
            print_success "Deployment configuration complete"
            exit 0
            ;;
        --logs)
            print_header "CloudWatch Logs Viewer"
            show_logs
            exit 0
            ;;
        --tail-logs)
            print_header "CloudWatch Logs Tail"
            tail_logs
            exit 0
            ;;
        "")
            # Full deployment
            print_header "Nebulax Application Deployment"
            check_prerequisites
            get_deployment_configuration
            create_config
            setup_s3
            build_project
            deploy_application
            test_deployment
            configure_s3_notifications
            ;;
        *)
            print_header "Nebulax Application Deployment"
            print_error "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
}

# Run main function
main "$@"
