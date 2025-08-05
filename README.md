# AWS Spring Boot Serverless Player Application

A production-ready **Spring Boot** serverless application for media player functionality with **AWS Lambda**, **API Gateway**, **DynamoDB**, and **S3**. This system provides a complete media upload, processing, and management workflow with support for videos, posters, and trailers.

```bash
./deploy-prod.sh [OPTIONS]
```

### 🔧 Available Options

| Option          | Description                            |
| --------------- | -------------------------------------- |
| `-h`, `--help`  | Show help message                      |
| `-t`, `--test`  | Test the existing deployment           |
| `-b`, `--build` | Only build the project (no deployment) |
| `-s`, `--setup` | Configure deployment settings only     |
| `-c`, `--clean` | Clean up all AWS resources             |
| `--logs`        | Show recent CloudWatch logs            |
| `--tail-logs`   | Tail CloudWatch logs in real-time      |

### ⚙️ Configuration

On the first run, the script will interactively prompt for:

- **Stack Name** (default: `spring-boot-demo`)
  - Lambda Function: `{stack-name}-func`
  - API Gateway: `{stack-name}-api`
  - S3 Bucket: `{stack-name}-artifacts-{account-id}`
- **AWS Region** (default: `us-east-1`)

These values are saved in `samconfig.toml` for future runs.
Use `--clean` to delete all deployed resources and reset the configuration.

### 🌍 Environment Variables

You can override default behavior using environment variables:

| Variable     | Description                            | Default            |
| ------------ | -------------------------------------- | ------------------ |
| `STACK_NAME` | The name of the CloudFormation stack   | `spring-boot-demo` |
| `REGION`     | AWS Region to deploy to                | `us-east-1`        |
| `STAGE`      | Deployment stage (e.g., `dev`, `prod`) | `dev`              |

### 📊 CloudWatch Monitoring

This deployment automatically configures **CloudWatch** log groups for enhanced observability:

- 📄 **Lambda Function Execution Logs**
- 🌐 **API Gateway Access Logs**

Use the following options to inspect logs:

- `--logs`: View recent logs for deployed resources
- `--tail-logs`: Continuously stream logs in real-time

These logs are crucial for debugging and monitoring your serverless application post-deployment.

## 👨‍💻 Author

[@xanderbilla](https://www.github.com/xanderbilla)
