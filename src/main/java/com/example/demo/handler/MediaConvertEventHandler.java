package com.example.demo.handler;

import com.amazonaws.services.lambda.runtime.Context;
import com.amazonaws.services.lambda.runtime.RequestHandler;
import com.example.demo.service.VideoService;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.boot.SpringApplication;
import org.springframework.context.ConfigurableApplicationContext;

import java.util.Map;

/**
 * AWS Lambda handler for processing MediaConvert job state change events.
 * Updates DynamoDB when MediaConvert jobs complete successfully or with errors.
 * 
 * @author Xander Billa
 * @since August 11, 2025
 */
public class MediaConvertEventHandler implements RequestHandler<Map<String, Object>, String> {

    private static final Logger logger = LoggerFactory.getLogger(MediaConvertEventHandler.class);

    private static ConfigurableApplicationContext applicationContext;
    private static VideoService videoService;
    private static final ObjectMapper objectMapper = new ObjectMapper();

    static {
        try {
            // Initialize Spring Boot application context
            System.setProperty("spring.profiles.active", "lambda");
            applicationContext = SpringApplication.run(com.example.demo.DemoApplication.class);
            videoService = applicationContext.getBean(VideoService.class);
            logger.info("Spring Boot application context initialized successfully");
        } catch (Exception e) {
            logger.error("Failed to initialize Spring Boot application context", e);
            throw new RuntimeException("Application initialization failed", e);
        }
    }

    @Override
    public String handleRequest(Map<String, Object> event, Context context) {
        logger.info("Processing MediaConvert event: {}", event);

        try {
            // Parse the EventBridge event
            JsonNode eventNode = objectMapper.valueToTree(event);
            
            // Extract event details
            String source = eventNode.get("source").asText();
            String detailType = eventNode.get("detail-type").asText();
            
            if (!"aws.mediaconvert".equals(source) || !"MediaConvert Job State Change".equals(detailType)) {
                logger.warn("Ignoring non-MediaConvert event: source={}, detailType={}", source, detailType);
                return "Ignored non-MediaConvert event";
            }

            JsonNode detail = eventNode.get("detail");
            String jobId = detail.get("jobId").asText();
            String status = detail.get("status").asText();
            
            logger.info("Processing MediaConvert job event: jobId={}, status={}", jobId, status);

            // Only process COMPLETE and ERROR statuses
            if ("COMPLETE".equals(status)) {
                handleJobComplete(jobId, detail);
            } else if ("ERROR".equals(status)) {
                handleJobError(jobId, detail);
            } else {
                logger.info("Ignoring job status: {}", status);
                return "Ignored job status: " + status;
            }

            return "Successfully processed MediaConvert event: " + jobId;

        } catch (Exception e) {
            logger.error("Error processing MediaConvert event", e);
            throw new RuntimeException("MediaConvert event processing failed", e);
        }
    }

    private void handleJobComplete(String jobId, JsonNode detail) {
        try {
            // Extract output details
            JsonNode outputGroupDetails = detail.get("outputGroupDetails");
            if (outputGroupDetails == null || !outputGroupDetails.isArray() || outputGroupDetails.size() == 0) {
                logger.error("No output group details found for job: {}", jobId);
                return;
            }

            JsonNode firstOutputGroup = outputGroupDetails.get(0);
            JsonNode outputDetails = firstOutputGroup.get("outputDetails");
            if (outputDetails == null || !outputDetails.isArray() || outputDetails.size() == 0) {
                logger.error("No output details found for job: {}", jobId);
                return;
            }

            JsonNode firstOutput = outputDetails.get(0);
            String outputFilePath = firstOutput.get("outputFilePaths").get(0).asText();
            
            // Extract the .m3u8 file path and convert S3 URI to HTTPS URL
            String m3u8Path = outputFilePath;
            if (outputFilePath.contains("/")) {
                // Construct the .m3u8 file path
                String basePath = outputFilePath.substring(0, outputFilePath.lastIndexOf("/"));
                String fileName = outputFilePath.substring(outputFilePath.lastIndexOf("/") + 1);
                if (fileName.contains(".")) {
                    fileName = fileName.substring(0, fileName.lastIndexOf("."));
                }
                m3u8Path = basePath + "/" + fileName + ".m3u8";
            }
            
            // Convert S3 URI to HTTPS URL
            String m3u8Url = m3u8Path;
            if (m3u8Path.startsWith("s3://")) {
                // Extract bucket and key from S3 URI: s3://bucket/key
                String s3UriWithoutProtocol = m3u8Path.substring(5); // Remove "s3://"
                int firstSlashIndex = s3UriWithoutProtocol.indexOf("/");
                if (firstSlashIndex > 0) {
                    String bucket = s3UriWithoutProtocol.substring(0, firstSlashIndex);
                    String key = s3UriWithoutProtocol.substring(firstSlashIndex + 1);
                    // Convert to HTTPS URL format
                    m3u8Url = String.format("https://%s.s3.us-east-1.amazonaws.com/%s", bucket, key);
                }
            }

            logger.info("MediaConvert job completed: jobId={}, m3u8Url={}", jobId, m3u8Url);

            // Get user metadata to determine if this is a trailer
            JsonNode userMetadata = detail.get("userMetadata");
            boolean isTrailer = false;
            String sourceKey = null;
            
            if (userMetadata != null) {
                JsonNode isTrailerNode = userMetadata.get("isTrailer");
                JsonNode sourceKeyNode = userMetadata.get("sourceKey");
                
                if (isTrailerNode != null) {
                    isTrailer = "true".equals(isTrailerNode.asText());
                }
                if (sourceKeyNode != null) {
                    sourceKey = sourceKeyNode.asText();
                }
            }

            // Update the video record in DynamoDB
            videoService.updateVideoJobComplete(jobId, m3u8Url, isTrailer, sourceKey);
            logger.info("Updated video job completion: jobId={}, isTrailer={}, sourceKey={}", 
                    jobId, isTrailer, sourceKey);

        } catch (Exception e) {
            logger.error("Failed to handle job completion for jobId: {}", jobId, e);
            throw e;
        }
    }

    private void handleJobError(String jobId, JsonNode detail) {
        try {
            String errorMessage = detail.get("errorMessage") != null ? 
                detail.get("errorMessage").asText() : "Unknown error";
            
            logger.error("MediaConvert job failed: jobId={}, error={}", jobId, errorMessage);

            // Get user metadata to determine if this is a trailer
            JsonNode userMetadata = detail.get("userMetadata");
            boolean isTrailer = false;
            String sourceKey = null;
            
            if (userMetadata != null) {
                JsonNode isTrailerNode = userMetadata.get("isTrailer");
                JsonNode sourceKeyNode = userMetadata.get("sourceKey");
                
                if (isTrailerNode != null) {
                    isTrailer = "true".equals(isTrailerNode.asText());
                }
                if (sourceKeyNode != null) {
                    sourceKey = sourceKeyNode.asText();
                }
            }

            // Update the video record in DynamoDB with error status
            videoService.updateVideoJobError(jobId, errorMessage, isTrailer, sourceKey);
            logger.info("Updated video job error: jobId={}, isTrailer={}, sourceKey={}, error={}", 
                    jobId, isTrailer, sourceKey, errorMessage);

        } catch (Exception e) {
            logger.error("Failed to handle job error for jobId: {}", jobId, e);
            throw e;
        }
    }

    // Optional: Cleanup method (though Lambda containers are ephemeral)
    public static void shutdown() {
        if (applicationContext != null) {
            applicationContext.close();
        }
    }
}
