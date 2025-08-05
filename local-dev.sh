#!/bin/bash

# Local Development Setup Script for Spring Boot Video Processing System
# This script sets up and runs the application locally with DynamoDB Local and LocalStack

set -e  # Exit on any error

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

# Function to check prerequisites
check_prerequisites() {
    print_step "Checking Prerequisites"
    
    # Check Docker
    if ! command -v docker &> /dev/null; then
        print_error "Docker is required but not installed"
        exit 1
    fi
    
    # Check Docker Compose
    if ! docker compose version &> /dev/null && ! docker-compose --version &> /dev/null; then
        print_error "Docker Compose is required but not installed"
        exit 1
    fi
    
    # Check Java
    if ! command -v java &> /dev/null; then
        print_error "Java is required but not installed"
        exit 1
    fi
    
    # Check Maven
    if ! command -v mvn &> /dev/null; then
        print_error "Maven is required but not installed"
        exit 1
    fi
    
    print_success "All prerequisites met"
}

# Function to start local services
start_local_services() {
    print_step "Starting Local AWS Services"
    
    # Create directories for persistent data
    mkdir -p docker/dynamodb
    mkdir -p docker/localstack
    
    # Start Docker services
    if docker compose version &> /dev/null; then
        docker compose up -d
    else
        docker-compose up -d
    fi
    
    # Wait for services to be ready
    print_info "Waiting for DynamoDB Local to be ready..."
    timeout=30
    while ! curl -s http://localhost:8000 > /dev/null 2>&1; do
        sleep 1
        timeout=$((timeout-1))
        if [ $timeout -eq 0 ]; then
            print_error "DynamoDB Local failed to start"
            exit 1
        fi
    done
    
    print_info "Waiting for LocalStack to be ready..."
    timeout=60
    while ! curl -s http://localhost:4566/_localstack/health > /dev/null 2>&1; do
        sleep 1
        timeout=$((timeout-1))
        if [ $timeout -eq 0 ]; then
            print_error "LocalStack failed to start"
            exit 1
        fi
    done
    
    print_success "Local AWS services are ready!"
    
    # Display service URLs
    echo ""
    echo -e "${BOLD}🌐 Local Services:${NC}"
    echo -e "  ${BOLD}DynamoDB Local:${NC} http://localhost:8000"
    echo -e "  ${BOLD}DynamoDB Admin:${NC} http://localhost:8001"
    echo -e "  ${BOLD}LocalStack (S3):${NC} http://localhost:4566"
    echo -e "  ${BOLD}LocalStack Health:${NC} http://localhost:4566/_localstack/health"
}

# Function to build application
build_application() {
    print_step "Building Application"
    
    mvn clean compile -DskipTests
    
    print_success "Application built successfully"
}

# Function to run application
run_application() {
    print_step "Starting Spring Boot Application"
    
    # Set local profile
    export SPRING_PROFILES_ACTIVE=local
    
    print_info "Starting application with local profile..."
    print_info "Application will be available at: http://localhost:8080"
    print_info "API Base URL: http://localhost:8080/api/v1"
    
    echo ""
    echo -e "${BOLD}🔗 Quick Test URLs:${NC}"
    echo -e "  ${BOLD}Health Check:${NC} http://localhost:8080/api/v1/health"
    echo -e "  ${BOLD}Videos:${NC} http://localhost:8080/api/v1/videos"
    
    echo ""
    print_info "Press Ctrl+C to stop the application"
    echo ""
    
    # Run Spring Boot application
    mvn spring-boot:run -Dspring-boot.run.profiles=local
}

# Function to stop services
stop_services() {
    print_step "Stopping Local Services"
    
    if docker compose version &> /dev/null; then
        docker compose down
    else
        docker-compose down
    fi
    
    print_success "Local services stopped"
}

# Function to show status
show_status() {
    print_step "Local Development Status"
    
    echo -e "${BOLD}🐳 Container Status:${NC}"
    docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" --filter "name=dynamodb-local" --filter "name=localstack" --filter "name=dynamodb-admin"
    
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
    else
        echo -e "  ${RED}❌ LocalStack (http://localhost:4566)${NC}"
    fi
    
    # Check DynamoDB Admin
    if curl -s http://localhost:8001 > /dev/null 2>&1; then
        echo -e "  ${GREEN}✅ DynamoDB Admin (http://localhost:8001)${NC}"
    else
        echo -e "  ${RED}❌ DynamoDB Admin (http://localhost:8001)${NC}"
    fi
}

# Function to show help
show_help() {
    echo "Local Development Script for Spring Boot Video Processing System"
    echo ""
    echo "Usage: $0 [COMMAND]"
    echo ""
    echo "Commands:"
    echo "  start       Start local AWS services and run the application"
    echo "  stop        Stop all local services"
    echo "  restart     Restart local services and application"
    echo "  status      Show status of local services"
    echo "  services    Start only local AWS services (DynamoDB, S3)"
    echo "  app         Run only the Spring Boot application (assumes services are running)"
    echo "  build       Build the application"
    echo "  clean       Clean up containers and volumes"
    echo "  logs        Show logs from local services"
    echo "  help        Show this help message"
}

# Function to show logs
show_logs() {
    print_step "Showing Local Service Logs"
    
    if docker compose version &> /dev/null; then
        docker compose logs -f
    else
        docker-compose logs -f
    fi
}

# Function to clean up
clean_up() {
    print_step "Cleaning Up Local Environment"
    
    print_warning "This will remove all containers, volumes, and data"
    read -p "Are you sure? (y/N): " -n 1 -r
    echo
    
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        if docker compose version &> /dev/null; then
            docker compose down -v
        else
            docker-compose down -v
        fi
        
        # Remove data directories
        rm -rf docker/
        
        print_success "Local environment cleaned up"
    else
        print_info "Cleanup cancelled"
    fi
}

# Main function
main() {
    case "${1:-start}" in
        start)
            print_header "Local Development Environment"
            check_prerequisites
            start_local_services
            build_application
            run_application
            ;;
        stop)
            print_header "Stopping Local Environment"
            stop_services
            ;;
        restart)
            print_header "Restarting Local Environment"
            stop_services
            sleep 2
            start_local_services
            run_application
            ;;
        status)
            print_header "Local Environment Status"
            show_status
            ;;
        services)
            print_header "Starting Local AWS Services"
            check_prerequisites
            start_local_services
            print_info "Services are running. Use './local-dev.sh app' to start the application."
            ;;
        app)
            print_header "Starting Spring Boot Application"
            build_application
            run_application
            ;;
        build)
            print_header "Building Application"
            build_application
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
            show_help
            exit 1
            ;;
    esac
}

# Handle Ctrl+C gracefully
trap 'echo -e "\n${YELLOW}Shutting down...${NC}"; stop_services; exit 0' INT

# Run main function
main "$@"
