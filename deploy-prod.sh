#!/bin/bash

# Spring Boot Serverless Player Application Deployment Script
# Complete deployment for AWS Lambda with API Gateway, DynamoDB, and S3

set -e  # Exit on any error

# Configuration
PROJECT_NAME="player-app"
STACK_NAME="player-app"
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
    
    # Package SAM template using CloudFormation with progress
    print_step "Packaging SAM template with CloudFormation..."
    
    # Show progress for packaging
    local jar_file="target/demo-lambda.jar"
    if [ -f "$jar_file" ]; then
        show_s3_upload_progress "$jar_file" "s3://$USER_S3_BUCKET/$STACK_NAME/"
    fi
    
    # Package the template using CloudFormation (works with SAM templates)
    (
        aws cloudformation package \
            --template-file template.yaml \
            --s3-bucket "$USER_S3_BUCKET" \
            --s3-prefix "$STACK_NAME" \
            --output-template-file packaged-template.yaml \
            --region "$REGION" >/dev/null 2>&1
    ) &
    show_spinner $! "Packaging SAM template"
    
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
        (
            aws cloudformation create-change-set \
                --template-body file://packaged-template.yaml \
                --stack-name "$STACK_NAME" \
                --change-set-name "$change_set_name" \
                --capabilities CAPABILITY_IAM \
                --parameters ParameterKey=Stage,ParameterValue="$STAGE" \
                --region "$REGION" >/dev/null 2>&1
        ) &
        show_spinner $! "Creating changeset"
        
        if [ $? -ne 0 ]; then
            print_error "Failed to create changeset"
            exit 1
        fi
        
        # Show changeset details and get confirmation
        show_change_set "$change_set_name"
        
        # Execute the changeset
        print_step "Executing CloudFormation changeset"
        (
            aws cloudformation execute-change-set \
                --stack-name "$STACK_NAME" \
                --change-set-name "$change_set_name" \
                --region "$REGION" >/dev/null 2>&1
        ) &
        show_spinner $! "Executing changeset"
        
        if [ $? -ne 0 ]; then
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
        (
            aws cloudformation deploy \
                --template-file packaged-template.yaml \
                --stack-name "$STACK_NAME" \
                --capabilities CAPABILITY_IAM \
                --parameter-overrides "Stage=$STAGE" \
                --region "$REGION" >/dev/null 2>&1
        ) &
        show_spinner $! "Creating new stack"
        
        if [ $? -ne 0 ]; then
            print_error "CloudFormation deployment failed"
            exit 1
        fi
    fi
    
    # Monitor stack operation progress with enhanced status reporting
    print_step "Monitoring Stack Operation Progress"
    
    local operation_status=""
    local spinner="/-\|"
    local i=0
    local status_count=0
    local last_status=""
    
    # Enhanced progress tracking
    while true; do
        operation_status=$(aws cloudformation describe-stacks \
            --stack-name "$STACK_NAME" \
            --region "$REGION" \
            --query 'Stacks[0].StackStatus' \
            --output text 2>/dev/null || echo "UNKNOWN")
        
        # Show status change notifications
        if [ "$operation_status" != "$last_status" ] && [ -n "$last_status" ]; then
            printf "\n${BLUE}📍 Status changed: ${last_status} → ${operation_status}${NC}\n"
        fi
        last_status="$operation_status"
        
        case "$operation_status" in
            CREATE_COMPLETE|UPDATE_COMPLETE)
                printf "\r${GREEN}✅ Stack operation completed successfully${NC}\n"
                
                # Show completion summary
                echo ""
                print_success "🎉 CloudFormation Stack Operation Summary:"
                echo -e "  ${BOLD}Stack Name:${NC} $STACK_NAME"
                echo -e "  ${BOLD}Region:${NC} $REGION"
                echo -e "  ${BOLD}Final Status:${NC} ${GREEN}$operation_status${NC}"
                echo -e "  ${BOLD}Completion Time:${NC} $(date)"
                break
                ;;
            CREATE_FAILED|UPDATE_FAILED|ROLLBACK_COMPLETE|UPDATE_ROLLBACK_COMPLETE)
                printf "\r${RED}❌ Stack operation failed${NC}\n"
                
                # Get stack events for failure details
                print_error "CloudFormation operation failed with status: $operation_status"
                print_info "Recent stack events:"
                aws cloudformation describe-stack-events \
                    --stack-name "$STACK_NAME" \
                    --region "$REGION" \
                    --query 'StackEvents[0:5].[Timestamp,LogicalResourceId,ResourceStatus,ResourceStatusReason]' \
                    --output table 2>/dev/null || echo "Could not retrieve stack events"
                exit 1
                ;;
            CREATE_IN_PROGRESS)
                printf "\r${CYAN}${spinner:$i:1} Creating stack resources... (${operation_status})${NC}"
                i=$(((i+1) % 4))
                status_count=$((status_count + 1))
                
                # Show periodic progress updates for long operations
                if [ $((status_count % 30)) -eq 0 ]; then
                    printf "\n${BLUE}📊 Still creating... (${status_count} checks completed)${NC}\n"
                fi
                sleep 2
                ;;
            UPDATE_IN_PROGRESS)
                printf "\r${CYAN}${spinner:$i:1} Updating stack resources... (${operation_status})${NC}"
                i=$(((i+1) % 4))
                status_count=$((status_count + 1))
                
                # Show periodic progress updates for long operations
                if [ $((status_count % 30)) -eq 0 ]; then
                    printf "\n${BLUE}📊 Still updating... (${status_count} checks completed)${NC}\n"
                fi
                sleep 2
                ;;
            UPDATE_ROLLBACK_IN_PROGRESS)
                printf "\r${YELLOW}${spinner:$i:1} Rolling back changes... (${operation_status})${NC}"
                i=$(((i+1) % 4))
                sleep 2
                ;;
            *)
                printf "\r${YELLOW}${spinner:$i:1} Waiting for stack operation... (${operation_status})${NC}"
                i=$(((i+1) % 4))
                sleep 2
                ;;
        esac
    done
    
    print_success "Deployment completed successfully"
}

# Function to get outputs and test
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

# Function to show recent logs
show_logs() {
    print_step "Fetching Recent Logs"
    
    # Get the Lambda function name
    FUNCTION_NAME="player-app-func"
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
    print_warning "This will delete all AWS resources"
    read -p "Are you sure? (y/N): " -n 1 -r
    echo
    
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        print_step "Deleting Resources"
        
        # Delete CloudFormation stack with loading animation
        if aws cloudformation describe-stacks --stack-name "$STACK_NAME" --region "$REGION" &>/dev/null; then
            (
                aws cloudformation delete-stack --stack-name "$STACK_NAME" --region "$REGION" 2>/dev/null || true
                aws cloudformation wait stack-delete-complete --stack-name "$STACK_NAME" --region "$REGION" 2>/dev/null || true
                sleep 2  # Simulate processing time
            ) &
            show_spinner $! "Deleting CloudFormation stack"
            wait $!
        fi
        
        # Delete S3 buckets with contents
        ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
        
        # Artifact bucket
        if [ -n "$USER_S3_BUCKET" ]; then
            ARTIFACT_BUCKET="$USER_S3_BUCKET"
        else
            ARTIFACT_BUCKET="${STACK_NAME}-artifact-${ACCOUNT_ID}"
        fi
        
        # Videos bucket
        if [ -n "$USER_STACK_NAME" ]; then
            VIDEOS_BUCKET="${USER_STACK_NAME}-s3-${ACCOUNT_ID}"
        else
            VIDEOS_BUCKET="${STACK_NAME}-s3-${ACCOUNT_ID}"
        fi
        
        # Delete artifact bucket
        if aws s3api head-bucket --bucket "$ARTIFACT_BUCKET" >/dev/null 2>&1; then
            (
                # Empty bucket first
                aws s3 rm s3://"$ARTIFACT_BUCKET" --recursive --quiet 2>/dev/null || true
                sleep 1
                # Delete bucket
                aws s3api delete-bucket --bucket "$ARTIFACT_BUCKET" --region "$REGION" 2>/dev/null || true
                sleep 1
            ) &
            show_spinner $! "Deleting artifact S3 bucket and contents"
            wait $!
        fi
        
        # Delete videos bucket
        if aws s3api head-bucket --bucket "$VIDEOS_BUCKET" >/dev/null 2>&1; then
            (
                # Empty bucket first
                aws s3 rm s3://"$VIDEOS_BUCKET" --recursive --quiet 2>/dev/null || true
                sleep 1
                # Delete bucket
                aws s3api delete-bucket --bucket "$VIDEOS_BUCKET" --region "$REGION" 2>/dev/null || true
                sleep 1
            ) &
            show_spinner $! "Deleting videos S3 bucket and contents"
            wait $!
        fi
        
        # Clean local files with loading
        (
            rm -f samconfig.toml 2>/dev/null || true
            rm -f packaged-template.yaml 2>/dev/null || true
            rm -f template.yaml.bak 2>/dev/null || true
            rm -f .env* 2>/dev/null || true
            rm -f .env.template 2>/dev/null || true
            sleep 0.5
        ) &
        show_spinner $! "Cleaning local configuration files"
        wait $!
        
        print_success "Cleanup complete - All resources deleted"
    else
        print_info "Cleanup cancelled"
    fi
}

# Function to show help
show_help() {
    echo "Spring Boot Player Application Deployment Script"
    echo ""
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -h, --help       Show this help message"
    echo "  -c, --clean      Clean up all AWS resources"
    echo "  -b, --build      Build only (no deploy)"
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
            print_header "Spring Boot Player Application Deployment"
            show_help
            exit 0
            ;;
        -c|--clean)
            print_header "Cleanup Deployment"
            cleanup_deployment
            exit 0
            ;;
        -t|--test)
            print_header "Spring Boot Player Application Deployment"
            test_deployment
            exit 0
            ;;
        -b|--build)
            print_header "Spring Boot Player Application Deployment"
            check_prerequisites
            build_project
            print_success "Build complete"
            exit 0
            ;;
        -s|--setup)
            print_header "Spring Boot Player Application Deployment"
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
            print_header "Spring Boot Player Application Deployment"
            check_prerequisites
            get_deployment_configuration
            create_config
            setup_s3
            build_project
            deploy_application
            test_deployment
            ;;
        *)
            print_header "Spring Boot Player Application Deployment"
            print_error "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
}

# Run main function
main "$@"
