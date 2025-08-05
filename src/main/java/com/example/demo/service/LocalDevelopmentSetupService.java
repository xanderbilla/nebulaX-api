package com.example.demo.service;

import com.example.demo.model.Video;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.CommandLineRunner;
import org.springframework.context.annotation.Profile;
import org.springframework.stereotype.Service;
import software.amazon.awssdk.enhanced.dynamodb.DynamoDbEnhancedClient;
import software.amazon.awssdk.enhanced.dynamodb.DynamoDbTable;
import software.amazon.awssdk.enhanced.dynamodb.TableSchema;
import software.amazon.awssdk.enhanced.dynamodb.model.CreateTableEnhancedRequest;
import software.amazon.awssdk.services.dynamodb.model.DynamoDbException;
import software.amazon.awssdk.services.dynamodb.model.ProvisionedThroughput;
import software.amazon.awssdk.services.dynamodb.model.ResourceInUseException;
import software.amazon.awssdk.services.s3.S3Client;
import software.amazon.awssdk.services.s3.model.CreateBucketRequest;
import software.amazon.awssdk.services.s3.model.HeadBucketRequest;
import software.amazon.awssdk.services.s3.model.NoSuchBucketException;

/**
 * Service for setting up local development environment with sample data.
 * Creates test videos, sample assets, and development configuration
 * to enable rapid local testing and development workflows.
 * 
 * @author Xander Billa
 * @since August 5, 2025
 * @see com.example.demo.service.VideoService
 * @see com.example.demo.model.Video
 */
@Slf4j
@Service
@Profile("local")
@RequiredArgsConstructor
public class LocalDevelopmentSetupService implements CommandLineRunner {

    private final DynamoDbEnhancedClient dynamoDbEnhancedClient;
    private final S3Client s3Client;

    @Value("${app.dynamodb.videos-table}")
    private String videosTableName;

    @Value("${aws.s3.bucket}")
    private String s3BucketName;

    @Override
    public void run(String... args) {
        log.info("Setting up local development environment...");

        setupDynamoDbTables();
        setupS3Buckets();

        log.info("Local development environment setup complete!");
    }

    private void setupDynamoDbTables() {
        try {
            log.info("Setting up DynamoDB table: {}", videosTableName);

            DynamoDbTable<Video> videoTable = dynamoDbEnhancedClient.table(videosTableName,
                    TableSchema.fromBean(Video.class));

            CreateTableEnhancedRequest createTableRequest = CreateTableEnhancedRequest.builder()
                    .provisionedThroughput(ProvisionedThroughput.builder()
                            .readCapacityUnits(5L)
                            .writeCapacityUnits(5L)
                            .build())
                    .build();

            videoTable.createTable(createTableRequest);

            // Wait for table to be created
            videoTable.describeTable();

            log.info("DynamoDB table '{}' created successfully", videosTableName);

        } catch (ResourceInUseException e) {
            log.info("DynamoDB table '{}' already exists", videosTableName);
        } catch (DynamoDbException e) {
            log.error("Failed to create DynamoDB table '{}': {}", videosTableName, e.getMessage());
        }
    }

    private void setupS3Buckets() {
        try {
            log.info("Setting up S3 bucket: {}", s3BucketName);

            // Check if bucket exists
            s3Client.headBucket(HeadBucketRequest.builder().bucket(s3BucketName).build());
            log.info("S3 bucket '{}' already exists", s3BucketName);

        } catch (NoSuchBucketException e) {
            try {
                // Create bucket
                s3Client.createBucket(CreateBucketRequest.builder()
                        .bucket(s3BucketName)
                        .build());

                log.info("S3 bucket '{}' created successfully", s3BucketName);
            } catch (Exception createException) {
                log.error("Failed to create S3 bucket '{}': {}", s3BucketName, createException.getMessage());
            }
        } catch (Exception e) {
            log.error("Failed to check S3 bucket '{}': {}", s3BucketName, e.getMessage());
        }
    }
}
