#!/bin/bash

# Local Development Setup Script for Nebulax Video Processing System
# This script sets up and runs the application locally with DynamoDB Local and LocalStack

# Remove set -e to handle errors more gracefully
# set -e  # Exit on any error

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

# Function to handle errors gracefully
handle_error() {
    local exit_code=$1
    local command="$2"
    local line_number=$3
    
    print_error "Command failed: $command (exit code: $exit_code, line: $line_number)"
    print_error "Error occurred in local-dev.sh"
    
    # Show detailed error information
    if [ $exit_code -ne 0 ]; then
        print_warning "Attempting to diagnose the issue..."
        
        # Check if Docker is running
        if ! docker info >/dev/null 2>&1; then
            print_error "Docker is not running. Please start Docker Desktop and try again."
            return 1
        fi
        
        # Check for port conflicts
        check_port_conflicts
        
        # Show container status if any exist
        if docker ps -a --format "table {{.Names}}\t{{.Status}}" | grep -E "(dynamodb-local|localstack|dynamodb-admin)" >/dev/null 2>&1; then
            print_info "Current container status:"
            docker ps -a --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" --filter "name=dynamodb-local" --filter "name=localstack" --filter "name=dynamodb-admin"
        fi
    fi
    
    return $exit_code
}

# Function to check for port conflicts
check_port_conflicts() {
    print_step "Checking for port conflicts"
    
    local ports=(8000 8001 4566 8080)
    local conflicts=false
    
    for port in "${ports[@]}"; do
        if lsof -i :$port >/dev/null 2>&1; then
            local process=$(lsof -i :$port -t | head -1)
            if [ ! -z "$process" ]; then
                local process_name=$(ps -p $process -o comm= 2>/dev/null || echo "Unknown")
                print_warning "Port $port is already in use by process: $process_name (PID: $process)"
                conflicts=true
            fi
        fi
    done
    
    if [ "$conflicts" = true ]; then
        print_error "Port conflicts detected. Please stop conflicting services or use different ports."
        print_info "You can stop all related containers with: docker compose down"
    else
        print_success "No port conflicts detected"
    fi
}

# Function to check prerequisites
check_prerequisites() {
    print_step "Checking Prerequisites"
    local missing_deps=false
    
    # Check Docker
    if ! command -v docker &> /dev/null; then
        print_error "Docker is required but not installed"
        print_info "Please install Docker Desktop: https://www.docker.com/products/docker-desktop"
        missing_deps=true
    else
        print_success "Docker found: $(docker --version | cut -d' ' -f3 | cut -d',' -f1)"
        
        # Check if Docker is running
        if ! docker info >/dev/null 2>&1; then
            print_error "Docker is installed but not running"
            print_info "Please start Docker Desktop and try again"
            missing_deps=true
        else
            print_success "Docker is running"
        fi
    fi
    
    # Check Docker Compose
    local compose_cmd=""
    if docker compose version &> /dev/null; then
        compose_cmd="docker compose"
        print_success "Docker Compose (v2) found: $(docker compose version --short)"
    elif docker-compose --version &> /dev/null; then
        compose_cmd="docker-compose"
        print_success "Docker Compose (v1) found: $(docker-compose --version | cut -d' ' -f3 | cut -d',' -f1)"
    else
        print_error "Docker Compose is required but not installed"
        print_info "Please install Docker Compose or use Docker Desktop which includes it"
        missing_deps=true
    fi
    
    # Check Java
    if ! command -v java &> /dev/null; then
        print_error "Java is required but not installed"
        print_info "Please install Java 17 or later: https://adoptium.net/"
        missing_deps=true
    else
        local java_version=$(java -version 2>&1 | head -1 | cut -d'"' -f2)
        print_success "Java found: $java_version"
    fi
    
    # Check Maven
    if ! command -v mvn &> /dev/null; then
        print_error "Maven is required but not installed"
        print_info "Please install Maven: https://maven.apache.org/install.html"
        missing_deps=true
    else
        local mvn_version=$(mvn -version | head -1 | cut -d' ' -f3)
        print_success "Maven found: $mvn_version"
    fi
    
    # Check curl (needed for health checks)
    if ! command -v curl &> /dev/null; then
        print_error "curl is required but not installed"
        print_info "Please install curl"
        missing_deps=true
    else
        print_success "curl found"
    fi
    
    # Check AWS CLI (needed for LocalStack setup)
    if ! command -v aws &> /dev/null; then
        print_warning "AWS CLI not found - LocalStack S3 bucket initialization will be skipped"
        print_info "Install AWS CLI for full functionality: https://aws.amazon.com/cli/"
    else
        local aws_version=$(aws --version 2>&1 | cut -d' ' -f1 | cut -d'/' -f2)
        print_success "AWS CLI found: $aws_version"
    fi
    
    if [ "$missing_deps" = true ]; then
        print_error "Missing required dependencies. Please install them and try again."
        exit 1
    fi
    
    print_success "All prerequisites met"
}

# Function to start local services
start_local_services() {
    print_step "Starting Local AWS Services"
    
    # Create directories for persistent data
    print_info "Creating data directories..."
    if ! mkdir -p docker/dynamodb docker/localstack 2>/dev/null; then
        print_error "Failed to create data directories"
        return 1
    fi
    print_success "Data directories created"
    
    # Check for port conflicts before starting
    check_port_conflicts
    
    # Determine which compose command to use
    local compose_cmd=""
    if docker compose version &> /dev/null; then
        compose_cmd="docker compose"
    else
        compose_cmd="docker-compose"
    fi
    
    # Stop any existing containers first
    print_info "Stopping any existing containers..."
    $compose_cmd down --remove-orphans >/dev/null 2>&1 || true
    
    # Start Docker services
    print_info "Starting Docker services..."
    if ! $compose_cmd up -d; then
        print_error "Failed to start Docker services"
        print_info "Checking Docker service logs:"
        $compose_cmd logs --tail=20
        return 1
    fi
    
    print_success "Docker services started"
    
    # Wait for services to be ready
    print_info "Waiting for DynamoDB Local to be ready..."
    local timeout=30
    local counter=0
    while ! curl -s http://localhost:8000 > /dev/null 2>&1; do
        sleep 1
        counter=$((counter+1))
        if [ $counter -ge $timeout ]; then
            print_error "DynamoDB Local failed to start within $timeout seconds"
            print_info "Container logs for dynamodb-local:"
            docker logs dynamodb-local --tail=20 2>/dev/null || print_warning "Could not get container logs"
            return 1
        fi
        printf "${CYAN}⏳ Waiting... (%d/%d)${NC}\r" "$counter" "$timeout"
    done
    echo ""
    print_success "DynamoDB Local is ready!"
    
    print_info "Waiting for LocalStack to be ready..."
    timeout=90  # LocalStack takes longer to start
    counter=0
    while ! curl -s http://localhost:4566/_localstack/health > /dev/null 2>&1; do
        sleep 1
        counter=$((counter+1))
        if [ $counter -ge $timeout ]; then
            print_error "LocalStack failed to start within $timeout seconds"
            print_info "Container logs for localstack:"
            docker logs localstack --tail=20 2>/dev/null || print_warning "Could not get container logs"
            return 1
        fi
        printf "${CYAN}⏳ Waiting... (%d/%d)${NC}\r" "$counter" "$timeout"
    done
    echo ""
    print_success "LocalStack is ready!"
    
    # Wait a bit more for DynamoDB Admin
    print_info "Waiting for DynamoDB Admin to be ready..."
    timeout=30
    counter=0
    while ! curl -s http://localhost:8001 > /dev/null 2>&1; do
        sleep 1
        counter=$((counter+1))
        if [ $counter -ge $timeout ]; then
            print_warning "DynamoDB Admin failed to start, but continuing..."
            break
        fi
        printf "${CYAN}⏳ Waiting... (%d/%d)${NC}\r" "$counter" "$timeout"
    done
    echo ""
    
    if curl -s http://localhost:8001 > /dev/null 2>&1; then
        print_success "DynamoDB Admin is ready!"
    else
        print_warning "DynamoDB Admin is not responding (optional service)"
    fi
    
    # Initialize LocalStack S3 bucket
    initialize_localstack_resources
    
    # Display service URLs
    echo ""
    echo -e "${BOLD}🌐 Local Services:${NC}"
    echo -e "  ${BOLD}DynamoDB Local:${NC} http://localhost:8000"
    echo -e "  ${BOLD}DynamoDB Admin:${NC} http://localhost:8001"
    echo -e "  ${BOLD}LocalStack (S3):${NC} http://localhost:4566"
    echo -e "  ${BOLD}LocalStack Health:${NC} http://localhost:4566/_localstack/health"
    
    return 0
}

# Function to initialize LocalStack resources
initialize_localstack_resources() {
    print_step "Initializing LocalStack S3 Resources"
    
    # Check if AWS CLI is available
    if ! command -v aws &> /dev/null; then
        print_warning "AWS CLI not found - skipping S3 bucket initialization"
        print_info "The application will still work, but you may need to create the bucket manually"
        return 0
    fi
    
    # Wait a bit more for LocalStack to be fully ready
    sleep 3
    
    # Set AWS credentials for LocalStack
    export AWS_ACCESS_KEY_ID=test
    export AWS_SECRET_ACCESS_KEY=test
    export AWS_DEFAULT_REGION=us-east-1
    
    # Create S3 bucket if it doesn't exist
    local bucket_name="local-nebulax-s3"
    
    print_info "Creating S3 bucket: $bucket_name"
    if aws --endpoint-url=http://localhost:4566 s3 mb s3://$bucket_name --region us-east-1 >/dev/null 2>&1; then
        print_success "S3 bucket created: $bucket_name"
    else
        # Check if bucket already exists
        if aws --endpoint-url=http://localhost:4566 s3 ls s3://$bucket_name >/dev/null 2>&1; then
            print_info "S3 bucket already exists: $bucket_name"
        else
            print_warning "Failed to create S3 bucket, but continuing..."
            print_info "You can create it manually later or the application will handle it"
        fi
    fi
    
    return 0
}

# Function to build application
build_application() {
    print_step "Building Application"
    
    print_info "Cleaning and compiling with Maven..."
    if ! mvn clean compile -DskipTests -q; then
        print_error "Maven build failed"
        print_info "Trying with verbose output to diagnose the issue:"
        mvn clean compile -DskipTests
        return 1
    fi
    
    print_success "Application built successfully"
    return 0
}

# Function to run application
run_application() {
    print_step "Starting Nebulax Application"
    
    # Set local profile
    export SPRING_PROFILES_ACTIVE=local
    
    # Set AWS credentials for LocalStack
    export AWS_ACCESS_KEY_ID=test
    export AWS_SECRET_ACCESS_KEY=test
    export AWS_DEFAULT_REGION=us-east-1
    
    print_info "Starting application with local profile..."
    print_info "Application will be available at: http://localhost:8080"
    print_info "API Base URL: http://localhost:8080/api/v1"
    
    echo ""
    echo -e "${BOLD}🔗 Quick Test URLs:${NC}"
    echo -e "  ${BOLD}Health Check:${NC} http://localhost:8080/api/v1/health"
    echo -e "  ${BOLD}Videos:${NC} http://localhost:8080/api/v1/videos"
    echo -e "  ${BOLD}DynamoDB Admin:${NC} http://localhost:8001"
    echo -e "  ${BOLD}LocalStack Dashboard:${NC} http://localhost:4566"
    
    echo ""
    print_info "Press Ctrl+C to stop the application"
    print_warning "If the application fails to start, check the error messages above"
    echo ""
    
    # Run Spring Boot application with error handling
    if ! mvn spring-boot:run -Dspring-boot.run.profiles=local; then
        print_error "Application failed to start"
        print_info "Common issues to check:"
        print_info "1. Port 8080 is already in use"
        print_info "2. Local services (DynamoDB/LocalStack) are not running"
        print_info "3. Java/Maven configuration issues"
        print_info "4. Missing dependencies or configuration"
        return 1
    fi
    
    return 0
}

# Function to stop services
stop_services() {
    print_step "Stopping Local Services"
    
    # Determine which compose command to use
    local compose_cmd=""
    if docker compose version &> /dev/null; then
        compose_cmd="docker compose"
    else
        compose_cmd="docker-compose"
    fi
    
    if ! $compose_cmd down --remove-orphans; then
        print_warning "Failed to stop some services gracefully, trying force stop..."
        docker stop dynamodb-local localstack dynamodb-admin 2>/dev/null || true
        docker rm dynamodb-local localstack dynamodb-admin 2>/dev/null || true
    fi
    
    print_success "Local services stopped"
    return 0
}

# Function to show status
show_status() {
    print_step "Local Development Status"
    
    echo -e "${BOLD}🐳 Container Status:${NC}"
    if docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" --filter "name=dynamodb-local" --filter "name=localstack" --filter "name=dynamodb-admin" | grep -q "dynamodb-local\|localstack\|dynamodb-admin"; then
        docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" --filter "name=dynamodb-local" --filter "name=localstack" --filter "name=dynamodb-admin"
    else
        print_info "No local development containers are running"
    fi
    
    echo ""
    echo -e "${BOLD}🌐 Service Health:${NC}"
    
    # Check DynamoDB Local
    if curl -s http://localhost:8000 > /dev/null 2>&1; then
        echo -e "  ${GREEN}✅ DynamoDB Local (http://localhost:8000)${NC}"
    else
        echo -e "  ${RED}❌ DynamoDB Local (http://localhost:8000)${NC}"
    fi
    
    # Check LocalStack
    if curl -s http://localhost:4566/_localstack/health > /dev/null 2>&1; then
        echo -e "  ${GREEN}✅ LocalStack (http://localhost:4566)${NC}"
        
        # Show LocalStack service status
        local health_response=$(curl -s http://localhost:4566/_localstack/health 2>/dev/null)
        if [ ! -z "$health_response" ]; then
            echo -e "    ${CYAN}Services: $(echo $health_response | grep -o '"[^"]*":"[^"]*"' | tr -d '"' | tr ':' '=' | tr '\n' ', ' | sed 's/, $//')${NC}"
        fi
    else
        echo -e "  ${RED}❌ LocalStack (http://localhost:4566)${NC}"
    fi
    
    # Check DynamoDB Admin
    if curl -s http://localhost:8001 > /dev/null 2>&1; then
        echo -e "  ${GREEN}✅ DynamoDB Admin (http://localhost:8001)${NC}"
    else
        echo -e "  ${RED}❌ DynamoDB Admin (http://localhost:8001)${NC}"
    fi
    
    # Check Application
    if curl -s http://localhost:8080/api/v1/health > /dev/null 2>&1; then
        echo -e "  ${GREEN}✅ Nebulax Application (http://localhost:8080)${NC}"
    else
        echo -e "  ${RED}❌ Nebulax Application (http://localhost:8080)${NC}"
    fi
    
    return 0
}

# Function to show help
show_help() {
    echo "Local Development Script for Nebulax Video Processing System"
    echo ""
    echo "Usage: $0 [COMMAND]"
    echo ""
    echo "Commands:"
    echo "  start       Start local AWS services and run the application (default)"
    echo "  stop        Stop all local services"
    echo "  restart     Restart local services and application"
    echo "  status      Show status of local services"
    echo "  services    Start only local AWS services (DynamoDB, S3)"
    echo "  app         Run only the Nebulax application (assumes services are running)"
    echo "  build       Build the application"
    echo "  clean       Clean up containers and volumes"
    echo "  logs        Show logs from local services"
    echo "  test        Test the local environment setup"
    echo "  help        Show this help message"
    echo ""
    echo "Environment Variables:"
    echo "  DEBUG=1                 Enable debug output"
    echo "  SKIP_TESTS=true        Skip application tests during build"
    echo ""
    echo "Examples:"
    echo "  $0                     # Start everything (default)"
    echo "  $0 services            # Start only infrastructure services"
    echo "  $0 app                 # Start only the application"
    echo "  $0 status              # Check service status"
    echo "  DEBUG=1 $0 start       # Start with debug output"
}

# Function to show logs
show_logs() {
    print_step "Showing Local Service Logs"
    
    # Determine which compose command to use
    local compose_cmd=""
    if docker compose version &> /dev/null; then
        compose_cmd="docker compose"
    else
        compose_cmd="docker-compose"
    fi
    
    if ! $compose_cmd logs -f; then
        print_warning "Failed to show compose logs, trying individual container logs..."
        echo ""
        print_info "DynamoDB Local logs:"
        docker logs dynamodb-local --tail=50 2>/dev/null || print_warning "No DynamoDB Local container found"
        
        echo ""
        print_info "LocalStack logs:"
        docker logs localstack --tail=50 2>/dev/null || print_warning "No LocalStack container found"
        
        echo ""
        print_info "DynamoDB Admin logs:"
        docker logs dynamodb-admin --tail=50 2>/dev/null || print_warning "No DynamoDB Admin container found"
    fi
    
    return 0
}

# Function to test environment
test_environment() {
    print_step "Testing Local Environment"
    
    # Test prerequisites
    print_info "Testing prerequisites..."
    if ! check_prerequisites; then
        return 1
    fi
    
    # Test Docker connectivity
    print_info "Testing Docker connectivity..."
    if ! docker info >/dev/null 2>&1; then
        print_error "Docker is not accessible"
        return 1
    fi
    print_success "Docker is accessible"
    
    # Test service endpoints if running
    print_info "Testing service endpoints..."
    
    if curl -s http://localhost:8000 > /dev/null 2>&1; then
        print_success "DynamoDB Local is responding"
    else
        print_warning "DynamoDB Local is not responding (may not be started)"
    fi
    
    if curl -s http://localhost:4566/_localstack/health > /dev/null 2>&1; then
        print_success "LocalStack is responding"
    else
        print_warning "LocalStack is not responding (may not be started)"
    fi
    
    if curl -s http://localhost:8080/api/v1/health > /dev/null 2>&1; then
        print_success "Nebulax Application is responding"
    else
        print_warning "Nebulax Application is not responding (may not be started)"
    fi
    
    print_success "Environment test completed"
    return 0
}

# Function to clean up
clean_up() {
    print_step "Cleaning Up Local Environment"
    
    print_warning "This will remove all containers, volumes, and data"
    read -p "Are you sure? (y/N): " -n 1 -r
    echo
    
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        # Determine which compose command to use
        local compose_cmd=""
        if docker compose version &> /dev/null; then
            compose_cmd="docker compose"
        else
            compose_cmd="docker-compose"
        fi
        
        print_info "Stopping and removing containers..."
        $compose_cmd down -v --remove-orphans || {
            print_warning "Compose cleanup failed, trying manual cleanup..."
            docker stop dynamodb-local localstack dynamodb-admin 2>/dev/null || true
            docker rm dynamodb-local localstack dynamodb-admin 2>/dev/null || true
        }
        
        # Remove data directories
        print_info "Removing data directories..."
        rm -rf docker/ 2>/dev/null || print_warning "Could not remove some data directories"
        
        # Remove any orphaned networks
        print_info "Cleaning up networks..."
        docker network prune -f >/dev/null 2>&1 || true
        
        print_success "Local environment cleaned up"
    else
        print_info "Cleanup cancelled"
    fi
    
    return 0
}

# Main function
main() {
    # Set up error handling
    set -E
    trap 'handle_error $? "$BASH_COMMAND" $LINENO' ERR
    
    # Enable debug mode if requested
    if [ "${DEBUG:-}" = "1" ]; then
        set -x
        print_info "Debug mode enabled"
    fi
    
    case "${1:-start}" in
        start)
            print_header "Local Development Environment"
            if check_prerequisites && start_local_services && build_application; then
                run_application
            else
                print_error "Failed to start local development environment"
                print_info "Run './local-dev.sh status' to check service status"
                print_info "Run './local-dev.sh logs' to see detailed logs"
                exit 1
            fi
            ;;
        stop)
            print_header "Stopping Local Environment"
            stop_services
            ;;
        restart)
            print_header "Restarting Local Environment"
            if stop_services && sleep 2 && start_local_services; then
                run_application
            else
                print_error "Failed to restart local environment"
                exit 1
            fi
            ;;
        status)
            print_header "Local Environment Status"
            show_status
            ;;
        services)
            print_header "Starting Local AWS Services"
            if check_prerequisites && start_local_services; then
                print_info "Services are running. Use './local-dev.sh app' to start the application."
            else
                print_error "Failed to start local services"
                exit 1
            fi
            ;;
        app)
            print_header "Starting Nebulax Application"
            if build_application; then
                run_application
            else
                print_error "Failed to start application"
                exit 1
            fi
            ;;
        build)
            print_header "Building Application"
            if ! build_application; then
                exit 1
            fi
            ;;
        test)
            print_header "Testing Local Environment"
            if ! test_environment; then
                exit 1
            fi
            ;;
        clean)
            print_header "Cleanup Local Environment"
            clean_up
            ;;
        logs)
            print_header "Local Service Logs"
            show_logs
            ;;
        help)
            show_help
            ;;
        *)
            print_error "Unknown command: $1"
            echo ""
            show_help
            exit 1
            ;;
    esac
}

# Handle Ctrl+C gracefully
trap 'echo -e "\n${YELLOW}Shutting down...${NC}"; stop_services; exit 0' INT

# Run main function
main "$@"
