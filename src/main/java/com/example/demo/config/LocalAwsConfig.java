package com.example.demo.config;

import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.context.annotation.Primary;
import org.springframework.context.annotation.Profile;
import software.amazon.awssdk.auth.credentials.AwsBasicCredentials;
import software.amazon.awssdk.auth.credentials.StaticCredentialsProvider;
import software.amazon.awssdk.enhanced.dynamodb.DynamoDbEnhancedClient;
import software.amazon.awssdk.regions.Region;
import software.amazon.awssdk.services.dynamodb.DynamoDbClient;
import software.amazon.awssdk.services.s3.S3Client;
import software.amazon.awssdk.services.s3.presigner.S3Presigner;

import java.net.URI;

@Slf4j
@Configuration
@Profile("local")
public class LocalAwsConfig {

    @Value("${aws.dynamodb.endpoint:http://localhost:8000}")
    private String dynamoDbEndpoint;

    @Value("${aws.dynamodb.region:us-east-1}")
    private String dynamoDbRegion;

    @Value("${aws.dynamodb.access-key:dummy}")
    private String dynamoDbAccessKey;

    @Value("${aws.dynamodb.secret-key:dummy}")
    private String dynamoDbSecretKey;

    @Value("${aws.s3.endpoint:http://localhost:4566}")
    private String s3Endpoint;

    @Value("${aws.s3.region:us-east-1}")
    private String s3Region;

    @Value("${aws.s3.access-key:test}")
    private String s3AccessKey;

    @Value("${aws.s3.secret-key:test}")
    private String s3SecretKey;

    @Bean
    @Primary
    public DynamoDbClient localDynamoDbClient() {
        log.info("🔧 Configuring DynamoDB Local client at: {}", dynamoDbEndpoint);

        return DynamoDbClient.builder()
                .endpointOverride(URI.create(dynamoDbEndpoint))
                .region(Region.of(dynamoDbRegion))
                .credentialsProvider(StaticCredentialsProvider.create(
                        AwsBasicCredentials.create(dynamoDbAccessKey, dynamoDbSecretKey)))
                .build();
    }

    @Bean
    @Primary
    public DynamoDbEnhancedClient localDynamoDbEnhancedClient(DynamoDbClient dynamoDbClient) {
        log.info("🔧 Configuring DynamoDB Enhanced Client for local development");

        return DynamoDbEnhancedClient.builder()
                .dynamoDbClient(dynamoDbClient)
                .build();
    }

    @Bean
    @Primary
    public S3Client localS3Client() {
        log.info("🔧 Configuring S3 Local client at: {}", s3Endpoint);

        return S3Client.builder()
                .endpointOverride(URI.create(s3Endpoint))
                .region(Region.of(s3Region))
                .credentialsProvider(StaticCredentialsProvider.create(
                        AwsBasicCredentials.create(s3AccessKey, s3SecretKey)))
                .forcePathStyle(true) // Required for LocalStack
                .build();
    }

    @Bean
    @Primary
    public S3Presigner localS3Presigner() {
        log.info("🔧 Configuring S3 Presigner for local development");

        return S3Presigner.builder()
                .endpointOverride(URI.create(s3Endpoint))
                .region(Region.of(s3Region))
                .credentialsProvider(StaticCredentialsProvider.create(
                        AwsBasicCredentials.create(s3AccessKey, s3SecretKey)))
                .build();
    }
}
