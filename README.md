# AWS Spring Boot Serverless Video Processing System

A production-ready **Nebulax** serverless application for media processing functionality with **AWS Lambda**, **API Gateway**, **DynamoDB**, and **S3**. This system provides a complete media upload, processing, and management workflow with support for videos, posters, and trailers.

## API Reference

#### Health check

```http
  GET /api/v1/health
```

Follow for complete [API documentation](/wiki)

## Deployment

```bash
./deploy-prod.sh [OPTIONS]
```

### Available Options

Usage: ./deploy-prod.sh [OPTIONS]

| Option       | Description                                               |
| ------------ | --------------------------------------------------------- |
| -h, --help   | Show this help message                                    |
| -c, --clean  | Clean up all AWS resources                                |
| -b, --build  | Build only (no deploy)                                    |
| -u, --update | Build and update existing deployment (skip configuration) |
| -t, --test   | Test existing deployment                                  |
| -s, --setup  | Configure deployment settings only                        |
| --logs       | Show recent CloudWatch logs                               |
| --tail-logs  | Tail CloudWatch logs in real-time                         |

### Configuration

On the first run, the script will interactively prompt for:

- **Stack Name** (default: `spring-boot-demo`)
  - Lambda Function: `{stack-name}-func`
  - API Gateway: `{stack-name}-api`
  - S3 Bucket: `{stack-name}-artifacts-{account-id}`
- **AWS Region** (default: `us-east-1`)

These values are saved in `samconfig.toml` for future runs.
Use `--clean` to delete all deployed resources and reset the configuration.

### Environment Variables

You can override default behavior using environment variables:

| Variable     | Description                            | Default            |
| ------------ | -------------------------------------- | ------------------ |
| `STACK_NAME` | The name of the CloudFormation stack   | `spring-boot-demo` |
| `REGION`     | AWS Region to deploy to                | `us-east-1`        |
| `STAGE`      | Deployment stage (e.g., `dev`, `prod`) | `dev`              |

### CloudWatch Monitoring

This deployment automatically configures **CloudWatch** log groups for enhanced observability:

- Lambda Function Execution Logs
- API Gateway Access Logs

Use the following options to inspect logs:

- `--logs`: View recent logs for deployed resources
- `--tail-logs`: Continuously stream logs in real-time

These logs are crucial for debugging and monitoring your serverless application post-deployment.

## Run Locally

To run the it locally

Usage: ./local-dev.sh [COMMAND]

| Command  | Description                                                     |
| -------- | --------------------------------------------------------------- |
| start    | Start local AWS services and run the application                |
| stop     | Stop all local services                                         |
| restart  | Restart local services and application                          |
| status   | Show status of local services                                   |
| services | Start only local AWS services (DynamoDB, S3)                    |
| app      | Run only the Nebulax application (assumes services are running) |
| build    | Build the application                                           |
| clean    | Clean up containers and volumes                                 |
| logs     | Show logs from local services                                   |
| help     | Show this help message                                          |

### Environment Variables

| Variable         | Description                          |
| ---------------- | ------------------------------------ |
| DEBUG=1          | Enable debug output                  |
| SKIP_TESTS=true  | Skip application tests during build  |

## Author

[@xanderbilla](https://www.github.com/xanderbilla)
[@rajv4rdhan](https://www.github.com/rajv4rdhan)