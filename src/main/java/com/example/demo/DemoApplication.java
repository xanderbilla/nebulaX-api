package com.example.demo;

import com.amazonaws.serverless.exceptions.ContainerInitializationException;
import com.amazonaws.serverless.proxy.model.AwsProxyRequest;
import com.amazonaws.serverless.proxy.model.AwsProxyResponse;
import com.amazonaws.serverless.proxy.spring.SpringBootLambdaContainerHandler;
import com.amazonaws.services.lambda.runtime.Context;
import com.amazonaws.services.lambda.runtime.RequestHandler;
import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;

/**
 * Main Spring Boot application class for Nebulax.
 * 
 * @author Vikas Singh
 * @since August 5, 2025
 */
@SpringBootApplication
public class DemoApplication implements RequestHandler<AwsProxyRequest, AwsProxyResponse> {

    private static SpringBootLambdaContainerHandler<AwsProxyRequest, AwsProxyResponse> handler;

    static {
        try {
            handler = SpringBootLambdaContainerHandler.getAwsProxyHandler(DemoApplication.class);
        } catch (ContainerInitializationException e) {
            // if we fail here, we re-throw the exception to force another cold start
            e.printStackTrace();
            throw new RuntimeException("Could not initialize Spring Boot application", e);
        }
    }

    @Override
    public AwsProxyResponse handleRequest(AwsProxyRequest input, Context context) {
        return handler.proxy(input, context);
    }

    public static void main(String[] args) {
        // Detect if running in Lambda environment vs local development
        String lambdaTaskRoot = System.getenv("LAMBDA_TASK_ROOT");
        String awsExecutionEnv = System.getenv("AWS_EXECUTION_ENV");

        if (lambdaTaskRoot != null || awsExecutionEnv != null) {
            // Running in AWS Lambda - no need to start embedded server
            System.out.println("Running in AWS Lambda environment");
            return;
        }

        // Running locally - start Spring Boot application with embedded server
        System.out.println("Starting Spring Boot application for local development...");
        SpringApplication.run(DemoApplication.class, args);
    }
}
